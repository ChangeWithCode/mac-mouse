import Foundation

/// What a user physically did with one or more buttons.
///
/// Triggers are the left-hand side of a binding: a trigger plus an action is a
/// rule. Chords (several buttons at once) are first-class rather than bolted on,
/// which is what lets a three-button mouse carry a dozen bindings.
public struct ButtonTrigger: Hashable, Codable, Sendable {

    public enum Kind: Hashable, Codable, Sendable {
        /// Pressed and released `count` times in quick succession.
        case click(count: Int)
        /// Held down past the hold threshold.
        case hold
        /// Held down and moved — the gesture behind "Scroll & Navigate".
        case drag
    }

    /// The buttons involved. More than one makes it a chord.
    public var buttons: Set<MouseButton>
    public var kind: Kind

    public init(buttons: Set<MouseButton>, kind: Kind) {
        self.buttons = buttons
        self.kind = kind
    }

    public init(_ button: MouseButton, _ kind: Kind) {
        self.init(buttons: [button], kind: kind)
    }

    public var isChord: Bool { buttons.count > 1 }

    /// Buttons in a stable order, for display and for deterministic encoding.
    public var orderedButtons: [MouseButton] { buttons.sorted() }

    public var displayName: String {
        let names = orderedButtons.map(\.displayName).joined(separator: " + ")
        switch kind {
        case .click(1): return names
        case .click(2): return "Double-click \(names)"
        case .click(3): return "Triple-click \(names)"
        case .click(let n): return "\(n)x click \(names)"
        case .hold: return "Hold \(names)"
        case .drag: return "Drag \(names)"
        }
    }

    /// How specific this trigger is, used to break ties when two could match.
    ///
    /// A chord always beats a single button, and within the same button count a
    /// longer gesture beats a shorter one — otherwise a double-click binding
    /// could never fire, because the single-click rule would always match first.
    public var specificity: Int {
        var score = buttons.count * 100
        switch kind {
        case .click(let n): score += n
        case .hold: score += 50
        case .drag: score += 60
        }
        return score
    }
}
