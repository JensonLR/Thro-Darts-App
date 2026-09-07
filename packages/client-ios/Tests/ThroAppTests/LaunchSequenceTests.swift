import XCTest
import SwiftUI
import ThroTokens
@testable import ThroApp

/// PD-007's opening, sixth version: the timeline and its cues, the easings it runs on, the throw as the
/// camera sees it, the mark's geometry and its change into the wordmark's Ø, the chalk stroke, and the
/// dart's anatomy — the parts that are plain values. The frame itself is drawn, not tested.
final class LaunchSequenceTests: XCTestCase {
    func testSegmentsAreContiguousAndTheOpeningIsNoLongerThanItsOwnReasons() {
        for timeline in [LaunchTimeline.standard, LaunchTimeline.reduced] {
            let s = timeline.segments
            XCTAssertEqual(s.count, 7)
            XCTAssertEqual(s.first?.start, 0)
            for (a, b) in zip(s, s.dropFirst()) { XCTAssertEqual(a.end, b.start, "\(a.name) must hand straight to \(b.name)") }
            // This ceiling was five seconds, which was engineering's own rule and not the founder's. The
            // founder asked for the tagline to be readable — "visible just a little bit longer so people
            // can read it properly" — and 5.36 s is what that costs. The rule is restated, not deleted,
            // and every extra millisecond of it is in the hold where the reading happens.
            XCTAssertLessThanOrEqual(timeline.total, 5.5, "an opening is a door, not a wait")
        }
        XCTAssertEqual(LaunchTimeline.standard.total, 5.36, accuracy: 1e-9)
        XCTAssertEqual(LaunchTimeline.standard.finishAt, 4.96, accuracy: 1e-9)
        // The founder's first verdict was "too fast"; the flight is a whole shot of its own.
        XCTAssertGreaterThanOrEqual(LaunchTimeline.standard.flight.duration, 1.2)
        // The lit spot is on screen before the throw, so the eye has somewhere to be.
        XCTAssertGreaterThanOrEqual(LaunchTimeline.standard.field.duration, 0.25)
        XCTAssertGreaterThanOrEqual(LaunchTimeline.standard.word.duration, 0.8, "three letters are struck in beside the mark")
    }

    /// The founder's ask, as a number: the tagline must be still, at full strength and alone with the name
    /// long enough to be read before anything begins to fade. It had 0.53 s, which was not enough.
    func testTheTaglineIsLeftAloneLongEnoughToRead() {
        let t = LaunchTimeline.standard
        XCTAssertGreaterThanOrEqual(t.taglineSettledFor, 1.2, "the tagline must be readable, not glimpsed")
        XCTAssertEqual(t.taglineSettledFor, 1.3748, accuracy: 1e-6)
        // it arrives as the last letter sets, inside the word segment, and has finished before the hold's end
        XCTAssertGreaterThan(t.taglineAt, t.word.start + t.word.duration * LaunchTimeline.stampFractions[2])
        XCTAssertLessThan(t.taglineAt, t.word.end)
        XCTAssertLessThan(t.taglineAt + LaunchTimeline.taglineSeconds, t.finishAt)
        // Reduce Motion shows it from the first frame and holds it at least as long
        XCTAssertEqual(LaunchTimeline.reduced.taglineAt, 0)
        XCTAssertGreaterThanOrEqual(LaunchTimeline.reduced.taglineSettledFor, 1.1)
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
        XCTAssertGreaterThan(r.hold.duration, 1.0, "long enough to read the name and the line under it")
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
        // The mark is in its slot before a letter is struck beside it. Its move runs on the resolve curve
        // over the first 0.62 of the word segment, so by the first stamp it is all but home, and by the
        // last it is home: a letter never lands against a mark still in transit.
        func markHome(_ fraction: Double) -> Double { Easing.resolve(Easing.unit(fraction / LaunchTimeline.markHomeBy)) }
        XCTAssertGreaterThan(markHome(LaunchTimeline.stampFractions[0]), 0.9)
        XCTAssertEqual(markHome(LaunchTimeline.stampFractions[2]), 1, accuracy: 1e-9)
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
        // Chalk starts at full speed and slows: no dead air between the thud and the first mark on the board.
        XCTAssertEqual(Easing.chalk(0), 0, accuracy: 1e-9)
        XCTAssertEqual(Easing.chalk(1), 1, accuracy: 1e-9)
        XCTAssertGreaterThan(Easing.chalk(0.1), 0.14, "the stroke is under way on its first frames")
        var lastChalk = -1.0
        for i in 0...50 { let y = Easing.chalk(Double(i) / 50); XCTAssertGreaterThanOrEqual(y, lastChalk); lastChalk = y }
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
        // The wall's apparent size is one over its distance, and the distance closes at a constant
        // proportional rate: a fifth of full size at the first frame, doubling every 0.43 of the flight,
        // full size at the strike. There is no part of the flight without approach in it.
        XCTAssertEqual(Throw.targetScale(0), Throw.farScale, accuracy: 1e-9)
        XCTAssertEqual(Throw.targetScale(1), 1, accuracy: 1e-9)
        XCTAssertEqual(Throw.targetScale(0.5), CGFloat(Double(Throw.farScale).squareRoot()), accuracy: 1e-6)
        for i in 0..<20 {
            let a = Double(i) / 20, b = Double(i + 1) / 20
            XCTAssertGreaterThan(Throw.targetScale(b) / Throw.targetScale(a), 1.05,
                                 "the wall grows in every twentieth of the flight, not only at its end")
        }
        XCTAssertEqual(Throw.approach(0), 0, accuracy: 1e-9)
        XCTAssertEqual(Throw.approach(1), 1, accuracy: 1e-9)
        var last = -1.0
        for i in 0...100 { let a = Throw.approach(Double(i) / 100); XCTAssertGreaterThanOrEqual(a, last); last = a }
        // The aim barely moves — it is what the throw is aimed at — and is exactly on the spot at the strike.
        XCTAssertEqual(Throw.targetOffset(0).dx, Throw.farOffset.dx); XCTAssertEqual(Throw.targetOffset(0).dy, Throw.farOffset.dy)
        XCTAssertEqual(Throw.targetOffset(1).dx, 0, accuracy: 1e-9); XCTAssertEqual(Throw.targetOffset(1).dy, 0, accuracy: 1e-9)
        XCTAssertLessThan(Throw.farOffset.dy, 0, "the far aim is up the screen")
        // The dart crosses the frame: a screen and a half behind its landed place at the first frame,
        // more than half of it covered in the first fifth, home exactly at the strike, never going back.
        XCTAssertEqual(Throw.reach(0), 0, accuracy: 1e-9)
        XCTAssertEqual(Throw.reach(1), 1, accuracy: 1e-9)
        XCTAssertGreaterThan(Throw.reach(0.2), 0.35, "the camera's aim catches it quickly")
        XCTAssertLessThan(Throw.reach(0.2), 0.65, "and does not finish the journey in the first fifth")
        XCTAssertEqual(Throw.travel(0), -Throw.travelLength, accuracy: 1e-9)
        XCTAssertEqual(Throw.travel(1), 0, accuracy: 1e-9)
        var lastTravel = -CGFloat.infinity
        for i in 0...100 { let d = Throw.travel(Double(i) / 100); XCTAssertGreaterThanOrEqual(d, lastTravel); lastTravel = d }
        // The dart is still closing at the strike — it drives in, it does not glide to a stop.
        XCTAssertGreaterThan(Throw.speed(1), 0.5)
        XCTAssertGreaterThan(Throw.speed(0), Throw.speed(0.5), "fastest as it enters the frame")
        // The smear is the speed and nothing else, so the blur can never outlive the motion.
        XCTAssertEqual(Throw.smear(0.37), Throw.smearGain * Throw.speed(0.37), accuracy: 1e-9)
        XCTAssertGreaterThan(Throw.smear(0), Throw.smear(0.3))
        XCTAssertEqual(Throw.bob(0), 0, accuracy: 1e-9); XCTAssertEqual(Throw.bob(0.5), 1, accuracy: 1e-9); XCTAssertEqual(Throw.bob(1), 0, accuracy: 1e-9)
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
        // The wordmark's Ø, against a cap height, carries the letters' own weight — and those numbers are
        // measured off Archivo ExtraBold, not chosen: at 300 pt its cap is 206 px, its O's outer radius
        // 0.524 cap and its side stroke 0.269 cap, its Ø's slash 0.130 cap. The ring had been 0.23 cap,
        // 17% light against the letters it stands in.
        let o = MarkGeometry(unit: 84, ratios: .wordmark)
        XCTAssertEqual(o.ringOuter, 0.524 * 84, accuracy: 1e-9)
        XCTAssertEqual(o.ringInner, 0.255 * 84, accuracy: 1e-9)
        XCTAssertEqual(o.halfWidth, 0.065 * 84, accuracy: 1e-9)
        XCTAssertEqual(o.tip, 0.95 * 84, accuracy: 1e-9)
        XCTAssertEqual(o.ringWidth / o.unit, 0.269, accuracy: 1e-9, "the O's own side stroke")
        XCTAssertEqual(2 * o.halfWidth / o.unit, 0.130, accuracy: 1e-9, "the Ø's own slash")
        XCTAssertGreaterThan(o.ringWidth / o.tipToTip, g.ringWidth / g.tipToTip, "heavier, for its size, than the mark")
        // Mixing: the mark at 0, the Ø at 1, and half way is half way in size and proportion.
        let atMark = MarkGeometry.mix(g, o, 0), atO = MarkGeometry.mix(g, o, 1)
        XCTAssertEqual(atMark.unit, g.unit, accuracy: 1e-9); XCTAssertEqual(atMark.ratios.ringOuter, 0.364, accuracy: 1e-9)
        XCTAssertEqual(atO.unit, o.unit, accuracy: 1e-9); XCTAssertEqual(atO.ratios.ringOuter, 0.524, accuracy: 1e-9)
        XCTAssertEqual(atO.ratios.halfWidth, 0.065, accuracy: 1e-9); XCTAssertEqual(atO.ratios.tip, 0.95, accuracy: 1e-9)
        let half = MarkGeometry.mix(g, o, 0.5)
        XCTAssertEqual(half.unit, (g.unit + o.unit) / 2, accuracy: 1e-9)
        XCTAssertEqual(half.ratios.ringOuter, (0.364 + 0.524) / 2, accuracy: 1e-9)
        XCTAssertEqual(WordmarkGeometry.tailPerCap, 0.10 + 0.524 + 0.95 * CGFloat(0.5).squareRoot(), accuracy: 1e-9)
        // The founder's mark itself is untouched: its ratios are the reconstruction of their artwork.
        XCTAssertEqual(MarkGeometry.Ratios.mark.ringOuter, 0.364, accuracy: 1e-9)
        XCTAssertEqual(MarkGeometry.Ratios.mark.ringInner, 0.250, accuracy: 1e-9)
        XCTAssertEqual(MarkGeometry.Ratios.mark.halfWidth, 0.040, accuracy: 1e-9)
        XCTAssertEqual(MarkGeometry.Ratios.mark.tip, 0.643, accuracy: 1e-9)
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
        // Chalk on a board has a rough edge, and it is the same roughness at the same angle on every
        // frame — otherwise the edge crawls while the ring sits still.
        var lo = CGFloat.infinity, hi = -CGFloat.infinity
        for deg in stride(from: -720.0, through: 720.0, by: 3.0) {
            let e = MarkGeometry.chalkEdge(deg)
            XCTAssertGreaterThanOrEqual(e, 0); XCTAssertLessThanOrEqual(e, 1)
            lo = min(lo, e); hi = max(hi, e)
        }
        XCTAssertLessThan(lo, 0.2); XCTAssertGreaterThan(hi, 0.8, "the edge actually varies")
        let rough = g.ringShape(at: c, radiusScale: 1, roughness: 0.06)
        XCTAssertFalse(rough.isEmpty)
        XCTAssertNotEqual(rough.boundingRect.width, whole.boundingRect.width, "roughness moves the edge")
        XCTAssertEqual(rough.boundingRect.width, whole.boundingRect.width, accuracy: g.ringWidth * 0.12, "but only a little")
    }

    /// The chalk dust on the wall is a fixed scatter: it is generated once, it is the same every run, and
    /// each speck's brightness lands in a tier the frame function can draw in one pass.
    func testTheWallsDustIsFixedAndItsBrightnessIsInRange() {
        let dust = LaunchFrame.wallDust
        XCTAssertEqual(dust.count, 420)
        for speck in dust {
            XCTAssertLessThanOrEqual((speck.u * speck.u + speck.v * speck.v).squareRoot(), 3.2 + 1e-6, "on the wall")
            XCTAssertGreaterThanOrEqual(speck.tier, 0)
            XCTAssertLessThan(speck.tier, LaunchFrame.dustTiers)
            XCTAssertGreaterThan(speck.r, 0)
        }
        // dust far from the lit spot is dimmer than dust on it, which is what keeps the corners dark
        let near = dust.filter { ($0.u * $0.u + $0.v * $0.v) < 0.25 }
        let far = dust.filter { ($0.u * $0.u + $0.v * $0.v) > 6.25 }
        XCTAssertFalse(near.isEmpty); XCTAssertFalse(far.isEmpty)
        XCTAssertGreaterThan(Double(near.map(\.tier).reduce(0, +)) / Double(near.count),
                             Double(far.map(\.tier).reduce(0, +)) / Double(far.count))
        XCTAssertEqual(LaunchFrame.wallDust.first?.u, dust.first?.u, "the same scatter on every frame")
    }

    func testTheDartIsAsLongAsTheBarAndMadeOfFourParts() {
        XCTAssertEqual(DartAnatomy.point + DartAnatomy.barrel + DartAnatomy.shaft + DartAnatomy.flight, 1, accuracy: 1e-9)
        let dart = DartAnatomy(length: 200)
        let parts = dart.parts(spin: 0)
        XCTAssertEqual(parts.point.boundingRect.width, 0.24 * 200, accuracy: 0.01)
        XCTAssertEqual(parts.barrel.boundingRect.width, 0.30 * 200, accuracy: 0.01)
        XCTAssertEqual(parts.shaft.boundingRect.width, 0.22 * 200, accuracy: 0.01)
        XCTAssertEqual(parts.nearFlights.boundingRect.minX, -200, accuracy: 0.01, "the flights end at the tail")
        // The barrel is a real barrel: a nose narrower than its grip, the grip at full width, a collar at the rear.
        XCTAssertEqual(dart.barrelRadius(at: dart.pointEnd, morph: 0), DartAnatomy.barrelNose * 200, accuracy: 1e-6)
        XCTAssertEqual(dart.barrelRadius(at: dart.pointEnd - 0.5 * (dart.pointEnd - dart.barrelEnd), morph: 0), DartAnatomy.barrelHalf * 200, accuracy: 1e-6)
        XCTAssertEqual(dart.barrelRadius(at: dart.barrelEnd, morph: 0), DartAnatomy.collarHalf * 200, accuracy: 1e-6)
        XCTAssertEqual(parts.barrel.boundingRect.height, 2 * DartAnatomy.barrelHalf * 200, accuracy: 0.01)
        XCTAssertFalse(parts.knurl.isEmpty); XCTAssertFalse(parts.grooves.isEmpty); XCTAssertFalse(parts.highlight.isEmpty)
        XCTAssertFalse(parts.shade.isEmpty); XCTAssertFalse(parts.collar.isEmpty)
        // Seen face-on the near flights are at full height and carry the mark; a quarter roll later they are
        // edge-on and the far pair shows.
        XCTAssertEqual(parts.nearFlights.boundingRect.height, 2 * 0.105 * 200, accuracy: 2.0)
        XCTAssertEqual(parts.nearScale, 1, accuracy: 1e-9)
        XCTAssertFalse(parts.logo.isEmpty, "the flights carry the mark")
        let rolled = dart.parts(spin: .pi / 2)
        XCTAssertTrue(rolled.nearFlights.isEmpty)
        XCTAssertTrue(rolled.logo.isEmpty, "no mark on an edge-on flight")
        XCTAssertEqual(rolled.farFlights.boundingRect.height, 2 * 0.105 * 200, accuracy: 2.0)
        // Which pair is in front is the sign of the roll, not its size. Taking the magnitude of both put
        // the far pair in front for half of every turn, so the tail flipped light and dark as it rolled.
        let facing = dart.parts(spin: 0.1 * .pi)
        XCTAssertGreaterThan(facing.nearScale, 0.9, "the pair facing the camera is the near one")
        let turnedAway = dart.parts(spin: 0.9 * .pi)
        XCTAssertLessThan(turnedAway.nearScale, 0.4, "past a quarter turn the other pair comes to the front")
        XCTAssertTrue(turnedAway.logo.isEmpty, "and it is too far edge-on to carry the mark")
        // The shaft has the mass of a shaft: a real dart's shaft is not a wire off a barrel.
        XCTAssertGreaterThan(DartAnatomy.shaftHalf / DartAnatomy.barrelHalf, 0.5)
        XCTAssertGreaterThan(DartAnatomy.collarHalf, DartAnatomy.shaftHalf, "the collar seats the flights")
        XCTAssertLessThan(DartAnatomy.collarHalf, DartAnatomy.barrelHalf)
    }

    func testTheDartFoldsIntoTheBar() {
        let dart = DartAnatomy(length: 200)
        let bar = dart.parts(spin: 0.7, morph: 1)
        XCTAssertTrue(bar.nearFlights.isEmpty && bar.farFlights.isEmpty, "the flights fold flat")
        let w = 2 * DartAnatomy.barHalf * 200
        XCTAssertEqual(bar.barrel.boundingRect.height, w, accuracy: 0.01, "the barrel is the bar's width")
        XCTAssertEqual(bar.point.boundingRect.height, w, accuracy: 0.01)
        XCTAssertEqual(bar.shaft.boundingRect.minX, -200, accuracy: 0.01, "the shaft runs on to the tail")
        XCTAssertTrue(bar.shade.isEmpty, "no roundness on a flat bar")
        XCTAssertTrue(bar.collar.isEmpty && bar.logo.isEmpty)
        // and the bar's half-width is the mark's, in the dart's own units
        XCTAssertEqual(DartAnatomy.barHalf, 0.040 / (2 * 0.643), accuracy: 1e-9)
        // half-way, the flights are half folded
        let half = dart.parts(spin: 0, morph: 0.5)
        XCTAssertEqual(half.nearFlights.boundingRect.height, 0.105 * 200, accuracy: 2.0)
    }
}
