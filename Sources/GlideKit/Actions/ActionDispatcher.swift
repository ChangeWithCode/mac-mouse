import AppKit
import CoreGraphics
import Foundation
import GlideCore
import os.log

/// Carries out a `GlideAction`.
///
/// ## A note on how system actions are triggered
///
/// macOS exposes no public API for "open Mission Control" or "move one space
/// left". The options are private CoreGraphics/CoreDock symbols — which break
/// between releases and bar an app from the Mac App Store — or synthesizing the
/// keyboard shortcut the system already listens for.
///
/// Glide synthesizes the shortcut. It is stable across releases and needs no
/// private symbols. The trade is real and worth stating plainly: if someone has
/// turned the corresponding shortcut off in System Settings → Keyboard, the
/// action will not fire. `SystemShortcut.isLikelyAvailable` is used by the UI to
/// warn about this at bind time rather than leaving the user to discover it.
public final class ActionDispatcher {

    private let log = Logger(subsystem: "com.glide.app", category: "Actions")
    private let macroPlayer: MacroPlayer

    /// Set from the store. Shell actions refuse to run unless this is on.
    public var allowsShellCommands: Bool = false

    /// Looks up a macro by identifier.
    public var macroProvider: (UUID) -> Macro? = { _ in nil }

    /// Called when a binding asks to activate a modal profile.
    public var onActivateProfile: ((UUID) -> Void)?

    public init(macroPlayer: MacroPlayer = MacroPlayer()) {
        self.macroPlayer = macroPlayer
    }

    // MARK: - Dispatch

    public func perform(_ action: GlideAction) {
        switch action {
        case .none:
            break

        // MARK: System
        case .missionControl:      SystemShortcut.missionControl.send()
        case .applicationWindows:  SystemShortcut.applicationWindows.send()
        case .showDesktop:         SystemShortcut.showDesktop.send()
        case .launchpad:           open(applicationAt: "/System/Applications/Launchpad.app")
        case .notificationCentre:  SystemShortcut.notificationCentre.send()
        case .spotlight:           SystemShortcut.spotlight.send()
        case .lockScreen:          SystemShortcut.lockScreen.send()
        case .sleepDisplay:        sleepDisplays()

        // MARK: Spaces
        case .spaceLeft:  SystemShortcut.spaceLeft.send()
        case .spaceRight: SystemShortcut.spaceRight.send()
        case .space(let index):
            // Ctrl+1…9. Off by default in System Settings, so the UI warns.
            guard (1...9).contains(index) else { return }
            let digits: [UInt16] = [0x12, 0x13, 0x14, 0x15, 0x17, 0x16, 0x1A, 0x1C, 0x19]
            KeyboardSynthesizer.send(Keystroke(keyCode: digits[index - 1], modifiers: .control))

        // MARK: Navigation
        case .back:      KeyboardSynthesizer.send(Keystroke(keyCode: 0x21, modifiers: .command))  // Cmd+[
        case .forward:   KeyboardSynthesizer.send(Keystroke(keyCode: 0x1E, modifiers: .command))  // Cmd+]
        case .lookUp:    KeyboardSynthesizer.send(Keystroke(keyCode: 0x02, modifiers: [.command, .control]))
        case .smartZoom: KeyboardSynthesizer.send(Keystroke(keyCode: 0x18, modifiers: .command))  // Cmd+=

        // MARK: Clicks
        case .leftClick:   MouseSynthesizer.click(.left)
        case .rightClick:  MouseSynthesizer.click(.right)
        case .middleClick: MouseSynthesizer.click(.center)

        // MARK: Continuous
        //
        // These are driven by GestureSession for as long as the trigger is held,
        // so a one-shot dispatch is a no-op by design.
        case .scrollAndNavigate, .autoScroll, .pinchZoom, .spaceNavigation:
            break

        // MARK: Media
        case .volumeUp:      MediaKey.soundUp.send()
        case .volumeDown:    MediaKey.soundDown.send()
        case .mute:          MediaKey.mute.send()
        case .brightnessUp:  MediaKey.brightnessUp.send()
        case .brightnessDown: MediaKey.brightnessDown.send()
        case .playPause:     MediaKey.play.send()
        case .nextTrack:     MediaKey.next.send()
        case .previousTrack: MediaKey.previous.send()

        // MARK: Composites
        case .keystroke(let stroke):
            KeyboardSynthesizer.send(stroke)

        case .macro(let id):
            guard let macro = macroProvider(id) else {
                log.error("Binding refers to macro \(id, privacy: .public), which no longer exists")
                return
            }
            macroPlayer.play(macro)

        case .launchApplication(let bundleIdentifier):
            guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) else {
                log.error("No application with identifier \(bundleIdentifier, privacy: .public)")
                return
            }
            NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())

        case .openURL(let string):
            guard let url = URL(string: string) else { return }
            NSWorkspace.shared.open(url)

        case .shellCommand(let command):
            // Gated deliberately. A profile is a JSON file that can be shared or
            // synced, so an imported one must not be able to run code just
            // because someone double-clicked it.
            guard allowsShellCommands else {
                log.error("Refusing to run a shell command: shell actions are disabled in Settings")
                return
            }
            runShell(command)

        case .activateProfile(let id):
            onActivateProfile?(id)
        }
    }

    /// Stops anything still running from a held binding.
    public func cancelContinuous() {
        macroPlayer.stop()
    }

    // MARK: - Helpers

    private func open(applicationAt path: String) {
        let url = URL(fileURLWithPath: path)
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
    }

    private func sleepDisplays() {
        // pmset is the supported route; there is no public framework call.
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/pmset")
        process.arguments = ["displaysleepnow"]
        try? process.run()
    }

    private func runShell(_ command: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", command]
        // Detached and output-discarding: a binding must never block the event
        // pipeline waiting on a command that decided to read from stdin.
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        process.standardInput = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            log.error("Shell command failed to launch: \(error.localizedDescription, privacy: .public)")
        }
    }
}
