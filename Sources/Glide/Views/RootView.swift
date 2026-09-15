import GlideCore
import GlideKit
import SwiftUI

struct RootView: View {

    @EnvironmentObject private var state: AppState

    var body: some View {
        if !state.permissionGranted {
            PermissionView()
        } else {
            NavigationSplitView {
                sidebar
            } detail: {
                detail
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Design.Palette.surface)
            }
            .navigationSplitViewStyle(.balanced)
        }
    }

    private var sidebar: some View {
        List(selection: $state.section) {
            Section {
                ForEach(AppState.Section.allCases) { item in
                    Label(item.title, systemImage: item.symbol).tag(item)
                }
            } header: {
                header
            }
        }
        .listStyle(.sidebar)
        .navigationSplitViewColumnWidth(min: 190, ideal: 210, max: 250)
        .safeAreaInset(edge: .bottom) { statusFooter }
    }

    private var header: some View {
        HStack(spacing: Design.Space.sm) {
            Image(systemName: "computermouse.fill")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Design.Palette.accentGradient)
            Text("Glide").font(Design.Typography.title)
        }
        .padding(.bottom, Design.Space.sm)
    }

    /// Always-visible answer to "is this thing actually doing anything", which
    /// is the first question anyone asks of a background utility.
    private var statusFooter: some View {
        VStack(alignment: .leading, spacing: Design.Space.sm) {
            Divider()
            HStack {
                StatusPill(
                    state.engine.isActive ? "Active" : "Paused",
                    tone: state.engine.isActive ? .positive : .warning
                )
                Spacer()
                Text("\(state.engine.connectedDevices.filter { !$0.isAppleDevice }.count) mice")
                    .font(Design.Typography.caption)
                    .foregroundStyle(Design.Palette.secondaryLabel)
            }
            if let app = state.engine.frontmostApplication {
                Text(app)
                    .font(Design.Typography.caption)
                    .foregroundStyle(Design.Palette.tertiaryLabel)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
        .padding(.horizontal, Design.Space.md)
        .padding(.bottom, Design.Space.md)
    }

    @ViewBuilder
    private var detail: some View {
        switch state.section {
        case .scrolling: ScrollTuningView()
        case .buttons:   ButtonsView()
        case .gestures:  GesturesView()
        case .profiles:  ProfilesView()
        case .devices:   DevicesView()
        case .macros:    MacrosView()
        case .general:   GeneralView()
        }
    }
}

/// Shown until Accessibility permission is granted. Without it the event tap
/// cannot install, and the failure is otherwise completely silent.
struct PermissionView: View {

    @EnvironmentObject private var state: AppState

    var body: some View {
        VStack(spacing: Design.Space.lg) {
            Spacer()

            Image(systemName: "hand.raised.fill")
                .font(.system(size: 52))
                .foregroundStyle(Design.Palette.accentGradient)

            VStack(spacing: Design.Space.sm) {
                Text("Glide needs Accessibility access").font(Design.Typography.display)
                Text("""
                     Glide works by reading mouse events before they reach your apps and \
                     replacing them with smoother ones. macOS requires explicit permission \
                     for that, and won't say why anything is failing without it.
                     """)
                    .font(Design.Typography.body)
                    .foregroundStyle(Design.Palette.secondaryLabel)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 440)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: Design.Space.md) {
                Button("Open System Settings") { AccessibilityPermission.openSettings() }
                    .buttonStyle(.borderedProminent)
                Button("Ask Again") { AccessibilityPermission.request() }
                    .buttonStyle(.bordered)
            }

            Text("Glide starts working the moment you tick the box — no restart needed.")
                .font(Design.Typography.caption)
                .foregroundStyle(Design.Palette.tertiaryLabel)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Design.Palette.surface)
    }
}
