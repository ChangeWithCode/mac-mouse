import Foundation

/// A physical mouse button, identified by its platform button number.
///
/// Modelled as a wrapped integer rather than an enum because gaming mice
/// routinely expose a dozen or more buttons and an enum would have to guess
/// where to stop. The common ones get names; the rest render as "Button 9".
public struct MouseButton: Hashable, Codable, Sendable, Comparable, Identifiable {

    public let number: Int
    public var id: Int { number }

    public init(_ number: Int) { self.number = max(0, number) }

    public static let left = MouseButton(0)
    public static let right = MouseButton(1)
    public static let middle = MouseButton(2)
    /// Thumb button, the one nearest the wrist. macOS calls it button 4.
    public static let back = MouseButton(3)
    /// Thumb button, the one nearest the fingertips.
    public static let forward = MouseButton(4)

    /// Buttons Glide will happily take over.
    ///
    /// Left and right are deliberately absent: remapping them is a foot-gun that
    /// can leave someone unable to click "undo" in the very app that did it.
    /// They can still take part in a chord as modifiers.
    public static let remappable: [MouseButton] = [.middle, .back, .forward] + (5...15).map(MouseButton.init)

    public var isRemappable: Bool { number >= 2 }

    public var displayName: String {
        switch number {
        case 0: return "Left Button"
        case 1: return "Right Button"
        case 2: return "Middle Button"
        case 3: return "Button 4"
        case 4: return "Button 5"
        default: return "Button \(number + 1)"
        }
    }

    /// Short form for tight spaces such as the binding list.
    public var shortName: String {
        switch number {
        case 0: return "L"
        case 1: return "R"
        case 2: return "M"
        default: return "\(number + 1)"
        }
    }

    public static func < (lhs: MouseButton, rhs: MouseButton) -> Bool { lhs.number < rhs.number }
}
