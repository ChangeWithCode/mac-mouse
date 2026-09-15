import Foundation

/// A recorded or hand-built sequence of steps bound to a single trigger.
public struct Macro: Identifiable, Hashable, Codable, Sendable {

    public enum Step: Hashable, Codable, Sendable {
        /// Press and release a key.
        case key(Keystroke)
        /// Hold a key down, to be released by a later `keyUp`.
        case keyDown(Keystroke)
        case keyUp(Keystroke)
        /// Type a literal string. Layout-independent — the characters are sent
        /// as unicode rather than resolved to key codes.
        case text(String)
        /// Wait before continuing.
        case delay(seconds: Double)
        /// Click a mouse button at the current pointer position.
        case click(MouseButton)
        /// Move the pointer. Absolute unless `relative` is set.
        case move(x: Double, y: Double, relative: Bool)

        public var displayName: String {
            switch self {
            case .key(let k): return "Press \(k.displayName)"
            case .keyDown(let k): return "Hold \(k.displayName)"
            case .keyUp(let k): return "Release \(k.displayName)"
            case .text(let s): return "Type \"\(s.count > 24 ? String(s.prefix(24)) + "…" : s)\""
            case .delay(let s): return String(format: "Wait %.2fs", s)
            case .click(let b): return "Click \(b.displayName)"
            case .move(let x, let y, let relative):
                return relative ? "Move by (\(Int(x)), \(Int(y)))" : "Move to (\(Int(x)), \(Int(y)))"
            }
        }
    }

    public var id: UUID
    public var name: String
    public var steps: [Step]

    /// Repeat the whole sequence while the trigger is held. Useful for things
    /// like a rapid-fire click or a held arrow key.
    public var repeatsWhileHeld: Bool

    /// Gap between repeats when `repeatsWhileHeld` is on.
    public var repeatInterval: Double

    public init(
        id: UUID = UUID(),
        name: String,
        steps: [Step] = [],
        repeatsWhileHeld: Bool = false,
        repeatInterval: Double = 0.1
    ) {
        self.id = id
        self.name = name
        self.steps = steps
        self.repeatsWhileHeld = repeatsWhileHeld
        self.repeatInterval = repeatInterval
    }

    /// Total time the macro takes, ignoring repeats. Shown in the editor so a
    /// macro with an accidental five-second delay is obvious at a glance.
    public var duration: Double {
        steps.reduce(0) { total, step in
            if case .delay(let seconds) = step { return total + seconds }
            return total + 0.008  // nominal cost of dispatching one event
        }
    }
}
