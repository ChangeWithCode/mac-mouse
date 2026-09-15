import AppKit
import CoreGraphics
import Foundation
import GlideCore

/// Posts synthetic keyboard events.
public enum KeyboardSynthesizer {

    private static let source = CGEventSource(stateID: .privateState)

    /// Sends a key down followed by a key up.
    public static func send(_ stroke: Keystroke) {
        press(stroke)
        release(stroke)
    }

    public static func press(_ stroke: Keystroke) {
        guard let event = CGEvent(keyboardEventSource: source, virtualKey: stroke.keyCode, keyDown: true) else { return }
        event.flags = CGEventFlags(rawValue: stroke.modifiers.rawValue)
        event.post(tap: .cgAnnotatedSessionEventTap)
    }

    public static func release(_ stroke: Keystroke) {
        guard let event = CGEvent(keyboardEventSource: source, virtualKey: stroke.keyCode, keyDown: false) else { return }
        event.flags = CGEventFlags(rawValue: stroke.modifiers.rawValue)
        event.post(tap: .cgAnnotatedSessionEventTap)
    }

    /// Types a literal string.
    ///
    /// Sent as UTF-16 rather than resolved to key codes, so it is independent of
    /// the active keyboard layout — the same macro types the same characters on
    /// a Dvorak or AZERTY layout.
    public static func type(_ string: String) {
        for chunk in string.chunked(into: 16) {
            guard let event = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: true) else { continue }
            var utf16 = Array(chunk.utf16)
            event.keyboardSetUnicodeString(stringLength: utf16.count, unicodeString: &utf16)
            event.post(tap: .cgAnnotatedSessionEventTap)

            guard let up = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: false) else { continue }
            up.keyboardSetUnicodeString(stringLength: utf16.count, unicodeString: &utf16)
            up.post(tap: .cgAnnotatedSessionEventTap)
        }
    }
}

/// Posts synthetic mouse clicks.
public enum MouseSynthesizer {

    private static let source = CGEventSource(stateID: .privateState)

    public static func click(_ button: CGMouseButton) {
        let location = CGEvent(source: nil)?.location ?? .zero
        let (down, up): (CGEventType, CGEventType)
        switch button {
        case .left:   (down, up) = (.leftMouseDown, .leftMouseUp)
        case .right:  (down, up) = (.rightMouseDown, .rightMouseUp)
        default:      (down, up) = (.otherMouseDown, .otherMouseUp)
        }
        for type in [down, up] {
            guard let event = CGEvent(mouseEventSource: source, mouseType: type, mouseCursorPosition: location, mouseButton: button) else { continue }
            event.setIntegerValueField(.eventSourceUserData, value: ScrollEventSynthesizer.signature)
            event.post(tap: .cgSessionEventTap)
        }
    }
}

/// Keyboard shortcuts macOS listens for system-wide.
///
/// See the note on `ActionDispatcher`: synthesizing these is the supported way
/// to reach features that expose no API, at the cost of depending on the
/// shortcut still being enabled.
public struct SystemShortcut {
    public let stroke: Keystroke
    public let settingsName: String

    public func send() { KeyboardSynthesizer.send(stroke) }

    public static let missionControl = SystemShortcut(
        stroke: Keystroke(keyCode: 0x7E, modifiers: .control), settingsName: "Mission Control")
    public static let applicationWindows = SystemShortcut(
        stroke: Keystroke(keyCode: 0x7D, modifiers: .control), settingsName: "Application windows")
    public static let showDesktop = SystemShortcut(
        stroke: Keystroke(keyCode: 0x67, modifiers: []), settingsName: "Show Desktop")
    public static let spaceLeft = SystemShortcut(
        stroke: Keystroke(keyCode: 0x7B, modifiers: .control), settingsName: "Move left a space")
    public static let spaceRight = SystemShortcut(
        stroke: Keystroke(keyCode: 0x7C, modifiers: .control), settingsName: "Move right a space")
    public static let spotlight = SystemShortcut(
        stroke: Keystroke(keyCode: 0x31, modifiers: .command), settingsName: "Show Spotlight search")
    public static let notificationCentre = SystemShortcut(
        stroke: Keystroke(keyCode: 0x91, modifiers: []), settingsName: "Notification Centre")
    public static let lockScreen = SystemShortcut(
        stroke: Keystroke(keyCode: 0x0C, modifiers: [.command, .control]), settingsName: "Lock Screen")
}

/// Media and hardware keys, which travel as `NSEvent` system-defined events
/// rather than ordinary key codes.
public struct MediaKey {
    public let code: Int32

    public static let soundUp = MediaKey(code: 0)
    public static let soundDown = MediaKey(code: 1)
    public static let brightnessUp = MediaKey(code: 2)
    public static let brightnessDown = MediaKey(code: 3)
    public static let mute = MediaKey(code: 7)
    public static let play = MediaKey(code: 16)
    public static let next = MediaKey(code: 17)
    public static let previous = MediaKey(code: 18)

    public func send() {
        post(down: true)
        post(down: false)
    }

    private func post(down: Bool) {
        // Subtype 8 is NX_SUBTYPE_AUX_CONTROL_BUTTONS. data1 packs the key code
        // and its state into the layout the window server expects.
        let data1 = Int((code << 16) | ((down ? 0x0A : 0x0B) << 8))
        guard let event = NSEvent.otherEvent(
            with: .systemDefined,
            location: .zero,
            modifierFlags: NSEvent.ModifierFlags(rawValue: 0xA00),
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            subtype: 8,
            data1: data1,
            data2: -1
        ) else { return }
        event.cgEvent?.post(tap: .cgSessionEventTap)
    }
}

private extension String {
    /// Unicode strings are posted in chunks; a single event has a practical
    /// limit well below an arbitrarily long macro string.
    func chunked(into size: Int) -> [String] {
        guard count > size else { return [self] }
        var result: [String] = []
        var index = startIndex
        while index < endIndex {
            let end = self.index(index, offsetBy: size, limitedBy: endIndex) ?? endIndex
            result.append(String(self[index..<end]))
            index = end
        }
        return result
    }
}
