import Foundation

/// A key press with modifiers, used both for "send this shortcut" bindings and
/// as the unit a recorded macro is built from.
public struct Keystroke: Hashable, Codable, Sendable {

    /// Virtual key code (the `kVK_*` constants).
    public var keyCode: UInt16

    /// Modifier flags, mirroring `CGEventFlags` bit positions so the value can
    /// be written straight into a synthesized event without a lookup table.
    public struct Modifiers: OptionSet, Hashable, Codable, Sendable {
        public let rawValue: UInt64
        public init(rawValue: UInt64) { self.rawValue = rawValue }

        public static let capsLock = Modifiers(rawValue: 0x00010000)
        public static let shift    = Modifiers(rawValue: 0x00020000)
        public static let control  = Modifiers(rawValue: 0x00040000)
        public static let option   = Modifiers(rawValue: 0x00080000)
        public static let command  = Modifiers(rawValue: 0x00100000)
        public static let function = Modifiers(rawValue: 0x00800000)

        public var symbolic: String {
            var out = ""
            if contains(.control) { out += "⌃" }
            if contains(.option)  { out += "⌥" }
            if contains(.shift)   { out += "⇧" }
            if contains(.command) { out += "⌘" }
            return out
        }
    }

    public var modifiers: Modifiers

    public init(keyCode: UInt16, modifiers: Modifiers = []) {
        self.keyCode = keyCode
        self.modifiers = modifiers
    }

    public var displayName: String { modifiers.symbolic + Keystroke.keyName(for: keyCode) }

    /// Human-readable name for the keys people actually bind. Anything unmapped
    /// falls back to the raw code rather than guessing at a layout-dependent
    /// character — the same physical key produces different letters on different
    /// keyboard layouts, and a wrong label is worse than an honest number.
    public static func keyName(for code: UInt16) -> String {
        switch code {
        case 0x24: return "Return"
        case 0x30: return "Tab"
        case 0x31: return "Space"
        case 0x33: return "Delete"
        case 0x35: return "Escape"
        case 0x7A: return "F1"
        case 0x78: return "F2"
        case 0x63: return "F3"
        case 0x76: return "F4"
        case 0x60: return "F5"
        case 0x61: return "F6"
        case 0x62: return "F7"
        case 0x64: return "F8"
        case 0x65: return "F9"
        case 0x6D: return "F10"
        case 0x67: return "F11"
        case 0x6F: return "F12"
        case 0x7B: return "←"
        case 0x7C: return "→"
        case 0x7D: return "↓"
        case 0x7E: return "↑"
        case 0x73: return "Home"
        case 0x77: return "End"
        case 0x74: return "Page Up"
        case 0x79: return "Page Down"
        default: return "Key \(code)"
        }
    }
}
