import Foundation

/// A unit cubic Bézier with implied endpoints `(0,0)` and `(1,1)`, matching the
/// semantics of CSS `cubic-bezier(x1, y1, x2, y2)`.
///
/// Used for two different jobs in Glide: shaping the acceleration curve that maps
/// wheel cadence to scroll distance, and shaping the ease applied to a single
/// discrete step. Both are user-editable in the UI, which is why the shape is a
/// Bézier rather than a hardcoded exponent — the curve editor manipulates these
/// four numbers directly.
///
/// The reference implementation and its test suite live in
/// `Tools/physics-lab/`; keep the two in sync.
public struct UnitBezier: Hashable, Sendable, Codable {

    /// Control point coordinates. These are the entire user-facing state.
    public let x1: Double
    public let y1: Double
    public let x2: Double
    public let y2: Double

    // Polynomial coefficients, derived once at init. B(t) = ((a*t + b)*t + c)*t
    private let ax: Double, bx: Double, cx: Double
    private let ay: Double, by: Double, cy: Double

    public init(_ x1: Double, _ y1: Double, _ x2: Double, _ y2: Double) {
        // x control points outside [0,1] make the curve non-monotonic in x, which
        // would make the inverse ambiguous. y is free to overshoot for bounce.
        let cx1 = min(max(x1, 0), 1)
        let cx2 = min(max(x2, 0), 1)

        self.x1 = cx1; self.y1 = y1
        self.x2 = cx2; self.y2 = y2

        self.cx = 3.0 * cx1
        self.bx = 3.0 * (cx2 - cx1) - self.cx
        self.ax = 1.0 - self.cx - self.bx

        self.cy = 3.0 * y1
        self.by = 3.0 * (y2 - y1) - self.cy
        self.ay = 1.0 - self.cy - self.by
    }

    // MARK: - Sampling

    @inlinable
    public func sampleX(_ t: Double) -> Double { ((ax * t + bx) * t + cx) * t }

    @inlinable
    public func sampleY(_ t: Double) -> Double { ((ay * t + by) * t + cy) * t }

    @inlinable
    public func sampleDerivativeX(_ t: Double) -> Double { (3.0 * ax * t + 2.0 * bx) * t + cx }

    // MARK: - Inversion

    /// Inverts `x = sampleX(t)` for `t`.
    ///
    /// Newton-Raphson first: it converges quadratically and typically lands in
    /// three or four iterations. Where the derivative collapses toward zero —
    /// `cubic-bezier(1, 0, 0, 1)` is exactly flat at `t = 0.5` — Newton either
    /// stalls or steps outside `[0, 1]`, so we hand over to bisection.
    ///
    /// Bisection converges the *bracket* rather than returning as soon as `x`
    /// lands within `epsilon`. Inverting a near-constant function is
    /// ill-conditioned: a satisfied `x` tolerance can still leave `t` wrong in
    /// the fifth decimal. Sixty halvings pin `t` as tightly as a `Double`
    /// allows and cost nothing at the once-per-frame rate this runs at.
    public func solveT(_ x: Double, epsilon: Double = 1e-9) -> Double {
        if x <= 0 { return 0 }
        if x >= 1 { return 1 }

        var t = x  // a good initial guess for a near-diagonal curve
        for _ in 0..<8 {
            let error = sampleX(t) - x
            if abs(error) < epsilon { return t }
            let derivative = sampleDerivativeX(t)
            if abs(derivative) < 1e-6 { break }  // too flat — bisect instead
            t -= error / derivative
        }

        var low = 0.0
        var high = 1.0
        t = x
        var iteration = 0
        while iteration < 60 && (high - low) > 1e-15 {
            if x > sampleX(t) { low = t } else { high = t }
            t = (high + low) * 0.5
            iteration += 1
        }
        return t
    }

    /// The easing function proper: maps progress `0...1` to eased `0...1`.
    public func evaluate(_ x: Double, epsilon: Double = 1e-9) -> Double {
        sampleY(solveT(x, epsilon: epsilon))
    }

    // MARK: - Presets

    public static let linear = UnitBezier(0.0, 0.0, 1.0, 1.0)
    public static let ease = UnitBezier(0.25, 0.1, 0.25, 1.0)
    public static let easeIn = UnitBezier(0.42, 0.0, 1.0, 1.0)
    public static let easeOut = UnitBezier(0.0, 0.0, 0.58, 1.0)
    public static let easeInOut = UnitBezier(0.42, 0.0, 0.58, 1.0)

    // MARK: - Codable / Hashable
    //
    // Only the control points are persisted; the coefficients are recomputed on
    // decode. Equality and hashing follow the control points for the same reason
    // — the derived fields carry no independent information.

    private enum CodingKeys: String, CodingKey { case x1, y1, x2, y2 }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            try container.decode(Double.self, forKey: .x1),
            try container.decode(Double.self, forKey: .y1),
            try container.decode(Double.self, forKey: .x2),
            try container.decode(Double.self, forKey: .y2)
        )
    }

    public static func == (lhs: UnitBezier, rhs: UnitBezier) -> Bool {
        lhs.x1 == rhs.x1 && lhs.y1 == rhs.y1 && lhs.x2 == rhs.x2 && lhs.y2 == rhs.y2
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(x1); hasher.combine(y1); hasher.combine(x2); hasher.combine(y2)
    }
}
