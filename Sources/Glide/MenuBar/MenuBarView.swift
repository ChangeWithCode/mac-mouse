import AppKit
import GlideCore
import SwiftUI

/// The menu bar popover — where Glide lives most of the time.
///
/// Kept to the two things anyone actually wants from the menu bar: confirming
/// it is working, and turning it off quickly when something needs the raw mouse.
struct MenuBarView: View {

    @EnvironmentObject private var state: AppState
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: Design.Space.md) {
            HStack(spacing: Design.Space.sm) {
                Image(systemName: "computermouse.fill")
                    .foregroundStyle(Design.Palette.accentGradient)
                Text("Glide").font(Design.Typography.title)
                Spacer()
                StatusPill(
                    state.engine.isRunning ? "Active" : "Paused",
                    tone: state.engine.isRunning ? .positive : .warning
                )
            }

            Divider()

            if let device = state.engine.connectedDevices.first(where: { !$0.isAppleDevice }) {
                row("Device", device.displayName)
            }
            if let app = state.engine.frontmostApplication {
                row("Frontmost", app)
            }
            row("Feel", state.engine.activeSettings.scrollPreset.name)

            Divider()

            Toggle("Enabled", isOn: .init(
                get: { state.engine.isRunning },
                set: { state.engine.setPaused(!$0) }
            ))
            .toggleStyle(.switch)

            Button("Settings…") { openWindow(id: "settings") }
                .buttonStyle(.bordered)

            Button("Quit Glide") { NSApplication.shared.terminate(nil) }
                .buttonStyle(.borderless)
                .foregroundStyle(Design.Palette.secondaryLabel)
        }
        .padding(Design.Space.lg)
        .frame(width: 260)
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).font(Design.Typography.caption).foregroundStyle(Design.Palette.secondaryLabel)
            Spacer()
            Text(value)
                .font(Design.Typography.caption)
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }
}
