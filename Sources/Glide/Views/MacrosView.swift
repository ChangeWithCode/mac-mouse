import GlideCore
import SwiftUI

struct MacrosView: View {

    @EnvironmentObject private var state: AppState

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Design.Space.lg) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Macros").font(Design.Typography.display)
                    Text("Sequences of keystrokes, clicks and pauses, bound to a single button.")
                        .font(Design.Typography.body)
                        .foregroundStyle(Design.Palette.secondaryLabel)
                }

                Card("Your macros") {
                    if state.document.macros.isEmpty {
                        VStack(spacing: Design.Space.sm) {
                            Image(systemName: "wand.and.stars")
                                .font(.system(size: 28))
                                .foregroundStyle(Design.Palette.tertiaryLabel)
                            Text("No macros yet").font(Design.Typography.body)
                                .foregroundStyle(Design.Palette.secondaryLabel)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, Design.Space.lg)
                    } else {
                        VStack(spacing: 0) {
                            ForEach(Array(state.document.macros.enumerated()), id: \.element.id) { index, macro in
                                if index > 0 { Divider() }
                                MacroRow(macro: macro) {
                                    state.edit { $0.macros.removeAll { $0.id == macro.id } }
                                }
                            }
                        }
                    }

                    Button {
                        state.edit { $0.macros.append(Macro(name: "New Macro", steps: [.delay(seconds: 0.1)])) }
                    } label: {
                        Label("Add Macro", systemImage: "plus")
                    }
                    .buttonStyle(.bordered)
                    .padding(.top, Design.Space.xs)
                }

                Card("Shell commands", subtitle: "Off by default.") {
                    SettingRow(
                        "Allow shell commands",
                        help: """
                              A profile is a JSON file that can be shared or synced. Importing \
                              one should not be enough to run code on your machine, so this \
                              stays off until you turn it on.
                              """
                    ) {
                        Toggle("", isOn: .init(
                            get: { state.document.allowsShellCommands },
                            set: { value in state.edit { $0.allowsShellCommands = value } }
                        ))
                        .labelsHidden()
                        .toggleStyle(.switch)
                    }
                }
            }
            .padding(Design.Space.xl)
            .frame(maxWidth: 780, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
    }
}

struct MacroRow: View {
    let macro: Macro
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: Design.Space.md) {
            Image(systemName: "wand.and.stars")
                .foregroundStyle(Design.Palette.accent)
                .frame(width: 24, height: 24)
                .background(Design.Palette.accent.opacity(0.10), in: RoundedRectangle(cornerRadius: Design.Radius.sm))

            VStack(alignment: .leading, spacing: 1) {
                Text(macro.name).font(Design.Typography.body)
                Text("\(macro.steps.count) steps · \(String(format: "%.2fs", macro.duration))")
                    .font(Design.Typography.caption)
                    .foregroundStyle(Design.Palette.tertiaryLabel)
            }

            Spacer()

            if macro.repeatsWhileHeld { StatusPill("Repeats", tone: .neutral) }
            Button(action: onDelete) { Image(systemName: "trash") }
                .buttonStyle(.borderless)
                .foregroundStyle(.red)
        }
        .padding(.vertical, Design.Space.sm)
    }
}
