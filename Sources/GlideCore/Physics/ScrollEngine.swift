import Foundation

/// Turns discrete wheel ticks into a stream of pixel-precise, correctly phased
/// scroll frames for one axis.
///
/// ## The model
///
/// Most smooth-scrolling implementations run two separate systems: an animator
/// that eases each notch toward a target, and a momentum simulation that takes
/// over on a flick. Handing off between them is where the seams show.
///
/// Glide uses one. Every tick injects an *impulse* into a single decaying
/// velocity, sized so that the impulse's own decay covers exactly the distance
/// the acceleration curve asked for:
///
///     v += distance(atCadence:) × friction
///
/// Because `∫v₀·e^(-kt) dt = v₀/k`, an impulse of `d·k` travels exactly `d`.
/// Three consequences fall out for free:
///
/// - **The acceleration curve becomes literally true.** "48 points per tick"
///   means the content moves 48 points, not roughly 48 — distance is conserved
///   no matter how the ticks overlap.
/// - **Momentum is not a special case.** Ticks arriving faster than the decay
///   top the velocity up and it sustains; stop ticking and the same decay is the
///   coast. There is no handoff, so there is no seam.
/// - **Frame rate stops mattering.** `dt` enters an exponent, so 60Hz, 120Hz and
///   a frame dropped under load all produce identical motion.
///
/// ## Phase sequencing
///
/// Views only turn on pixel-precise scrolling and rubber-band bounce when they
/// see a well-formed gesture, so the engine emits `began → changed… → ended`
/// followed by a momentum tail. The transition to momentum happens when ticks
/// stop arriving, not when the velocity drops — which is what makes releasing a
/// spun wheel bounce off the end of a document the way a trackpad does.
public final class ScrollEngine {

    /// One frame of output, ready to be written into a scroll event.
    public struct Frame: Sendable, Hashable {
        /// Whole points to scroll this frame. Sub-point remainders are carried.
        public let delta: Int
        public let phase: GesturePhase
        public let momentumPhase: MomentumPhase
        /// True on the last frame of a gesture; the engine is idle afterwards.
        public let isFinal: Bool
    }

    private enum State {
        case idle
        /// The user is actively turning the wheel.
        case tracking
        /// Input stopped and momentum is off, but the last notch still owes
        /// distance. The gesture stays open while that decays out.
        case settling
        /// Input stopped and the remaining velocity is coasting as momentum.
        case coasting
    }

    // MARK: - Configuration

    /// The feel being applied. Swapping this mid-gesture is safe and takes
    /// effect on the next frame, which is what makes the curve editor live.
    public var preset: ScrollPreset

    /// Extra impulse applied while the wheel is being spun freely. A hard flick
    /// should outrun the sum of its notches, or it reads as unresponsive.
    public var flickBoost: Double = 1.6

    /// Inverts the axis. Independent of the system setting, so Glide can leave
    /// the trackpad alone while flipping the mouse.
    public var inverted: Bool = false

    /// Silence after the last tick, in seconds, before the gesture is released
    /// into its momentum phase. Roughly one slow notch: long enough that
    /// deliberate scrolling is not chopped into separate gestures, short enough
    /// that letting go feels immediate.
    public var inputTimeout: Double = 0.09

    // MARK: - State

    private var state: State = .idle
    private var velocity: Double = 0
    private var remainder: Double = 0
    private var lastTickTime: Double = 0
    private var lastFrameTime: Double?
    /// Whether the first frame of the *current stream* has been emitted. Reset
    /// at every stream boundary, because a gesture and its momentum tail are two
    /// separate streams and each needs its own opening frame.
    private var streamHasOpened = false
    /// Whether `began` has been sent without a matching `ended`.
    private var gestureIsOpen = false
    /// Set when a coast is interrupted: the momentum stream must be closed
    /// before a new gesture opens.
    private var needsMomentumEnd = false
    private var detector = FreeSpinDetector()

    public init(preset: ScrollPreset = .default) {
        self.preset = preset
    }

    /// Whether anything is in flight. Lets the host park its display link.
    public var isActive: Bool { state != .idle }

    /// Cadence of the wheel right now, in ticks/second. Surfaced in the UI's
    /// live readout so the acceleration curve can be tuned against real input.
    public var inputCadence: Double { detector.currentSpeed }

    // MARK: - Input

    /// Feeds one wheel notch.
    ///
    /// - Parameters:
    ///   - direction: `+1` or `-1`. Magnitude is ignored; devices disagree about
    ///     what a "line" is, and the acceleration curve is the only thing that
    ///     should decide distance.
    ///   - timestamp: Event time in seconds, from the same clock as `advance`.
    public func ingest(direction: Double, timestamp: Double) {
        guard direction != 0 else { return }
        let sign: Double = direction < 0 ? -1 : 1
        let signedDirection = inverted ? -sign : sign

        detector.register(timestamp: timestamp)

        // Reversing direction cancels what is in flight rather than fighting it.
        // Without this, flicking back after a long fling feels like wading.
        if velocity != 0 && (velocity < 0) != (signedDirection < 0) {
            velocity = 0
            remainder = 0
        }

        let cadence = detector.currentSpeed
        var distance = preset.acceleration.distance(atSpeed: cadence)
        if detector.isSpinning { distance *= flickBoost }

        // Size the impulse so its own decay covers exactly `distance`.
        let momentum = MomentumScroll(friction: preset.friction, stopThreshold: preset.stopThreshold)
        velocity += momentum.velocityToTravel(distance) * signedDirection

        lastTickTime = timestamp
        if state != .tracking {
            // Resuming out of a coast: that gesture was already closed with
            // `ended`, so the momentum stream has to be closed and a new gesture
            // opened. Resuming out of `settling` is different — the gesture is
            // still open there, so it simply carries on as `changed`.
            if state == .coasting {
                needsMomentumEnd = true
                streamHasOpened = false
            }
            if state == .idle { lastFrameTime = nil }
            state = .tracking
        }
    }

    /// Advances to `now` and returns the frame to emit, if any.
    ///
    /// Returns `nil` when there is nothing to send — a zero-delta frame mid-coast
    /// is not worth an event — but never swallows a phase transition, because a
    /// dropped `ended` leaves the scrolled view believing a finger is still down.
    public func advance(now: Double) -> Frame? {
        guard state != .idle else { return nil }

        // Close the momentum stream before the new gesture opens over the top.
        if needsMomentumEnd {
            needsMomentumEnd = false
            lastFrameTime = now
            return Frame(delta: 0, phase: .none, momentumPhase: .end, isFinal: false)
        }

        let deltaTime = lastFrameTime.map { max(0, min(now - $0, 0.1)) } ?? 0
        lastFrameTime = now

        let momentum = MomentumScroll(friction: preset.friction, stopThreshold: preset.stopThreshold)

        // Input has gone quiet: decide how this gesture ends.
        if state == .tracking && (now - lastTickTime) > inputTimeout {
            detector.reset()
            if preset.momentumEnabled && abs(velocity) >= momentum.stopThreshold {
                state = .coasting
                streamHasOpened = false   // the momentum stream opens fresh
                gestureIsOpen = false
                // The `ended` event must carry no delta: it tells the view the
                // finger lifted, and motion attached to it is double-counted.
                return Frame(delta: 0, phase: .ended, momentumPhase: .none, isFinal: false)
            }
            // Momentum is off — but the notch still owes distance. Let it decay
            // out inside the open gesture rather than truncating it, which would
            // quietly lose several points off every single tick.
            state = .settling
        }

        let stepped = momentum.step(velocity: velocity, deltaTime: deltaTime)
        velocity = stepped.velocity

        // Accumulate sub-point motion rather than truncating it. Dropping the
        // fraction every frame loses up to a point per frame — at 120Hz that is
        // a visible drag on slow, precise scrolling.
        remainder += stepped.delta
        let whole = remainder.rounded(.towardZero)
        remainder -= whole
        let delta = Int(whole)

        if momentum.hasStopped(velocity: velocity) && (state == .coasting || state == .settling) {
            return finish(trailingDelta: delta)
        }

        if delta == 0 && streamHasOpened { return nil }

        let phase: GesturePhase
        let momentumPhase: MomentumPhase
        if state == .coasting {
            phase = .none
            momentumPhase = streamHasOpened ? .`continue` : .begin
        } else {
            phase = gestureIsOpen ? .changed : .began
            momentumPhase = .none
            gestureIsOpen = true
        }
        streamHasOpened = true

        return Frame(delta: delta, phase: phase, momentumPhase: momentumPhase, isFinal: false)
    }

    /// Ends the gesture immediately — used when input stops with momentum off,
    /// when a coast decays out, and when the host cancels (focus loss, sleep).
    @discardableResult
    public func finish(trailingDelta: Int = 0) -> Frame {
        let wasCoasting = state == .coasting
        let hadOpenGesture = gestureIsOpen

        state = .idle
        velocity = 0
        remainder = 0
        lastFrameTime = nil
        streamHasOpened = false
        gestureIsOpen = false
        needsMomentumEnd = false
        detector.reset()

        // A coast that decays out ends its momentum stream; a gesture that
        // settles ends the gesture itself. Sending the wrong one leaves views
        // stuck believing a finger is still down.
        return Frame(
            delta: wasCoasting ? trailingDelta : 0,
            phase: wasCoasting ? .none : (hadOpenGesture ? .ended : .none),
            momentumPhase: wasCoasting ? .end : .none,
            isFinal: true
        )
    }

    /// Drops everything in flight without emitting. For app switches and sleep,
    /// where the target view is going away anyway.
    public func reset() {
        state = .idle
        velocity = 0
        remainder = 0
        lastFrameTime = nil
        streamHasOpened = false
        gestureIsOpen = false
        needsMomentumEnd = false
        detector.reset()
    }
}
