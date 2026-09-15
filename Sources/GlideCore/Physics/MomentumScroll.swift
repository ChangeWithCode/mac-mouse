import Foundation

/// Exponential-decay momentum, integrated exactly.
///
/// Velocity follows `v(t) = v₀·e^(-kt)`, which is chosen over the more common
/// per-frame `v *= 0.95` for three reasons:
///
/// 1. It is frame-rate independent. A 120Hz display, a 60Hz display and a frame
///    dropped under load all produce identical motion, because `dt` enters the
///    exponent rather than the iteration count.
/// 2. It integrates in closed form, so the UI can state how far a fling will
///    reach before the first frame is drawn.
/// 3. Its per-frame integral is *also* closed form, so stepping introduces no
///    numerical drift at all.
///
/// That last point matters more than it sounds. Integrating the frame with a
/// trapezoid — the obvious choice — over-estimates a convex curve, drifting
/// roughly 0.7pt on a hard fling at 60Hz and considerably more at 30Hz, and it
/// lets the accumulated distance exceed the advertised total. The exact form is
/// both correct and cheaper. See `Tools/physics-lab/spec.js`.
public struct MomentumScroll: Sendable, Hashable {

    /// Decay constant `k`, in units of 1/second. Larger stops sooner.
    public var friction: Double
    /// Velocity in points/second below which motion is considered finished.
    public var stopThreshold: Double

    public init(friction: Double, stopThreshold: Double = 8.0) {
        self.friction = friction
        self.stopThreshold = stopThreshold
    }

    /// One display-link frame.
    ///
    /// The integral of the decay across the frame is itself closed form:
    ///
    ///     ∫₀^dt v·e^(-kt) dt = (v - v') / k
    ///
    /// so the delta is taken directly instead of approximated.
    public func step(velocity: Double, deltaTime: Double) -> (velocity: Double, delta: Double) {
        guard friction > 0 else { return (velocity, velocity * deltaTime) }
        let next = velocity * exp(-friction * deltaTime)
        return (next, (velocity - next) / friction)
    }

    /// Total points a fling at `velocity` covers before crossing `stopThreshold`.
    public func projectedDistance(velocity: Double) -> Double {
        guard friction > 0 else { return .infinity }
        let magnitude = abs(velocity)
        guard magnitude > stopThreshold else { return 0 }
        return (magnitude - stopThreshold) / friction * (velocity < 0 ? -1 : 1)
    }

    /// Seconds until a fling at `velocity` crosses `stopThreshold`.
    public func projectedDuration(velocity: Double) -> Double {
        guard friction > 0 else { return .infinity }
        let magnitude = abs(velocity)
        guard magnitude > stopThreshold else { return 0 }
        return log(magnitude / stopThreshold) / friction
    }

    /// The launch velocity needed to travel exactly `distance` points.
    ///
    /// The inverse of `projectedDistance`, and the key to the whole engine: it
    /// lets a wheel tick that "should move 48 points" be expressed as an impulse,
    /// so momentum and discrete stepping become the same mechanism.
    public func velocityToTravel(_ distance: Double) -> Double {
        distance * friction
    }

    public func hasStopped(velocity: Double) -> Bool { abs(velocity) < stopThreshold }
}
