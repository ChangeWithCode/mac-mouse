import XCTest
@testable import GlideCore

final class MomentumScrollTests: XCTestCase {

    private let momentum = MomentumScroll(friction: 5.2, stopThreshold: 1.0)

    /// Simulates a fling frame by frame, as the display link will.
    private func simulate(velocity: Double, frameRate: Double) -> (distance: Double, frames: Int, finalVelocity: Double) {
        var v = velocity
        var x = 0.0
        var frames = 0
        let dt = 1.0 / frameRate
        while !momentum.hasStopped(velocity: v) && frames < 100_000 {
            let step = momentum.step(velocity: v, deltaTime: dt)
            x += step.delta
            v = step.velocity
            frames += 1
        }
        return (x, frames, v)
    }

    /// The point of integrating the decay in closed form: there is no drift to
    /// accumulate, at any frame rate. A trapezoid loses ~0.7pt on a hard fling.
    func testDiscreteIntegrationMatchesTheClosedFormExactly() {
        for frameRate in [30.0, 60.0, 120.0] {
            for velocity in [200.0, 900.0, 2400.0, 6000.0] {
                let result = simulate(velocity: velocity, frameRate: frameRate)
                let exact = (velocity - result.finalVelocity) / 5.2
                XCTAssertEqual(result.distance, exact, accuracy: 1e-9,
                               "drifted at \(frameRate)fps, v0=\(velocity)")
            }
        }
    }

    /// `projectedDistance` is the travel needed to decay exactly *to* the stop
    /// threshold, but a frame-stepped fling stops at the first frame *below* it.
    /// The simulation therefore always overshoots the projection slightly, and
    /// by a knowable amount: at most one frame of decay from threshold speed.
    ///
    /// Asserting that two-sided bound is stronger than the strict inequality it
    /// replaces — it pins the discrepancy rather than merely tolerating it.
    func testProjectedDistanceMatchesTheSimulationToWithinOneFrame() {
        let frameRate = 60.0
        for velocity in [100.0, 1000.0, 8000.0] {
            let result = simulate(velocity: velocity, frameRate: frameRate)
            let projected = momentum.projectedDistance(velocity: velocity)
            // Travel contributed by one frame starting at exactly stopThreshold.
            let slack = momentum.stopThreshold * (1 - exp(-5.2 / frameRate)) / 5.2

            XCTAssertGreaterThanOrEqual(result.distance, projected - 1e-9,
                                        "v0=\(velocity): fell short of the projection")
            XCTAssertLessThanOrEqual(result.distance, projected + slack + 1e-9,
                                     "v0=\(velocity): overshot by more than one frame")
        }
    }

    func testProjectedDurationAgreesWithTheSimulation() {
        for velocity in [500.0, 3000.0] {
            let predicted = momentum.projectedDuration(velocity: velocity)
            let actual = Double(simulate(velocity: velocity, frameRate: 60).frames) / 60
            XCTAssertEqual(actual, predicted, accuracy: 1.0 / 30.0)
        }
    }

    func testVelocityDecaysStrictlyAndTerminates() {
        var v = 4000.0
        var frames = 0
        while !momentum.hasStopped(velocity: v) {
            let next = momentum.step(velocity: v, deltaTime: 1.0 / 60).velocity
            XCTAssertLessThan(next, v)
            v = next
            frames += 1
            XCTAssertLessThan(frames, 2000, "fling is not terminating")
        }
    }

    /// The inverse relationship the whole scroll engine is built on.
    func testVelocityToTravelRoundTrips() {
        for distance in [12.0, 48.0, 220.0, 1000.0] {
            let velocity = momentum.velocityToTravel(distance)
            XCTAssertEqual(velocity / 5.2, distance, accuracy: 1e-9)
        }
    }
}

final class RubberBandTests: XCTestCase {

    func testIsZeroAtOriginAndOddSymmetric() {
        XCTAssertEqual(RubberBand.damp(offset: 0, limit: 500), 0, accuracy: 1e-12)
        for offset in [10.0, 250.0, 900.0] {
            XCTAssertEqual(RubberBand.damp(offset: -offset, limit: 500),
                           -RubberBand.damp(offset: offset, limit: 500), accuracy: 1e-12)
        }
    }

    func testNeverExceedsTheLimit() {
        for offset in [100.0, 1000.0, 100_000.0, 1e9] {
            XCTAssertLessThan(abs(RubberBand.damp(offset: offset, limit: 500)), 500)
        }
    }

    func testResistanceOnlyIncreases() {
        var previousGain = Double.infinity
        for offset in stride(from: 1.0, to: 2000.0, by: 1.0) {
            let gain = RubberBand.damp(offset: offset, limit: 500) / offset
            XCTAssertLessThanOrEqual(gain, previousGain + 1e-12)
            previousGain = gain
        }
    }

    func testZeroLimitProducesNoMovement() {
        XCTAssertEqual(RubberBand.damp(offset: 300, limit: 0), 0, accuracy: 1e-12)
    }
}

final class FreeSpinDetectorTests: XCTestCase {

    func testDeliberateSlowTicksNeverRegister() {
        var detector = FreeSpinDetector()
        var time = 0.0
        for _ in 0..<20 {
            time += 0.18
            XCTAssertFalse(detector.register(timestamp: time))
        }
    }

    func testAFastSpinEngagesButNotBeforeTheRequiredTicks() {
        var detector = FreeSpinDetector(speedThreshold: 14, requiredTicks: 3)
        var time = 0.0
        var firstActive = -1
        for tick in 0..<12 {
            time += 1.0 / 40.0
            if detector.register(timestamp: time), firstActive < 0 { firstActive = tick }
        }
        XCTAssertGreaterThanOrEqual(firstActive, 3)
        XCTAssertLessThanOrEqual(firstActive, 6)
    }

    func testAPauseResetsTheSpin() {
        var detector = FreeSpinDetector(speedThreshold: 14, requiredTicks: 3)
        var time = 0.0
        for _ in 0..<12 { time += 1.0 / 40.0; detector.register(timestamp: time) }
        XCTAssertTrue(detector.isSpinning)
        time += 1.0
        detector.register(timestamp: time)
        XCTAssertFalse(detector.isSpinning)
    }

    func testReportedSpeedTracksASteadyCadence() {
        var detector = FreeSpinDetector()
        var time = 0.0
        for _ in 0..<10 { time += 1.0 / 25.0; detector.register(timestamp: time) }
        XCTAssertEqual(detector.currentSpeed, 25, accuracy: 0.5)
    }

    /// A lone tick has no cadence; guessing one would make the first notch of
    /// every scroll unpredictable.
    func testASingleTickReportsNoCadence() {
        var detector = FreeSpinDetector()
        detector.register(timestamp: 1.0)
        XCTAssertEqual(detector.currentSpeed, 0)
    }
}
