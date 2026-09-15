import Foundation
import IOKit.hid
import GlideCore
import os.log

/// Enumerates connected pointing devices and tracks which one is being used.
///
/// Two jobs. First, discovery: what is plugged in, so the UI can offer per-device
/// settings and so Apple's own devices can be left alone. Second, attribution:
/// which physical device produced the event currently being handled.
///
/// Attribution is necessary because `CGEvent` does not carry a device
/// identifier. The standard approach — the one every tool in this category uses
/// — is to correlate: IOHID reports input from a specific device, the tap sees a
/// matching `CGEvent` a fraction of a millisecond later, and the most recent HID
/// reporter is taken to be the source. This is a heuristic, not a guarantee. It
/// is reliable in practice because a person only physically operates one mouse at
/// a time; two devices moving simultaneously can be misattributed for a frame.
public final class HIDDeviceMonitor {

    private let log = Logger(subsystem: "com.glide.app", category: "HID")

    private var manager: IOHIDManager?
    private let lock = NSLock()

    private var devicesByRef: [IOHIDDevice: DeviceIdentity] = [:]
    private var lastActive: (identity: DeviceIdentity, time: Double)?

    /// How stale an attribution may be before it is discarded, in seconds.
    /// A HID report and the `CGEvent` it produces arrive within well under a
    /// millisecond; 50ms is generous while still rejecting anything unrelated.
    private let attributionWindow: Double = 0.05

    /// Called on the main run loop when the device list changes.
    public var onDevicesChanged: (([DeviceIdentity]) -> Void)?

    public init() {}

    deinit { stop() }

    /// Every connected pointing device, Apple's included.
    public var devices: [DeviceIdentity] {
        lock.lock(); defer { lock.unlock() }
        return Array(devicesByRef.values).sorted { $0.displayName < $1.displayName }
    }

    /// Devices Glide will manage — everything except Apple's own, which macOS
    /// already handles properly and whose gestures we would break.
    public var manageableDevices: [DeviceIdentity] {
        devices.filter { !$0.isAppleDevice }
    }

    /// The device most likely responsible for the event being handled right now.
    public func currentDevice() -> DeviceIdentity? {
        lock.lock(); defer { lock.unlock() }
        guard let last = lastActive else { return nil }
        guard MonotonicClock.now - last.time <= attributionWindow else { return nil }
        return last.identity
    }

    public func start() {
        guard manager == nil else { return }

        let hidManager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))

        // Mice and generic pointers. Trackpads report as pointers too, which is
        // why identification later filters Apple devices out rather than relying
        // on the usage page alone.
        let matching: [[String: Any]] = [
            [kIOHIDDeviceUsagePageKey: kHIDPage_GenericDesktop, kIOHIDDeviceUsageKey: kHIDUsage_GD_Mouse],
            [kIOHIDDeviceUsagePageKey: kHIDPage_GenericDesktop, kIOHIDDeviceUsageKey: kHIDUsage_GD_Pointer],
        ]
        IOHIDManagerSetDeviceMatchingMultiple(hidManager, matching as CFArray)

        let context = Unmanaged.passUnretained(self).toOpaque()

        IOHIDManagerRegisterDeviceMatchingCallback(hidManager, { context, _, _, device in
            guard let context else { return }
            Unmanaged<HIDDeviceMonitor>.fromOpaque(context).takeUnretainedValue().deviceAdded(device)
        }, context)

        IOHIDManagerRegisterDeviceRemovalCallback(hidManager, { context, _, _, device in
            guard let context else { return }
            Unmanaged<HIDDeviceMonitor>.fromOpaque(context).takeUnretainedValue().deviceRemoved(device)
        }, context)

        // Fires for every movement and button report. Kept as cheap as possible:
        // it only records which device spoke last.
        IOHIDManagerRegisterInputValueCallback(hidManager, { context, _, _, value in
            guard let context else { return }
            let element = IOHIDValueGetElement(value)
            guard let device = IOHIDElementGetDevice(element) as IOHIDDevice? else { return }
            Unmanaged<HIDDeviceMonitor>.fromOpaque(context).takeUnretainedValue().deviceReportedInput(device)
        }, context)

        IOHIDManagerScheduleWithRunLoop(hidManager, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue)

        let opened = IOHIDManagerOpen(hidManager, IOOptionBits(kIOHIDOptionsTypeNone))
        if opened != kIOReturnSuccess {
            // Not fatal. Without HID, Glide still scrolls and remaps — it simply
            // cannot tell two mice apart, so per-device profiles stop applying.
            log.error("Could not open the HID manager (\(opened)); per-device settings are unavailable")
        }
        manager = hidManager
    }

    public func stop() {
        guard let manager else { return }
        IOHIDManagerUnscheduleFromRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue)
        IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        self.manager = nil
        lock.lock()
        devicesByRef.removeAll()
        lastActive = nil
        lock.unlock()
    }

    // MARK: - Callbacks

    private func deviceAdded(_ device: IOHIDDevice) {
        guard let identity = HIDDeviceMonitor.identify(device) else { return }
        lock.lock()
        devicesByRef[device] = identity
        let snapshot = Array(devicesByRef.values)
        lock.unlock()
        log.info("Device connected: \(identity.displayName, privacy: .public)")
        notify(snapshot)
    }

    private func deviceRemoved(_ device: IOHIDDevice) {
        lock.lock()
        let removed = devicesByRef.removeValue(forKey: device)
        // Drop a stale attribution pointing at a device that just went away.
        if let removed, lastActive?.identity.key == removed.key { lastActive = nil }
        let snapshot = Array(devicesByRef.values)
        lock.unlock()
        if let removed { log.info("Device disconnected: \(removed.displayName, privacy: .public)") }
        notify(snapshot)
    }

    private func deviceReportedInput(_ device: IOHIDDevice) {
        lock.lock()
        if let identity = devicesByRef[device] {
            lastActive = (identity, MonotonicClock.now)
        }
        lock.unlock()
    }

    private func notify(_ snapshot: [DeviceIdentity]) {
        let sorted = snapshot.sorted { $0.displayName < $1.displayName }
        DispatchQueue.main.async { [weak self] in self?.onDevicesChanged?(sorted) }
    }

    // MARK: - Identification

    private static func identify(_ device: IOHIDDevice) -> DeviceIdentity? {
        func string(_ key: String) -> String? {
            IOHIDDeviceGetProperty(device, key as CFString) as? String
        }
        func number(_ key: String) -> Int? {
            (IOHIDDeviceGetProperty(device, key as CFString) as? NSNumber)?.intValue
        }

        guard let vendorID = number(kIOHIDVendorIDKey), let productID = number(kIOHIDProductIDKey) else {
            return nil
        }

        // Real button count, read from the HID descriptor rather than guessed.
        // Needed so the bindings UI can offer the buttons a device actually has
        // instead of a fixed list of five.
        let buttonMatch: [String: Any] = [kIOHIDElementUsagePageKey: kHIDPage_Button]
        let buttons = IOHIDDeviceCopyMatchingElements(
            device, buttonMatch as CFDictionary, IOOptionBits(kIOHIDOptionsTypeNone)
        ) as? [IOHIDElement]

        let transport = string(kIOHIDTransportKey) ?? ""
        return DeviceIdentity(
            vendorID: vendorID,
            productID: productID,
            serialNumber: string(kIOHIDSerialNumberKey),
            productName: string(kIOHIDProductKey) ?? "Pointing Device",
            manufacturer: string(kIOHIDManufacturerKey),
            buttonCount: buttons.map { $0.count },
            isWireless: transport.localizedCaseInsensitiveContains("bluetooth")
                || transport.localizedCaseInsensitiveContains("wireless")
        )
    }
}
