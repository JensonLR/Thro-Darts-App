import XCTest
import SwiftUI
import ThroTokens
// `Easing` and `MarkGeometry` are ThroDesign's since SLATE B.0. The assertions below are
// unchanged — this import is the whole cost of the move.
import ThroDesign
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
            // The ceiling was engineering's own five seconds, then 5.5 when the founder asked for the
            // tagline to be readable. They have now read it at 1.37 s and asked for "maybe half a second
            // shorter at the end", so the opening is back under five and the ceiling with it. It is the
            // founder's number in both directions; the rule is restated, never deleted.
            XCTAssertLessThanOrEqual(timeline.total, 5.0, "an opening is a door, not a wait")
        }
        XCTAssertEqual(LaunchTimeline.standard.total, 4.86, accuracy: 1e-9)
        XCTAssertEqual(LaunchTimeline.standard.finishAt, 4.46, accuracy: 1e-9)
        // The half second came out of the hold and nowhere else: every other cut is where it was.
        XCTAssertEqual(LaunchTimeline.standard.flight.end, 1.68, accuracy: 1e-9)
        XCTAssertEqual(LaunchTimeline.standard.impact.end, 2.06, accuracy: 1e-9)
        XCTAssertEqual(LaunchTimeline.standard.ring.end, 2.58, accuracy: 1e-9)
        XCTAssertEqual(LaunchTimeline.standard.word.end, 3.42, accuracy: 1e-9)
        XCTAssertEqual(LaunchTimeline.standard.exit.duration, 0.40, accuracy: 1e-9)
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
        // The founder set this number twice. At 0.53 s they could not read it; at 1.37 s they could, and
        // asked for half a second back. 0.87 s is that, and it is still two thirds again the version they
        // could not read — so the floor here is the founder's judgement, not engineering's taste.
        XCTAssertGreaterThanOrEqual(t.taglineSettledFor, 0.85, "the tagline must be readable, not glimpsed")
        XCTAssertEqual(t.taglineSettledFor, 0.8748, accuracy: 1e-6)
        XCTAssertEqual(LaunchTimeline.standard.hold.duration, 1.04, accuracy: 1e-9)
        // it arrives as the last letter sets, inside the word segment, and has finished before the hold's end
        XCTAssertGreaterThan(t.taglineAt, t.word.start + t.word.duration * LaunchTimeline.stampFractions[2])
        XCTAssertLessThan(t.taglineAt, t.word.end)
        XCTAssertLessThan(t.taglineAt + LaunchTimeline.taglineSeconds, t.finishAt)
        // Reduce Motion shows it from the first frame and holds it at least as long
        XCTAssertEqual(LaunchTimeline.reduced.taglineAt, 0)
        XCTAssertGreaterThanOrEqual(LaunchTimeline.reduced.taglineSettledFor, 1.1)
    }

    /// The eighth look, and the first note nobody had to give: **the peak of the film lasted one frame.**
    func testTheFinishedMarkIsHeldStillBeforeItLeavesForTheName() {
        let timeline = LaunchTimeline.standard
        let held = timeline.ring.duration * (1 - LaunchFrame.Tune.chalkRunsFor)
        XCTAssertGreaterThanOrEqual(held, 0.15,
                                    "a whole Ø with a dart through it is what the whole opening is building "
                                    + "towards; it has to be still long enough to be an image")
        XCTAssertLessThan(LaunchFrame.Tune.chalkRunsFor, 1.0)
        // And it costs nothing. Five seconds is the founder's ceiling in both directions, so a beat that
        // had to be paid for in length would not have been worth having.
        XCTAssertEqual(timeline.total, 4.86, accuracy: 1e-9)
        XCTAssertEqual(timeline.ring.end, 2.58, accuracy: 1e-9)
    }

    func testTheChalkComesOffWhenTheRingIsSetAndIsStillSettlingAfterTheMarkHasGone() {
        let timeline = LaunchTimeline.standard
        let closes = timeline.ring.start + timeline.ring.duration * LaunchFrame.Tune.chalkRunsFor
        XCTAssertGreaterThan(closes + LaunchFrame.Tune.fallSeconds, timeline.word.start + 0.3,
                             "dust that stopped when the mark left would make the beat a pause again")
        XCTAssertLessThan(closes + LaunchFrame.Tune.fallSeconds, timeline.finishAt,
                          "and it is gone by the time the name is being read")
        XCTAssertEqual(LaunchFrame.fallingChalk.count, LaunchFrame.Tune.fallMotes)
        for mote in LaunchFrame.fallingChalk {
            XCTAssertGreaterThanOrEqual(mote.radius, 0.95,
                                        "a mote inside the band is invisible against pure chalk")
            XCTAssertGreaterThan(mote.size, 0)
            XCTAssertGreaterThan(mote.life, 0)
            XCTAssertLessThanOrEqual(mote.life, 1)
            XCTAssertLessThan(mote.lag, 0.2, "chalk comes off at the strike, not in a second wave")
        }
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

    /// The ring is struck into being by the strike's shock, not drawn on by a stick.
    ///
    /// The founder saw the old mechanism fail: "breakage at the bottom right". That was structural, not
    /// a tuning error. Two chalk strokes ran out from the dart's crossings and met at 45° and 225°, and
    /// a stroke thins to a point where it leads — so the ring closed on two hairline pinches that never
    /// filled. Two tapered ends cannot meet in a whole ring.
    ///
    /// So the ring is set rather than drawn. The shock is stretched along the dart's own line, reaches
    /// the mark's radius first exactly where the dart crosses it and last square to that, and sets the
    /// chalk at FULL WIDTH wherever it crosses. What these assertions defend is that: the ignition runs
    /// from nothing to a closed ring, it is monotone, and the band never narrows anywhere along it — so
    /// two fronts merging can only overlap, and 45° cannot break again.
    func testTheRingIsSetByTheShockAtFullWidthSoItCannotBreakWhereTheFrontsMeet() {
        let g = MarkGeometry(tipToTip: 361)
        let c = CGPoint(x: 200, y: 200)

        // The shock reaches furthest along the dart's line and least square to it.
        for angle in MarkGeometry.crossingAngles {
            XCTAssertEqual(MarkGeometry.shockReach(angle), 1 + MarkGeometry.shockStretch, accuracy: 1e-12)
            XCTAssertEqual(MarkGeometry.shockReach(angle + 90), 1 - MarkGeometry.shockStretch, accuracy: 1e-12)
        }
        // A shock leaves the point round and is shaped as it travels, so it does not trace the dart.
        XCTAssertEqual(MarkGeometry.shockReach(135, at: 0), 1, accuracy: 1e-12)
        XCTAssertGreaterThan(MarkGeometry.shockReach(135, at: MarkGeometry.shockTouches), 1.29)

        // Ignition: nothing until the front touches, a closed ring once it has passed all of it, and
        // strictly increasing in between. 45° — where the founder saw the break — is the last to light.
        XCTAssertEqual(MarkGeometry.litDegrees(shock: 0), 0)
        XCTAssertEqual(MarkGeometry.litDegrees(shock: MarkGeometry.shockTouches), 0)
        XCTAssertEqual(MarkGeometry.litDegrees(shock: MarkGeometry.shockClears), 90)
        XCTAssertEqual(MarkGeometry.litDegrees(shock: 99), 90, "and stays closed as the shock runs on")
        var previous = -1.0
        for step in 0...200 {
            let s = MarkGeometry.shockTouches
                + (MarkGeometry.shockClears - MarkGeometry.shockTouches) * Double(step) / 200
            let lit = MarkGeometry.litDegrees(shock: s)
            XCTAssertGreaterThanOrEqual(lit, previous, "the ring is set once and never un-set")
            XCTAssertLessThanOrEqual(lit, 90)
            previous = lit
        }
        XCTAssertGreaterThan(previous, 89.999, "and it does close")

        // The band the shock sets is full width from inner to outer radius everywhere along it — which is
        // the whole guarantee. A 20° band and a 60° band have the same radial thickness at their ends.
        func thickness(_ band: Path, at degrees: Double) -> CGFloat {
            // the band's extent along the ray at this angle, found from its bounding box in a rotated frame
            let phi = degrees * .pi / 180
            var lo = CGFloat.infinity, hi = -CGFloat.infinity
            band.forEach { element in
                let points: [CGPoint]
                switch element {
                case .move(to: let p): points = [p]
                case .line(to: let p): points = [p]
                default: points = []
                }
                for p in points {
                    let along = (p.x - c.x) * CGFloat(cos(phi)) + (p.y - c.y) * CGFloat(sin(phi))
                    let across = -(p.x - c.x) * CGFloat(sin(phi)) + (p.y - c.y) * CGFloat(cos(phi))
                    guard abs(across) < g.ringWidth * 0.30 else { continue }
                    lo = min(lo, along); hi = max(hi, along)
                }
            }
            return hi - lo
        }
        let short = g.ringBand(at: c, fromDegrees: 100, sweepDegrees: 20, taperDegrees: 0)
        let long = g.ringBand(at: c, fromDegrees: 100, sweepDegrees: 60, taperDegrees: 0)
        XCTAssertEqual(thickness(short, at: 100), g.ringWidth, accuracy: 0.6, "full width at the start")
        XCTAssertEqual(thickness(short, at: 120), g.ringWidth, accuracy: 0.6, "and at the leading end")
        XCTAssertEqual(thickness(long, at: 160), g.ringWidth, accuracy: 0.6, "however far it has run")
        XCTAssertEqual(g.ringShape(at: c).boundingRect.width, 2 * g.ringOuter, accuracy: 0.5)
        XCTAssertTrue(g.ringBand(at: c, fromDegrees: 0, sweepDegrees: 0, taperDegrees: 0).isEmpty)

        // A point on the ring is where the fronts and their glow are put, so it must be the centreline.
        let east = g.onRing(c, degrees: 0)
        XCTAssertEqual(east.x - c.x, g.ringCentreRadius, accuracy: 1e-9)
        XCTAssertEqual(east.y, c.y, accuracy: 1e-9)

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
        XCTAssertEqual(rough.boundingRect.width, g.ringShape(at: c).boundingRect.width,
                       accuracy: g.ringWidth * 0.12, "roughness moves the edge, but only a little")
    }

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

/// The dart's material against the mark's chalk (the seam at the lower-left crossing).
final class DartInkTests: XCTestCase {

    func testEveryPartOfTheDartIsPureChalkByTheTimeItIsTheBar() {
        // The property that stops the grey line through the Ø coming back: at the end of the morph
        // nothing on the dart is a shade under chalk, so the bar and the ring are one colour and
        // the crossings cannot show a join.
        for under in [0.54, 0.9, 0.97] {
            XCTAssertEqual(DartInk.chalked(under, morph: 1), 1, accuracy: 1e-9, "\(under) did not resolve")
        }
        // And nothing that is NOT chalk survives it: the green behind a far flight, a collar's hairline.
        XCTAssertEqual(DartInk.material(1), 0, accuracy: 1e-9)
    }

    func testABarelyThrownDartStillLooksLikeAMetalDart() {
        // The other half: before the morph the material is untouched, or the dart would arrive as a
        // flat white lozenge and the whole point of drawing a dart would be lost.
        XCTAssertEqual(DartInk.chalked(0.54, morph: 0), 0.54, accuracy: 1e-9)
        XCTAssertEqual(DartInk.chalked(0.9, morph: 0), 0.9, accuracy: 1e-9)
        XCTAssertEqual(DartInk.material(0), 1, accuracy: 1e-9)
    }

    func testItMovesOneWayAndNeverPastEitherEnd() {
        var last = DartInk.chalked(0.54, morph: 0)
        for step in 1...20 {
            let now = DartInk.chalked(0.54, morph: Double(step) / 20)
            XCTAssertGreaterThanOrEqual(now, last, "the material never gets darker again")
            XCTAssertLessThanOrEqual(now, 1)
            last = now
        }
        // Out of range is clamped rather than overshooting into an opacity above 1.
        XCTAssertEqual(DartInk.chalked(0.9, morph: 1.4), 1, accuracy: 1e-9)
        XCTAssertEqual(DartInk.chalked(0.9, morph: -0.3), 0.9, accuracy: 1e-9)
    }
}

/// Which of the two things resolves the dart into chalk, and when.
extension DartInkTests {

    func testTheRingClosingChalksTheDartBeforeTheWordmarkEverStarts() {
        // The beat the seam lived in: the ring is whole and the wordmark has not begun, so a dart
        // still made of metal lay across a band of pure chalk.
        XCTAssertEqual(DartInk.morph(wordmark: 0, ring: 1), 1, accuracy: 1e-9)
        XCTAssertEqual(DartInk.chalked(0.9, morph: DartInk.morph(wordmark: 0, ring: 1)), 1, accuracy: 1e-9)
    }

    func testItKeepsItsMetalForAllOfTheRingAnybodyWatches() {
        // Three quarters of the ring being drawn is the part with the two fronts racing round it.
        // Chalking the dart there would throw away the reason it is drawn as a dart at all.
        XCTAssertEqual(DartInk.morph(wordmark: 0, ring: 0.0), 0, accuracy: 1e-9)
        XCTAssertEqual(DartInk.morph(wordmark: 0, ring: 0.75), 0, accuracy: 1e-9)
        XCTAssertEqual(DartInk.morph(wordmark: 0, ring: 0.875), 0.5, accuracy: 1e-9)
    }

    func testWhicheverIsFurtherAlongWins() {
        // The wordmark can be ahead when the opening is replayed or scrubbed; neither may undo the other.
        XCTAssertEqual(DartInk.morph(wordmark: 1, ring: 0), 1, accuracy: 1e-9)
        XCTAssertEqual(DartInk.morph(wordmark: 0.4, ring: 0.8), 0.4, accuracy: 1e-9)
        XCTAssertEqual(DartInk.morph(wordmark: 0.1, ring: 0.95), 0.8, accuracy: 1e-9)
    }

    // MARK: - the board (PD-173)

    /// The board's proportions are a real board's, not invented ones.
    ///
    /// A clock dartboard is 451 mm across the double ring's outer edge, the treble ring's outer edge sits at
    /// 214 mm diameter and the bull is 12.7 mm. Those are the ratios the film uses, so that anybody who has
    /// stood in front of one recognises it at a glance without a single number or colour being drawn.
    func testTheBoardHasARealBoardsProportions() {
        // Against the double ring's OUTER radius, which is the board's own 1.0.
        XCTAssertEqual(BoardFace.doubleRing, 1.0, accuracy: 0.0001)
        XCTAssertEqual(BoardFace.trebleRing, 214.0 / 451.0, accuracy: 0.01, "the treble ring, to the real board")
        XCTAssertEqual(BoardFace.bull, 12.7 / 451.0, accuracy: 0.005, "the bull, to the real board")
        XCTAssertEqual(BoardFace.outerBull, 31.8 / 451.0, accuracy: 0.01, "the 25, to the real board")
        XCTAssertTrue(BoardFace.bull < BoardFace.outerBull)
        XCTAssertTrue(BoardFace.outerBull < BoardFace.trebleRing)
        XCTAssertTrue(BoardFace.trebleRing < BoardFace.doubleRing)
    }

    /// Twenty beds, and the wire between two of them is where a real board puts it.
    ///
    /// A board's 20 is at the top, and the wires sit HALFWAY between bed centres — a wire at 0° would put the
    /// 20 on one side of a wire rather than under the light. Getting this wrong is the kind of thing nobody
    /// can name and everybody can see.
    func testTheBoardHasTwentyBedsWithTheWiresBetweenThem() {
        let wires = BoardFace.wireAngles
        XCTAssertEqual(wires.count, 20)
        // Evenly spaced, 18° apart, and none of them straight up: the 20 sits under the light, not a wire.
        for (a, b) in zip(wires, wires.dropFirst()) {
            XCTAssertEqual(b - a, 18, accuracy: 0.0001, "the beds are equal")
        }
        XCTAssertEqual(wires.first, -81, "half a bed off vertical, so the top bed is whole")
        XCTAssertFalse(wires.contains(where: { abs($0 + 90) < 0.001 }), "no wire straight up the middle")
    }

    /// The board is gone before the chalk arrives.
    ///
    /// It exists to be thrown at and for no other reason. The moment the shock starts setting the ring, the
    /// board must be leaving — two circles competing for the same centre is the one way this idea could
    /// spoil the thing it is meant to serve.
    func testTheBoardIsGoneBeforeTheChalkIsSet() {
        let t = LaunchTimeline.standard
        XCTAssertGreaterThan(BoardFace.presence(at: t.impact.start, timeline: t), 0, "it is there to be hit")
        // It goes across the strike, not after it: the burst is radial chalk and so are the wires, so the
        // board must be leaving while the burst is thrown or the burst has nothing to be seen against.
        XCTAssertLessThan(BoardFace.presence(at: t.impact.start + 0.6 * t.impact.duration, timeline: t),
                          0.5 * BoardFace.presence(at: t.impact.start, timeline: t),
                          "half gone before the strike's own segment is over")
        XCTAssertEqual(BoardFace.presence(at: t.ring.start, timeline: t), 0, accuracy: 0.0001,
                       "and gone before the first chalk is set")
        XCTAssertEqual(BoardFace.presence(at: t.ring.end, timeline: t), 0, accuracy: 0.0001,
                       "and gone by the time the ring is whole")
        XCTAssertEqual(BoardFace.presence(at: t.word.start, timeline: t), 0, accuracy: 0.0001)
        XCTAssertEqual(BoardFace.presence(at: t.hold.start, timeline: t), 0, accuracy: 0.0001)
    }

    /// It arrives with the wall, not with the film. Far away there is nothing to see.
    func testTheBoardResolvesOnlyAsTheWallArrives() {
        let t = LaunchTimeline.standard
        let early = BoardFace.presence(at: t.flight.start + 0.1 * t.flight.duration, timeline: t)
        let late = BoardFace.presence(at: t.flight.end - 0.05, timeline: t)
        XCTAssertLessThan(early, late * 0.5, "it is a suggestion at distance and a board on arrival")
        XCTAssertLessThanOrEqual(late, 1.0)
    }

    /// Reduce Motion has no throw, so there is nothing to throw at.
    func testTheBoardIsNotDrawnWhenNothingMoves() {
        let t = LaunchTimeline.reduced
        for at in [0.0, 0.5, 1.0, 1.2] {
            XCTAssertEqual(BoardFace.presence(at: at, timeline: t), 0, accuracy: 0.0001)
        }
    }

    // MARK: - the camera (PD-175)

    /// The camera never steps. It used to, twice.
    ///
    /// The sway took its sine on the absolute clock behind a `tau > 0` gate, so on the first frame of the
    /// flight `sin(2π · 0.45 · 0.28)` was already 0.712 and the whole frame moved most of the sway in one
    /// frame — a jump landing on the film's first real movement — then moved back when the gate closed.
    /// Walking it at 120 Hz is the cheapest way to say "and it must never do that again".
    func testTheCameraNeverStepsBetweenOneFrameAndTheNext() {
        let t = LaunchTimeline.standard
        var previous = LaunchCamera.sway(at: 0, timeline: t)
        var biggest = 0.0
        var at = 0.0
        while at <= t.total {
            let now = LaunchCamera.sway(at: at, timeline: t)
            let step = hypot(now.dx - previous.dx, now.dy - previous.dy)
            biggest = max(biggest, step)
            previous = now
            at += 1.0 / 120.0
        }
        // A point and a half at 120 Hz would be 180 points a second, which is a cut rather than a camera.
        XCTAssertLessThan(biggest, 0.5, "the camera moves smoothly or it is not a camera")
    }

    /// It starts still, ends still, and is felt in between.
    func testTheCameraIsStillAtBothEndsOfTheThrowAndMovesInTheMiddle() {
        let t = LaunchTimeline.standard
        XCTAssertEqual(hypot(LaunchCamera.sway(at: t.flight.start, timeline: t).dx,
                             LaunchCamera.sway(at: t.flight.start, timeline: t).dy), 0, accuracy: 0.001)
        XCTAssertEqual(hypot(LaunchCamera.sway(at: t.flight.end, timeline: t).dx,
                             LaunchCamera.sway(at: t.flight.end, timeline: t).dy), 0, accuracy: 0.001)
        // Somewhere in the middle it is actually felt: 2.6 points on a 402-point screen was not.
        var most = 0.0
        var at = t.flight.start
        while at <= t.flight.end {
            let v = LaunchCamera.sway(at: at, timeline: t)
            most = max(most, hypot(v.dx, v.dy))
            at += 1.0 / 60.0
        }
        XCTAssertGreaterThan(most, 2.5, "a camera you cannot see is a tripod")
    }

    /// Reduce Motion has no camera at all.
    func testTheCameraDoesNotMoveWhenNothingMoves() {
        let t = LaunchTimeline.reduced
        for at in [0.0, 0.4, 0.9, 1.3] {
            let v = LaunchCamera.sway(at: at, timeline: t)
            XCTAssertEqual(hypot(v.dx, v.dy), 0, accuracy: 0.0001)
        }
    }

    // MARK: - the throw's own speed (PD-176)

    /// A dart arrives. It does not drift in.
    ///
    /// `speed` used to fall monotonically from 3.72 to 0.91 dart-lengths per unit of flight — fastest as it
    /// left, slowest as it landed — so the throw crossed the frame early and then floated the last third into
    /// the board. A dart that floats in robs the strike of everything the strike does afterwards. It leaves
    /// fast, loses speed to the air, and then the wall comes up to meet it.
    func testTheDartArrivesFasterThanItDrifts() {
        let mid = Throw.speed(0.55)
        let landing = Throw.speed(0.98)
        XCTAssertGreaterThan(landing, mid, "the wall comes up to meet it")
        XCTAssertGreaterThan(Throw.speed(0.0), landing, "and it still leaves the hand fastest of all")
    }

    /// `speed` is `reach`'s own derivative, or the smear is a decoration rather than a measurement.
    ///
    /// The blur is `smearGain * speed` and nothing else, which is the whole reason it looks right. If the two
    /// ever drift apart the dart is blurred by an amount unrelated to how fast it is going, and nobody would
    /// be able to say why it looked wrong.
    func testSpeedIsTheDerivativeOfReach() {
        let h = 1e-5
        for u in [0.05, 0.2, 0.4, 0.6, 0.8, 0.95] {
            let numerical = (Throw.reach(u + h) - Throw.reach(u - h)) / (2 * h)
            let analytic = Double(Throw.speed(u) / Throw.travelLength)
            XCTAssertEqual(analytic, numerical, accuracy: 1e-3, "speed must be d(reach)/du at \(u)")
        }
    }

    /// It still starts behind the frame and lands where it lands.
    func testTheThrowStillCoversItsWholeJourney() {
        XCTAssertEqual(Throw.reach(0), 0, accuracy: 1e-9)
        XCTAssertEqual(Throw.reach(1), 1, accuracy: 1e-9)
        for (a, b) in zip(stride(from: 0.0, through: 0.99, by: 0.01), stride(from: 0.01, through: 1.0, by: 0.01)) {
            XCTAssertGreaterThan(Throw.reach(b), Throw.reach(a), "it never goes backwards")
        }
    }

    // MARK: - The barrel's material (PD-178)

    /// WCAG 2.x, the same arithmetic the design system's `AccentBranding` uses. Repeated here rather
    /// than imported because these are fixed sRGB colours and that one takes the token layer.
    private func luminance(_ colour: Color) -> Double {
        let r = colour.resolve(in: EnvironmentValues())
        func channel(_ v: Float) -> Double {
            let d = Double(v)
            return d <= 0.03928 ? d / 12.92 : pow((d + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * channel(r.red) + 0.7152 * channel(r.green) + 0.0722 * channel(r.blue)
    }

    private func contrast(_ a: Color, _ b: Color) -> Double {
        let (la, lb) = (luminance(a), luminance(b))
        return (max(la, lb) + 0.05) / (min(la, lb) + 0.05)
    }

    /// **A highlight nobody can see is a flat shape.** The barrel was filled in chalk (#F7F6F2) with
    /// a highlight stroked along it in chalk-raised (#FFFFFF): four values apart in eight bits, a
    /// contrast ratio of 1.08:1. That is not a machined cylinder catching a stage lamp, it is a white
    /// rectangle, and no amount of camera work rescues a sprite.
    ///
    /// A cylinder has a range. This asks for one — not a specific palette, just that the darkest
    /// thing on the barrel and the brightest are far enough apart to read as the same object turning
    /// away from a light.
    func testTheBarrelIsMadeOfSomethingRatherThanNothing() {
        let stops = BarrelMaterial.across(morph: 0)
        let darkest = stops.min { luminance($0.color) < luminance($1.color) }!.color
        let brightest = stops.max { luminance($0.color) < luminance($1.color) }!.color
        XCTAssertGreaterThan(contrast(brightest, darkest), 2.5,
                             "the barrel has no tonal range — it is a white shape, not a cylinder")
    }

    /// The shaft takes the same light at less of it. Both halves of that matter: a shaft with no
    /// range is the flat stick the barrel's new material made obvious, and a shaft with the barrel's
    /// full range is nylon pretending to be tungsten.
    func testTheShaftIsLitLikeTheBarrelButIsNotMadeOfIt() {
        func range(_ stops: [Gradient.Stop]) -> Double {
            let d = stops.min { luminance($0.color) < luminance($1.color) }!.color
            let b = stops.max { luminance($0.color) < luminance($1.color) }!.color
            return contrast(b, d)
        }
        let shaft = range(BarrelMaterial.across(morph: 0, gloss: 0.66))
        XCTAssertGreaterThan(shaft, 1.6, "the shaft is a flat white stick")
        XCTAssertLessThan(shaft, range(BarrelMaterial.across(morph: 0)), "the shaft is not tungsten")
    }

    /// And it still resolves. The ring's band is pure chalk, so anything darker laid across it shows
    /// as a grey line through the Ø — which is the seam the founder saw, and the reason the dart's
    /// material resolves with the dart rather than outlasting it.
    func testTheBarrelResolvesIntoTheBarWithoutASeam() {
        for stop in BarrelMaterial.across(morph: 1) {
            XCTAssertEqual(contrast(stop.color, BarrelMaterial.chalk), 1.0, accuracy: 0.001,
                           "a stop that is not chalk at full morph is a line through the Ø")
        }
    }

    /// The glint must travel. A highlight painted at a fixed place on a barrel is a decal: it says
    /// the dart is a picture of a dart. It moves because the angle between a cylinder and its light
    /// changes as the cylinder crosses the room, and in this film both of them are moving.
    func testTheGlintTravelsAlongTheBarrel() {
        let axis = CGVector(dx: cos(-Double.pi / 4), dy: sin(-Double.pi / 4))
        // The dart's barrel walking its own path up the frame, against a lamp above the middle.
        let light = CGPoint(x: 201, y: 262)
        let seen = stride(from: 0.0, through: 1.0, by: 0.1).map { u -> Double in
            let at = CGPoint(x: 40 + 220 * u, y: 700 - 400 * u)
            return BarrelMaterial.glint(axis: axis, from: at, toLight: light)
        }
        for g in seen { XCTAssertTrue(g >= 0 && g <= 1, "the glint left the barrel: \(g)") }
        XCTAssertGreaterThan(seen.max()! - seen.min()!, 0.30,
                             "the glint barely moves across the whole throw — it is a decal")
    }

    // MARK: - The strike (PD-180)

    /// **A strike you cannot feel is a cut.** The board is hit at 1.68 s, and what the camera did
    /// about it was a 3.8-point shake on an 874-point screen: four tenths of one percent, less than
    /// the breathing sway that runs through the whole flight. The loudest moment in the film moved the
    /// frame less than its quietest one.
    ///
    /// This asks for a real one, and for it to start and finish at exactly nothing — a kick that is
    /// cut off mid-swing steps the frame on the way out, which is the defect PD-175 found in the sway.
    func testTheStrikeIsFeltAndLeavesNothingBehind() {
        XCTAssertEqual(LaunchCamera.kick(sinceImpact: 0).dx, 0, accuracy: 1e-9)
        XCTAssertEqual(LaunchCamera.kick(sinceImpact: 0).dy, 0, accuracy: 1e-9)
        var peak = 0.0
        for step in 0...600 {
            let s = 0.5 * Double(step) / 600
            let v = LaunchCamera.kick(sinceImpact: s)
            peak = max(peak, (v.dx * v.dx + v.dy * v.dy).squareRoot())
        }
        XCTAssertGreaterThan(peak, 11, "the strike moves the camera less than a breath does")
        for s in [0.34, 0.5, 1.0, 3.0] {
            let v = LaunchCamera.kick(sinceImpact: s)
            XCTAssertEqual((v.dx * v.dx + v.dy * v.dy).squareRoot(), 0, accuracy: 1e-9,
                           "the kick is still running at \(s) s")
        }
    }

    /// And the frame is punched. A camera that is only shaken sideways reads as a wobble; an impact
    /// reads when the whole picture jumps *at* the thing that was hit and settles back.
    ///
    /// It has to leave the composition exactly where it found it — the wordmark's position is the
    /// finished frame, and a punch that does not return is a layout error that only happens sometimes.
    func testTheFrameIsPunchedAndPutBackExactly() {
        XCTAssertEqual(LaunchCamera.punch(sinceImpact: 0), 1, accuracy: 1e-9)
        for s in [0.6, 1.0, 3.0] {
            XCTAssertEqual(LaunchCamera.punch(sinceImpact: s), 1, accuracy: 1e-9,
                           "the punch is still going at \(s) s")
        }
        let peak = stride(from: 0.0, through: 0.6, by: 0.001).map { LaunchCamera.punch(sinceImpact: $0) }.max()!
        XCTAssertGreaterThan(peak, 1.015, "the punch cannot be seen")
        XCTAssertLessThan(peak, 1.05, "the punch is a zoom")
    }

    /// The flights ring at their own rate.
    ///
    /// The shaft and the flights were both given 8 Hz and the same 0.22 decay, 25 ms apart — so the
    /// flights were a delayed copy of the shaft and the dart whipped as **one bent rod**. A flight is
    /// a few grams of folded plastic on the end of a stiff shaft: it is lighter, so it rings faster,
    /// and it has far more air on it, so it stops sooner. Two rates is the difference between a dart
    /// that landed and a shape that bent.
    func testTheFlightsRingFasterThanTheShaftAndStopFirst() {
        func crossings(_ f: (Double) -> Double) -> Int {
            var count = 0, previous = f(0.0)
            for step in 1...2000 {
                let value = f(0.4 * Double(step) / 2000)
                if (previous < 0) != (value < 0) { count += 1 }
                previous = value
            }
            return count
        }
        XCTAssertGreaterThan(crossings(DartRing.flights), crossings(DartRing.shaft),
                             "the flights are a delayed copy of the shaft, not a lighter part")
        // Quiet first: a tenth of a degree is nothing anybody can see at this size.
        func quietAt(_ f: (Double) -> Double) -> Double {
            for step in 0...2400 {
                let s = 1.2 * Double(step) / 2400
                if stride(from: s, through: 1.2, by: 0.01).allSatisfy({ abs(f($0)) < 0.1 * .pi / 180 }) { return s }
            }
            return 1.2
        }
        XCTAssertLessThan(quietAt(DartRing.flights), quietAt(DartRing.shaft),
                          "the flights are still ringing after the shaft has stopped")
    }

    // MARK: - The composition, on a screen that is not an iPhone (PD-181)

    /// Every screen THRØ has ever been run on or asked about, in points. The iPads are here because
    /// the app ships without an iPad-only build but iOS runs it on one anyway, and the opening is the
    /// first thing it shows.
    private static let screens: [(name: String, size: CGSize)] = [
        ("iPhone SE", CGSize(width: 375, height: 667)),
        ("iPhone 17", CGSize(width: 393, height: 852)),
        ("iPhone 17 Pro", CGSize(width: 402, height: 874)),
        ("iPhone 17 Pro Max", CGSize(width: 440, height: 956)),
        ("iPad mini", CGSize(width: 744, height: 1133)),
        ("iPad Pro 11", CGSize(width: 834, height: 1210)),
        ("iPad Pro 13", CGSize(width: 1024, height: 1366)),
        ("iPad Pro 13, turned", CGSize(width: 1366, height: 1024)),
        ("a window half a desk wide", CGSize(width: 1366, height: 600)),
    ]

    /// **The same picture on every screen.**
    ///
    /// The mark's width was `min(size.width * 0.84, 380)`. On every iPhone ever made the first term
    /// wins and the cap is dead code; on an iPad Pro the cap wins by a mile and the title card becomes
    /// a small island in the middle of a very large green field — the same composition it is on a
    /// phone, rendered at a third of the size, with two thirds of the screen doing nothing.
    ///
    /// The fix is not a bigger cap. A cap is the wrong shape of answer: what bounds this composition
    /// is the width it has to fit across *and* the height it has to leave the tagline room in, and
    /// both of those are properties of the screen. So the assertion is the thing anybody actually
    /// wants — that the opening looks like itself everywhere — expressed as the mark taking the same
    /// share of the space available to it on all of them.
    func testTheTitleCardIsTheSamePictureOnEveryScreen() {
        let shares = Self.screens.map { screen -> (String, Double) in
            // What the composition has to work with, stated from the composition's own geometry and
            // not from the implementation: the mark is centred at 0.44 of the height, so half of it
            // plus the tagline under it plus room to breathe is about 0.57 of the height — and it
            // must fit across the width whatever else is true.
            let available = min(screen.size.width, screen.size.height * 0.57)
            return (screen.name, Double(LaunchComposition.markWidth(in: screen.size) / available))
        }
        let smallest = shares.min { $0.1 < $1.1 }!
        let largest = shares.max { $0.1 < $1.1 }!
        XCTAssertLessThan(largest.1 / smallest.1, 1.05,
                          "\(smallest.0) gets \(smallest.1) of its frame and \(largest.0) gets \(largest.1)")
    }

    /// And no iPhone moves. This is the whole reason the change is safe to make: the founder has judged
    /// this film frame by frame on a 402-point screen, and a composition change that moved it would
    /// throw that away to fix a screen nobody has yet run it on.
    func testNoPhoneMovesByAPoint() {
        for screen in Self.screens where screen.name.hasPrefix("iPhone") {
            XCTAssertEqual(LaunchComposition.markWidth(in: screen.size),
                           min(screen.size.width * 0.84, 380), accuracy: 1e-9,
                           "\(screen.name) is not where it was")
        }
    }
}
