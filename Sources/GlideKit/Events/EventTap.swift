import CoreGraphics
import Foundation
import os.log

/// Owns a `CGEventTap` and keeps it alive.
///
/// The lifecycle here is the part people get wrong. macOS disables a tap that
/// takes too long inside its callback, and it does so silently — the app keeps
/// running, the mouse just quietly stops working until it is relaunched. The tap
/// must watch for `tapDisabledByTimeout` and re-enable itself, and it must do as
/// little work as possible inside the callback so the timeout never fires in the
/// first place.
public final class EventTap {

    public enum TapError: Error, LocalizedError {
        case creationFailed

        public var errorDescription: String? {
            switch self {
            case .creationFailed:
                return "Glide could not install its event tap. This almost always means "
                     + "Accessibility permission has not been granted."
            }
        }
    }

    /// What to do with an event.
    public enum Disposition {
        /// Let it through untouched.
        case pass
        /// Swallow it. Used when Glide has replaced the event with its own.
        case discard
        /// Replace it with a different event.
        case replace(CGEvent)
    }

    private let log = Logger(subsystem: "com.glide.app", category: "EventTap")

    private var machPort: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private let eventMask: CGEventMask
    private let handler: (CGEventType, CGEvent) -> Disposition

    /// How many times the tap has been re-enabled after being disabled by the
    /// system. Surfaced in the diagnostics pane: a climbing number means the
    /// handler is too slow.
    public private(set) var timeoutRecoveries: Int = 0

    public var isEnabled: Bool {
        guard let machPort else { return false }
        return CGEvent.tapIsEnabled(tap: machPort)
    }

    /// - Parameters:
    ///   - eventTypes: Types to intercept.
    ///   - handler: Called on the run loop the tap is attached to. Must return
    ///     quickly — anything slow here risks the tap being disabled.
    public init(
        eventTypes: [CGEventType],
        handler: @escaping (CGEventType, CGEvent) -> Disposition
    ) {
        self.eventMask = eventTypes.reduce(CGEventMask(0)) { $0 | (1 << CGEventMask($1.rawValue)) }
        self.handler = handler
    }

    deinit { stop() }

    /// Installs the tap. Throws if Accessibility permission is missing.
    public func start() throws {
        guard machPort == nil else { return }

        let callback: CGEventTapCallBack = { _, type, event, userInfo in
            guard let userInfo else { return Unmanaged.passUnretained(event) }
            let tap = Unmanaged<EventTap>.fromOpaque(userInfo).takeUnretainedValue()
            return tap.handle(type: type, event: event)
        }

        guard let port = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: eventMask,
            callback: callback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            throw TapError.creationFailed
        }

        machPort = port
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, port, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: port, enable: true)
        log.info("Event tap installed")
    }

    public func stop() {
        if let port = machPort { CGEvent.tapEnable(tap: port, enable: false) }
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }
        if let port = machPort { CFMachPortInvalidate(port) }
        runLoopSource = nil
        machPort = nil
    }

    /// Temporarily stops intercepting without tearing the tap down. Used by the
    /// binding recorder, which needs to *see* clicks rather than act on them.
    public func setPassthrough(_ passthrough: Bool) {
        guard let port = machPort else { return }
        CGEvent.tapEnable(tap: port, enable: !passthrough)
    }

    private func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        // The system disables a tap whose callback overran, and disables it
        // again on certain user input. Neither is reported anywhere except here,
        // so failing to re-enable means the app silently stops working.
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let port = machPort {
                timeoutRecoveries += 1
                log.error("Tap disabled by the system (\(type == .tapDisabledByTimeout ? "timeout" : "user input")); re-enabling")
                CGEvent.tapEnable(tap: port, enable: true)
            }
            return nil
        }

        switch handler(type, event) {
        case .pass: return Unmanaged.passUnretained(event)
        case .discard: return nil
        case .replace(let replacement): return Unmanaged.passUnretained(replacement)
        }
    }
}
