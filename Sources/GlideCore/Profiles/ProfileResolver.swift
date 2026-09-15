import Foundation

/// Flattens the profile stack into one concrete configuration.
///
/// Glide layers rather than picks. Most tools of this kind make you choose a
/// single profile, which means a per-app profile has to restate every global
/// setting — and then drift out of sync the moment you change your mind about
/// one of them. Here the global profile is the base, a device profile lays over
/// it, an app profile over that, and a modal profile over everything. Each layer
/// overrides only what it actually sets.
public struct ProfileResolver {

    public init() {}

    /// Resolves the active configuration for a given app and device.
    ///
    /// - Parameters:
    ///   - profiles: Every profile, in any order.
    ///   - application: Bundle identifier of the frontmost app.
    ///   - device: The device that produced the event being handled.
    ///   - modalProfileID: A profile activated by a binding, if one is held.
    public func resolve(
        profiles: [Profile],
        application: String?,
        device: DeviceIdentity?,
        modalProfileID: UUID? = nil
    ) -> ResolvedSettings {

        // Scope matches, weakest first, so stronger layers overwrite them.
        // Ties are broken by name for a stable, predictable order rather than
        // whatever order the store happened to hand back.
        var layers = profiles
            .filter { $0.isEnabled && !$0.isModal && $0.scope.matches(application: application, device: device) }
            .sorted { lhs, rhs in
                lhs.scope.specificity == rhs.scope.specificity
                    ? lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
                    : lhs.scope.specificity < rhs.scope.specificity
            }

        // A held modal profile sits above every scope-matched layer.
        if let modalProfileID, let modal = profiles.first(where: { $0.id == modalProfileID && $0.isEnabled }) {
            layers.append(modal)
        }

        var scroll = ScrollSettings()
        var pointer = PointerSettings()
        for layer in layers {
            scroll = layer.scroll.overlaying(scroll)
            pointer = layer.pointer.overlaying(pointer)
        }

        // Bindings resolve per trigger: the most specific layer that binds a
        // trigger owns it. Walking the layers in reverse means the first match
        // found is already the winner.
        var seen = Set<ButtonTrigger>()
        var bindings: [Binding] = []
        for layer in layers.reversed() {
            for binding in layer.bindings where binding.isEnabled {
                guard !seen.contains(binding.trigger) else { continue }
                seen.insert(binding.trigger)
                bindings.append(binding)
            }
        }
        // Most specific trigger first, so a chord is tested before its members.
        bindings.sort { $0.trigger.specificity > $1.trigger.specificity }

        let base = ResolvedSettings.fallback
        return ResolvedSettings(
            scrollPreset: scroll.preset ?? base.scrollPreset,
            invertVertical: scroll.invertVertical ?? base.invertVertical,
            invertHorizontal: scroll.invertHorizontal ?? base.invertHorizontal,
            horizontalEnabled: scroll.horizontalEnabled ?? base.horizontalEnabled,
            flickBoost: scroll.flickBoost ?? base.flickBoost,
            smoothingEnabled: scroll.smoothingEnabled ?? base.smoothingEnabled,
            pointerSensitivity: pointer.sensitivity ?? base.pointerSensitivity,
            disablePointerAcceleration: pointer.disableAcceleration ?? base.disablePointerAcceleration,
            pointerAccelerationCurve: pointer.accelerationCurve,
            bindings: bindings
        )
    }

    /// Which profiles contributed to a resolution, for the UI's "why is this
    /// setting what it is" explainer.
    public func contributingProfiles(
        profiles: [Profile],
        application: String?,
        device: DeviceIdentity?
    ) -> [Profile] {
        profiles
            .filter { $0.isEnabled && !$0.isModal && $0.scope.matches(application: application, device: device) }
            .sorted { $0.scope.specificity < $1.scope.specificity }
    }
}
