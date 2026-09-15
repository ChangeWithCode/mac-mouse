import Foundation

/// Phase of a continuous scroll gesture.
///
/// Raw values match `NSEvent.Phase`, because they are written straight into the
/// synthesized scroll events that AppKit and every scrollable view read. Getting
/// the phase sequence right is the whole reason Glide's scrolling feels like a
/// trackpad instead of a fast mouse wheel: a view only engages pixel-precise
/// scrolling, overscroll and rubber-band bounce when it sees a well-formed
/// `began → changed… → ended` run.
public enum GesturePhase: UInt32, Sendable, Hashable {
    case none = 0
    case began = 1
    case stationary = 2
    case changed = 4
    case ended = 8
    case cancelled = 16
    case mayBegin = 32
}

/// Phase of the momentum tail that follows a released gesture.
///
/// Raw values match `NSEvent.Phase`'s momentum counterpart. Views use this to
/// decide when to bounce: an overscroll during `none` is the user's finger and
/// resists, the same overscroll during a momentum phase triggers the rubber band.
public enum MomentumPhase: UInt32, Sendable, Hashable {
    case none = 0
    case begin = 1
    case `continue` = 2
    case end = 3
}
