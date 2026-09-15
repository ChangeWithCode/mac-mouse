import GlideCore
import SwiftUI

struct ScrollTuningView: View {

    @EnvironmentObject private var state: AppState

    var body: some View {
        ProfilePane("Scrolling", subtitle: "How a wheel notch becomes movement on screen.") {
            presetPicker
            curveCard
            feelCard
            directionCard
        }
    }

    // MARK: - Derived bindings
    //
    // Profile settings are optional so that a layer can inherit. These bindings
    // read through to the resolved value and write a concrete one, so the UI
    // never shows an empty control and editing always creates an override.

    private var preset: ScrollPreset {
        state.selectedProfile?.scroll.preset ?? .default
    }

    private func binding<T>(
        _ keyPath: WritableKeyPath<ScrollSettings, T?>,
        default defaultValue: T
    ) -> Binding<T> {
        Binding(
            get: { state.selectedProfile?.scroll[keyPath: keyPath] ?? defaultValue },
            set: { newValue in state.editSelectedProfile { $0.scroll[keyPath: keyPath] = newValue } }
        )
    }

    private var presetBinding: Binding<ScrollPreset> {
        Binding(
            get: { preset },
            set: { newValue in state.editSelectedProfile { $0.scroll.preset = newValue } }
        )
    }

    private var curveBinding: Binding<AccelerationCurve> {
        Binding(
            get: { preset.acceleration },
            set: { newCurve in
                state.editSelectedProfile { profile in
                    var updated = profile.scroll.preset ?? .default
                    // Editing a built-in forks it, so the shipped presets stay
                    // a reliable place to return to.
                    if updated.isBuiltIn { updated = updated.customized() }
                    updated.acceleration = newCurve
                    profile.scroll.preset = updated
                }
            }
        )
    }

    // MARK: - Sections

    private var presetPicker: some View {
        Card("Feel", subtitle: "A starting point. Every value stays editable.") {
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 150), spacing: Design.Space.md)],
                spacing: Design.Space.md
            ) {
                ForEach(ScrollPreset.builtIn) { candidate in
                    PresetCard(
                        preset: candidate,
                        isSelected: preset.id == candidate.id
                    ) {
                        presetBinding.wrappedValue = candidate
                    }
                }
            }

            if !preset.isBuiltIn {
                HStack(spacing: Design.Space.sm) {
                    Image(systemName: "slider.horizontal.3")
                    Text("Using a customised curve based on this preset.")
                    Spacer()
                    Button("Reset") { presetBinding.wrappedValue = .default }
                        .buttonStyle(.link)
                }
                .font(Design.Typography.caption)
                .foregroundStyle(Design.Palette.secondaryLabel)
            }
        }
    }

    private var curveCard: some View {
        Card(
            "Acceleration",
            subtitle: "Drag the handles. The teal marker follows your wheel as you scroll."
        ) {
            CurveEditor(curve: curveBinding, liveCadence: 0)

            HStack(spacing: Design.Space.xl) {
                readout("Slow", value: preset.acceleration.distance(atSpeed: 2))
                readout("Medium", value: preset.acceleration.distance(atSpeed: 10))
                readout("Fast", value: preset.acceleration.distance(atSpeed: 26))
            }
            .padding(.top, Design.Space.xs)
        }
    }

    private func readout(_ label: String, value: Double) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(Design.Typography.caption).foregroundStyle(Design.Palette.secondaryLabel)
            Text("\(Int(value.rounded())) pt")
                .font(Design.Typography.readout)
                .foregroundStyle(Design.Palette.label)
        }
    }

    private var feelCard: some View {
        Card("Momentum", subtitle: "What happens after you stop turning the wheel.") {
            SettingRow(
                "Coasting",
                help: momentumSummary
            ) {
                Toggle("", isOn: Binding(
                    get: { preset.momentumEnabled },
                    set: { newValue in
                        state.editSelectedProfile { profile in
                            var updated = profile.scroll.preset ?? .default
                            if updated.isBuiltIn { updated = updated.customized() }
                            updated.momentumEnabled = newValue
                            profile.scroll.preset = updated
                        }
                    }
                ))
                .labelsHidden()
                .toggleStyle(.switch)
            }

            Divider()

            SettingRow("Friction", help: "Higher stops sooner.") {
                HStack(spacing: Design.Space.sm) {
                    Slider(
                        value: Binding(
                            get: { preset.friction },
                            set: { newValue in
                                state.editSelectedProfile { profile in
                                    var updated = profile.scroll.preset ?? .default
                                    if updated.isBuiltIn { updated = updated.customized() }
                                    updated.friction = newValue
                                    profile.scroll.preset = updated
                                }
                            }
                        ),
                        in: 2.0...30.0
                    )
                    .frame(width: 180)
                    Text(String(format: "%.1f", preset.friction))
                        .font(Design.Typography.readout)
                        .frame(width: 34, alignment: .trailing)
                }
            }

            Divider()

            SettingRow("Flick boost", help: "Extra reach when you spin the wheel hard.") {
                HStack(spacing: Design.Space.sm) {
                    Slider(value: binding(\.flickBoost, default: 1.6), in: 1.0...3.0)
                        .frame(width: 180)
                    Text(String(format: "%.1f×", state.selectedProfile?.scroll.flickBoost ?? 1.6))
                        .font(Design.Typography.readout)
                        .frame(width: 34, alignment: .trailing)
                }
            }
        }
    }

    /// The closed-form projection, stated in plain language. Being able to say
    /// this before a frame is drawn is the practical payoff of choosing an
    /// analytically integrable decay.
    private var momentumSummary: String {
        guard preset.momentumEnabled else { return "The content stops when the wheel does." }
        let flickVelocity = 16_100.0
        let distance = preset.projectedFlingDistance(velocity: flickVelocity)
        let duration = preset.projectedFlingDuration(velocity: flickVelocity)
        return String(format: "A firm flick coasts about %d pt over %.1f s.", Int(distance.rounded()), duration)
    }

    private var directionCard: some View {
        Card("Direction") {
            SettingRow("Invert vertical", help: "Independent of the system setting, so your trackpad is unaffected.") {
                Toggle("", isOn: binding(\.invertVertical, default: false)).labelsHidden().toggleStyle(.switch)
            }
            Divider()
            SettingRow("Invert horizontal") {
                Toggle("", isOn: binding(\.invertHorizontal, default: false)).labelsHidden().toggleStyle(.switch)
            }
            Divider()
            SettingRow("Horizontal scrolling", help: "For tilt wheels and thumb wheels.") {
                Toggle("", isOn: binding(\.horizontalEnabled, default: true)).labelsHidden().toggleStyle(.switch)
            }
            Divider()
            SettingRow("Smooth scrolling", help: "Off hands the wheel straight back to macOS.") {
                Toggle("", isOn: binding(\.smoothingEnabled, default: true)).labelsHidden().toggleStyle(.switch)
            }
        }
    }
}

/// One preset in the picker.
struct PresetCard: View {
    let preset: ScrollPreset
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: Design.Space.xs) {
                HStack {
                    Text(preset.name).font(Design.Typography.heading)
                    Spacer()
                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(Design.Palette.accent)
                    }
                }
                Text(preset.blurb)
                    .font(Design.Typography.caption)
                    .foregroundStyle(Design.Palette.secondaryLabel)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(Design.Space.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: Design.Radius.md, style: .continuous)
                    .fill(isSelected ? Design.Palette.accent.opacity(0.10) : Design.Palette.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Design.Radius.md, style: .continuous)
                    .strokeBorder(
                        isSelected ? Design.Palette.accent : Design.Palette.separator.opacity(0.6),
                        lineWidth: isSelected ? 1.5 : 1
                    )
            )
        }
        .buttonStyle(.plain)
        .animation(Design.Motion.subtle, value: isSelected)
    }
}
