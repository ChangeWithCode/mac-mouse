import Foundation

/// Identifies a physical pointing device.
///
/// Built from the IOHID properties rather than anything macOS assigns at
/// runtime, so a mouse keeps its settings across reboots, across USB ports and
/// across a Bluetooth re-pair.
public struct DeviceIdentity: Hashable, Codable, Sendable, Identifiable {

    public var vendorID: Int
    public var productID: Int
    /// Present on most wired devices, rarely on Bluetooth ones. When two
    /// identical mice are plugged in, this is the only thing telling them apart.
    public var serialNumber: String?
    public var productName: String
    public var manufacturer: String?
    /// Number of buttons reported by the HID descriptor, when it is trustworthy.
    public var buttonCount: Int?
    public var isWireless: Bool

    public init(
        vendorID: Int,
        productID: Int,
        serialNumber: String? = nil,
        productName: String,
        manufacturer: String? = nil,
        buttonCount: Int? = nil,
        isWireless: Bool = false
    ) {
        self.vendorID = vendorID
        self.productID = productID
        self.serialNumber = serialNumber
        self.productName = productName
        self.manufacturer = manufacturer
        self.buttonCount = buttonCount
        self.isWireless = isWireless
    }

    public var id: String { key }

    /// Stable key used to attach profiles to this device.
    ///
    /// Falls back to vendor/product alone when there is no serial number, which
    /// means two identical serial-less mice share settings. That is the right
    /// trade: the alternative is settings that silently reset when a device
    /// reconnects on a different port.
    public var key: String {
        if let serial = serialNumber, !serial.isEmpty {
            return "\(vendorID):\(productID):\(serial)"
        }
        return "\(vendorID):\(productID)"
    }

    public var displayName: String {
        if let manufacturer, !productName.lowercased().contains(manufacturer.lowercased()) {
            return "\(manufacturer) \(productName)"
        }
        return productName
    }

    /// Apple's own pointing devices, which Glide leaves strictly alone: macOS
    /// already scrolls them properly, and intercepting a Magic Trackpad would
    /// break the very gestures we are imitating.
    public var isAppleDevice: Bool { vendorID == 0x05AC || vendorID == 0x004C }
}
