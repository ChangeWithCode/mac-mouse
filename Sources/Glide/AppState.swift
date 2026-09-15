import Combine
import Foundation
import GlideCore
import GlideKit
import SwiftUI

/// The app's single source of truth.
///
/// Holds the document, owns the engine, and is responsible for keeping the two
/// in step: every edit re-resolves the profile stack and pushes it into the
/// running pipeline, so the settings window always shows what is actually in
/// force rather than what was saved last.
@MainActor
public final class AppState: ObservableObject {

    public enum Section: String, CaseIterable, Identifiable, Hashable {
        case scrolling, buttons, gestures, profiles, devices, macros, general
        public var id: String { rawValue }

        public var title: String {
            switch self {
            case .scrolling: return "Scrolling"
            case .buttons:   return "Buttons"
            case .gestures:  return "Gestures"
            case .profiles:  return "Profiles"
            case .devices:   return "Devices"
            case .macros:    return "Macros"
            case .general:   return "General"
            }
        }

        public var symbol: String {
            switch self {
            case .scrolling: return "arrow.up.and.down.circle"
            case .buttons:   return "computermouse"
            case .gestures:  return "hand.draw"
            case .profiles:  return "square.stack.3d.up"
            case .devices:   return "cable.connector"
            case .macros:    return "wand.and.stars"
            case .general:   return "gearshape"
            }
        }
    }

    @Published public var document: ProfileStore.Document
    @Published public var section: Section = .scrolling
    @Published public var selectedProfileID: UUID?
    @Published public var permissionGranted: Bool
    @Published public var saveError: String?

    public let engine = GlideEngine()
    private let store: ProfileStore
    private var permissionTimer: Timer?
    private var saveWorkItem: DispatchWorkItem?
    private var cancellables = Set<AnyCancellable>()

    public init() {
        let url = (try? ProfileStore.defaultURL()) ?? URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("glide-profiles.json")
        self.store = ProfileStore(url: url)
        // A document written by a newer Glide throws rather than being
        // overwritten — better to run on defaults for one session than to
        // destroy settings this build cannot represent.
        self.document = (try? store.load()) ?? ProfileStore.Document()
        self.permissionGranted = AccessibilityPermission.isGranted
        self.selectedProfileID = document.profiles.first?.id

        // SwiftUI observes AppState, not the engine nested inside it, so the
        // engine's own changes — devices appearing, the frontmost app switching,
        // the tap being paused — would never redraw anything. Forwarding its
        // notifications is what keeps the status footer honest.
        engine.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)

        push()
        if permissionGranted { startEngine() } else { watchForPermission() }
    }

    // MARK: - Engine

    private func startEngine() {
        do {
            try engine.start()
        } catch {
            saveError = error.localizedDescription
        }
    }

    private func watchForPermission() {
        permissionTimer = AccessibilityPermission.waitForGrant { [weak self] in
            guard let self else { return }
            self.permissionGranted = true
            self.startEngine()
        }
    }

    /// Pushes the current document into the running engine.
    public func push() {
        engine.apply(
            profiles: document.profiles,
            macros: document.macros,
            allowsShellCommands: document.allowsShellCommands
        )
    }

    // MARK: - Editing

    /// Applies an edit, pushes it to the engine immediately, and schedules a save.
    ///
    /// The engine is updated synchronously so that dragging a curve handle is
    /// felt in the very next scroll, while the disk write is coalesced — a drag
    /// produces dozens of edits a second and each one does not need its own
    /// atomic file replacement.
    public func edit(_ mutate: (inout ProfileStore.Document) -> Void) {
        mutate(&document)
        push()
        scheduleSave()
    }

    /// Mutates the selected profile.
    public func editSelectedProfile(_ mutate: (inout Profile) -> Void) {
        guard let id = selectedProfileID,
              let index = document.profiles.firstIndex(where: { $0.id == id }) else { return }
        edit { document in mutate(&document.profiles[index]) }
    }

    public var selectedProfile: Profile? {
        document.profiles.first { $0.id == selectedProfileID }
    }

    private func scheduleSave() {
        saveWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.saveNow() }
        saveWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: work)
    }

    public func saveNow() {
        do {
            try store.save(document)
            saveError = nil
        } catch {
            saveError = error.localizedDescription
        }
    }

    // MARK: - Profiles

    public func addProfile(name: String = "New Profile", scope: ProfileScope = .global) {
        let profile = Profile(name: name, scope: scope)
        edit { $0.profiles.append(profile) }
        selectedProfileID = profile.id
    }

    public func deleteProfile(_ id: UUID) {
        // The last profile is the base of the stack; removing it would leave
        // nothing for the resolver to fall back to.
        guard document.profiles.count > 1 else { return }
        edit { $0.profiles.removeAll { $0.id == id } }
        if selectedProfileID == id { selectedProfileID = document.profiles.first?.id }
    }

    public func duplicateProfile(_ id: UUID) {
        guard var copy = document.profiles.first(where: { $0.id == id }) else { return }
        copy.id = UUID()
        copy.name += " Copy"
        edit { $0.profiles.append(copy) }
        selectedProfileID = copy.id
    }
}
