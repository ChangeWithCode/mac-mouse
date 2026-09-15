import XCTest
@testable import GlideCore

/// Mirrors Tools/physics-lab/engine.spec.js.
final class ScrollEngineTests: XCTestCase {

    private struct Tick { let at: Double; let direction: Double }

    /// Drives an engine through a scripted tick sequence at a fixed frame rate.
    private func run(
        _ engine: ScrollEngine,
        ticks: [Tick],
        frameRate: Double = 60,
        maxSeconds: Double = 20
    ) -> [ScrollEngine.Frame] {
        var frames: [ScrollEngine.Frame] = []
        var queue = ticks
        var time = 0.0
        let dt = 1.0 / frameRate
        while time < maxSeconds {
            while let next = queue.first, next.at <= time {
                queue.removeFirst()
                engine.ingest(direction: next.direction, timestamp: next.at)
            }
            if let frame = engine.advance(now: time) { frames.append(frame) }
            if queue.isEmpty && !engine.isActive { break }
            time += dt
        }
        return frames
    }

    /// A gesture is well-formed only if a scrolled view could actually follow it.
    private func assertWellFormed(
        _ frames: [ScrollEngine.Frame],
        expectMomentum: Bool? = nil,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertFalse(frames.isEmpty, "no frames produced", file: file, line: line)
        var gestureOpen = false
        var inMomentum = false
        var sawEnded = false

        for (index, frame) in frames.enumerated() {
            switch frame.phase {
            case .began:
                XCTAssertFalse(gestureOpen, "began while already open (frame \(index))", file: file, line: line)
                XCTAssertFalse(inMomentum, "began during momentum (frame \(index))", file: file, line: line)
                gestureOpen = true
                sawEnded = false
            case .changed:
                XCTAssertTrue(gestureOpen, "changed with no open gesture (frame \(index))", file: file, line: line)
            case .ended:
                XCTAssertTrue(gestureOpen, "ended with no open gesture (frame \(index))", file: file, line: line)
                // An `ended` carrying motion would be double-counted by the view.
                XCTAssertEqual(frame.delta, 0, "ended carried motion (frame \(index))", file: file, line: line)
                gestureOpen = false
                sawEnded = true
            default:
                break
            }

            switch frame.momentumPhase {
            case .begin:
                XCTAssertFalse(gestureOpen, "momentum began with the gesture still open", file: file, line: line)
                XCTAssertTrue(sawEnded, "momentum began without a preceding ended", file: file, line: line)
                XCTAssertFalse(inMomentum, "momentum began twice", file: file, line: line)
                inMomentum = true
            case .`continue`:
                XCTAssertTrue(inMomentum, "momentum continued with none in flight", file: file, line: line)
            case .end:
                XCTAssertTrue(inMomentum, "momentum ended with none in flight", file: file, line: line)
                inMomentum = false
            case .none:
                break
            }
        }

        XCTAssertFalse(gestureOpen, "the gesture never closed", file: file, line: line)
        XCTAssertFalse(inMomentum, "the momentum stream never closed", file: file, line: line)
        XCTAssertTrue(frames.last?.isFinal ?? false, "the last frame must be final", file: file, line: line)

        if let expectMomentum {
            let had = frames.contains { $0.momentumPhase == .begin }
            XCTAssertEqual(had, expectMomentum, file: file, line: line)
        }
    }

    func testAnIdleEngineEmitsNothing() {
        let engine = ScrollEngine(preset: .balanced)
        for step in 0..<10 {
            XCTAssertNil(engine.advance(now: Double(step) / 60))
        }
    }

    func testASingleTickProducesAWellFormedGesture() {
        let engine = ScrollEngine(preset: .balanced)
        assertWellFormed(run(engine, ticks: [Tick(at: 0, direction: 1)]), expectMomentum: true)
    }

    /// The core promise of the impulse model: the acceleration curve's "points
    /// per tick" is literally true, not approximately true.
    func testDistanceIsConserved() {
        let engine = ScrollEngine(preset: .balanced)
        engine.flickBoost = 1.0  // isolate the curve from the boost
        let ticks = (0..<10).map { Tick(at: 0.2 * Double($0), direction: 1) }
        let total = run(engine, ticks: ticks).reduce(0) { $0 + $1.delta }

        // Cadence settles at 5/s; the first tick has no measurable cadence and
        // falls back to the slow anchor.
        let curve = ScrollPreset.balanced.acceleration
        let expected = curve.distance(atSpeed: 0) + 9 * curve.distance(atSpeed: 5)
        XCTAssertEqual(Double(total), expected, accuracy: 10)
    }

    func testDistanceIsIndependentOfFrameRate() {
        let totals = [30.0, 60.0, 120.0, 144.0].map { rate -> Int in
            let engine = ScrollEngine(preset: .balanced)
            engine.flickBoost = 1.0
            let ticks = (0..<8).map { Tick(at: 0.15 * Double($0), direction: 1) }
            return run(engine, ticks: ticks, frameRate: rate).reduce(0) { $0 + $1.delta }
        }
        XCTAssertLessThanOrEqual((totals.max() ?? 0) - (totals.min() ?? 0), 2,
                                 "frame rate changed the distance: \(totals)")
    }

    /// Grabbing a coasting page must open a new gesture: the old one was already
    /// closed with `ended`, and a `changed` after that orphans it.
    func testResumingMidCoastOpensANewGesture() {
        let engine = ScrollEngine(preset: .balanced)
        let frames = run(engine, ticks: [
            Tick(at: 0.00, direction: 1), Tick(at: 0.05, direction: 1), Tick(at: 0.10, direction: 1),
            Tick(at: 0.60, direction: 1), Tick(at: 0.65, direction: 1),
        ])
        assertWellFormed(frames)
        XCTAssertEqual(frames.filter { $0.phase == .began }.count, 2)
    }

    func testReversingCancelsTheFling() {
        let forwardOnly = run(ScrollEngine(preset: .balanced), ticks: [
            Tick(at: 0, direction: 1), Tick(at: 0.05, direction: 1),
        ]).reduce(0) { $0 + $1.delta }

        let frames = run(ScrollEngine(preset: .balanced), ticks: [
            Tick(at: 0.00, direction: 1), Tick(at: 0.05, direction: 1),
            Tick(at: 0.12, direction: -1), Tick(at: 0.17, direction: -1),
        ])
        let net = frames.reduce(0) { $0 + $1.delta }
        XCTAssertLessThan(net, forwardOnly)
        XCTAssertTrue(frames.contains { $0.delta < 0 })
    }

    func testMomentumDisabledPresetsEmitNoMomentumPhase() {
        let frames = run(ScrollEngine(preset: .snappy), ticks: [
            Tick(at: 0, direction: 1), Tick(at: 0.05, direction: 1),
        ], maxSeconds: 10)
        assertWellFormed(frames, expectMomentum: false)
    }

    /// Regression: the input timeout used to discard the still-decaying velocity,
    /// quietly losing several points off every notch.
    func testMomentumDisabledPresetsStillDeliverTheFullNotch() {
        let lineByLine = ScrollPreset.lineByLine
        let engine = ScrollEngine(preset: lineByLine)
        engine.flickBoost = 1.0
        let ticks = (0..<20).map { Tick(at: 0.25 * Double($0), direction: 1) }
        let total = run(engine, ticks: ticks, frameRate: 120, maxSeconds: 30).reduce(0) { $0 + $1.delta }
        // 20 notches x 40pt.
        XCTAssertEqual(Double(total), 800, accuracy: 20)
    }

    func testInvertedModeMirrorsTheOutput() {
        let ticks = [Tick(at: 0, direction: 1), Tick(at: 0.05, direction: 1)]
        let normal = run(ScrollEngine(preset: .balanced), ticks: ticks).reduce(0) { $0 + $1.delta }
        let inverted = ScrollEngine(preset: .balanced)
        inverted.inverted = true
        XCTAssertEqual(normal, -run(inverted, ticks: ticks).reduce(0) { $0 + $1.delta })
    }

    func testALongSpinStaysWellFormedAndTerminates() {
        let ticks = (0..<60).map { Tick(at: Double($0) / 45, direction: 1) }
        assertWellFormed(run(ScrollEngine(preset: .balanced), ticks: ticks, maxSeconds: 30),
                         expectMomentum: true)
    }
}
