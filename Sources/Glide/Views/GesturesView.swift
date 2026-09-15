import GlideCore
import SwiftUI

struct GesturesView: View {

    @EnvironmentObject private var state: AppState

    private let gestures: [GlideAction] = [.scrollAndNavigate, .autoScroll, .pinchZoom, .spaceNavigation]

    var body: some View {
        ProfilePane("Gestures", subtitle: "Turn a held button into a trackpad.") {
            Card("Continuous actions", subtitle: "Bind any of these to a button's Drag or Hold gesture.") {
                VStack(spacing: 0) {
                    ForEach(Array(gestures.enumerated()), id: \.offset) { index, gesture in
                        if index > 0 { Divider() }
                        HStack(alignment: .top, spacing: Design.Space.md) {
                            Image(systemName: gesture.symbolName)
                                .font(.system(size: 14))
                                .foregroundStyle(Design.Palette.accent)
                                .frame(width: 26, height: 26)
                                .background(Design.Palette.accent.opacity(0.10), in: RoundedRectangle(cornerRadius: Design.Radius.sm))

                            VStack(alignment: .leading, spacing: 2) {
                                Text(gesture.displayName).font(Design.Typography.body)
                                Text(explanation(for: gesture))
                                    .font(Design.Typography.caption)
                                    .foregroundStyle(Design.Palette.secondaryLabel)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            Spacer()
                            if isBound(gesture) { StatusPill("Bound", tone: .positive) }
                        }
                        .padding(.vertical, Design.Space.md)
                    }
                }
            }

            Card("While a gesture runs") {
                Text("""
                     The pointer is decoupled from the mouse and hidden, so the cursor stays \
                     where it was instead of drifting into a screen edge mid-scroll. When you \
                     let go it is put back exactly where the gesture started.
                     """)
                    .font(Design.Typography.body)
                    .foregroundStyle(Design.Palette.secondaryLabel)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func isBound(_ action: GlideAction) -> Bool {
        state.selectedProfile?.bindings.contains { $0.action == action && $0.isEnabled } ?? false
    }

    private func explanation(for action: GlideAction) -> String {
        switch action {
        case .scrollAndNavigate:
            return "Drag to scroll in any direction, and swipe sideways to go back and forward."
        case .autoScroll:
            return "Windows-style. Push away from where you pressed to scroll faster; hold still to stop."
        case .pinchZoom:
            return "Drag up and down to zoom, as a trackpad pinch."
        case .spaceNavigation:
            return "Drag sideways to move between desktops, up for Mission Control."
        default:
            return ""
        }
    }
}
