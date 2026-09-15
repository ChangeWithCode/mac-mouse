import Foundation

/// Everything a binding can do.
///
/// Deliberately an enum with associated values rather than a class hierarchy:
/// bindings are persisted as JSON and edited in a picker, and an enum keeps both
/// of those honest — adding a case forces every switch to be updated.
public enum GlideAction: Hashable, Codable, Sendable {

    /// Explicitly nothing. Distinct from having no binding: `none` *swallows*
    /// the button, which is how you stop a stray thumb button from triggering
    /// an app's own back navigation.
    case none

    // MARK: System

    case missionControl
    case applicationWindows
    case showDesktop
    case launchpad
    case notificationCentre
    case spotlight
    case lockScreen
    case sleepDisplay

    // MARK: Spaces

    case spaceLeft
    case spaceRight
    /// Jump to a specific desktop, 1-indexed as the UI presents them.
    case space(index: Int)

    // MARK: Navigation

    case back
    case forward
    case lookUp
    case smartZoom

    // MARK: Pointer passthrough
    //
    // Some buttons are most useful as other buttons — a broken middle click
    // remapped onto a thumb button, for instance.

    case leftClick
    case rightClick
    case middleClick

    // MARK: Continuous gestures
    //
    // These run for as long as the trigger is held, rather than firing once.

    /// Drag to scroll in any direction and swipe-navigate, emulating two fingers
    /// on a trackpad. The cursor is frozen and a stand-in is drawn while active.
    case scrollAndNavigate
    /// Windows-style autoscroll: press, then the distance from the origin sets a
    /// continuous scroll velocity.
    case autoScroll
    /// Drag to zoom, as a trackpad pinch.
    case pinchZoom
    /// Drag to move between desktops and into Mission Control.
    case spaceNavigation

    // MARK: Media and system levels

    case volumeUp
    case volumeDown
    case mute
    case brightnessUp
    case brightnessDown
    case playPause
    case nextTrack
    case previousTrack

    // MARK: Composites

    case keystroke(Keystroke)
    case macro(id: UUID)
    case launchApplication(bundleIdentifier: String)
    case openURL(String)
    /// Runs a shell command. Off by default and gated behind an explicit
    /// opt-in in settings, because a synced profile could otherwise carry
    /// arbitrary code onto another machine.
    case shellCommand(String)
    /// Switches the active profile, giving the mouse modal layers.
    case activateProfile(id: UUID)

    /// Whether the action runs continuously while held rather than firing once.
    /// Continuous actions are the only ones that may bind to `.drag`.
    public var isContinuous: Bool {
        switch self {
        case .scrollAndNavigate, .autoScroll, .pinchZoom, .spaceNavigation: return true
        default: return false
        }
    }

    /// Whether the action needs the shell opt-in before it will run.
    public var requiresScriptingConsent: Bool {
        if case .shellCommand = self { return true }
        return false
    }

    public var displayName: String {
        switch self {
        case .none: return "Do Nothing"
        case .missionControl: return "Mission Control"
        case .applicationWindows: return "Application Windows"
        case .showDesktop: return "Show Desktop"
        case .launchpad: return "Launchpad"
        case .notificationCentre: return "Notification Centre"
        case .spotlight: return "Spotlight"
        case .lockScreen: return "Lock Screen"
        case .sleepDisplay: return "Sleep Display"
        case .spaceLeft: return "Move Left a Space"
        case .spaceRight: return "Move Right a Space"
        case .space(let i): return "Switch to Desktop \(i)"
        case .back: return "Back"
        case .forward: return "Forward"
        case .lookUp: return "Look Up"
        case .smartZoom: return "Smart Zoom"
        case .leftClick: return "Left Click"
        case .rightClick: return "Right Click"
        case .middleClick: return "Middle Click"
        case .scrollAndNavigate: return "Scroll & Navigate"
        case .autoScroll: return "Auto Scroll"
        case .pinchZoom: return "Pinch to Zoom"
        case .spaceNavigation: return "Space Navigation"
        case .volumeUp: return "Volume Up"
        case .volumeDown: return "Volume Down"
        case .mute: return "Mute"
        case .brightnessUp: return "Brightness Up"
        case .brightnessDown: return "Brightness Down"
        case .playPause: return "Play / Pause"
        case .nextTrack: return "Next Track"
        case .previousTrack: return "Previous Track"
        case .keystroke(let k): return "Send \(k.displayName)"
        case .macro: return "Run Macro"
        case .launchApplication(let id): return "Open \(id)"
        case .openURL(let url): return "Open \(url)"
        case .shellCommand: return "Run Shell Command"
        case .activateProfile: return "Switch Profile"
        }
    }

    /// SF Symbol name for the action picker.
    public var symbolName: String {
        switch self {
        case .none: return "circle.slash"
        case .missionControl, .applicationWindows: return "rectangle.3.group"
        case .showDesktop: return "menubar.dock.rectangle"
        case .launchpad: return "square.grid.3x3"
        case .notificationCentre: return "bell"
        case .spotlight: return "magnifyingglass"
        case .lockScreen: return "lock"
        case .sleepDisplay: return "moon"
        case .spaceLeft: return "arrow.left.square"
        case .spaceRight: return "arrow.right.square"
        case .space: return "square.on.square"
        case .back: return "chevron.backward"
        case .forward: return "chevron.forward"
        case .lookUp: return "character.book.closed"
        case .smartZoom: return "plus.magnifyingglass"
        case .leftClick, .rightClick, .middleClick: return "computermouse"
        case .scrollAndNavigate: return "hand.draw"
        case .autoScroll: return "arrow.up.arrow.down"
        case .pinchZoom: return "arrow.up.left.and.arrow.down.right"
        case .spaceNavigation: return "rectangle.split.3x1"
        case .volumeUp: return "speaker.wave.3"
        case .volumeDown: return "speaker.wave.1"
        case .mute: return "speaker.slash"
        case .brightnessUp: return "sun.max"
        case .brightnessDown: return "sun.min"
        case .playPause: return "playpause"
        case .nextTrack: return "forward.end"
        case .previousTrack: return "backward.end"
        case .keystroke: return "keyboard"
        case .macro: return "wand.and.stars"
        case .launchApplication: return "app"
        case .openURL: return "link"
        case .shellCommand: return "terminal"
        case .activateProfile: return "person.crop.square.filled.and.at.rectangle"
        }
    }

    /// Grouping used by the action picker's sections.
    public var category: String {
        switch self {
        case .none: return "General"
        case .missionControl, .applicationWindows, .showDesktop, .launchpad,
             .notificationCentre, .spotlight, .lockScreen, .sleepDisplay: return "System"
        case .spaceLeft, .spaceRight, .space: return "Spaces"
        case .back, .forward, .lookUp, .smartZoom: return "Navigation"
        case .leftClick, .rightClick, .middleClick: return "Clicks"
        case .scrollAndNavigate, .autoScroll, .pinchZoom, .spaceNavigation: return "Gestures"
        case .volumeUp, .volumeDown, .mute, .brightnessUp, .brightnessDown,
             .playPause, .nextTrack, .previousTrack: return "Media"
        case .keystroke, .macro, .launchApplication, .openURL, .shellCommand,
             .activateProfile: return "Custom"
        }
    }
}
