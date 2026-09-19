import AppKit
import CoreGraphics
import Foundation
import GlideCore
import os.log

/// Wires everything together: the tap, the recognisers, the device monitor and
/// the profile stack.
///
/// One object owns the whole input pipeline so there is exactly one place where
/// an event's fate is decided, and one place to look when something is handled
/// wrongly.
///
/// ## Threading
///
/// Confined to the main run loop, but deliberately *not* marked `@MainActor`.
/// The event tap delivers through a C callback that the compiler cannot see is
/// main-isolated, so annotating the class would make every handler an
/// actor-hop — adding latency to the one path that must never be slow, and
/// risking the tap being disabled for overrunning. The tap, the HID manager and
/// the recogniser timer are all scheduled on `CFRunLoopGetMain`, so every
/// mutation below already happens on the main thread; `@Published` updates are
/// therefore safe for SwiftUI to observe.
public final class GlideEngine: ObservableObject {

    private let log = Logger(subsystem: "com.glide.app", category: "Engine")

    // Components
    private var tap: EventTap?
    private let scroll = ScrollCoordinator()
    private let devices = HIDDeviceMonitor()
    private let dispatcher = ActionDispatcher()
    private let resolver = ProfileResolver()
    private var recognizer = ChordRecognizer()
    private var recognizerTimer: Timer?
    private var workspaceObserver: NSObjectProtocol?

    // State
    @Published public private(set) var isRunning = false
    /// Whether events are being handed straight back to macOS. Distinct from
    /// `isRunning`: the tap is still installed, it is just not intercepting.
    @Published public private(set) var isPaused = false
    @Published public private(set) var connectedDevices: [DeviceIdentity] = []
    @Published public private(set) var frontmostApplication: String?
    @Published public private(set) var lastError: String?

    private var profiles: [Profile] = []
    private var macros: [UUID: Macro] = [:]
    private var modalProfileID: UUID?
    private var resolved: ResolvedSettings = .fallback
    private var activeDevice: DeviceIdentity?

    public init() {
        devices.onDevicesChanged = { [weak self] list in
            guard let self else { return }
            self.connectedDevices = list
            self.refreshResolution()
        }
        dispatcher.onActivateProfile = { [weak self] id in
            self?.modalProfileID = id
            self?.refreshResolution()
        }
        dispatcher.macroProvider = { [weak self] id in self?.macros[id] }
        configureRecognizer()
    }

    // MARK: - Lifecycle

    /// Starts intercepting. Throws if Accessibility permission is missing.
    public func start() throws {
        guard !isRunning else { return }
        guard AccessibilityPermission.isGranted else {
            throw EventTap.TapError.creationFailed
        }

        devices.start()
        observeFrontmostApplication()

        let tap = EventTap(
            eventTypes: [
                .scrollWheel,
                .otherMouseDown, .otherMouseUp,
                .leftMouseDown, .leftMouseUp,
                .rightMouseDown, .rightMouseUp,
                .mouseMoved, .otherMouseDragged, .leftMouseDragged,
            ],
            handler: { [weak self] type, event in
                guard let self else { return .pass }
                return self.handle(type: type, event: event)
            }
        )

        do {
            try tap.start()
        } catch {
            lastError = error.localizedDescription
            throw error
        }

        self.tap = tap

        // Drives the recogniser's holds and multi-click deadlines. 120Hz so a
        // hold fires within a frame of its threshold rather than visibly late.
        let timer = Timer(timeInterval: 1.0 / 120.0, repeats: true) { [weak self] _ in
            guard let self else { return }
            let events = self.recognizer.tick(now: MonotonicClock.now)
            for event in events { self.apply(event) }
        }
        RunLoop.main.add(timer, forMode: .common)
        recognizerTimer = timer

        Diagnostics.reset()
        isRunning = true
        isPaused = false
        lastError = nil
        log.info("Glide engine started")
    }

    public func stop() {
        tap?.stop()
        tap = nil
        recognizerTimer?.invalidate()
        recognizerTimer = nil
        scroll.cancel()
        GestureSession.shared.end()
        devices.stop()
        recognizer.reset()
        if let workspaceObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(workspaceObserver)
            self.workspaceObserver = nil
        }
        isRunning = false
        isPaused = false
        log.info("Glide engine stopped")
    }

    /// Whether Glide is actually intercepting: started *and* not paused. The
    /// status readouts want this, not `isRunning` — a paused tap is still
    /// running and reporting it as "Active" is how the UI ends up lying.
    public var isActive: Bool { isRunning && !isPaused }

    /// Whether the tap is installed at all — distinct from `isRunning`, because
    /// a failed install throws and is surfaced separately. Diagnostics.
    public var isTapInstalled: Bool { tap != nil }

    /// How many times the system has disabled the tap for running slow and
    /// Glide has re-enabled it. A climbing number means the event path is too
    /// slow. Diagnostics.
    public var tapRecoveries: Int { tap?.timeoutRecoveries ?? 0 }

    /// Temporarily hands every event back to macOS without tearing down.
    public func setPaused(_ paused: Bool) {
        tap?.setPassthrough(paused)
        isPaused = paused
        if paused {
            scroll.cancel()
            // A gesture in flight must not survive its recogniser: with events
            // passing through, nothing will ever release it, and the cursor
            // stays decoupled and hidden with no way back.
            GestureSession.shared.end()
            recognizer.reset()
        }
    }

    // MARK: - Configuration

    public func apply(profiles: [Profile], macros: [Macro], allowsShellCommands: Bool) {
        self.profiles = profiles
        self.macros = Dictionary(uniqueKeysWithValues: macros.map { ($0.id, $0) })
        dispatcher.allowsShellCommands = allowsShellCommands
        refreshResolution()
    }

    /// The configuration currently in force. Drives the "what applies right now"
    /// readout in the UI.
    public var activeSettings: ResolvedSettings { resolved }

    private func refreshResolution() {
        resolved = resolver.resolve(
            profiles: profiles,
            application: frontmostApplication,
            device: activeDevice,
            modalProfileID: modalProfileID
        )
        scroll.apply(resolved)
    }

    private func configureRecognizer() {
        recognizer.isBound = { [weak self] trigger in
            self?.resolved.binding(for: trigger) != nil
        }
        recognizer.hasAnyBinding = { [weak self] button in
            self?.resolved.hasAnyBinding(for: button) ?? false
        }
    }

    private func observeFrontmostApplication() {
        frontmostApplication = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        workspaceObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self else { return }
            let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            self.frontmostApplication = app?.bundleIdentifier
            // The view being scrolled has gone away; anything in flight belongs
            // to it, not to the app that just came forward. That includes a
            // live gesture: dropping the recogniser without ending the session
            // leaves the cursor decoupled and hidden forever.
            self.scroll.cancel()
            GestureSession.shared.end()
            self.recognizer.reset()
            self.refreshResolution()
        }
    }

    // MARK: - Event handling

    private func handle(type: CGEventType, event: CGEvent) -> EventTap.Disposition {
        // Attribute the event to a device before anything else: which profile
        // applies depends on it.
        if let device = devices.currentDevice(), device.key != activeDevice?.key {
            activeDevice = device
            refreshResolution()
        }

        // Apple's own devices are never touched.
        if let activeDevice, activeDevice.isAppleDevice {
            Diagnostics.trace("engine.apple", "passing \(type.rawValue) from \(activeDevice.displayName)")
            return .pass
        }

        switch type {
        case .scrollWheel:
            let consumed = scroll.handle(scrollEvent: event)
            Diagnostics.trace(
                "engine.scroll",
                "device=\(activeDevice?.displayName ?? "none") consumed=\(consumed)"
            )
            return consumed ? .discard : .pass

        case .otherMouseDown, .leftMouseDown, .rightMouseDown:
            return handleButton(event: event, isDown: true)

        case .otherMouseUp, .leftMouseUp, .rightMouseUp:
            return handleButton(event: event, isDown: false)

        case .mouseMoved, .otherMouseDragged, .leftMouseDragged:
            let dx = Double(event.getIntegerValueField(.mouseEventDeltaX))
            let dy = Double(event.getIntegerValueField(.mouseEventDeltaY))

            // A running gesture owns the pointer: movement becomes scroll input
            // and must not also reach the app as cursor motion.
            if GestureSession.shared.isActive {
                GestureSession.shared.update(deltaX: dx, deltaY: dy)
                return .discard
            }

            let distance = (dx * dx + dy * dy).squareRoot()
            let events = recognizer.move(by: distance, at: MonotonicClock.now)
            for recognized in events { apply(recognized) }
            return .pass

        default:
            return .pass
        }
    }

    private func handleButton(event: CGEvent, isDown: Bool) -> EventTap.Disposition {
        guard !ScrollEventSynthesizer.isSynthetic(event) else { return .pass }

        let number = Int(event.getIntegerValueField(.mouseEventButtonNumber))
        let button = MouseButton(number)
        let now = MonotonicClock.now

        let events = isDown
            ? recognizer.press(button, at: now)
            : recognizer.release(button, at: now)

        Diagnostics.trace(
            "engine.button",
            "button=\(button.number) down=\(isDown) events=\(events.count) bindings=\(resolved.bindings.count)"
        )

        // A pass-through means the recogniser never took an interest, so the
        // original event must reach the app untouched and on time.
        if events.count == 1, case .passThrough = events[0] { return .pass }

        for recognized in events { apply(recognized) }
        return .discard
    }

    private func apply(_ event: ChordRecognizer.Event) {
        switch event {
        case .fire(let trigger):
            guard let binding = resolved.binding(for: trigger) else { return }
            dispatcher.perform(binding.action)

        case .begin(let trigger):
            guard let binding = resolved.binding(for: trigger) else { return }
            if binding.action.isContinuous {
                // Defensive: a session left active by a missed `.end` would
                // silently refuse to begin, leaving its cursor freeze in place.
                GestureSession.shared.end()
                GestureSession.shared.begin(binding.action)
            } else {
                dispatcher.perform(binding.action)
            }

        case .end(let trigger):
            // A live gesture ends here even if the binding no longer resolves
            // (the profile changed mid-hold): the cursor freeze outlives the
            // binding that started it, and nothing else will release it.
            if GestureSession.shared.isActive {
                GestureSession.shared.end()
            } else if let binding = resolved.binding(for: trigger) {
                dispatcher.cancelContinuous()
            }

        case .passThrough:
            break

        case .synthesizeClick(let button):
            // The press was swallowed while the recogniser deliberated and
            // nothing matched, so hand the click back rather than eating it.
            MouseSynthesizer.click(button)
        }
    }
}
