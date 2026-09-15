import XCTest
@testable import GlideCore

final class ProfileResolverTests: XCTestCase {

    private let resolver = ProfileResolver()

    private let mouse = DeviceIdentity(
        vendorID: 0x046D, productID: 0xC52B, serialNumber: "ABC123",
        productName: "MX Master", manufacturer: "Logitech"
    )
    private let trackball = DeviceIdentity(
        vendorID: 0x046D, productID: 0xB012, productName: "MX Ergo"
    )

    private func base(
        preset: ScrollPreset = .balanced,
        invert: Bool = false,
        bindings: [Binding] = []
    ) -> Profile {
        Profile(
            name: "Base",
            scope: .global,
            scroll: ScrollSettings(preset: preset, invertVertical: invert, smoothingEnabled: true),
            bindings: bindings
        )
    }

    func testAGlobalProfileAppliesEverywhere() {
        let resolved = resolver.resolve(
            profiles: [base(preset: .glide)], application: "com.apple.Safari", device: mouse
        )
        XCTAssertEqual(resolved.scrollPreset.id, "glide")
    }

    /// The point of layering: an app profile that changes one thing inherits
    /// everything else rather than having to restate it.
    func testAnAppLayerOverridesOnlyWhatItSets() {
        let appLayer = Profile(
            name: "Safari",
            scope: ProfileScope(applications: ["com.apple.Safari"]),
            scroll: ScrollSettings(invertVertical: true)   // preset deliberately nil
        )
        let resolved = resolver.resolve(
            profiles: [base(preset: .glide), appLayer],
            application: "com.apple.Safari", device: mouse
        )
        XCTAssertTrue(resolved.invertVertical, "the app layer's override was lost")
        XCTAssertEqual(resolved.scrollPreset.id, "glide", "the inherited preset was clobbered")
    }

    func testALayerDoesNotApplyOutsideItsScope() {
        let appLayer = Profile(
            name: "Safari",
            scope: ProfileScope(applications: ["com.apple.Safari"]),
            scroll: ScrollSettings(invertVertical: true)
        )
        let resolved = resolver.resolve(
            profiles: [base(), appLayer], application: "com.figma.Desktop", device: mouse
        )
        XCTAssertFalse(resolved.invertVertical)
    }

    /// An app constraint outranks a device constraint: what you are doing
    /// changes more often, and more meaningfully, than what you are holding.
    func testAnAppLayerOutranksADeviceLayer() {
        let deviceLayer = Profile(
            name: "Mouse", scope: ProfileScope(devices: [mouse.key]),
            scroll: ScrollSettings(preset: .precise)
        )
        let appLayer = Profile(
            name: "Figma", scope: ProfileScope(applications: ["com.figma.Desktop"]),
            scroll: ScrollSettings(preset: .snappy)
        )
        let resolved = resolver.resolve(
            profiles: [base(), deviceLayer, appLayer],
            application: "com.figma.Desktop", device: mouse
        )
        XCTAssertEqual(resolved.scrollPreset.id, "snappy")
    }

    func testADeviceLayerOnlyAppliesToThatDevice() {
        let deviceLayer = Profile(
            name: "Trackball", scope: ProfileScope(devices: [trackball.key]),
            scroll: ScrollSettings(invertVertical: true)
        )
        XCTAssertTrue(resolver.resolve(profiles: [base(), deviceLayer], application: nil, device: trackball).invertVertical)
        XCTAssertFalse(resolver.resolve(profiles: [base(), deviceLayer], application: nil, device: mouse).invertVertical)
    }

    func testADisabledLayerContributesNothing() {
        var appLayer = Profile(
            name: "Safari", scope: ProfileScope(applications: ["com.apple.Safari"]),
            scroll: ScrollSettings(invertVertical: true)
        )
        appLayer.isEnabled = false
        let resolved = resolver.resolve(
            profiles: [base(), appLayer], application: "com.apple.Safari", device: mouse
        )
        XCTAssertFalse(resolved.invertVertical)
    }

    func testAModalLayerSitsAboveEverything() {
        let appLayer = Profile(
            name: "Safari", scope: ProfileScope(applications: ["com.apple.Safari"]),
            scroll: ScrollSettings(preset: .snappy)
        )
        var modal = Profile(name: "Precision Mode", scroll: ScrollSettings(preset: .precise))
        modal.isModal = true

        let resolved = resolver.resolve(
            profiles: [base(), appLayer, modal],
            application: "com.apple.Safari", device: mouse, modalProfileID: modal.id
        )
        XCTAssertEqual(resolved.scrollPreset.id, "precise")
    }

    func testAModalLayerIsInertUntilActivated() {
        var modal = Profile(name: "Precision Mode", scroll: ScrollSettings(preset: .precise))
        modal.isModal = true
        let resolved = resolver.resolve(
            profiles: [base(preset: .glide), modal], application: nil, device: mouse
        )
        XCTAssertEqual(resolved.scrollPreset.id, "glide")
    }

    // MARK: - Bindings

    func testTheMostSpecificLayerOwnsATrigger() {
        let trigger = ButtonTrigger(.middle, .click(count: 1))
        let global = base(bindings: [Binding(trigger: trigger, action: .missionControl)])
        let appLayer = Profile(
            name: "Safari", scope: ProfileScope(applications: ["com.apple.Safari"]),
            bindings: [Binding(trigger: trigger, action: .launchpad)]
        )
        let resolved = resolver.resolve(
            profiles: [global, appLayer], application: "com.apple.Safari", device: mouse
        )
        XCTAssertEqual(resolved.binding(for: trigger)?.action, .launchpad)
        XCTAssertEqual(resolved.bindings.filter { $0.trigger == trigger }.count, 1,
                       "the overridden binding was not removed")
    }

    func testUnrelatedBindingsFromLowerLayersSurvive() {
        let middle = ButtonTrigger(.middle, .click(count: 1))
        let back = ButtonTrigger(.back, .click(count: 1))
        let global = base(bindings: [
            Binding(trigger: middle, action: .missionControl),
            Binding(trigger: back, action: .back),
        ])
        let appLayer = Profile(
            name: "Safari", scope: ProfileScope(applications: ["com.apple.Safari"]),
            bindings: [Binding(trigger: middle, action: .launchpad)]
        )
        let resolved = resolver.resolve(
            profiles: [global, appLayer], application: "com.apple.Safari", device: mouse
        )
        XCTAssertEqual(resolved.binding(for: middle)?.action, .launchpad)
        XCTAssertEqual(resolved.binding(for: back)?.action, .back)
    }

    /// A chord must be tested before its member buttons, or it could never win.
    func testChordsSortAheadOfSingleButtons() {
        let single = ButtonTrigger(.back, .click(count: 1))
        let chord = ButtonTrigger(buttons: [.back, .forward], kind: .click(count: 1))
        let resolved = resolver.resolve(
            profiles: [base(bindings: [
                Binding(trigger: single, action: .back),
                Binding(trigger: chord, action: .missionControl),
            ])],
            application: nil, device: mouse
        )
        XCTAssertEqual(resolved.bindings.first?.trigger, chord)
    }

    func testHasAnyBindingDrivesTheRecognizerFastPath() {
        let resolved = resolver.resolve(
            profiles: [base(bindings: [Binding(trigger: ButtonTrigger(.back, .click(count: 1)), action: .back)])],
            application: nil, device: mouse
        )
        XCTAssertTrue(resolved.hasAnyBinding(for: .back))
        XCTAssertFalse(resolved.hasAnyBinding(for: .middle))
    }

    func testResolutionFallsBackToDefaultsWithNoProfiles() {
        let resolved = resolver.resolve(profiles: [], application: nil, device: nil)
        XCTAssertEqual(resolved.scrollPreset.id, ScrollPreset.default.id)
        XCTAssertTrue(resolved.bindings.isEmpty)
    }

    // MARK: - Identity

    /// Settings must survive a reconnect on a different port, which is why the
    /// key comes from HID properties rather than anything assigned at runtime.
    func testDeviceKeyIsStableAndDistinct() {
        XCTAssertEqual(mouse.key, DeviceIdentity(
            vendorID: 0x046D, productID: 0xC52B, serialNumber: "ABC123",
            productName: "MX Master", manufacturer: "Logitech"
        ).key)
        XCTAssertNotEqual(mouse.key, trackball.key)
    }

    func testAppleDevicesAreRecognised() {
        XCTAssertTrue(DeviceIdentity(vendorID: 0x05AC, productID: 0x030D, productName: "Magic Trackpad").isAppleDevice)
        XCTAssertFalse(mouse.isAppleDevice)
    }
}
