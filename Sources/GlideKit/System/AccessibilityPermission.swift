import AppKit
import ApplicationServices
import Foundation

/// Accessibility permission, which Glide cannot function without.
///
/// A `CGEventTap` simply fails to install without it, and the failure is silent
/// — which is why onboarding checks explicitly rather than waiting for something
/// not to work.
public enum AccessibilityPermission {

    /// Whether permission has been granted. Cheap; safe to poll.
    public static var isGranted: Bool { AXIsProcessTrusted() }

    /// Asks the system to show the permission prompt.
    ///
    /// macOS only shows this once per app binary. After that the prompt is
    /// silently suppressed and the call just returns the current state, so the
    /// UI must also offer a route to System Settings rather than relying on it.
    @discardableResult
    public static func request() -> Bool {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
        return AXIsProcessTrustedWithOptions(options as CFDictionary)
    }

    /// Opens System Settings at Privacy & Security → Accessibility.
    public static func openSettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        NSWorkspace.shared.open(url)
    }

    /// Calls back when permission is granted.
    ///
    /// Polling is not laziness: granting Accessibility does not notify the
    /// application, and macOS historically required a relaunch to pick it up.
    /// Watching for it lets Glide start working the moment the box is ticked.
    public static func waitForGrant(
        pollInterval: TimeInterval = 1.0,
        onGranted: @escaping () -> Void
    ) -> Timer {
        let timer = Timer.scheduledTimer(withTimeInterval: pollInterval, repeats: true) { timer in
            guard isGranted else { return }
            timer.invalidate()
            DispatchQueue.main.async(execute: onGranted)
        }
        RunLoop.main.add(timer, forMode: .common)
        return timer
    }
}
