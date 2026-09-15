import CoreVideo
import Foundation
import os.log

/// Drives animation at the display's refresh rate.
///
/// Scroll frames are generated here rather than on a timer so that motion lands
/// in step with the compositor. A 60Hz timer against a 120Hz display produces
/// visible unevenness that no amount of physics tuning can hide.
///
/// The callback runs on a high-priority thread owned by CoreVideo, *not* the
/// main thread. That is deliberate — hopping to main to post each frame adds a
/// frame of latency and lets scroll events coalesce behind UI work. Callers are
/// responsible for their own synchronisation; `ScrollCoordinator` takes a lock
/// around the small amount of state it shares.
public final class DisplayLink {

    private let log = Logger(subsystem: "com.glide.app", category: "DisplayLink")
    private var link: CVDisplayLink?
    private let onFrame: (Double) -> Void

    public private(set) var isRunning = false

    /// - Parameter onFrame: Called once per refresh with the current monotonic
    ///   time. Runs off the main thread.
    public init(onFrame: @escaping (Double) -> Void) {
        self.onFrame = onFrame
    }

    deinit { stop() }

    public func start() {
        guard !isRunning else { return }

        if link == nil {
            var created: CVDisplayLink?
            // NOTE: CVDisplayLink is soft-deprecated in favour of CADisplayLink,
            // which is only available from macOS 14 and is tied to an NSView or
            // NSWindow. Glide's scroll engine is headless and supports macOS 13,
            // so CVDisplayLink remains the right tool here.
            guard CVDisplayLinkCreateWithActiveCGDisplays(&created) == kCVReturnSuccess,
                  let displayLink = created else {
                log.error("Could not create a display link; scrolling will not animate")
                return
            }

            let result = CVDisplayLinkSetOutputHandler(displayLink) { [weak self] _, _, _, _, _ in
                self?.onFrame(MonotonicClock.now)
                return kCVReturnSuccess
            }
            guard result == kCVReturnSuccess else {
                log.error("Could not attach the display link output handler")
                return
            }
            link = displayLink
        }

        guard let link else { return }
        CVDisplayLinkStart(link)
        isRunning = true
    }

    /// Stops the link. Called the moment scrolling settles: leaving it running
    /// wakes the CPU at the refresh rate forever and is plainly visible in
    /// Activity Monitor and in battery life.
    public func stop() {
        guard let link, isRunning else { return }
        CVDisplayLinkStop(link)
        isRunning = false
    }
}
