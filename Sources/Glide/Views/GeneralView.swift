import AppKit
import GlideCore
import GlideKit
import ServiceManagement
import SwiftUI

struct GeneralView: View {

    @EnvironmentObject private var state: AppState
    @State private var launchAtLoginError: String?

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
                    Divider()
                    SettingRow("Event tap", help: tapHelp) {
                        StatusPill(
                            state.engine.isTapInstalled ? "Installed" : "Not installed",
                            tone: state.engine.isTapInstalled ? .positive : .critical
                        )
                    }
                    if state.engine.tapRecoveries > 0 {
                        Divider()
                        SettingRow("Tap recoveries", help: "The system paused Glide's event tap for taking too long and Glide restarted it. A rising number means this Mac is struggling to keep up with the event stream.") {
                            Text("\(state.engine.tapRecoveries)")
                                .font(Design.Typography.readout)
                        }
                    }
                    if let error = state.engine.lastError {
                        Divider()
                        Label(error, systemImage: "exclamationmark.triangle")
                            .font(Design.Typography.caption)
                            .foregroundStyle(.red)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                Card("Startup", subtitle: "A utility that is not running helps nobody.") {
                    SettingRow("Launch at Login", help: launchHelp) {
                        Toggle("Launch at Login", isOn: Binding(
                            get: { SMAppService.mainApp.status == .enabled },
                            set: { setLaunchAtLogin($0) }
                        ))
                        .toggleStyle(.switch)
                        .labelsHidden()
                    }
                    if let launchAtLoginError {
                        Label(launchAtLoginError, systemImage: "exclamationmark.triangle")
                            .font(Design.Typography.caption)
                            .foregroundStyle(.orange)
                            .fixedSize(horizontal: false, vertical: true)
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

    private var tapHelp: String {
        state.engine.isTapInstalled
            ? "Glide is intercepting mouse events before they reach your applications."
            : "No event tap is installed, so Glide is not intercepting anything. Re-check Accessibility in System Settings, or quit and reopen Glide."
    }

    private var launchHelp: String {
        "Registers Glide with macOS so it starts when you log in. If macOS flags it as pending approval, check System Settings → General → Login Items."
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            launchAtLoginError = nil
        } catch {
            // Registration can fail when macOS wants the login item approved by
            // hand; surface it rather than leaving the toggle lying.
            launchAtLoginError = error.localizedDescription
        }
    }

    private func revealConfiguration() {
        guard let url = try? ProfileStore.defaultURL() else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }
}
