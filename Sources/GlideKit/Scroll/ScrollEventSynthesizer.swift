import CoreGraphics
import Foundation

/// Posts scroll events that macOS treats as coming from a trackpad.
///
/// This is what actually makes Glide's scrolling feel different. A mouse wheel
/// produces *line*-based, non-continuous events, and views respond to those with
/// a discrete jump. A trackpad produces pixel-precise continuous events carrying
/// a gesture phase, and views respond to *those* with smooth scrolling,
/// overscroll and rubber-band bounce. Same API, entirely different feel.
///
/// The phase fields are not exposed in `CGEventField`, so they are addressed by
/// their documented raw values. They have been stable since the first trackpad
/// shipped, and every tool in this category relies on them.
public enum ScrollEventSynthesizer {

    /// `kCGScrollWheelEventScrollPhase`
    private static let scrollPhaseField = CGEventField(rawValue: 99)!
    /// `kCGScrollWheelEventMomentumPhase`
    private static let momentumPhaseField = CGEventField(rawValue: 123)!
    /// `kCGScrollWheelEventScrollCount`
    private static let scrollCountField = CGEventField(rawValue: 100)!

    /// A private event source, so Glide's own events are distinguishable from
    /// the user's. Without this the tap would re-process everything it posts and
    /// scroll forever.
    private static let source: CGEventSource? = {
        let source = CGEventSource(stateID: .privateState)
        // Glide's synthetic events must not feed macOS's own pointer
        // acceleration — that would compound with our acceleration curve.
        source?.setLocalEventsFilterDuringSuppressionState(
            [.permitLocalMouseEvents, .permitLocalKeyboardEvents],
            state: .eventSuppressionStateSuppressionInterval
        )
        return source
    }()

    /// Marker written into every event Glide posts, so the tap can recognise and
    /// ignore its own output.
    public static let signature: Int64 = 0x474C4944  // "GLID"
    private static let signatureField = CGEventField.eventSourceUserData

    /// Posts one scroll frame.
    ///
    /// - Parameters:
    ///   - deltaY: Vertical movement in points. Positive scrolls content down.
    ///   - deltaX: Horizontal movement in points.
    ///   - phase: Gesture phase. A view needs a well-formed `began → changed →
    ///     ended` run before it will scroll smoothly.
    ///   - momentumPhase: Momentum phase, for the coast after release.
    public static func post(
        deltaY: Int,
        deltaX: Int = 0,
        phase: GesturePhaseValue,
        momentumPhase: MomentumPhaseValue
    ) {
        // `units: .pixel` is what marks this as trackpad-style rather than
        // wheel-style; wheel1 is vertical, wheel2 horizontal.
        guard let event = CGEvent(
            scrollWheelEvent2Source: source,
            units: .pixel,
            wheelCount: 2,
            wheel1: Int32(clamping: deltaY),
            wheel2: Int32(clamping: deltaX),
            wheel3: 0
        ) else {
            Diagnostics.trace("synth.failed", "CGEvent could not be created")
            return
        }

        event.setIntegerValueField(.scrollWheelEventIsContinuous, value: 1)
        event.setIntegerValueField(.scrollWheelEventPointDeltaAxis1, value: Int64(deltaY))
        event.setIntegerValueField(.scrollWheelEventPointDeltaAxis2, value: Int64(deltaX))
        event.setIntegerValueField(scrollPhaseField, value: Int64(phase.rawValue))
        event.setIntegerValueField(momentumPhaseField, value: Int64(momentumPhase.rawValue))
        event.setIntegerValueField(signatureField, value: signature)

        // Views use scroll count to distinguish a deliberate gesture from
        // stray movement; a phase-carrying gesture should always report one.
        if phase != .none { event.setIntegerValueField(scrollCountField, value: 1) }

        event.post(tap: .cgSessionEventTap)
    }

    /// Whether an event was posted by Glide, so the tap can pass its own work
    /// through instead of reprocessing it into an infinite loop.
    public static func isSynthetic(_ event: CGEvent) -> Bool {
        event.getIntegerValueField(signatureField) == signature
    }

    /// Whether an incoming wheel event already carries gesture or momentum
    /// phases — macOS's own inertial continuation of a wheel flick, or a driver
    /// that emits phased output. Re-ingesting those injects a second impulse
    /// into a coast that is already running; Glide rewrites only plain,
    /// unphased, non-continuous wheel ticks.
    public static func carriesPhase(_ event: CGEvent) -> Bool {
        event.getIntegerValueField(scrollPhaseField) != 0
            || event.getIntegerValueField(momentumPhaseField) != 0
    }

    /// Mirrors `GlideCore.GesturePhase`, kept separate so GlideCore stays free
    /// of CoreGraphics.
    public enum GesturePhaseValue: UInt32 {
        case none = 0, began = 1, stationary = 2, changed = 4, ended = 8, cancelled = 16, mayBegin = 32
    }

    public enum MomentumPhaseValue: UInt32 {
        case none = 0, begin = 1, `continue` = 2, end = 3
    }
}
