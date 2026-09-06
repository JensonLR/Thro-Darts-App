import XCTest
import SwiftUI
import ThroTokens
@testable import ThroApp

/// PD-007's opening, fourth version: the timeline and its cues, the easings it runs on, the throw as the
/// camera sees it, the mark's geometry and its change into the wordmark's Ø, the chalk stroke, and the
/// dart's anatomy — the parts that are plain values. The frame itself is drawn, not tested.
final class LaunchSequenceTests: XCTestCase {
    func testSegmentsAreContiguousAndTheOpeningStaysUnderFiveSeconds() {
        for timeline in [LaunchTimeline.standard, LaunchTimeline.reduced] {
            let s = timeline.segments
            XCTAssertEqual(s.count, 7)
            XCTAssertEqual(s.first?.start, 0)
            for (a, b) in zip(s, s.dropFirst()) { XCTAssertEqual(a.end, b.start, "\(a.name) must hand straight to \(b.name)") }
            XCTAssertLessThanOrEqual(timeline.total, 5.0, "an opening is a door, not a wait")
        }
        XCTAssertEqual(LaunchTimeline.standard.total, 4.70, accuracy: 1e-9)
        XCTAssertEqual(LaunchTimeline.standard.finishAt, 4.30, accuracy: 1e-9)
        // The founder's first verdict was "too fast"; the flight is a tracking shot now and longer than ever.
        XCTAssertGreaterThanOrEqual(LaunchTimeline.standard.flight.duration, 1.0)
        // The target is on screen before the throw, so the eye has somewhere to be.
        XCTAssertGreaterThanOrEqual(LaunchTimeline.standard.field.duration, 0.4)
        // The name is read in the hold, with the tagline arriving in its first third.
        XCTAssertGreaterThanOrEqual(LaunchTimeline.standard.hold.duration, 0.8)
        XCTAssertGreaterThanOrEqual(LaunchTimeline.standard.word.duration, 0.8, "three letters stamp in beside the mark")
    }

    func testReduceMotionHasNoMotionAndNoCues() {
        let r = LaunchTimeline.reduced
        for seg in [r.flight, r.impact, r.ring, r.word] {
            XCTAssertEqual(seg.duration, 0, seg.name)
            XCTAssertEqual(seg.progress(at: 0), 1, "\(seg.name) reads complete from the first frame")
        }
        XCTAssertTrue(r.cues.isEmpty, "no motion, nothing to score")
        XCTAssertFalse(r.isAnimated, "the frame draws no flight, no strike, no dust and no pulse")
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
        // Each letter lands with a firm tap, in order, inside the word segment, after the mark has begun to move.
        let stamps = cues["stamp"] ?? []
        XCTAssertEqual(stamps.count, 3)
        XCTAssertEqual(stamps, stamps.sorted())
        for stamp in stamps {
            XCTAssertGreaterThan(stamp, t.word.start + 0.2)
            XCTAssertLessThan(stamp, t.word.end)
        }
        XCTAssertEqual(LaunchTimeline.stampFractions, LaunchTimeline.stampFractions.sorted())
        for cue in t.cues { XCTAssertLessThan(cue.at, t.finishAt, "\(cue.name) plays before the cross-fade") }
        // Every sound cue names a file the bundle carries.
        for cue in t.cues where !["haptic", "stamp"].contains(cue.name) {
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
        XCTAssertLessThan(Easing.exit(0.5), 0.4, "the exit curve accelerates into its end")
        XCTAssertGreaterThan(Easing.throwCurve(0.3), 0.6, "the throw curve is front-loaded, as a settle should feel")
        XCTAssertEqual(Easing.unit(-1), 0); XCTAssertEqual(Easing.unit(2), 1); XCTAssertEqual(Easing.unit(0.3), 0.3)
    }

    func testADampedSettleStartsAtRestSwingsBothWaysAndDiesAway() {
        XCTAssertEqual(Easing.damped(0, amplitude: 1, hertz: 6.5, decay: 0.24), 0)
        XCTAssertEqual(Easing.damped(-1, amplitude: 1, hertz: 6.5, decay: 0.24), 0)
        let samples = (1...90).map { Easing.damped(Double($0) / 100, amplitude: 1, hertz: 6.5, decay: 0.24) }
        XCTAssertTrue(samples.contains { $0 > 0.2 } && samples.contains { $0 < -0.2 }, "swings both ways")
        XCTAssertLessThan(abs(samples.last!), 0.05, "settled by the end")
    }

    func testTheThrowAsTheCameraSeesIt() {
        // The wall comes to the dart: nothing until the dart has settled in frame, then slow, then fast, and arrived at the strike.
        XCTAssertEqual(Throw.approach(0), 0)
        XCTAssertEqual(Throw.approach(Throw.approachStart), 0)
        XCTAssertLessThan(Throw.approach(0.6), 0.2, "far away for most of the flight")
        XCTAssertGreaterThan(Throw.approach(0.9), 0.5, "rushing in at the end")
        XCTAssertEqual(Throw.approach(1), 1, accuracy: 1e-9)
        var last = -1.0
        for i in 0...100 { let a = Throw.approach(Double(i) / 100); XCTAssertGreaterThanOrEqual(a, last); last = a }
        // The light is small and off to the upper right when far, full size and centred when arrived.
        XCTAssertEqual(Throw.targetScale(0), Throw.farScale)
        XCTAssertEqual(Throw.targetScale(1), 1, accuracy: 1e-9)
        XCTAssertEqual(Throw.targetOffset(0).dx, Throw.farOffset.dx); XCTAssertEqual(Throw.targetOffset(0).dy, Throw.farOffset.dy)
        XCTAssertEqual(Throw.targetOffset(1).dx, 0, accuracy: 1e-9); XCTAssertEqual(Throw.targetOffset(1).dy, 0, accuracy: 1e-9)
        XCTAssertLessThan(Throw.farOffset.dy, 0, "the far light is up the screen")
        // The camera rolls from a flat throw to the mark's angle and has settled before the strike.
        XCTAssertEqual(Throw.rollDegrees(0), Throw.cameraRollDegrees)
        XCTAssertEqual(Throw.rollDegrees(Throw.rollEnd), 0, accuracy: 1e-6)
        XCTAssertEqual(Throw.rollDegrees(1), 0, accuracy: 1e-6)
        XCTAssertGreaterThan(Throw.rollDegrees(0.5), 0)
        // The dart slides in and is in its tracked place by a quarter of the flight; it bobs once; it flies
        // nose-up and is flat on the axis at the strike.
        XCTAssertEqual(Throw.entry(0), Throw.entryDistance)
        XCTAssertEqual(Throw.entry(Throw.entryEnd), 0, accuracy: 1e-9)
        XCTAssertEqual(Throw.entry(1), 0, accuracy: 1e-9)
        XCTAssertEqual(Throw.bob(0), 0, accuracy: 1e-9); XCTAssertEqual(Throw.bob(0.5), 1, accuracy: 1e-9); XCTAssertEqual(Throw.bob(1), 0, accuracy: 1e-9)
        XCTAssertEqual(Throw.pitch(0), Throw.pitchDegrees * .pi / 180, accuracy: 1e-9)
        XCTAssertEqual(Throw.pitch(1), 0, accuracy: 1e-9)
    }

    func testTheGeometryKeepsTheMeasuredProportionsAndBecomesTheWordmarksO() {
        let g = MarkGeometry(tipToTip: 104)
        XCTAssertEqual(g.tipToTip, 104, accuracy: 1e-9)
        XCTAssertEqual(g.ringOuter / g.unit, 0.364, accuracy: 1e-9)
        XCTAssertEqual(g.ringInner / g.unit, 0.250, accuracy: 1e-9)
        let box = g.bar(at: CGPoint(x: 100, y: 100)).boundingRect
        XCTAssertEqual(box.width, 2 * g.tip * CGFloat(0.5).squareRoot(), accuracy: 0.01)
        XCTAssertEqual(box.height, box.width, accuracy: 0.01)
        XCTAssertTrue(g.ringArc(at: .zero, fromDegrees: 315, sweepDegrees: 0).isEmpty)
        XCTAssertFalse(g.ringArc(at: .zero, fromDegrees: 315, sweepDegrees: 360).isEmpty)
        // The wordmark's Ø, against a cap height, has the letters' weight: a wider ring and a heavier bar.
        let o = MarkGeometry(unit: 84, ratios: .wordmark)
        XCTAssertEqual(o.ringOuter, 0.53 * 84, accuracy: 1e-9)
        XCTAssertEqual(o.ringInner, 0.30 * 84, accuracy: 1e-9)
        XCTAssertEqual(o.halfWidth, 0.067 * 84, accuracy: 1e-9)
        XCTAssertEqual(o.tip, 0.95 * 84, accuracy: 1e-9)
        XCTAssertGreaterThan(o.ringWidth / o.tipToTip, g.ringWidth / g.tipToTip, "heavier, for its size, than the mark")
        // Mixing: the mark at 0, the Ø at 1, and half way is half way in size and proportion.
        let atMark = MarkGeometry.mix(g, o, 0), atO = MarkGeometry.mix(g, o, 1)
        XCTAssertEqual(atMark.unit, g.unit, accuracy: 1e-9); XCTAssertEqual(atMark.ratios.ringOuter, 0.364, accuracy: 1e-9)
        XCTAssertEqual(atO.unit, o.unit, accuracy: 1e-9); XCTAssertEqual(atO.ratios.ringOuter, 0.53, accuracy: 1e-9)
        XCTAssertEqual(atO.ratios.halfWidth, 0.067, accuracy: 1e-9); XCTAssertEqual(atO.ratios.tip, 0.95, accuracy: 1e-9)
        let half = MarkGeometry.mix(g, o, 0.5)
        XCTAssertEqual(half.unit, (g.unit + o.unit) / 2, accuracy: 1e-9)
        XCTAssertEqual(half.ratios.ringOuter, (0.364 + 0.53) / 2, accuracy: 1e-9)
        XCTAssertEqual(WordmarkGeometry.tailPerCap, 0.10 + 0.53 + 0.95 * CGFloat(0.5).squareRoot(), accuracy: 1e-9)
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
}
