import XCTest
@testable import GlideCore

/// Mirrors Tools/physics-lab/spec.js. Both must pass; the JS version is the one
/// that can be run without a Mac, so it is kept in step deliberately.
final class UnitBezierTests: XCTestCase {

    private let curves: [UnitBezier] = [
        UnitBezier(0.25, 0.1, 0.25, 1.0),   // ease
        UnitBezier(0.42, 0.0, 1.0, 1.0),    // ease-in
        UnitBezier(0.0, 0.0, 0.58, 1.0),    // ease-out
        UnitBezier(0.42, 0.0, 0.58, 1.0),   // ease-in-out
        UnitBezier(0.0, 0.0, 1.0, 1.0),     // linear
        UnitBezier(1.0, 0.0, 0.0, 1.0),     // derivative collapses at t = 0.5
        UnitBezier(0.0, 0.9, 1.0, 0.1),     // inverted S
    ]

    func testEndpointsArePinned() {
        for curve in curves {
            XCTAssertEqual(curve.evaluate(0), 0, accuracy: 1e-12)
            XCTAssertEqual(curve.evaluate(1), 1, accuracy: 1e-12)
        }
    }

    /// The well-conditioned contract: solving for t and sampling back must
    /// reproduce the input for every curve.
    func testSolveInvertsSampleX() {
        for curve in curves {
            for step in 0...200 {
                let x = Double(step) / 200
                XCTAssertEqual(curve.sampleX(curve.solveT(x)), x, accuracy: 1e-8,
                               "x round-trip failed at \(x)")
            }
        }
    }

    /// Recovering `t` itself is ill-conditioned where dx/dt collapses, so the
    /// tight bound is asserted only where the derivative carries information.
    func testSolveRecoversParameterWhereWellConditioned() {
        for curve in curves {
            for step in 0...200 {
                let t = Double(step) / 200
                guard abs(curve.sampleDerivativeX(t)) >= 0.05 else { continue }
                XCTAssertEqual(curve.solveT(curve.sampleX(t)), t, accuracy: 1e-6)
            }
        }
    }

    func testSolveNeverEscapesUnitRangeOrProducesNaN() {
        for curve in curves {
            for step in -10...210 {
                let t = curve.solveT(Double(step) / 200)
                XCTAssertTrue(t.isFinite)
                XCTAssertTrue(t >= 0 && t <= 1)
            }
        }
    }

    func testOutputIsMonotonicForInRangeControlPoints() {
        for curve in curves.dropLast() {
            var previous = -Double.infinity
            for step in 0...500 {
                let y = curve.evaluate(Double(step) / 500)
                XCTAssertGreaterThanOrEqual(y, previous - 1e-9)
                previous = y
            }
        }
    }

    /// The bisection fallback has to engage here; Newton stalls on a derivative
    /// of exactly zero at the midpoint.
    func testSymmetricSCurveResolvesAtItsMidpoint() {
        XCTAssertEqual(UnitBezier(1.0, 0.0, 0.0, 1.0).evaluate(0.5), 0.5, accuracy: 1e-6)
    }

    func testControlPointsSurviveACodableRoundTrip() throws {
        let original = UnitBezier(0.31, -0.2, 0.68, 1.4)
        let decoded = try JSONDecoder().decode(UnitBezier.self, from: JSONEncoder().encode(original))
        XCTAssertEqual(decoded, original)
        // The derived coefficients must be rebuilt, not merely the stored points.
        XCTAssertEqual(decoded.evaluate(0.37), original.evaluate(0.37), accuracy: 1e-12)
    }
}

final class AccelerationCurveTests: XCTestCase {

    private let curve = AccelerationCurve(
        minSpeed: 1, maxSpeed: 28, minDistance: 48, maxDistance: 220,
        shape: UnitBezier(0.35, 0, 0.65, 1)
    )

    func testClampsOutsideTheSpeedRange() {
        XCTAssertEqual(curve.distance(atSpeed: 0), 48, accuracy: 1e-9)
        XCTAssertEqual(curve.distance(atSpeed: -50), 48, accuracy: 1e-9)
        XCTAssertEqual(curve.distance(atSpeed: 28), 220, accuracy: 1e-9)
        XCTAssertEqual(curve.distance(atSpeed: 1000), 220, accuracy: 1e-9)
    }

    func testIsMonotonicAndBounded() {
        var previous = -Double.infinity
        for step in stride(from: -5.0, through: 60.0, by: 0.05) {
            let distance = curve.distance(atSpeed: step)
            XCTAssertGreaterThanOrEqual(distance, previous - 1e-9)
            XCTAssertTrue(distance >= 48 - 1e-9 && distance <= 220 + 1e-9)
            previous = distance
        }
    }

    func testDegenerateRangeDoesNotDivideByZero() {
        let degenerate = AccelerationCurve(
            minSpeed: 5, maxSpeed: 5, minDistance: 10, maxDistance: 99, shape: .ease
        )
        XCTAssertTrue(degenerate.distance(atSpeed: 5).isFinite)
    }
}

final class ScrollPresetTests: XCTestCase {

    /// The perceptual guard rails enforced by Tools/physics-lab/presets.js. If a
    /// preset is hand-edited past them, this is what catches it.
    func testBuiltInPresetsStayInsideTheirGuardRails() {
        let flick = 16_100.0
        for preset in ScrollPreset.builtIn {
            let slow = preset.acceleration.distance(atSpeed: 2)
            let fast = preset.acceleration.distance(atSpeed: 26)

            XCTAssertGreaterThanOrEqual(slow, 12, "\(preset.name): slow step below the perceptual floor")
            XCTAssertLessThanOrEqual(fast, 420, "\(preset.name): fast step overshoots a screen")
            XCTAssertGreaterThanOrEqual(fast, slow, "\(preset.name): acceleration curve is inverted")

            if preset.momentumEnabled {
                let duration = preset.projectedFlingDuration(velocity: flick)
                let distance = preset.projectedFlingDistance(velocity: flick)
                XCTAssertTrue((0.25...3.0).contains(duration), "\(preset.name): settles in \(duration)s")
                XCTAssertTrue((400.0...6000.0).contains(distance), "\(preset.name): travels \(distance)pt")
            }
        }
    }

    func testMomentumDisabledPresetsProjectNoFling() {
        for preset in ScrollPreset.builtIn where !preset.momentumEnabled {
            XCTAssertEqual(preset.projectedFlingDistance(velocity: 16_100), 0)
            XCTAssertEqual(preset.projectedFlingDuration(velocity: 16_100), 0)
        }
    }

    func testCustomisingForksTheIdentity() {
        let custom = ScrollPreset.balanced.customized()
        XCTAssertFalse(custom.isBuiltIn)
        XCTAssertTrue(ScrollPreset.balanced.isBuiltIn)
    }
}
