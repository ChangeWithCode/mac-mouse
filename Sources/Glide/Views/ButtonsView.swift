import GlideCore
import SwiftUI

struct ButtonsView: View {

    @EnvironmentObject private var state: AppState
    @State private var editing: ActionBinding?
    @State private var isAdding = false

    private var bindings: [ActionBinding] {
        (state.selectedProfile?.bindings ?? []).sorted { $0.trigger.specificity > $1.trigger.specificity }
    }

    var body: some View {
        ProfilePane("Buttons", subtitle: "What each button, chord and gesture does.") {
            Card(
                "Bindings",
                subtitle: "Unbound buttons are never intercepted, so they keep working exactly as before."
            ) {
                if bindings.isEmpty {
                    emptyState
                } else {
                    VStack(spacing: 0) {
                        ForEach(Array(bindings.enumerated()), id: \.element.id) { index, binding in
                            if index > 0 { Divider() }
                            BindingRow(binding: binding) {
                                editing = binding
                            } onDelete: {
                                state.editSelectedProfile { $0.bindings.removeAll { $0.id == binding.id } }
                            } onToggle: { enabled in
                                state.editSelectedProfile { profile in
                                    guard let i = profile.bindings.firstIndex(where: { $0.id == binding.id }) else { return }
                                    profile.bindings[i].isEnabled = enabled
                                }
                            }
                        }
                    }
                }

                Button {
                    isAdding = true
                } label: {
                    Label("Add Binding", systemImage: "plus")
                }
                .buttonStyle(.bordered)
                .padding(.top, Design.Space.xs)
            }

            Card("Chords", subtitle: "Hold two buttons together to reach a third action.") {
                Text("""
                     Any buttons held at the same time form one chord. A three-button mouse \
                     can carry a dozen actions this way — and because a chord is more specific \
                     than either button alone, it always wins the match.
                     """)
                    .font(Design.Typography.body)
                    .foregroundStyle(Design.Palette.secondaryLabel)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .sheet(item: $editing) { binding in
            BindingEditor(binding: binding) { updated in
                state.editSelectedProfile { profile in
                    guard let i = profile.bindings.firstIndex(where: { $0.id == updated.id }) else { return }
                    profile.bindings[i] = updated
                }
            }
        }
        .sheet(isPresented: $isAdding) {
            BindingEditor(
                binding: ActionBinding(trigger: ButtonTrigger(.middle, .click(count: 1)), action: .missionControl)
            ) { created in
                state.editSelectedProfile { $0.bindings.append(created) }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: Design.Space.sm) {
            Image(systemName: "computermouse")
                .font(.system(size: 28))
                .foregroundStyle(Design.Palette.tertiaryLabel)
            Text("No bindings in this layer")
                .font(Design.Typography.body)
                .foregroundStyle(Design.Palette.secondaryLabel)
            Text("Buttons fall through to the layer beneath, or to the app itself.")
                .font(Design.Typography.caption)
                .foregroundStyle(Design.Palette.tertiaryLabel)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Design.Space.lg)
    }
}

struct BindingRow: View {
    let binding: ActionBinding
    let onEdit: () -> Void
    let onDelete: () -> Void
    let onToggle: (Bool) -> Void

    @State private var isHovering = false

    var body: some View {
        HStack(spacing: Design.Space.md) {
            Image(systemName: binding.action.symbolName)
                .font(.system(size: 13))
                .foregroundStyle(Design.Palette.accent)
                .frame(width: 24, height: 24)
                .background(Design.Palette.accent.opacity(0.10), in: RoundedRectangle(cornerRadius: Design.Radius.sm))

            VStack(alignment: .leading, spacing: 1) {
                Text(binding.trigger.displayName).font(Design.Typography.body)
                Text(binding.action.displayName)
                    .font(Design.Typography.caption)
                    .foregroundStyle(Design.Palette.secondaryLabel)
            }

            Spacer()

            if binding.trigger.isChord { StatusPill("Chord", tone: .neutral) }

            if isHovering {
                Button(action: onEdit) { Image(systemName: "pencil") }.buttonStyle(.borderless)
                Button(action: onDelete) { Image(systemName: "trash") }.buttonStyle(.borderless).foregroundStyle(.red)
            }

            Toggle("", isOn: .init(get: { binding.isEnabled }, set: onToggle))
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.mini)
        }
        .padding(.vertical, Design.Space.sm)
        .contentShape(Rectangle())
        .onHover { isHovering = $0 }
        .opacity(binding.isEnabled ? 1 : 0.5)
    }
}

/// Sheet for creating or changing a binding.
struct BindingEditor: View {

    @State private var draft: ActionBinding
    @Environment(\.dismiss) private var dismiss
    private let onSave: (ActionBinding) -> Void

    init(binding: ActionBinding, onSave: @escaping (ActionBinding) -> Void) {
        _draft = State(initialValue: binding)
        self.onSave = onSave
    }

    private static let availableActions: [GlideAction] = [
        .none, .missionControl, .applicationWindows, .showDesktop, .launchpad,
        .spotlight, .lockScreen, .spaceLeft, .spaceRight, .back, .forward,
        .lookUp, .middleClick, .rightClick, .scrollAndNavigate, .autoScroll,
        .volumeUp, .volumeDown, .mute, .playPause, .nextTrack, .previousTrack,
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: Design.Space.lg) {
            Text("Binding").font(Design.Typography.title)

            Card("Trigger") {
                SettingRow("Button") {
                    Picker("", selection: buttonBinding) {
                        ForEach(MouseButton.remappable.prefix(8)) { button in
                            Text(button.displayName).tag(button)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 170)
                }
                Divider()
                SettingRow("Gesture") {
                    Picker("", selection: kindBinding) {
                        Text("Click").tag(ButtonTrigger.Kind.click(count: 1))
                        Text("Double-click").tag(ButtonTrigger.Kind.click(count: 2))
                        Text("Hold").tag(ButtonTrigger.Kind.hold)
                        Text("Drag").tag(ButtonTrigger.Kind.drag)
                    }
                    .labelsHidden()
                    .frame(width: 170)
                }
            }

            Card("Action") {
                Picker("", selection: $draft.action) {
                    ForEach(Self.availableActions, id: \.self) { action in
                        Label(action.displayName, systemImage: action.symbolName).tag(action)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)

                if draft.trigger.kindIsDrag && !draft.action.isContinuous {
                    Label(
                        "A drag needs a continuous action such as Scroll & Navigate.",
                        systemImage: "exclamationmark.triangle"
                    )
                    .font(Design.Typography.caption)
                    .foregroundStyle(.orange)
                }
            }

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Save") { onSave(draft); dismiss() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(Design.Space.xl)
        .frame(width: 460)
    }

    private var buttonBinding: SwiftUI.Binding<MouseButton> {
        .init(
            get: { draft.trigger.orderedButtons.first ?? .middle },
            set: { draft.trigger.buttons = [$0] }
        )
    }

    private var kindBinding: SwiftUI.Binding<ButtonTrigger.Kind> {
        .init(get: { draft.trigger.kind }, set: { draft.trigger.kind = $0 })
    }
}

private extension ButtonTrigger {
    var kindIsDrag: Bool { if case .drag = kind { return true }; return false }
}
