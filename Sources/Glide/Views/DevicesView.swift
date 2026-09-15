import GlideCore
import SwiftUI

struct DevicesView: View {

    @EnvironmentObject private var state: AppState

    private var managed: [DeviceIdentity] { state.engine.connectedDevices.filter { !$0.isAppleDevice } }
    private var apple: [DeviceIdentity] { state.engine.connectedDevices.filter { $0.isAppleDevice } }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Design.Space.lg) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Devices").font(Design.Typography.display)
                    Text("Every pointing device Glide can see.")
                        .font(Design.Typography.body)
                        .foregroundStyle(Design.Palette.secondaryLabel)
                }

                Card("Managed", subtitle: "These can have their own layer of settings.") {
                    if managed.isEmpty {
                        Text("No third-party mice connected.")
                            .font(Design.Typography.body)
                            .foregroundStyle(Design.Palette.secondaryLabel)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, Design.Space.lg)
                    } else {
                        VStack(spacing: 0) {
                            ForEach(Array(managed.enumerated()), id: \.element.key) { index, device in
                                if index > 0 { Divider() }
                                DeviceRow(device: device) {
                                    state.addProfile(
                                        name: device.displayName,
                                        scope: ProfileScope(devices: [device.key])
                                    )
                                    state.section = .scrolling
                                }
                            }
                        }
                    }
                }

                if !apple.isEmpty {
                    Card("Left alone", subtitle: "Apple's own devices are never intercepted.") {
                        VStack(spacing: 0) {
                            ForEach(Array(apple.enumerated()), id: \.element.key) { index, device in
                                if index > 0 { Divider() }
                                HStack(spacing: Design.Space.md) {
                                    Image(systemName: "hand.point.up.left")
                                        .foregroundStyle(Design.Palette.tertiaryLabel)
                                    Text(device.displayName).font(Design.Typography.body)
                                    Spacer()
                                    StatusPill("Passthrough", tone: .neutral)
                                }
                                .padding(.vertical, Design.Space.sm)
                            }
                        }
                        Text("""
                             macOS already scrolls these properly, and intercepting a Magic \
                             Trackpad would break the very gestures Glide imitates.
                             """)
                            .font(Design.Typography.caption)
                            .foregroundStyle(Design.Palette.tertiaryLabel)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .padding(Design.Space.xl)
            .frame(maxWidth: 780, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
    }
}

struct DeviceRow: View {
    let device: DeviceIdentity
    let onCreateProfile: () -> Void

    var body: some View {
        HStack(spacing: Design.Space.md) {
            Image(systemName: device.isWireless ? "wave.3.right.circle" : "cable.connector")
                .font(.system(size: 15))
                .foregroundStyle(Design.Palette.accent)

            VStack(alignment: .leading, spacing: 1) {
                Text(device.displayName).font(Design.Typography.body)
                HStack(spacing: Design.Space.sm) {
                    Text(String(format: "%04X:%04X", device.vendorID, device.productID))
                        .font(Design.Typography.readout)
                    if let count = device.buttonCount, count > 0 {
                        Text("\(count) buttons").font(Design.Typography.caption)
                    }
                    if device.serialNumber == nil {
                        // Worth surfacing: two identical serial-less mice share
                        // one identity, so they cannot have separate settings.
                        Text("no serial").font(Design.Typography.caption)
                    }
                }
                .foregroundStyle(Design.Palette.tertiaryLabel)
            }

            Spacer()

            Button("Add Layer", action: onCreateProfile).buttonStyle(.bordered).controlSize(.small)
        }
        .padding(.vertical, Design.Space.sm)
    }
}
