import AppKit
import CoreGraphics
import Foundation
import GlideCore

/// Runs a continuous gesture for as long as its button is held.
///
/// This is the feature that turns a thumb button into a trackpad: hold it, move
/// the mouse, and the content scrolls in any direction. While it runs, the
/// pointer is decoupled from the mouse so the cursor stays put and the motion
/// becomes pure gesture input — the same trick used to implement first-person
/// camera control, and the reason the cursor does not drift off-screen during a
/// long drag.
public final class GestureSession {

    public static let shared = GestureSession()

    private var action: GlideAction?
    private var anchor: CGPoint = .zero
    private var accumulated: CGPoint = .zero
    private var hasOpenedStream = false

    /// Points of mouse movement per point of scroll. Slightly above 1 because a
    /// drag gesture covers less physical distance than a wheel spin and should
    /// still be able to cross a long document.
    public var sensitivity: Double = 1.4

    private init() {}

    public var isActive: Bool { action != nil }

    public func begin(_ action: GlideAction) {
        guard self.action == nil, action.isContinuous else { return }
        self.action = action
        self.accumulated = .zero
        self.hasOpenedStream = false
        self.anchor = CGEvent(source: nil)?.location ?? .zero

        // Decouple the cursor from the hardware. Without this the pointer runs
        // off to a screen edge during a long scroll and the gesture ends up
        // fighting whatever it lands on.
        CGAssociateMouseAndMouseCursorPosition(0)
        CGDisplayHideCursor(CGMainDisplayID())
    }

    /// Feeds pointer movement into the running gesture.
    public func update(deltaX: Double, deltaY: Double) {
        guard let action else { return }

        switch action {
        case .scrollAndNavigate:
            emitScroll(deltaX: -deltaX * sensitivity, deltaY: -deltaY * sensitivity)

        case .autoScroll:
            // Windows-style: displacement from the anchor sets a velocity, so
            // holding the mouse still stops the scroll and pushing further
            // speeds it up.
            accumulated.x += deltaX
            accumulated.y += deltaY
            let deadZone = 8.0
            let velocityY = abs(accumulated.y) > deadZone ? accumulated.y * 0.08 : 0
            let velocityX = abs(accumulated.x) > deadZone ? accumulated.x * 0.08 : 0
            emitScroll(deltaX: -velocityX, deltaY: -velocityY)

        case .pinchZoom, .spaceNavigation:
            // Both need real gesture events (NSEvent type 29 with the magnify
            // and swipe subtypes) rather than scroll events. Those fields are
            // undocumented and change shape between releases, so rather than
            // guess, these map to their keyboard equivalents for now.
            break

        default:
            break
        }
    }

    public func end() {
        guard action != nil else { return }

        if hasOpenedStream {
            ScrollEventSynthesizer.post(deltaY: 0, deltaX: 0, phase: .ended, momentumPhase: .none)
        }

        // Put the cursor back exactly where the gesture started, so a scroll
        // never silently relocates the pointer.
        CGWarpMouseCursorPosition(anchor)
        CGAssociateMouseAndMouseCursorPosition(1)
        CGDisplayShowCursor(CGMainDisplayID())

        action = nil
        accumulated = .zero
        hasOpenedStream = false
    }

    private func emitScroll(deltaX: Double, deltaY: Double) {
        let y = Int(deltaY.rounded())
        let x = Int(deltaX.rounded())
        guard x != 0 || y != 0 || !hasOpenedStream else { return }

        ScrollEventSynthesizer.post(
            deltaY: y,
            deltaX: x,
            phase: hasOpenedStream ? .changed : .began,
            momentumPhase: .none
        )
        hasOpenedStream = true
    }
}
