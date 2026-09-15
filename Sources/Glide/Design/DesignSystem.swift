import AppKit
import SwiftUI

/// The visual vocabulary for the whole app.
///
/// Centralised so that spacing, colour and type stay consistent without every
/// view re-deciding them. Values are deliberately few: a small palette used
/// consistently reads as considered, where a large one reads as accidental.
public enum Design {

    // MARK: - Spacing
    //
    // A 4pt base grid. Every inset, gap and padding in the app is one of these.

    public enum Space {
        public static let xs: CGFloat = 4
        public static let sm: CGFloat = 8
        public static let md: CGFloat = 12
        public static let lg: CGFloat = 20
        public static let xl: CGFloat = 32
        public static let xxl: CGFloat = 48
    }

    // MARK: - Radii

    public enum Radius {
        public static let sm: CGFloat = 6
        public static let md: CGFloat = 10
        public static let lg: CGFloat = 16
        public static let pill: CGFloat = 999
    }

    // MARK: - Colour
    //
    // Built on the system's semantic colours so the app follows the user's
    // appearance, accent colour and increased-contrast setting for free. Only
    // the two brand tints are fixed values.

    public enum Palette {
        /// The brand accent — a deep, slightly cool violet.
        public static let accent = Color(red: 0.38, green: 0.36, blue: 0.92)
        /// Secondary accent used for the velocity trace and live readouts.
        public static let signal = Color(red: 0.17, green: 0.74, blue: 0.68)

        public static let surface = Color(nsColor: .controlBackgroundColor)
        public static let elevated = Color(nsColor: .textBackgroundColor)
        public static let separator = Color(nsColor: .separatorColor)
        public static let label = Color(nsColor: .labelColor)
        public static let secondaryLabel = Color(nsColor: .secondaryLabelColor)
        public static let tertiaryLabel = Color(nsColor: .tertiaryLabelColor)

        /// Gradient used on the curve editor and hero surfaces.
        public static let accentGradient = LinearGradient(
            colors: [accent, accent.opacity(0.55), signal.opacity(0.75)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    // MARK: - Typography
    //
    // Rounded for display sizes, the system face for body text. The rounded
    // face at large sizes is what gives the app its friendlier register without
    // straying from the platform.

    public enum Typography {
        public static let display = Font.system(size: 28, weight: .bold, design: .rounded)
        public static let title = Font.system(size: 19, weight: .semibold, design: .rounded)
        public static let heading = Font.system(size: 14, weight: .semibold)
        public static let body = Font.system(size: 13)
        public static let caption = Font.system(size: 11)
        /// Tabular figures, so live numeric readouts do not jitter as digits change.
        public static let readout = Font.system(size: 12, weight: .medium, design: .monospaced)
    }

    // MARK: - Motion

    public enum Motion {
        /// For state changes the user initiated and is watching.
        public static let standard = Animation.spring(response: 0.34, dampingFraction: 0.82)
        /// For incidental changes that should not draw the eye.
        public static let subtle = Animation.easeOut(duration: 0.18)
    }
}

// MARK: - Shared building blocks

/// A titled group of settings. The app's main structural unit.
public struct Card<Content: View>: View {
    private let title: String?
    private let subtitle: String?
    private let content: Content

    public init(_ title: String? = nil, subtitle: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.subtitle = subtitle
        self.content = content()
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: Design.Space.md) {
            if title != nil || subtitle != nil {
                VStack(alignment: .leading, spacing: 2) {
                    if let title {
                        Text(title).font(Design.Typography.heading).foregroundStyle(Design.Palette.label)
                    }
                    if let subtitle {
                        Text(subtitle).font(Design.Typography.caption).foregroundStyle(Design.Palette.secondaryLabel)
                    }
                }
            }
            content
        }
        .padding(Design.Space.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Design.Palette.elevated, in: RoundedRectangle(cornerRadius: Design.Radius.lg, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Design.Radius.lg, style: .continuous)
                .strokeBorder(Design.Palette.separator.opacity(0.6), lineWidth: 1)
        )
    }
}

/// A single labelled control in a card.
public struct SettingRow<Control: View>: View {
    private let title: String
    private let help: String?
    private let control: Control

    public init(_ title: String, help: String? = nil, @ViewBuilder control: () -> Control) {
        self.title = title
        self.help = help
        self.control = control()
    }

    public var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Design.Space.lg) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(Design.Typography.body)
                if let help {
                    Text(help)
                        .font(Design.Typography.caption)
                        .foregroundStyle(Design.Palette.secondaryLabel)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: Design.Space.md)
            control
        }
    }
}

/// Small status pill, used for "Active", "Needs permission" and similar.
public struct StatusPill: View {
    public enum Tone { case positive, neutral, warning, critical }

    private let text: String
    private let tone: Tone

    public init(_ text: String, tone: Tone = .neutral) {
        self.text = text
        self.tone = tone
    }

    private var colour: Color {
        switch tone {
        case .positive: return Design.Palette.signal
        case .neutral:  return Design.Palette.secondaryLabel
        case .warning:  return .orange
        case .critical: return .red
        }
    }

    public var body: some View {
        HStack(spacing: Design.Space.xs) {
            Circle().fill(colour).frame(width: 6, height: 6)
            Text(text).font(Design.Typography.caption).foregroundStyle(colour)
        }
        .padding(.horizontal, Design.Space.sm)
        .padding(.vertical, Design.Space.xs)
        .background(colour.opacity(0.12), in: Capsule())
    }
}
