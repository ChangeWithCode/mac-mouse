import Foundation

/// Resolves raw button presses into triggers: clicks, multi-clicks, holds,
/// drags and chords.
///
/// ## Why this is not trivial
///
/// A single click and the first half of a double-click are the same event. So
/// are a click and the beginning of a hold. Deciding between them means waiting
/// — and waiting on every click would make the mouse feel broken.
///
/// The recogniser therefore only waits when waiting can change the answer. It
/// asks the host which triggers actually have bindings, and:
///
/// - A button with no bindings at all is never intercepted, so its events reach
///   the app with no added latency whatsoever.
/// - A button bound only to a single click fires on release, with no
///   multi-click delay.
/// - The multi-click window is only entered when a multi-click binding exists.
/// - A hold fires the instant the threshold passes, not on release.
///
/// ## Chords
///
/// Any buttons held together form one group. The group grows while at least one
/// button is down and resolves when the last is released, so pressing 4 then 5
/// then releasing both is the chord {4,5}, not two separate clicks.
///
/// ## Driving it
///
/// The recogniser holds no timers — the host calls `tick` from the same runloop
/// that feeds it events. That keeps it deterministic and testable.
public struct ChordRecognizer {

    /// What the host should do in response.
    public enum Event: Hashable, Sendable {
        /// Run a one-shot action.
        case fire(ButtonTrigger)
        /// Start a continuous action (hold or drag).
        case begin(ButtonTrigger)
        /// Stop the continuous action started by a matching `begin`.
        case end(ButtonTrigger)
        /// Nothing was bound. Let the original press through untouched.
        case passThrough(MouseButton)
        /// Nothing was bound, but the press was already swallowed while we
        /// waited. Synthesize the click so the app still sees it.
        case synthesizeClick(MouseButton)
    }

    // MARK: - Tuning

    /// How long a button must be held before it counts as a hold.
    public var holdThreshold: Double = 0.2
    /// How long to wait for a follow-up click before committing to a count.
    public var multiClickWindow: Double = 0.25
    /// Pointer movement, in points, that turns a held button into a drag.
    public var dragThreshold: Double = 5.0

    /// Longest click run recognised. Past four, the gesture stops being
    /// something anyone can perform deliberately.
    public static let maxClickCount = 4

    // MARK: - Host callbacks

    /// Whether this exact trigger has a binding.
    public var isBound: (ButtonTrigger) -> Bool = { _ in false }
    /// Whether any trigger involving this button is bound. Consulted before
    /// swallowing anything, so unbound buttons stay latency-free.
    public var hasAnyBinding: (MouseButton) -> Bool = { _ in false }

    // MARK: - State

    private var held: Set<MouseButton> = []
    /// Every button that took part in the gesture in progress, including ones
    /// already released — so a chord still resolves as a chord when the user
    /// lets go of one button a moment before the other.
    private var group: Set<MouseButton> = []
    private var groupStart: Double = 0
    private var dragDistance: Double = 0

    private var continuousTrigger: ButtonTrigger?
    private var holdFired = false

    /// A completed group waiting to see whether another click follows.
    private var pendingClicks: (group: Set<MouseButton>, count: Int, deadline: Double)?

    public init() {}

    // MARK: - Input

    public mutating func press(_ button: MouseButton, at time: Double) -> [Event] {
        // Untouched buttons stay untouched. This is the fast path and it matters:
        // it is why a left click through Glide costs exactly nothing.
        guard hasAnyBinding(button) else { return [.passThrough(button)] }

        var events: [Event] = []

        // A press for a different group abandons the pending multi-click.
        if let pending = pendingClicks, pending.group != group.union([button]) {
            events += resolvePending(pending)
            pendingClicks = nil
        }

        if held.isEmpty && continuousTrigger == nil {
            group = []
            groupStart = time
            dragDistance = 0
            holdFired = false
        }

        held.insert(button)
        group.insert(button)

        // Growing a chord invalidates a hold already in flight for the smaller
        // group — the user is reaching for something else.
        if let active = continuousTrigger, active.buttons != group {
            events.append(.end(active))
            continuousTrigger = nil
            holdFired = false
            groupStart = time
        }

        return events
    }

    public mutating func release(_ button: MouseButton, at time: Double) -> [Event] {
        guard hasAnyBinding(button) else { return [.passThrough(button)] }

        held.remove(button)
        var events: [Event] = []

        // End a continuous action once every button backing it is up.
        if let active = continuousTrigger, held.isEmpty {
            events.append(.end(active))
            continuousTrigger = nil
            holdFired = false
            group = []
            return events
        }

        guard held.isEmpty else { return events }  // chord still partly down

        // A hold or drag already consumed this gesture; releasing is not a click.
        if holdFired {
            holdFired = false
            group = []
            return events
        }

        let resolved = group
        group = []

        let count = (pendingClicks?.group == resolved ? pendingClicks!.count : 0) + 1

        // Only pay the multi-click delay if a longer click could actually match.
        //
        // `stride`, not `(count + 1)...maxClickCount`: on the fourth rapid click
        // that range is 5...4, and an inverted ClosedRange traps at runtime.
        let longerExists = stride(from: count + 1, through: ChordRecognizer.maxClickCount, by: 1)
            .contains { isBound(ButtonTrigger(buttons: resolved, kind: .click(count: $0))) }
        if longerExists {
            pendingClicks = (resolved, count, time + multiClickWindow)
        } else {
            pendingClicks = nil
            events += emitClick(group: resolved, count: count)
        }
        return events
    }

    /// Feeds pointer movement so a held button can become a drag.
    public mutating func move(by distance: Double, at time: Double) -> [Event] {
        guard !held.isEmpty, continuousTrigger == nil, !holdFired else { return [] }
        dragDistance += distance
        guard dragDistance >= dragThreshold else { return [] }

        let trigger = ButtonTrigger(buttons: group, kind: .drag)
        guard isBound(trigger) else { return [] }
        continuousTrigger = trigger
        holdFired = true  // a drag consumes the gesture; no click on release
        return [.begin(trigger)]
    }

    /// Advances time. Fires holds whose threshold has passed and commits
    /// multi-click groups whose window has closed.
    public mutating func tick(now: Double) -> [Event] {
        var events: [Event] = []

        if !held.isEmpty, !holdFired, continuousTrigger == nil,
           now - groupStart >= holdThreshold {
            let trigger = ButtonTrigger(buttons: group, kind: .hold)
            if isBound(trigger) {
                continuousTrigger = trigger
                holdFired = true
                events.append(.begin(trigger))
            } else {
                // Nothing bound to holding these buttons. Stop re-checking every
                // tick for the rest of the press.
                holdFired = true
                events += unboundGestureFallback(group)
            }
        }

        if let pending = pendingClicks, now >= pending.deadline {
            events += resolvePending(pending)
            pendingClicks = nil
        }

        return events
    }

    /// Drops all state without emitting. For focus loss, sleep and profile swaps,
    /// where the buttons' owner is going away regardless.
    public mutating func reset() {
        held = []
        group = []
        dragDistance = 0
        continuousTrigger = nil
        holdFired = false
        pendingClicks = nil
    }

    /// The continuous action currently running, if any.
    public var activeContinuousTrigger: ButtonTrigger? { continuousTrigger }

    // MARK: - Resolution

    private mutating func resolvePending(_ pending: (group: Set<MouseButton>, count: Int, deadline: Double)) -> [Event] {
        emitClick(group: pending.group, count: pending.count)
    }

    private func emitClick(group: Set<MouseButton>, count: Int) -> [Event] {
        let trigger = ButtonTrigger(buttons: group, kind: .click(count: count))
        if isBound(trigger) { return [.fire(trigger)] }

        // Fall back to the longest bound click shorter than what was performed,
        // so a triple-click on a button bound only to double still does
        // something sensible rather than nothing.
        for shorter in stride(from: count - 1, through: 1, by: -1) {
            let candidate = ButtonTrigger(buttons: group, kind: .click(count: shorter))
            if isBound(candidate) { return [.fire(candidate)] }
        }
        return unboundGestureFallback(group)
    }

    /// Nothing matched, and the press was swallowed while we deliberated. Give
    /// the click back to the app rather than eating it.
    private func unboundGestureFallback(_ group: Set<MouseButton>) -> [Event] {
        group.sorted().map { .synthesizeClick($0) }
    }
}
