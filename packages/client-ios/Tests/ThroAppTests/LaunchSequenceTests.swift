import XCTest
import SwiftUI
import ThroTokens
@testable import ThroApp

/// PD-007's opening, second version: the timeline and its cues, the easings it runs on, the mark's
/// geometry, and the dart's anatomy — the parts that are plain values.
final class LaunchSequenceTests: XCTestCase {
    func testSegmentsAreContiguousAndTheOpeningStaysUnderFiveSeconds() {
        for timeline in [LaunchTimeline.standard, LaunchTimeline.reduced] {
            let s = timeline.segments
            XCTAssertEqual(s.first?.start, 0)
            for (a, b) in zip(s, s.dropFirst()) { XCTAssertEqual(a.end, b.start, "\(a.name) must hand straight to \(b.name)") }
            XCTAssertLessThanOrEqual(timeline.total, 5.0, "an opening is a door, not a wait")
        }
        XCTAssertEqual(LaunchTimeline.standard.total, 4.50, accuracy: 1e-9)
        XCTAssertEqual(LaunchTimeline.standard.finishAt, 4.10, accuracy: 1e-9)
        // The founder's first verdict was "too fast": the flight alone now lasts longer than the old loop.
        XCTAssertGreaterThanOrEqual(LaunchTimeline.standard.flight.duration, 0.75)
        XCTAssertGreaterThanOrEqual(LaunchTimeline.standard.hold.duration, 0.8)
    }

    func testReduceMotionHasNoMotionAndNoCues() {
        let r = LaunchTimeline.reduced
        for seg in [r.flight, r.impact, r.ring, r.resolve] {
            XCTAssertEqual(seg.duration, 0, seg.name)
            XCTAssertEqual(seg.progress(at: 0), 1, "\(seg.name) reads complete from the first frame")
        }
        XCTAssertTrue(r.cues.isEmpty, "no motion, nothing to score")
        XCTAssertGreaterThan(r.hold.duration, 0.5, "a moment to read the name")
    }

    func testCuesLandOnTheirBeatsInsideTheTimeline() {
        let t = LaunchTimeline.standard
        let cues = Dictionary(uniqueKeysWithValues: t.cues.map { ($0.name, $0.at) })
        XCTAssertEqual(cues["whoosh"], t.flight.start)
        XCTAssertEqual(cues["thud"], t.impact.start)
        XCTAssertEqual(cues["haptic"], t.impact.start)
        XCTAssertEqual(cues["chalk"], t.ring.start)
        for cue in t.cues { XCTAssertLessThan(cue.at, t.finishAt, "\(cue.name) plays before the cross-fade") }
        // Every sound cue names a file the bundle carries.
        for cue in t.cues where cue.name != "haptic" {
            XCTAssertTrue(OpeningPreferences.soundFiles.contains("thro-" + cue.name), cue.name)
        }
    }

    func testProgressClampsAndIsLinearWithin() {
        let flight = LaunchTimeline.standard.flight
        XCTAssertEqual(flight.progress(at: 0), 0)
        XCTAssertEqual(flight.progress(at: flight.start + flight.duration / 2), 0.5, accuracy: 1e-9)
        XCTAssertEqual(flight.progress(at: 9), 1)
    }

    func testTokenEasingsAreMonotoneAndHitTheirEnds() {
        for curve in [ThroMotion.motionEasingThrow, ThroMotion.motionEasingImpact, ThroMotion.motionEasingResolve,
                      ThroMotion.motionEasingSet, ThroMotion.motionEasingExit] {
            XCTAssertEqual(Easing.cubicBezier(curve, 0), 0, accuracy: 1e-6)
            XCTAssertEqual(Easing.cubicBezier(curve, 1), 1, accuracy: 1e-6)
            var last = -1.0
            for i in 0...50 {
                let y = Easing.cubicBezier(curve, Double(i) / 50)
                XCTAssertGreaterThanOrEqual(y, last - 1e-6); last = y
            }
        }
        // The flight accelerates into the board: most of the distance comes late.
        XCTAssertLessThan(Easing.exit(0.5), 0.4)
        // The throw curve is front-loaded, as the settle should feel.
        XCTAssertGreaterThan(Easing.throwCurve(0.3), 0.6)
    }

    func testADampedSettleStartsAtRestSwingsBothWaysAndDiesAway() {
        XCTAssertEqual(Easing.damped(0, amplitude: 1, hertz: 6.5, decay: 0.24), 0)
        XCTAssertEqual(Easing.damped(-1, amplitude: 1, hertz: 6.5, decay: 0.24), 0)
        let samples = (1...90).map { Easing.damped(Double($0) / 100, amplitude: 1, hertz: 6.5, decay: 0.24) }
        XCTAssertTrue(samples.contains { $0 > 0.2 } && samples.contains { $0 < -0.2 }, "swings both ways")
        XCTAssertLessThan(abs(samples.last!), 0.05, "settled by the end")
    }

    func testTheGeometryKeepsTheMeasuredProportions() {
        let g = MarkGeometry(tipToTip: 104)
        XCTAssertEqual(g.tipToTip, 104, accuracy: 1e-9)
        XCTAssertEqual(g.ringOuter / g.unit, 0.364, accuracy: 1e-9)
        XCTAssertEqual(g.ringInner / g.unit, 0.250, accuracy: 1e-9)
        let box = g.bar(at: CGPoint(x: 100, y: 100)).boundingRect
        XCTAssertEqual(box.width, 2 * g.tip * CGFloat(0.5).squareRoot(), accuracy: 0.01)
        XCTAssertEqual(box.height, box.width, accuracy: 0.01)
        XCTAssertTrue(g.ringArc(at: .zero, fromDegrees: 315, sweepDegrees: 0).isEmpty)
        XCTAssertFalse(g.ringArc(at: .zero, fromDegrees: 315, sweepDegrees: 360).isEmpty)
    }

    func testTheDartIsAsLongAsTheBarAndMadeOfFourParts() {
        XCTAssertEqual(DartAnatomy.needle + DartAnatomy.barrel + DartAnatomy.shaft + DartAnatomy.flight, 1, accuracy: 1e-9)
        let dart = DartAnatomy(length: 200)
        let parts = dart.parts(spin: 0)
        XCTAssertEqual(parts.needle.boundingRect.width, 0.28 * 200, accuracy: 0.01)
        XCTAssertEqual(parts.barrel.boundingRect.width, 0.24 * 200, accuracy: 0.01)
        XCTAssertEqual(parts.shaft.boundingRect.width, 0.20 * 200, accuracy: 0.01)
        XCTAssertEqual(parts.nearFlights.boundingRect.minX, -200, accuracy: 0.01, "the flights end at the tail")
        // Seen face-on the near flights are at full width; a quarter roll later they are edge-on and the far pair shows.
        XCTAssertEqual(parts.nearFlights.boundingRect.height, 2 * 0.085 * 200, accuracy: 0.5)
        let rolled = dart.parts(spin: .pi / 2)
        XCTAssertTrue(rolled.nearFlights.isEmpty)
        XCTAssertEqual(rolled.farFlights.boundingRect.height, 2 * 0.085 * 200, accuracy: 0.5)
    }
}
