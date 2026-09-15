import Foundation

/// Tells a deliberate nudge apart from a flick of a free-spinning wheel.
///
/// A wheel reports identical notches either way; the only signal is cadence. We
/// keep a short rolling window of inter-tick intervals and declare a free spin
/// once the cadence has held above a threshold for several consecutive ticks —
/// consecutive, so that one accidental fast pair during careful scrolling cannot
/// launch the page.
public struct FreeSpinDetector: Sendable {

    /// Ticks/second at or above which a tick counts as "fast".
    public var speedThreshold: Double
    /// How many consecutive fast ticks are needed before a spin is declared.
    public var requiredTicks: Int
    /// How many intervals to average when computing cadence.
    public var windowSize: Int
    /// A gap longer than this means the user let go; the window resets.
    public var resetInterval: Double

    private var intervals: [Double] = []
    private var lastTimestamp: Double?
    private var consecutiveFast: Int = 0

    /// Whether the wheel is currently being spun freely.
    public private(set) var isSpinning: Bool = false

    public init(
        speedThreshold: Double = 14.0,
        requiredTicks: Int = 3,
        windowSize: Int = 5,
        resetInterval: Double = 0.25
    ) {
        self.speedThreshold = speedThreshold
        self.requiredTicks = requiredTicks
        self.windowSize = windowSize
        self.resetInterval = resetInterval
    }

    /// Feeds one wheel tick. Returns whether this tick is part of a free spin.
    @discardableResult
    public mutating func register(timestamp: Double) -> Bool {
        if let last = lastTimestamp {
            let gap = timestamp - last
            if gap > resetInterval {
                reset()
            } else {
                intervals.append(gap)
                if intervals.count > windowSize { intervals.removeFirst() }
            }
        }
        lastTimestamp = timestamp

        if currentSpeed >= speedThreshold {
            consecutiveFast += 1
        } else {
            consecutiveFast = 0
        }
        isSpinning = consecutiveFast >= requiredTicks
        return isSpinning
    }

    /// Smoothed cadence in ticks/second across the rolling window.
    ///
    /// Zero until a second tick arrives — a lone tick has no cadence, and
    /// guessing one would make the first notch of every scroll unpredictable.
    public var currentSpeed: Double {
        guard !intervals.isEmpty else { return 0 }
        let mean = intervals.reduce(0, +) / Double(intervals.count)
        return mean > 0 ? 1.0 / mean : 0
    }

    public mutating func reset() {
        intervals.removeAll(keepingCapacity: true)
        consecutiveFast = 0
        isSpinning = false
    }
}
