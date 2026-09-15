import GlideKit
import SwiftUI

@main
struct GlideApp: App {

    @StateObject private var state = AppState()
    @Environment(\.openWindow) private var openWindow

    var body: some Scene {
        Window("Glide", id: "settings") {
            RootView()
                .environmentObject(state)
                .frame(minWidth: 940, minHeight: 620)
        }
        .windowToolbarStyle(.unified(showsTitle: false))
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandGroup(after: .appSettings) {
                Button("Pause Glide") { state.engine.setPaused(true) }
                    .keyboardShortcut("p", modifiers: [.command, .shift])
            }
        }

        // The menu bar item is the app's real home: most of the time Glide
        // should be invisible, and the settings window is somewhere you visit
        // occasionally rather than keep open.
        MenuBarExtra("Glide", systemImage: "computermouse.fill") {
            MenuBarView()
                .environmentObject(state)
        }
        .menuBarExtraStyle(.window)
    }
}
