import XCTest
@testable import GlideCore

/// Mirrors Tools/physics-lab/chord.spec.js.
final class ChordRecognizerTests: XCTestCase {

    /// Builds a recogniser bound to the given triggers.
    private func recognizer(bound: [ButtonTrigger]) -> ChordRecognizer {
        var recognizer = ChordRecognizer()
        let set = Set(bound)
        recognizer.isBound = { set.contains($0) }
        recognizer.hasAnyBinding = { button in set.contains { $0.buttons.contains(button) } }
        return recognizer
    }

    private func isFire(_ event: ChordRecognizer.Event) -> ButtonTrigger? {
        if case .fire(let trigger) = event { return trigger }
        return nil
    }

    /// The fast path, and the reason Glide adds no latency to ordinary clicking.
    func testAnUnboundButtonIsNeverIntercepted() {
        var recognizer = self.recognizer(bound: [ButtonTrigger(.back, .click(count: 1))])
        let down = recognizer.press(.left, at: 0)
        let up = recognizer.release(.left, at: 0.05)
        XCTAssertEqual(down.count, 1)
        XCTAssertEqual(up.count, 1)
        if case .passThrough = down[0] {} else { XCTFail("expected a pass-through, got \(down)") }
        if case .passThrough = up[0] {} else { XCTFail("expected a pass-through, got \(up)") }
    }

    func testASingleClickBindingFiresImmediatelyOnRelease() {
        var recognizer = self.recognizer(bound: [ButtonTrigger(.back, .click(count: 1))])
        _ = recognizer.press(.back, at: 0)
        let events = recognizer.release(.back, at: 0.05)
        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(isFire(events[0])?.kind, .click(count: 1))
    }

    /// The multi-click delay is only paid when a longer click could match.
    func testADoubleClickBindingMakesASingleClickWait() {
        var recognizer = self.recognizer(bound: [
            ButtonTrigger(.back, .click(count: 1)),
            ButtonTrigger(.back, .click(count: 2)),
        ])
        _ = recognizer.press(.back, at: 0)
        XCTAssertTrue(recognizer.release(.back, at: 0.05).isEmpty, "fired before the window closed")
        XCTAssertTrue(recognizer.tick(now: 0.1).isEmpty)
        let late = recognizer.tick(now: 0.31)
        XCTAssertEqual(isFire(late.first ?? .passThrough(.left))?.kind, .click(count: 1))
    }

    func testTwoQuickClicksResolveAsOneDoubleClick() {
        var recognizer = self.recognizer(bound: [
            ButtonTrigger(.back, .click(count: 1)),
            ButtonTrigger(.back, .click(count: 2)),
        ])
        _ = recognizer.press(.back, at: 0)
        _ = recognizer.release(.back, at: 0.04)
        _ = recognizer.press(.back, at: 0.10)
        var events = recognizer.release(.back, at: 0.14)
        events += recognizer.tick(now: 0.45)

        let fires = events.compactMap(isFire)
        XCTAssertEqual(fires.count, 1)
        XCTAssertEqual(fires.first?.kind, .click(count: 2))
    }

    func testAHoldFiresAtTheThresholdRatherThanOnRelease() {
        var recognizer = self.recognizer(bound: [ButtonTrigger(.back, .hold)])
        _ = recognizer.press(.back, at: 0)
        XCTAssertTrue(recognizer.tick(now: 0.1).isEmpty, "fired before the threshold")

        let began = recognizer.tick(now: 0.25)
        guard case .begin = began.first else { return XCTFail("expected begin, got \(began)") }

        let ended = recognizer.release(.back, at: 0.8)
        guard case .end = ended.first else { return XCTFail("expected end, got \(ended)") }
    }

    func testAHoldDoesNotAlsoProduceAClick() {
        var recognizer = self.recognizer(bound: [
            ButtonTrigger(.back, .hold), ButtonTrigger(.back, .click(count: 1)),
        ])
        _ = recognizer.press(.back, at: 0)
        _ = recognizer.tick(now: 0.25)
        XCTAssertTrue(recognizer.release(.back, at: 0.6).compactMap(isFire).isEmpty)
    }

    func testAChordResolvesAsOneTrigger() {
        let chord = ButtonTrigger(buttons: [.back, .forward], kind: .click(count: 1))
        var recognizer = self.recognizer(bound: [chord])
        _ = recognizer.press(.back, at: 0)
        _ = recognizer.press(.forward, at: 0.02)
        _ = recognizer.release(.back, at: 0.10)
        let events = recognizer.release(.forward, at: 0.12)
        XCTAssertEqual(events.compactMap(isFire).first, chord)
    }

    func testAChordSurvivesOneButtonBeingReleasedEarly() {
        let chord = ButtonTrigger(buttons: [.back, .forward], kind: .click(count: 1))
        var recognizer = self.recognizer(bound: [chord])
        _ = recognizer.press(.back, at: 0)
        _ = recognizer.press(.forward, at: 0.02)
        XCTAssertTrue(recognizer.release(.back, at: 0.05).isEmpty, "resolved before the chord completed")
        XCTAssertEqual(recognizer.release(.forward, at: 0.09).compactMap(isFire).first, chord)
    }

    func testADragBeginsPastTheThresholdAndSuppressesTheClick() {
        var recognizer = self.recognizer(bound: [
            ButtonTrigger(.middle, .drag), ButtonTrigger(.middle, .click(count: 1)),
        ])
        _ = recognizer.press(.middle, at: 0)
        XCTAssertTrue(recognizer.move(by: 2, at: 0.01).isEmpty, "began before the threshold")

        let began = recognizer.move(by: 4, at: 0.02)
        guard case .begin = began.first else { return XCTFail("expected begin, got \(began)") }

        let ended = recognizer.release(.middle, at: 0.4)
        XCTAssertEqual(ended.count, 1)
        guard case .end = ended[0] else { return XCTFail("expected a bare end, got \(ended)") }
    }

    /// The press was swallowed while the recogniser deliberated, so an unmatched
    /// gesture must hand the click back rather than eat it.
    func testABoundButtonWithAnUnmatchedGestureReturnsTheClick() {
        var recognizer = self.recognizer(bound: [ButtonTrigger(.back, .hold)])
        _ = recognizer.press(.back, at: 0)
        let events = recognizer.release(.back, at: 0.05)
        guard case .synthesizeClick(let button) = events.first else {
            return XCTFail("expected a synthesized click, got \(events)")
        }
        XCTAssertEqual(button, .back)
    }

    func testHoldingAButtonWithNoHoldBindingDoesNotStrandIt() {
        var recognizer = self.recognizer(bound: [ButtonTrigger(.back, .click(count: 2))])
        _ = recognizer.press(.back, at: 0)
        let held = recognizer.tick(now: 0.3)
        XCTAssertTrue(held.contains { if case .synthesizeClick = $0 { return true }; return false })
        XCTAssertTrue(recognizer.release(.back, at: 0.9).compactMap(isFire).isEmpty)
        XCTAssertNil(recognizer.activeContinuousTrigger)
    }

    /// Growing a chord abandons the hold for the smaller group; the user is
    /// reaching for something else.
    func testGrowingAChordCancelsTheSmallerHold() {
        let single = ButtonTrigger(.back, .hold)
        let chord = ButtonTrigger(buttons: [.back, .forward], kind: .hold)
        var recognizer = self.recognizer(bound: [single, chord])

        _ = recognizer.press(.back, at: 0)
        guard case .begin(let first) = recognizer.tick(now: 0.25).first else {
            return XCTFail("the single-button hold never began")
        }
        XCTAssertEqual(first, single)

        let grown = recognizer.press(.forward, at: 0.3)
        XCTAssertTrue(grown.contains { if case .end(let t) = $0 { return t == single }; return false },
                      "the single-button hold was never ended")

        XCTAssertTrue(recognizer.tick(now: 0.55).contains {
            if case .begin(let t) = $0 { return t == chord }; return false
        }, "the chord hold never began")
    }

    /// Regression: the search for a longer click used `(count + 1)...4`, which
    /// on the fourth rapid click becomes 5...4 — an inverted ClosedRange, which
    /// traps. Rapid clicking is exactly what a mouse invites, so this crashed.
    func testAFourthRapidClickDoesNotTrap() {
        var recognizer = self.recognizer(bound: [
            ButtonTrigger(.back, .click(count: 1)),
            ButtonTrigger(.back, .click(count: 2)),
        ])
        var time = 0.0
        for _ in 0..<8 {
            _ = recognizer.press(.back, at: time)
            _ = recognizer.release(.back, at: time + 0.02)
            _ = recognizer.tick(now: time + 0.03)
            time += 0.05   // faster than the multi-click window, so the count climbs
        }
        // Reaching here without trapping is the assertion; confirm it still works.
        XCTAssertNil(recognizer.activeContinuousTrigger)
    }

    func testResetLeavesNoStateBehind() {
        var recognizer = self.recognizer(bound: [ButtonTrigger(.back, .hold)])
        _ = recognizer.press(.back, at: 0)
        _ = recognizer.tick(now: 0.25)
        recognizer.reset()
        XCTAssertNil(recognizer.activeContinuousTrigger)
        XCTAssertTrue(recognizer.tick(now: 1.0).isEmpty)
    }
}
