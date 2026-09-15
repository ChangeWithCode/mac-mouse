import AppKit
import GlideCore
import GlideKit
import SwiftUI

struct GeneralView: View {

    @EnvironmentObject private var state: AppState

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Design.Space.lg) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("General").font(Design.Typography.display)
                    Text("Glide's own behaviour.")
                        .font(Design.Typography.body)
                        .foregroundStyle(Design.Palette.secondaryLabel)
                }

                Card("Status") {
                    SettingRow("Engine", help: engineHelp) {
                        HStack(spacing: Design.Space.sm) {
                            StatusPill(
                                state.engine.isRunning ? "Running" : "Stopped",
                                tone: state.engine.isRunning ? .positive : .warning
                            )
                            Button(state.engine.isRunning ? "Pause" : "Resume") {
                                state.engine.setPaused(state.engine.isRunning)
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }
                    }
                    Divider()
                    SettingRow("Accessibility") {
                        StatusPill(
                            state.permissionGranted ? "Granted" : "Required",
                            tone: state.permissionGranted ? .positive : .critical
                        )
                    }
                }

                Card("Configuration", subtitle: "Stored as readable JSON, so it can live in a dotfiles repo.") {
                    HStack(spacing: Design.Space.sm) {
                        Button("Save Now") { state.saveNow() }.buttonStyle(.bordered)
                        Button("Reveal in Finder") { revealConfiguration() }.buttonStyle(.bordered)
                        Spacer()
                    }
                    if let error = state.saveError {
                        Label(error, systemImage: "exclamationmark.triangle")
                            .font(Design.Typography.caption)
                            .foregroundStyle(.orange)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                Card("About") {
                    VStack(alignment: .leading, spacing: Design.Space.xs) {
                        Text("Glide").font(Design.Typography.heading)
                        Text("""
                             A pointing-device utility for macOS, in the spirit of Mac Mouse Fix, \
                             with layered profiles, per-device settings, chords and macros.
                             """)
                            .font(Design.Typography.caption)
                            .foregroundStyle(Design.Palette.secondaryLabel)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .padding(Design.Space.xl)
            .frame(maxWidth: 780, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
    }

    private var engineHelp: String {
        state.engine.isRunning
            ? "Intercepting events for \(state.engine.connectedDevices.filter { !$0.isAppleDevice }.count) device(s)."
            : "Every event is passing straight through to macOS."
    }

    private func revealConfiguration() {
        guard let url = try? ProfileStore.defaultURL() else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }
}
