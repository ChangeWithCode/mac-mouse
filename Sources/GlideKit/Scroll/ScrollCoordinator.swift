import CoreGraphics
import Foundation
import GlideCore

/// Turns incoming wheel events into smooth, phased scroll output.
///
/// Owns one `ScrollEngine` per axis and the display link that drives them. The
/// axes are independent so a tilt wheel and a vertical wheel can be flicked at
/// once without either stealing the other's momentum.
///
/// ## Threading
///
/// `handle(scrollEvent:)` runs on the event tap's run loop; `tick` runs on the
/// display link's thread. The lock around engine state is deliberately tiny —
/// anything slow on the tap side risks macOS disabling the tap entirely.
public final class ScrollCoordinator {

    private let verticalEngine = ScrollEngine()
    private let horizontalEngine = ScrollEngine()
    private let lock = NSLock()
    private var displayLink: DisplayLink?
    private var settings: ResolvedSettings = .fallback

    public init() {
        displayLink = DisplayLink { [weak self] now in self?.tick(now) }
    }

    /// Applies resolved settings. Safe to call mid-gesture: the new curve takes
    /// effect on the next frame, which is what makes the curve editor live.
    public func apply(_ settings: ResolvedSettings) {
        lock.lock(); defer { lock.unlock() }
        self.settings = settings
        verticalEngine.preset = settings.scrollPreset
        horizontalEngine.preset = settings.scrollPreset
        verticalEngine.inverted = settings.invertVertical
        horizontalEngine.inverted = settings.invertHorizontal
        verticalEngine.flickBoost = settings.flickBoost
        horizontalEngine.flickBoost = settings.flickBoost
    }

    /// Handles one wheel event.
    ///
    /// - Returns: `true` if Glide consumed it and will emit its own frames.
    ///   `false` means the event should pass through untouched.
    public func handle(scrollEvent event: CGEvent) -> Bool {
        // Never reprocess our own output, or the tap feeds itself forever.
        guard !ScrollEventSynthesizer.isSynthetic(event) else { return false }

        lock.lock()
        let enabled = settings.smoothingEnabled
        let horizontalEnabled = settings.horizontalEnabled
        lock.unlock()

        guard enabled else { return false }

        // A continuous event is already pixel-precise and already phased — it
        // came from a trackpad or an Apple Magic Mouse. Those are exactly what
        // Glide is imitating, so passing them through is not a limitation; it is
        // the point.
        guard event.getIntegerValueField(.scrollWheelEventIsContinuous) == 0 else { return false }

        let verticalDelta = event.getIntegerValueField(.scrollWheelEventDeltaAxis1)
        let horizontalDelta = event.getIntegerValueField(.scrollWheelEventDeltaAxis2)
        guard verticalDelta != 0 || horizontalDelta != 0 else { return false }

        let now = MonotonicClock.now
        lock.lock()
        if verticalDelta != 0 {
            verticalEngine.ingest(direction: Double(verticalDelta), timestamp: now)
        }
        if horizontalDelta != 0 && horizontalEnabled {
            horizontalEngine.ingest(direction: Double(horizontalDelta), timestamp: now)
        }
        lock.unlock()

        startIfNeeded()
        return true
    }

    /// Abandons anything in flight. Called on sleep, on a profile switch, and
    /// when the frontmost app changes — the view that was being scrolled is gone.
    public func cancel() {
        lock.lock()
        verticalEngine.reset()
        horizontalEngine.reset()
        lock.unlock()
        displayLink?.stop()
    }

    // MARK: - Frame generation

    private func startIfNeeded() {
        guard let displayLink, !displayLink.isRunning else { return }
        displayLink.start()
    }

    private func tick(_ now: Double) {
        lock.lock()
        let vertical = verticalEngine.advance(now: now)
        let horizontal = horizontalEngine.advance(now: now)
        let stillActive = verticalEngine.isActive || horizontalEngine.isActive
        lock.unlock()

        // Combine the axes into one event where both moved this frame. Two
        // separate events would be read as two gestures, and diagonal scrolling
        // would stutter between them.
        if let vertical, let horizontal, vertical.phase == horizontal.phase {
            post(deltaY: vertical.delta, deltaX: horizontal.delta, frame: vertical)
        } else {
            if let vertical { post(deltaY: vertical.delta, deltaX: 0, frame: vertical) }
            if let horizontal { post(deltaY: 0, deltaX: horizontal.delta, frame: horizontal) }
        }

        // Park the link the moment nothing is moving. Leaving it running wakes
        // the CPU at the refresh rate indefinitely, which is plainly visible in
        // battery life.
        if !stillActive { displayLink?.stop() }
    }

    private func post(deltaY: Int, deltaX: Int, frame: ScrollEngine.Frame) {
        ScrollEventSynthesizer.post(
            deltaY: deltaY,
            deltaX: deltaX,
            phase: .init(rawValue: frame.phase.rawValue) ?? .none,
            momentumPhase: .init(rawValue: frame.momentumPhase.rawValue) ?? .none
        )
    }
}
