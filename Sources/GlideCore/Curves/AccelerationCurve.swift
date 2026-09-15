import Foundation

/// Maps wheel cadence (ticks per second) to scroll distance (points per tick).
///
/// This is the single most important curve in the app. A mouse wheel reports
/// identical notches whether you are nudging one line or spinning to the bottom
/// of a file; the only thing distinguishing the two is how fast the notches
/// arrive. Turning that cadence into distance is what makes a cheap wheel feel
/// either precise or hopelessly twitchy.
///
/// Slow cadence maps to `minDistance` so a single deliberate notch always moves
/// the same, predictable amount. Fast cadence maps to `maxDistance`. The shape
/// in between is a user-editable Bézier.
public struct AccelerationCurve: Hashable, Sendable, Codable {

    /// Cadence at or below which every tick moves exactly `minDistance`.
    public var minSpeed: Double
    /// Cadence at or above which every tick moves exactly `maxDistance`.
    public var maxSpeed: Double
    /// Distance in points for one tick at the slow end.
    public var minDistance: Double
    /// Distance in points for one tick at the fast end.
    public var maxDistance: Double
    /// Shape of the ramp between the two anchors.
    public var shape: UnitBezier

    public init(
        minSpeed: Double,
        maxSpeed: Double,
        minDistance: Double,
        maxDistance: Double,
        shape: UnitBezier
    ) {
        self.minSpeed = minSpeed
        self.maxSpeed = maxSpeed
        self.minDistance = minDistance
        self.maxDistance = maxDistance
        self.shape = shape
    }

    /// Points to travel for a single wheel tick arriving at `speed` ticks/second.
    ///
    /// Clamped at both ends, so an absurd cadence from a free-spinning wheel can
    /// never produce an absurd jump.
    public func distance(atSpeed speed: Double) -> Double {
        let span = maxSpeed - minSpeed
        // A degenerate range collapses to the slow anchor rather than dividing by zero.
        guard span > 0 else { return minDistance }

        let progress = min(max((speed - minSpeed) / span, 0), 1)
        return minDistance + shape.evaluate(progress) * (maxDistance - minDistance)
    }

    /// True when the curve applies no acceleration at all — every tick is equal.
    public var isFlat: Bool { minDistance == maxDistance }
}
