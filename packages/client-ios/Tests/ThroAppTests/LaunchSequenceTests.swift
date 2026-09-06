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
        XCTAssertEqual(LaunchTimeline.standard.total, 4.60, accuracy: 1e-9)
        XCTAssertEqual(LaunchTimeline.standard.finishAt, 4.20, accuracy: 1e-9)
        // The founder's first verdict was "too fast": the flight alone now lasts longer than the old loop.
        XCTAssertGreaterThanOrEqual(LaunchTimeline.standard.flight.duration, 0.75)
        XCTAssertGreaterThanOrEqual(LaunchTimeline.standard.hold.duration, 0.8)
        // The target is on screen before the throw, so the eye has somewhere to be.
        XCTAssertGreaterThanOrEqual(LaunchTimeline.standard.field.duration, 0.4)
    }

    func testReduceMotionHasNoMotionAndNoCues() {
        let r = LaunchTimeline.reduced
        for seg in [r.flight, r.impact, r.ring, r.resolve] {
            XCTAssertEqual(seg.duration, 0, seg.name)
            XCTAssertEqual(seg.progress(at: 0), 1, "\(seg.name) reads complete from the first frame")
        }
        XCTAssertTrue(r.cues.isEmpty, "no motion, nothing to score")
        XCTAssertFalse(r.isAnimated, "the frame draws no strike, no dust and no pulse")
        XCTAssertTrue(LaunchTimeline.standard.isAnimated)
        XCTAssertGreaterThan(r.hold.duration, 0.5, "a moment to read the name")
    }

    func testCuesLandOnTheirBeatsInsideTheTimeline() {
        let t = LaunchTimeline.standard
        let cues = Dictionary(grouping: t.cues, by: \.name).mapValues { $0.map(\.at) }
        XCTAssertEqual(cues["whoosh"], [t.flight.start])
        XCTAssertEqual(cues["thud"], [t.impact.start])
        XCTAssertEqual(cues["haptic"], [t.impact.start])
        XCTAssertEqual(cues["chalk"], [t.ring.start])
        // The point cuts the chalk ring twice on its way in, a light tick each time, both in the last part
        // of the flight and before the strike: tick, tick, thud.
        let ticks = cues["tick"] ?? []
        XCTAssertEqual(ticks.count, 2)
        XCTAssertEqual(ticks, ticks.sorted())
        for tick in ticks {
            XCTAssertGreaterThan(tick, t.flight.start + t.flight.duration / 2)
            XCTAssertLessThan(tick, t.impact.start)
        }
        XCTAssertLessThan(t.impact.start - ticks[1], 0.15, "the second cut is just before the strike")
        for cue in t.cues { XCTAssertLessThan(cue.at, t.finishAt, "\(cue.name) plays before the cross-fade") }
        // Every sound cue names a file the bundle carries.
        for cue in t.cues where cue.name != "haptic" && cue.name != "tick" {
            XCTAssertTrue(OpeningPreferences.soundFiles.contains("thro-" + cue.name), cue.name)
        }
    }

    func testTheFlightCurveInvertsAndThePointCutsTheRingTwice() {
        for i in 0...20 {
            let x = Double(i) / 20
            XCTAssertEqual(Easing.flightTime(for: Easing.flight(x)), x, accuracy: 1e-6)
        }
        // On the phone's own layout: the point enters the ring at the lower left and leaves it at the
        // upper right, both before it lands.
        let geo = MarkGeometry(tipToTip: 361)
        let centre = CGPoint(x: 215, y: 410)
        let landed = geo.onAxis(centre, geo.tip)
        let path = FlightPath(end: landed, axis: MarkGeometry.axis, tipToTip: geo.tipToTip, drop: 93)
        let cuts = path.crossings(centre: centre, radius: geo.ringCentreRadius)
        XCTAssertEqual(cuts.count, 2)
        XCTAssertLessThan(cuts[0], cuts[1])
        XCTAssertLessThan(cuts[1], 1)
        let entry = path.point(cuts[0]), exit = path.point(cuts[1])
        XCTAssertLessThan(entry.x, centre.x); XCTAssertGreaterThan(entry.y, centre.y)
        XCTAssertGreaterThan(exit.x, centre.x); XCTAssertLessThan(exit.y, centre.y)
        // and the nominal cuts the haptics use are within a hair of them
        XCTAssertEqual(FlightPath.nominalCuts.count, 2)
        for (a, b) in zip(FlightPath.nominalCuts, cuts) { XCTAssertEqual(a, b, accuracy: 0.01) }
        // the path lands heading along the axis
        let h = path.heading(1)
        XCTAssertEqual(h.dx, MarkGeometry.axis.dx, accuracy: 1e-6)
        XCTAssertEqual(h.dy, MarkGeometry.axis.dy, accuracy: 1e-6)
    }

    func testAChalkStrokeIsTheRingsWidthAndThinsOnlyAtItsLeadingEnd() {
        let g = MarkGeometry(tipToTip: 361)
        let c = CGPoint(x: 200, y: 200)
        // a full stroke with no taper spans outer to inner radius
        let whole = g.ringShape(at: c)
        XCTAssertEqual(whole.boundingRect.width, 2 * g.ringOuter, accuracy: 0.5)
        // a quarter stroke thinning over its last thirty degrees still starts at full width
        let stroke = g.ringBand(at: c, fromDegrees: 0, sweepDegrees: 90, taperDegrees: 30)
        XCTAssertFalse(stroke.isEmpty)
        XCTAssertEqual(stroke.boundingRect.maxX, c.x + g.ringOuter, accuracy: 0.5, "full width where the stroke begins")
        XCTAssertLessThan(stroke.boundingRect.maxY, c.y + g.ringOuter - 0.5, "a point, not a full end, where it leads")
        XCTAssertTrue(g.ringBand(at: c, fromDegrees: 0, sweepDegrees: 0, taperDegrees: 10).isEmpty)
    }

    func testTheDartFoldsIntoTheBar() {
        let dart = DartAnatomy(length: 200)
        let bar = dart.parts(spin: 0.7, morph: 1)
        XCTAssertTrue(bar.nearFlights.isEmpty && bar.farFlights.isEmpty, "the flights fold flat")
        let w = 2 * DartAnatomy.barHalf * 200
        XCTAssertEqual(bar.barrel.boundingRect.height, w, accuracy: 0.01, "the barrel is the bar's width")
        XCTAssertEqual(bar.needle.boundingRect.height, w, accuracy: 0.01)
        XCTAssertEqual(bar.shaft.boundingRect.minX, -200, accuracy: 0.01, "the shaft runs on to the tail")
        XCTAssertTrue(bar.shade.isEmpty, "no roundness on a flat bar")
        // and the bar's half-width is the mark's, in the dart's own units
        XCTAssertEqual(DartAnatomy.barHalf, 0.040 / (2 * 0.643), accuracy: 1e-9)
        // half-way, the flights are half folded
        let half = dart.parts(spin: 0, morph: 0.5)
        XCTAssertEqual(half.nearFlights.boundingRect.height, 0.085 * 200, accuracy: 1.0)
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
        // The flight accelerates into the board — most of the distance comes late — but the dart is
        // never parked: a third of the way through it has covered a fifth of the distance.
        XCTAssertLessThan(Easing.exit(0.5), 0.4)
        XCTAssertLessThan(Easing.flight(0.5), 0.5)
        XCTAssertGreaterThan(Easing.flight(0.33), 0.2)
        XCTAssertEqual(Easing.flight(1), 1, accuracy: 1e-6)
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
