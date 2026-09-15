import GlideCore
import SwiftUI

struct ProfilesView: View {

    @EnvironmentObject private var state: AppState

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Design.Space.lg) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Profiles").font(Design.Typography.display)
                    Text("Layers of settings, applied from general to specific.")
                        .font(Design.Typography.body)
                        .foregroundStyle(Design.Palette.secondaryLabel)
                }

                explainer

                Card("Layers") {
                    VStack(spacing: 0) {
                        ForEach(Array(sortedProfiles.enumerated()), id: \.element.id) { index, profile in
                            if index > 0 { Divider() }
                            ProfileRow(
                                profile: profile,
                                isSelected: state.selectedProfileID == profile.id,
                                depth: profile.scope.specificity
                            ) {
                                state.selectedProfileID = profile.id
                            } onToggle: { enabled in
                                state.edit { document in
                                    guard let i = document.profiles.firstIndex(where: { $0.id == profile.id }) else { return }
                                    document.profiles[i].isEnabled = enabled
                                }
                            } onDuplicate: {
                                state.duplicateProfile(profile.id)
                            } onDelete: {
                                state.deleteProfile(profile.id)
                            }
                        }
                    }

                    HStack(spacing: Design.Space.sm) {
                        Button { state.addProfile() } label: { Label("Add Layer", systemImage: "plus") }
                            .buttonStyle(.bordered)
                        Button {
                            state.addProfile(
                                name: state.engine.frontmostApplication ?? "App Layer",
                                scope: ProfileScope(applications: [state.engine.frontmostApplication ?? ""])
                            )
                        } label: {
                            Label("Add for Current App", systemImage: "app.badge")
                        }
                        .buttonStyle(.bordered)
                        .disabled(state.engine.frontmostApplication == nil)
                    }
                    .padding(.top, Design.Space.xs)
                }

                if let profile = state.selectedProfile {
                    scopeEditor(for: profile)
                }
            }
            .padding(Design.Space.xl)
            .frame(maxWidth: 780, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
    }

    private var sortedProfiles: [Profile] {
        state.document.profiles.sorted {
            $0.scope.specificity == $1.scope.specificity
                ? $0.name.localizedStandardCompare($1.name) == .orderedAscending
                : $0.scope.specificity < $1.scope.specificity
        }
    }

    /// Most tools in this category make you pick one profile, which means a
    /// per-app profile has to restate everything. Explaining the difference up
    /// front saves the confusion of an override that appears not to work.
    private var explainer: some View {
        HStack(alignment: .top, spacing: Design.Space.md) {
            Image(systemName: "square.3.layers.3d.top.filled")
                .font(.system(size: 22))
                .foregroundStyle(Design.Palette.accentGradient)
            VStack(alignment: .leading, spacing: 4) {
                Text("Layers stack, they don't compete").font(Design.Typography.heading)
                Text("""
                     The base layer applies everywhere. A device layer sits on top of it, an \
                     app layer on top of that. Each one overrides only the settings it actually \
                     changes, so a layer that just flips scroll direction says exactly that and \
                     inherits the rest.
                     """)
                    .font(Design.Typography.caption)
                    .foregroundStyle(Design.Palette.secondaryLabel)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(Design.Space.lg)
        .background(Design.Palette.accent.opacity(0.07), in: RoundedRectangle(cornerRadius: Design.Radius.lg, style: .continuous))
    }

    private func scopeEditor(for profile: Profile) -> some View {
        Card("Applies to", subtitle: "Leave both empty for a layer that applies everywhere.") {
            SettingRow("Applications", help: "Bundle identifiers, comma separated.") {
                TextField("com.apple.Safari, com.figma.Desktop", text: .init(
                    get: { profile.scope.applications.sorted().joined(separator: ", ") },
                    set: { text in
                        let items = text.split(separator: ",")
                            .map { $0.trimmingCharacters(in: .whitespaces) }
                            .filter { !$0.isEmpty }
                        state.editSelectedProfile { $0.scope.applications = Set(items) }
                    }
                ))
                .textFieldStyle(.roundedBorder)
                .frame(width: 300)
            }

            Divider()

            SettingRow("Devices") {
                VStack(alignment: .trailing, spacing: Design.Space.xs) {
                    ForEach(state.engine.connectedDevices.filter { !$0.isAppleDevice }) { device in
                        Toggle(device.displayName, isOn: .init(
                            get: { profile.scope.devices.contains(device.key) },
                            set: { on in
                                state.editSelectedProfile { editing in
                                    if on { editing.scope.devices.insert(device.key) }
                                    else { editing.scope.devices.remove(device.key) }
                                }
                            }
                        ))
                        .toggleStyle(.checkbox)
                    }
                    if state.engine.connectedDevices.filter({ !$0.isAppleDevice }).isEmpty {
                        Text("No third-party mice connected")
                            .font(Design.Typography.caption)
                            .foregroundStyle(Design.Palette.tertiaryLabel)
                    }
                }
            }
        }
    }
}

struct ProfileRow: View {
    let profile: Profile
    let isSelected: Bool
    let depth: Int
    let onSelect: () -> Void
    let onToggle: (Bool) -> Void
    let onDuplicate: () -> Void
    let onDelete: () -> Void

    @State private var isHovering = false

    var body: some View {
        HStack(spacing: Design.Space.md) {
            // Indentation mirrors the layer order, so the stack is legible at a
            // glance rather than needing to be read.
            Spacer().frame(width: CGFloat(depth) * 14)

            Image(systemName: profile.symbolName)
                .foregroundStyle(isSelected ? Design.Palette.accent : Design.Palette.secondaryLabel)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 1) {
                Text(profile.name).font(Design.Typography.body)
                Text(summary)
                    .font(Design.Typography.caption)
                    .foregroundStyle(Design.Palette.tertiaryLabel)
            }

            Spacer()

            if isHovering {
                Button(action: onDuplicate) { Image(systemName: "doc.on.doc") }.buttonStyle(.borderless)
                Button(action: onDelete) { Image(systemName: "trash") }.buttonStyle(.borderless).foregroundStyle(.red)
            }

            Toggle("", isOn: .init(get: { profile.isEnabled }, set: onToggle))
                .labelsHidden().toggleStyle(.switch).controlSize(.mini)
        }
        .padding(.vertical, Design.Space.sm)
        .padding(.horizontal, Design.Space.sm)
        .background(
            RoundedRectangle(cornerRadius: Design.Radius.sm)
                .fill(isSelected ? Design.Palette.accent.opacity(0.09) : .clear)
        )
        .contentShape(Rectangle())
        .onTapGesture(perform: onSelect)
        .onHover { isHovering = $0 }
        .opacity(profile.isEnabled ? 1 : 0.5)
    }

    private var summary: String {
        var parts: [String] = []
        if profile.scope.isGlobal { parts.append("Everywhere") }
        if !profile.scope.applications.isEmpty { parts.append("\(profile.scope.applications.count) app(s)") }
        if !profile.scope.devices.isEmpty { parts.append("\(profile.scope.devices.count) device(s)") }
        if !profile.bindings.isEmpty { parts.append("\(profile.bindings.count) binding(s)") }
        return parts.joined(separator: " · ")
    }
}
