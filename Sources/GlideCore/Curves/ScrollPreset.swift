import Foundation

/// A complete, named scrolling feel: how far a tick travels, and how a fling decays.
///
/// Presets are a starting point, not a cage — every field is editable, and doing
/// so simply produces a preset with a `custom` identity.
public struct ScrollPreset: Identifiable, Hashable, Sendable, Codable {

    public var id: String
    public var name: String
    /// One-line description, shown under the preset name in the picker.
    public var blurb: String

    /// Cadence-to-distance mapping.
    public var acceleration: AccelerationCurve

    /// Exponential decay constant `k` for momentum, in units of 1/second.
    ///
    /// Total coast distance is exactly `v0 / k` and time to a standstill is
    /// `ln(v0 / stopThreshold) / k`, which is what lets the UI state a fling's
    /// reach before a single frame is drawn.
    public var friction: Double

    /// Velocity in points/second below which a fling is considered finished.
    ///
    /// Held around 8 rather than 0: below that the motion is under a seventh of
    /// a point per frame, invisible, and merely delays the end-of-gesture event
    /// that lets the scrolled view settle.
    public var stopThreshold: Double

    /// When false, releasing the wheel stops the content immediately.
    public var momentumEnabled: Bool

    public init(
        id: String,
        name: String,
        blurb: String,
        acceleration: AccelerationCurve,
        friction: Double,
        stopThreshold: Double,
        momentumEnabled: Bool
    ) {
        self.id = id
        self.name = name
        self.blurb = blurb
        self.acceleration = acceleration
        self.friction = friction
        self.stopThreshold = stopThreshold
        self.momentumEnabled = momentumEnabled
    }

    /// Points a fling launched at `velocity` will cover before stopping.
    ///
    /// Closed form, not a simulation: the integral of `v0·e^(-kt)` from zero to
    /// the moment velocity crosses `stopThreshold`.
    public func projectedFlingDistance(velocity: Double) -> Double {
        guard momentumEnabled, friction > 0 else { return 0 }
        let v = abs(velocity)
        guard v > stopThreshold else { return 0 }
        return (v - stopThreshold) / friction
    }

    /// Seconds a fling launched at `velocity` will take to settle.
    public func projectedFlingDuration(velocity: Double) -> Double {
        guard momentumEnabled, friction > 0 else { return 0 }
        let v = abs(velocity)
        guard v > stopThreshold else { return 0 }
        return log(v / stopThreshold) / friction
    }

    /// A copy marked as user-modified, so the UI stops claiming it is a built-in.
    public func customized(name: String? = nil) -> ScrollPreset {
        var copy = self
        copy.id = "custom.\(UUID().uuidString)"
        copy.name = name ?? "\(self.name) (Modified)"
        copy.blurb = "Customised from \(self.name)."
        return copy
    }

    /// Whether this preset is one Glide ships, as opposed to a user's own.
    public var isBuiltIn: Bool { !id.hasPrefix("custom.") }
}
