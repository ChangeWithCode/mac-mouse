import Foundation

/// Scroll settings as stored in a profile.
///
/// Every field is optional, and that is the point: `nil` means "inherit from the
/// layer beneath". A per-app profile that only wants to flip the scroll
/// direction says so and leaves everything else alone, instead of having to
/// carry a full copy of the global settings that then goes stale.
public struct ScrollSettings: Hashable, Codable, Sendable {

    public var preset: ScrollPreset?
    public var invertVertical: Bool?
    public var invertHorizontal: Bool?
    /// Whether a tilting wheel or a horizontal axis scrolls sideways.
    public var horizontalEnabled: Bool?
    /// Extra impulse on a recognised flick.
    public var flickBoost: Double?
    /// Master switch. Off hands the wheel straight back to macOS, which is the
    /// escape hatch for apps that do their own scroll handling.
    public var smoothingEnabled: Bool?

    public init(
        preset: ScrollPreset? = nil,
        invertVertical: Bool? = nil,
        invertHorizontal: Bool? = nil,
        horizontalEnabled: Bool? = nil,
        flickBoost: Double? = nil,
        smoothingEnabled: Bool? = nil
    ) {
        self.preset = preset
        self.invertVertical = invertVertical
        self.invertHorizontal = invertHorizontal
        self.horizontalEnabled = horizontalEnabled
        self.flickBoost = flickBoost
        self.smoothingEnabled = smoothingEnabled
    }

    /// Lays this layer over `base`. Fields set here win; the rest show through.
    public func overlaying(_ base: ScrollSettings) -> ScrollSettings {
        ScrollSettings(
            preset: preset ?? base.preset,
            invertVertical: invertVertical ?? base.invertVertical,
            invertHorizontal: invertHorizontal ?? base.invertHorizontal,
            horizontalEnabled: horizontalEnabled ?? base.horizontalEnabled,
            flickBoost: flickBoost ?? base.flickBoost,
            smoothingEnabled: smoothingEnabled ?? base.smoothingEnabled
        )
    }

    /// Whether this layer overrides anything at all. Drives the "customised"
    /// badge in the profile list.
    public var isEmpty: Bool {
        preset == nil && invertVertical == nil && invertHorizontal == nil
            && horizontalEnabled == nil && flickBoost == nil && smoothingEnabled == nil
    }
}

/// Pointer (cursor) settings, kept separate from scrolling because the two are
/// tuned independently and people often want one without the other.
public struct PointerSettings: Hashable, Codable, Sendable {

    /// Cursor speed multiplier. `nil` inherits.
    public var sensitivity: Double?
    /// Disables macOS pointer acceleration, giving a 1:1 response. The single
    /// most requested feature from anyone who also plays games.
    public var disableAcceleration: Bool?
    /// Custom acceleration curve, applied when `disableAcceleration` is off.
    public var accelerationCurve: UnitBezier?

    public init(
        sensitivity: Double? = nil,
        disableAcceleration: Bool? = nil,
        accelerationCurve: UnitBezier? = nil
    ) {
        self.sensitivity = sensitivity
        self.disableAcceleration = disableAcceleration
        self.accelerationCurve = accelerationCurve
    }

    public func overlaying(_ base: PointerSettings) -> PointerSettings {
        PointerSettings(
            sensitivity: sensitivity ?? base.sensitivity,
            disableAcceleration: disableAcceleration ?? base.disableAcceleration,
            accelerationCurve: accelerationCurve ?? base.accelerationCurve
        )
    }

    public var isEmpty: Bool {
        sensitivity == nil && disableAcceleration == nil && accelerationCurve == nil
    }
}

/// A fully determined configuration, with every inheritance question answered.
/// This is what the event pipeline reads; it never sees an optional.
public struct ResolvedSettings: Hashable, Sendable {

    public var scrollPreset: ScrollPreset
    public var invertVertical: Bool
    public var invertHorizontal: Bool
    public var horizontalEnabled: Bool
    public var flickBoost: Double
    public var smoothingEnabled: Bool

    public var pointerSensitivity: Double
    public var disablePointerAcceleration: Bool
    public var pointerAccelerationCurve: UnitBezier?

    /// Bindings in match order, most specific first.
    public var bindings: [Binding]

    /// The defaults a fresh install runs with.
    public static let fallback = ResolvedSettings(
        scrollPreset: .default,
        invertVertical: false,
        invertHorizontal: false,
        horizontalEnabled: true,
        flickBoost: 1.6,
        smoothingEnabled: true,
        pointerSensitivity: 1.0,
        disablePointerAcceleration: false,
        pointerAccelerationCurve: nil,
        bindings: []
    )

    public init(
        scrollPreset: ScrollPreset,
        invertVertical: Bool,
        invertHorizontal: Bool,
        horizontalEnabled: Bool,
        flickBoost: Double,
        smoothingEnabled: Bool,
        pointerSensitivity: Double,
        disablePointerAcceleration: Bool,
        pointerAccelerationCurve: UnitBezier?,
        bindings: [Binding]
    ) {
        self.scrollPreset = scrollPreset
        self.invertVertical = invertVertical
        self.invertHorizontal = invertHorizontal
        self.horizontalEnabled = horizontalEnabled
        self.flickBoost = flickBoost
        self.smoothingEnabled = smoothingEnabled
        self.pointerSensitivity = pointerSensitivity
        self.disablePointerAcceleration = disablePointerAcceleration
        self.pointerAccelerationCurve = pointerAccelerationCurve
        self.bindings = bindings
    }

    /// The binding that should handle `trigger`, or nil.
    public func binding(for trigger: ButtonTrigger) -> Binding? {
        bindings.first { $0.isEnabled && $0.trigger == trigger }
    }

    /// Whether any enabled binding involves `button`. Drives the recogniser's
    /// fast path — an untouched button is never intercepted.
    public func hasAnyBinding(for button: MouseButton) -> Bool {
        bindings.contains { $0.isEnabled && $0.trigger.buttons.contains(button) }
    }
}
