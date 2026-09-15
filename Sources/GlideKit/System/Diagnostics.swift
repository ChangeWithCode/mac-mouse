import Foundation
import os.log

/// Rate-limited tracing for the event path.
///
/// The pipeline runs at the refresh rate inside a callback macOS will disable
/// for overrunning, so it cannot simply log every event. Each site gets a small
/// budget: enough to show what the first flick of a wheel actually did, then
/// silence. Budgets reset when the engine starts, so re-enabling Glide gives a
/// fresh trace without a relaunch.
public enum Diagnostics {

    private static let log = Logger(subsystem: "com.glide.app", category: "Trace")

    /// Whether tracing is on. Off by default; `GLIDE_TRACE=1` turns it on, so a
    /// release build carries no cost beyond one boolean test.
    public static let isEnabled = ProcessInfo.processInfo.environment["GLIDE_TRACE"] == "1"

    private static let lock = NSLock()
    private static var budgets: [String: Int] = [:]

    /// How many times a single site may speak before it goes quiet.
    private static let budget = 20

    public static func reset() {
        lock.lock(); budgets.removeAll(); lock.unlock()
    }

    /// Logs `message` under `site`, up to that site's budget.
    public static func trace(_ site: String, _ message: @autoclosure () -> String) {
        guard isEnabled else { return }
        lock.lock()
        let used = budgets[site, default: 0]
        budgets[site] = used + 1
        lock.unlock()
        guard used < budget else { return }
        let text = message()
        log.info("[\(site, privacy: .public)] \(text, privacy: .public)")
        if used == budget - 1 {
            log.info("[\(site, privacy: .public)] (further messages from this site suppressed)")
        }
    }
}
