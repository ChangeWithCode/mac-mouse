import CoreGraphics
import Foundation
import GlideCore

/// Plays back a recorded macro.
///
/// Runs on its own serial queue so a macro containing a two-second delay cannot
/// stall the event tap. Playback is cancellable at every step, because a macro
/// bound to "repeat while held" must stop the moment the button comes up.
public final class MacroPlayer {

    private let queue = DispatchQueue(label: "com.glide.macro-player", qos: .userInitiated)
    private let lock = NSLock()
    private var generation: Int = 0

    public init() {}

    /// Starts playback, cancelling anything already running.
    public func play(_ macro: Macro) {
        lock.lock()
        generation += 1
        let token = generation
        lock.unlock()

        queue.async { [weak self] in
            guard let self else { return }
            repeat {
                for step in macro.steps {
                    guard self.isCurrent(token) else { return }
                    self.execute(step)
                }
                if macro.repeatsWhileHeld {
                    Thread.sleep(forTimeInterval: macro.repeatInterval)
                }
            } while macro.repeatsWhileHeld && self.isCurrent(token)
        }
    }

    /// Stops playback. Steps already dispatched to the window server will still
    /// land — there is no recalling a posted event — but nothing further runs.
    public func stop() {
        lock.lock()
        generation += 1
        lock.unlock()
    }

    private func isCurrent(_ token: Int) -> Bool {
        lock.lock(); defer { lock.unlock() }
        return generation == token
    }

    private func execute(_ step: Macro.Step) {
        switch step {
        case .key(let stroke):
            KeyboardSynthesizer.send(stroke)
        case .keyDown(let stroke):
            KeyboardSynthesizer.press(stroke)
        case .keyUp(let stroke):
            KeyboardSynthesizer.release(stroke)
        case .text(let string):
            KeyboardSynthesizer.type(string)
        case .delay(let seconds):
            Thread.sleep(forTimeInterval: seconds)
        case .click(let button):
            MouseSynthesizer.click(CGMouseButton(rawValue: UInt32(button.number)) ?? .left)
        case .move(let x, let y, let relative):
            move(x: x, y: y, relative: relative)
        }

        // A short gap between steps. Without it, applications that debounce
        // their own input drop everything after the first event.
        if case .delay = step {} else { Thread.sleep(forTimeInterval: 0.008) }
    }

    private func move(x: Double, y: Double, relative: Bool) {
        let current = CGEvent(source: nil)?.location ?? .zero
        let target = relative
            ? CGPoint(x: current.x + x, y: current.y + y)
            : CGPoint(x: x, y: y)
        CGEvent(
            mouseEventSource: nil,
            mouseType: .mouseMoved,
            mouseCursorPosition: target,
            mouseButton: .left
        )?.post(tap: .cgSessionEventTap)
    }
}
