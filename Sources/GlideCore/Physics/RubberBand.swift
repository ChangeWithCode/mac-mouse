import Foundation

/// Overscroll resistance matching the feel of AppKit's rubber band.
///
/// Glide only applies this itself when it is driving a surface that does not
/// implement its own bounce — the "Scroll & Navigate" cursor overlay, and the
/// preview strip in the curve editor. Ordinary scrolling hands well-formed
/// momentum-phase events to the app and lets the app bounce natively.
public enum RubberBand {

    /// Apple's resistance curve, empirically `c ≈ 0.55`.
    public static let defaultCoefficient = 0.55

    /// Damps a raw overscroll `offset` against a soft `limit`.
    ///
    ///     d = (1 - 1/(c·x/L + 1))·L
    ///
    /// The reciprocal gives the characteristic stiffening — every additional
    /// point of pull yields strictly less movement than the last — and the
    /// result approaches `limit` asymptotically, so no amount of force can tear
    /// the content off its edge.
    public static func damp(
        offset: Double,
        limit: Double,
        coefficient: Double = defaultCoefficient
    ) -> Double {
        guard limit > 0 else { return 0 }
        let sign: Double = offset < 0 ? -1 : 1
        let magnitude = abs(offset)
        return sign * (1.0 - 1.0 / ((coefficient * magnitude / limit) + 1.0)) * limit
    }
}
