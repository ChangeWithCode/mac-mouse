import Foundation

/// A trigger bound to an action.
public struct ActionBinding: Identifiable, Hashable, Codable, Sendable {
    public var id: UUID
    public var trigger: ButtonTrigger
    public var action: GlideAction
    public var isEnabled: Bool

    public init(id: UUID = UUID(), trigger: ButtonTrigger, action: GlideAction, isEnabled: Bool = true) {
        self.id = id
        self.trigger = trigger
        self.action = action
        self.isEnabled = isEnabled
    }
}

/// Where a profile applies.
///
/// Empty sets mean "anything", so a scope with no applications and no devices is
/// the global layer. Sets rather than single values because one profile covering
/// every JetBrains IDE, or both of your mice, should not need duplicating.
public struct ProfileScope: Hashable, Codable, Sendable {

    /// Bundle identifiers this profile applies to. Empty matches every app.
    public var applications: Set<String>
    /// Device keys this profile applies to. Empty matches every device.
    public var devices: Set<String>

    public init(applications: Set<String> = [], devices: Set<String> = []) {
        self.applications = applications
        self.devices = devices
    }

    public static let global = ProfileScope()

    public var isGlobal: Bool { applications.isEmpty && devices.isEmpty }

    public func matches(application: String?, device: DeviceIdentity?) -> Bool {
        if !applications.isEmpty {
            guard let application, applications.contains(application) else { return false }
        }
        if !devices.isEmpty {
            guard let device, devices.contains(device.key) else { return false }
        }
        return true
    }

    /// How specific this scope is. Layers are applied in ascending order, so a
    /// higher number wins. An app constraint outranks a device constraint
    /// because "what I am doing" changes more often, and more meaningfully,
    /// than "what I am holding".
    public var specificity: Int {
        var score = 0
        if !devices.isEmpty { score += 1 }
        if !applications.isEmpty { score += 2 }
        return score
    }
}

/// One layer of configuration.
public struct Profile: Identifiable, Hashable, Codable, Sendable {

    public var id: UUID
    public var name: String
    public var isEnabled: Bool
    public var scope: ProfileScope
    public var scroll: ScrollSettings
    public var pointer: PointerSettings
    public var bindings: [ActionBinding]

    /// Set on a profile activated by an `activateProfile` binding rather than by
    /// scope matching. Modal layers sit above everything else while active.
    public var isModal: Bool

    /// SF Symbol shown in the sidebar.
    public var symbolName: String

    public init(
        id: UUID = UUID(),
        name: String,
        isEnabled: Bool = true,
        scope: ProfileScope = .global,
        scroll: ScrollSettings = ScrollSettings(),
        pointer: PointerSettings = PointerSettings(),
        bindings: [ActionBinding] = [],
        isModal: Bool = false,
        symbolName: String = "square.stack.3d.up"
    ) {
        self.id = id
        self.name = name
        self.isEnabled = isEnabled
        self.scope = scope
        self.scroll = scroll
        self.pointer = pointer
        self.bindings = bindings
        self.isModal = isModal
        self.symbolName = symbolName
    }

    /// Whether this layer changes anything.
    public var isEmpty: Bool { scroll.isEmpty && pointer.isEmpty && bindings.isEmpty }

    /// The profile a fresh install starts with: sensible defaults and the three
    /// bindings that make a cheap mouse immediately better than it was.
    public static func makeDefault() -> Profile {
        Profile(
            name: "All Applications",
            scope: .global,
            scroll: ScrollSettings(
                preset: .default,
                invertVertical: false,
                invertHorizontal: false,
                horizontalEnabled: true,
                flickBoost: 1.6,
                smoothingEnabled: true
            ),
            pointer: PointerSettings(sensitivity: 1.0, disableAcceleration: false),
            bindings: [
                ActionBinding(trigger: ButtonTrigger(.middle, .click(count: 1)), action: .missionControl),
                ActionBinding(trigger: ButtonTrigger(.back, .click(count: 1)), action: .back),
                ActionBinding(trigger: ButtonTrigger(.forward, .click(count: 1)), action: .forward),
                ActionBinding(trigger: ButtonTrigger(.middle, .drag), action: .scrollAndNavigate),
            ],
            symbolName: "globe"
        )
    }
}
