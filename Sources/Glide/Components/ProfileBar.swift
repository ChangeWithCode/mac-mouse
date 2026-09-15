import GlideCore
import SwiftUI

/// The layer selector that sits above every pane which edits profile data.
///
/// Settings in Glide always belong to a layer, and hiding that would make the
/// app confusing the first time a per-app profile overrode something: you would
/// change a setting, watch it not take effect, and have no way to see why. The
/// bar keeps the answer on screen.
struct ProfileBar: View {

    @EnvironmentObject private var state: AppState

    var body: some View {
        HStack(spacing: Design.Space.sm) {
            Text("Editing")
                .font(Design.Typography.caption)
                .foregroundStyle(Design.Palette.secondaryLabel)

            Menu {
                ForEach(state.document.profiles) { profile in
                    Button {
                        state.selectedProfileID = profile.id
                    } label: {
                        Label(profile.name, systemImage: profile.symbolName)
                    }
                }
            } label: {
                HStack(spacing: Design.Space.xs) {
                    Image(systemName: state.selectedProfile?.symbolName ?? "square.stack.3d.up")
                    Text(state.selectedProfile?.name ?? "No Profile")
                    Image(systemName: "chevron.up.chevron.down").font(.system(size: 9))
                }
                .font(Design.Typography.body)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()

            if let scope = state.selectedProfile?.scope, !scope.isGlobal {
                StatusPill(scopeDescription(scope), tone: .neutral)
            }

            Spacer()

            if state.selectedProfile?.scope.isGlobal == false {
                Text("Overrides the base layer")
                    .font(Design.Typography.caption)
                    .foregroundStyle(Design.Palette.tertiaryLabel)
            }
        }
        .padding(.horizontal, Design.Space.lg)
        .padding(.vertical, Design.Space.sm)
        .background(.ultraThinMaterial)
        .overlay(alignment: .bottom) { Divider() }
    }

    private func scopeDescription(_ scope: ProfileScope) -> String {
        var parts: [String] = []
        if !scope.applications.isEmpty { parts.append("\(scope.applications.count) app\(scope.applications.count == 1 ? "" : "s")") }
        if !scope.devices.isEmpty { parts.append("\(scope.devices.count) device\(scope.devices.count == 1 ? "" : "s")") }
        return parts.joined(separator: " · ")
    }
}

/// A pane with the profile bar pinned above scrolling content.
struct ProfilePane<Content: View>: View {
    private let title: String
    private let subtitle: String
    private let content: Content

    init(_ title: String, subtitle: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.subtitle = subtitle
        self.content = content()
    }

    var body: some View {
        VStack(spacing: 0) {
            ProfileBar()
            ScrollView {
                VStack(alignment: .leading, spacing: Design.Space.lg) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(title).font(Design.Typography.display)
                        Text(subtitle)
                            .font(Design.Typography.body)
                            .foregroundStyle(Design.Palette.secondaryLabel)
                    }
                    content
                }
                .padding(Design.Space.xl)
                .frame(maxWidth: 780, alignment: .leading)
                .frame(maxWidth: .infinity)
            }
        }
    }
}
