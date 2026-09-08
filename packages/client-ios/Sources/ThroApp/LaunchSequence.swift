import SwiftUI
import ThroTokens
import ThroDesign

// PD-007, seventh version. The sixth answered the founder's fifth look — "Feels like the end screen
// with the bottom text should be visible just a little bit longer so people can read it properly.
// Also any further visual upgrades to the intro" — by holding the tagline still and fully legible
// for 1.37 seconds, two and a half times what it had. The seventh answers the sixth look: the Ø is
// struck into being by the shock rather than drawn on, and half a second comes out of the end. The
// tagline still has 0.87 s of stillness, two thirds again what the fifth version gave it.
//
// The **handover** is the eighth change and the only one in this file's neighbourhood rather than
// in it: the cross-fade to the app used `.easeInOut`, Apple's curve, on the single most important
// transition THRØ has. It is `Animation.throExit` now — the design's own — and the app comes
// towards the viewer by `motionScaleImpact` as the opening leaves, so the handover is one movement
// in one direction rather than a cut. Both withdraw under Reduce Motion. See `ThroRootView`.
//
// The opening is one shot. It opens on a place: a lit spot far off in a dark hall under a beam from
// above, with chalk dust on it. The dart comes in from the lower left at the mark's 45° and never
// changes direction: no roll of the camera, no pitch. It crosses a screen and a half as the camera's aim
// catches it, smeared by exactly its own speed, then settles into a slow closing drift while the wall
// comes on at a constant proportional rate — real perspective, an apparent size of one over distance —
// so every speck of dust on it slides outward from the spot being aimed at and draws into a streak.
// Nothing else looks like flying at a surface. Then the strike, on the frame of the thud: a flash at the
// point, chalk knocked off the board and falling, the frame shaking, the board giving and holding while
// the shaft and flights whip and the tungsten does not. From the point, a thin line of chalk runs both
// ways from each crossing and the stroke fills in behind it until the ring is whole. Then the mark
// becomes the name: it is home in the last slot of THRØ before the first letter is struck beside it, and
// its ring carries the letters' own weight — measured off Archivo ExtraBold, not guessed. The tagline
// tracks in as the last letter sets, and is then left alone to be read. The first frame is the launch
// screen's flat green. Cold launch only; a tap skips; Reduce Motion shows the name, still.

/// The spine of the opening, in seconds from the first frame. Segments are contiguous; effects that
/// outlive their segment (the quiver, the ring's pulse) run from a segment's boundary on their own clock.
public struct LaunchTimeline: Equatable, Sendable {
    public struct Segment: Equatable, Sendable {
        public let name: String
        public let start: Double
        public let end: Double
        public var duration: Double { end - start }
        /// 0 before the segment, 1 after it, linear within; a zero-length segment is 1 from its instant.
        public func progress(at t: Double) -> Double {
            guard end > start else { return t >= end ? 1 : 0 }
            return min(1, max(0, (t - start) / (end - start)))
        }
    }

    public let field: Segment
    public let flight: Segment
    public let impact: Segment
    public let ring: Segment
    public let word: Segment
    public let hold: Segment
    public let exit: Segment

    public var segments: [Segment] { [field, flight, impact, ring, word, hold, exit] }
    public var total: Double { exit.end }
    /// When the root begins the cross-fade to Home.
    public var finishAt: Double { exit.start }

    /// The lit spot to 280 ms; the flight to 1680; the strike's beat, through which the shock travels
    /// out, to 2060; the ring it sets to 2580; the word to 3420; the hold, in which the tagline arrives
    /// and is then left alone, to 4460; the cross-fade to 4860.
    ///
    /// The sixth version held the tagline for 1.37 s and the founder read it and asked for "maybe half a
    /// second shorter at the end". That half second comes out of the hold and nothing else, so the
    /// tagline still has 0.87 s of stillness — two thirds again what the fifth version gave it, which
    /// was the version they could not read.
    public static let standard = LaunchTimeline(cuts: [0, 0.28, 1.68, 2.06, 2.58, 3.42, 4.46, 4.86])
    /// Reduce Motion: the finished composition from the first frame, long enough to read it, the fade.
    public static let reduced = LaunchTimeline(cuts: [0, 0, 0, 0, 0, 0, 1.10, 1.40])
    /// When T, H and R are struck in, as fractions of the word segment — after the mark is in its slot.
    public static let stampFractions: [Double] = [0.46, 0.57, 0.68]
    /// How long the tagline takes to track in.
    public static let taglineSeconds: Double = 0.35
    /// When the mark has finished moving into the name's last slot, as a fraction of the word segment.
    /// The letters are struck in after it, so a letter never lands against a mark still in transit.
    public static let markHomeBy: Double = 0.62

    /// When the tagline starts to arrive: as the last letter sets, so the composition assembles as one
    /// gesture rather than in two acts.
    public var taglineAt: Double { isAnimated ? word.start + 0.78 * word.duration : 0 }
    /// How long the tagline is still, at full strength, and alone with the name before the cross-fade
    /// begins. This is the thing the founder asked for, so it is a number the tests hold.
    public var taglineSettledFor: Double { finishAt - (taglineAt + (isAnimated ? Self.taglineSeconds : 0)) }

    /// Whether anything moves. False under Reduce Motion, where every effect is already at rest from
    /// the first frame: no flight, no strike, no dust, no pulse, no cue.
    public var isAnimated: Bool { flight.duration > 0 }

    /// Sound and haptic cues, by name and time: the whoosh with the flight, the thud and the heavy haptic
    /// at the strike, the chalk with the ring, a firm stamp as each letter lands. None under Reduce
    /// Motion: no motion, nothing to score.
    public var cues: [LaunchCue] {
        guard isAnimated else { return [] }
        var cues = [LaunchCue(name: "whoosh", at: flight.start),
                    LaunchCue(name: "thud", at: impact.start),
                    LaunchCue(name: "haptic", at: impact.start),
                    LaunchCue(name: "chalk", at: ring.start)]
        for fraction in Self.stampFractions {
            cues.append(LaunchCue(name: "stamp", at: word.start + fraction * word.duration))
        }
        return cues
    }

    init(cuts c: [Double]) {
        precondition(c.count == 8, "seven segments need eight cuts")
        let names = ["field", "flight", "impact", "ring", "word", "hold", "exit"]
        let s = (0..<7).map { Segment(name: names[$0], start: c[$0], end: c[$0 + 1]) }
        field = s[0]; flight = s[1]; impact = s[2]; ring = s[3]; word = s[4]; hold = s[5]; exit = s[6]
    }
}

public struct LaunchCue: Equatable, Sendable {
    public let name: String
    public let at: Double
}

// `Easing` and `MarkGeometry` moved to `ThroDesign/Geometry.swift` (SLATE B.0): the token
// layer's easings and the founder's mark's proportions are the design's, not the opening's,
// and the chalk terminations are drawn from the same geometry. Byte for byte, no behaviour
// change; this file already imports ThroDesign.

/// The throw as the camera sees it, over the flight's time `tau` (0...1), in dart-lengths. The dart flies
/// at the mark's angle from the first frame to the strike: no roll of the camera, no pitch, no change of
/// direction. The camera flies with it, a little behind and outside the line, so the dart holds its size
/// while the wall grows — and the wall's growth is perspective, not a curve chosen for looks: apparent
/// size is one over distance, and the distance closes at a constant proportional rate, so the wall doubles
/// every 0.43 of the flight and there is no part of the throw without approach in it. The camera's aim
/// lags at the start and catches up: the dart crosses a screen and a half in the first fifth of the
/// flight, then settles into a slow closing drift and drives in at the strike.
public enum Throw {
    /// How large the wall is when the throw starts, of its size at the strike — a fifth, which is a
    /// distance of five board-widths closing to one.
    public static let farScale: CGFloat = 0.20
    /// Where the aim sits when the wall is far, from the spot it is aimed at, in dart-lengths.
    public static let farOffset = CGVector(dx: 0.10, dy: -0.12)
    /// How far behind its landed place the dart starts, in dart-lengths — more than a screen's height.
    public static let travelLength: CGFloat = 1.50
    /// The smear per unit of the dart's speed, so the blur is the motion and nothing else.
    public static let smearGain: CGFloat = 0.17
    public static let bobPoints: CGFloat = 7

    /// The wall's apparent size, of its size at the strike.
    public static func targetScale(_ tau: Double) -> CGFloat {
        CGFloat(pow(Double(farScale), 1 - Easing.unit(tau)))
    }
    /// The same curve as 0 far to 1 arrived, for everything that strengthens as the wall nears.
    public static func approach(_ tau: Double) -> Double {
        Double((targetScale(tau) - farScale) / (1 - farScale))
    }
    /// How much of its journey across the frame the dart has made, 0 at the first frame to 1 at the strike.
    public static func reach(_ tau: Double) -> Double {
        let u = Easing.unit(tau)
        return 0.62 * (1 - pow(1 - u, 4)) + 0.38 * pow(u, 1.6)
    }
    /// Where the dart is along its own line relative to its landed place, in dart-lengths: behind it,
    /// closing to nothing at the strike.
    public static func travel(_ tau: Double) -> CGFloat {
        -(1 - CGFloat(reach(tau))) * travelLength
    }
    /// The derivative of `reach`, in dart-lengths per unit of flight: the dart's speed across the frame.
    public static func speed(_ tau: Double) -> CGFloat {
        let u = Easing.unit(tau)
        return travelLength * CGFloat(2.48 * pow(1 - u, 3) + 0.608 * pow(u, 0.6))
    }
    /// The motion smear along the dart's line, in dart-lengths: its speed, so it is never longer than the
    /// motion and never outlives it.
    public static func smear(_ tau: Double) -> CGFloat { smearGain * speed(tau) }
    /// One rise and fall across the line of flight, 0...1...0.
    public static func bob(_ tau: Double) -> Double { sin(.pi * Easing.unit(tau)) }
    /// Where the aim is, from the spot being aimed at, in dart-lengths.
    public static func targetOffset(_ tau: Double) -> CGVector {
        let p = CGFloat(approach(tau))
        return CGVector(dx: farOffset.dx * (1 - p), dy: farOffset.dy * (1 - p))
    }
}

/// A dart as a dart, in profile, pointing along +x with its point at the origin: a fine point with a bright
/// core, a tapered tungsten barrel with grip rings and two grooves, a collar where the shaft seats, a slim
/// shaft with a ring where the flights seat, and standard flights carrying the mark. Lengths and half-widths
/// are fractions of the whole, which is the mark's bar tip to tip, so the landed dart lies exactly where the
/// bar will be. Point 0.24, barrel 0.30, shaft 0.22, flights 0.24.
public struct DartAnatomy: Equatable, Sendable {
    public static let point: CGFloat = 0.24
    public static let barrel: CGFloat = 0.30
    public static let shaft: CGFloat = 0.22
    public static let flight: CGFloat = 0.24
    /// Half-widths as fractions of the whole length.
    public static let pointHalf: CGFloat = 0.008
    public static let barrelHalf: CGFloat = 0.027
    public static let barrelNose: CGFloat = 0.016
    public static let shaftHalf: CGFloat = 0.0165
    public static let collarHalf: CGFloat = 0.0205
    public static let flightHalf: CGFloat = 0.105
    /// The mark's bar half-width as a fraction of the dart's length: what every part's half-width
    /// becomes as the dart resolves into the bar.
    public static let barHalf: CGFloat = MarkGeometry.halfWidthRatio / (2 * MarkGeometry.tipRatio)

    /// The dart's length tip to tail.
    public let length: CGFloat
    public init(length: CGFloat) { self.length = length }

    /// Where each part ends, measured back from the point along the dart (negative x).
    public var pointEnd: CGFloat { -Self.point * length }
    public var barrelEnd: CGFloat { pointEnd - Self.barrel * length }
    public var shaftEnd: CGFloat { barrelEnd - Self.shaft * length }
    public var tailEnd: CGFloat { shaftEnd - Self.flight * length }

    /// The barrel's radius at `x`: a nose taper over the front third, a grip section, a short collar at
    /// the rear; mixed toward the bar's half-width by `morph`.
    public func barrelRadius(at x: CGFloat, morph m: CGFloat) -> CGFloat {
        let a = pointEnd, b = barrelEnd
        let u = (a - x) / (a - b)
        let bh = Self.barrelHalf, nose = Self.barrelNose
        let r: CGFloat
        if u < 0.33 {
            let q = u / 0.33
            r = nose + (bh - nose) * (1 - (1 - q) * (1 - q))
        } else if u < 0.9 {
            r = bh
        } else {
            r = Self.collarHalf + (bh - Self.collarHalf) * max(0, (0.93 - u) / 0.03)
        }
        return (r + (Self.barHalf - r) * m) * length
    }

    /// Paths in a frame where the dart points along +x with its point at the origin.
    public struct Parts {
        public var point = Path()
        public var pointCore = Path()
        public var barrel = Path()
        public var highlight = Path()
        public var shade = Path()
        public var knurl = Path()
        public var grooves = Path()
        public var shaft = Path()
        public var collar = Path()
        public var nearFlights = Path()
        public var farFlights = Path()
        public var logo = Path()
        /// How face-on the near flights are, 0 edge-on to 1 face-on.
        public var nearScale: CGFloat = 0
    }

    /// `spin` is the roll about the dart's own axis, which foreshortens the flights. `morph`, 0...1,
    /// resolves the dart into the mark's bar: the flights fold flat, every half-width becomes the bar's,
    /// and the shaft runs on to the tail and tapers to the bar's point.
    public func parts(spin: Double, morph: CGFloat = 0) -> Parts {
        let m = min(1, max(0, morph))
        func mix(_ a: CGFloat, _ b: CGFloat) -> CGFloat { a + (b - a) * m }
        let L = length
        let pEnd = pointEnd, bEnd = barrelEnd, sEnd = shaftEnd, fEnd = tailEnd
        var parts = Parts()
        // the point: a fine cone, with a bright core
        let ph = mix(Self.pointHalf, Self.barHalf) * L
        parts.point.move(to: CGPoint(x: 0, y: 0))
        parts.point.addLine(to: CGPoint(x: pEnd, y: -ph))
        parts.point.addLine(to: CGPoint(x: pEnd, y: ph))
        parts.point.closeSubpath()
        parts.pointCore.move(to: CGPoint(x: -0.015 * L, y: -ph * 0.15))
        parts.pointCore.addLine(to: CGPoint(x: pEnd, y: -ph * 0.35))
        // the barrel: its profile as a closed shape; a highlight along its top; a shade band along its lower half
        let steps = 28
        var top: [CGPoint] = [], bottom: [CGPoint] = []
        for i in 0...steps {
            let x = pEnd + (bEnd - pEnd) * CGFloat(i) / CGFloat(steps)
            let r = barrelRadius(at: x, morph: m)
            top.append(CGPoint(x: x, y: -r)); bottom.append(CGPoint(x: x, y: r))
        }
        parts.barrel.move(to: top[0])
        for pt in top.dropFirst() { parts.barrel.addLine(to: pt) }
        for pt in bottom.reversed() { parts.barrel.addLine(to: pt) }
        parts.barrel.closeSubpath()
        for (i, pt) in top.enumerated() {
            let q = CGPoint(x: pt.x, y: pt.y * 0.62)
            if i == 0 { parts.highlight.move(to: q) } else { parts.highlight.addLine(to: q) }
        }
        if m < 1 {
            parts.shade.move(to: CGPoint(x: bottom[0].x, y: bottom[0].y * 0.30))
            for pt in bottom.dropFirst() { parts.shade.addLine(to: CGPoint(x: pt.x, y: pt.y * 0.30)) }
            for pt in bottom.reversed() { parts.shade.addLine(to: CGPoint(x: pt.x, y: pt.y * 0.88)) }
            parts.shade.closeSubpath()
        }
        // grip rings across the middle of the barrel, and two deeper grooves
        let gripA = pEnd - (pEnd - bEnd) * 0.36, gripB = pEnd - (pEnd - bEnd) * 0.86
        for i in 0...11 {
            let x = gripA + (gripB - gripA) * CGFloat(i) / 11
            let r = barrelRadius(at: x, morph: m) * 0.92
            parts.knurl.move(to: CGPoint(x: x, y: -r)); parts.knurl.addLine(to: CGPoint(x: x, y: r))
        }
        for u in [CGFloat(0.30), CGFloat(0.62)] {
            let x = pEnd - (pEnd - bEnd) * u
            let r = barrelRadius(at: x, morph: m)
            parts.grooves.move(to: CGPoint(x: x, y: -r)); parts.grooves.addLine(to: CGPoint(x: x, y: r))
        }
        // the shaft: a slim rod at rest; resolving, it runs on to the tail and tapers to the bar's point
        let sh = mix(Self.shaftHalf, Self.barHalf) * L
        let tail = mix(sEnd, fEnd)
        let tailHalf = sh * (1 - m)
        parts.shaft.move(to: CGPoint(x: bEnd, y: -sh))
        parts.shaft.addLine(to: CGPoint(x: tail, y: -tailHalf))
        parts.shaft.addLine(to: CGPoint(x: tail, y: tailHalf))
        parts.shaft.addLine(to: CGPoint(x: bEnd, y: sh))
        parts.shaft.closeSubpath()
        // the ring where the flights seat
        let ch = mix(Self.collarHalf, Self.barHalf) * L, cl = 0.016 * L
        if m < 1 {
            parts.collar.addRoundedRect(in: CGRect(x: sEnd - cl * 0.2, y: -ch, width: cl, height: 2 * ch),
                                        cornerSize: CGSize(width: ch * 0.45, height: ch * 0.45))
        }
        // the flights: two pairs at right angles, the standard shape — a swelling leading edge, a rounded top
        // corner, a near-vertical trailing edge — seen edge-on to face-on as the dart rolls; folded flat by the morph
        let fl = sEnd - fEnd, fh = Self.flightHalf * L
        func fins(_ scale: CGFloat) -> Path {
            var p = Path()
            guard scale > 0.02 else { return p }
            let h = fh * scale
            for sign in [CGFloat(1), CGFloat(-1)] {
                p.move(to: CGPoint(x: sEnd, y: sign * sh))
                p.addCurve(to: CGPoint(x: fEnd + 0.11 * fl, y: sign * h),
                           control1: CGPoint(x: sEnd - 0.52 * fl, y: sign * h * 0.16),
                           control2: CGPoint(x: sEnd - 0.72 * fl, y: sign * h * 0.72))
                p.addQuadCurve(to: CGPoint(x: fEnd, y: sign * h * 0.86), control: CGPoint(x: fEnd + 0.012 * fl, y: sign * h))
                p.addLine(to: CGPoint(x: fEnd, y: sign * sh))
                p.closeSubpath()
            }
            return p
        }
        // Which pair of vanes is in front is the sign of the roll, not its size: the pair facing the
        // camera is the near one, and the other goes behind. Taking the magnitude of each, as this did,
        // put the far pair in front for half of every turn.
        let a = CGFloat(abs(cos(spin))) * (1 - m), b = CGFloat(abs(sin(spin))) * (1 - m)
        let firstPairIsNear = cos(spin) >= 0
        let nearScale = firstPairIsNear ? a : b, farScale = firstPairIsNear ? b : a
        parts.nearFlights = fins(nearScale)
        parts.farFlights = fins(farScale)
        parts.nearScale = nearScale
        // the mark, small, on each near flight, as flights carry a maker's mark — only while the vane is
        // face-on enough to carry it, or it reads as a scratch
        if nearScale > 0.55 && m < 0.05 {
            let logo = MarkGeometry(unit: fh * nearScale * 0.34)
            for sign in [CGFloat(1), CGFloat(-1)] {
                let c = CGPoint(x: fEnd + 0.40 * fl, y: sign * fh * nearScale * 0.55)
                parts.logo.addPath(logo.ringShape(at: c))
                parts.logo.addPath(logo.bar(at: c))
            }
        }
        return parts
    }
}

/// The wordmark: Archivo ExtraBold's letters, and the Ø's place after them (docs/design/brand/render_wordmark.py).
public enum WordmarkGeometry {
    public static let ringOuter = MarkGeometry.Ratios.wordmark.ringOuter
    public static let ringInner = MarkGeometry.Ratios.wordmark.ringInner
    public static let halfWidth = MarkGeometry.Ratios.wordmark.halfWidth
    public static let tip = MarkGeometry.Ratios.wordmark.tip
    /// The gap after the R, of the cap height.
    public static let gap: CGFloat = 0.10
    /// Archivo ExtraBold's vertical metrics, from the face's own tables.
    public static let capHeightPerEm: CGFloat = 687.0 / 1000.0
    public static let ascenderPerEm: CGFloat = 878.0 / 1000.0
    public static let descenderPerEm: CGFloat = 210.0 / 1000.0
    /// What the Ø adds to the width of THR, per unit of cap height: the gap, the ring's left half, and
    /// the upper-right tip beyond it.
    public static let tailPerCap: CGFloat = gap + ringOuter + tip * CGFloat(0.5).squareRoot()
}

/// The opening. Draws every frame from a Canvas as a pure function of time; scores it with the
/// soundtrack and haptics; a tap finishes it early.
public struct LaunchSequenceView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage(OpeningPreferences.soundKey) private var soundOn: Bool = true
    @AppStorage(OpeningPreferences.hapticsKey) private var hapticsOn: Bool = true
    /// Called with how long the cross-fade to Home should take: the exit segment when the opening runs
    /// its course, and a shorter one when a tap skips it, because a skip should feel answered.
    private let onFinished: (Double) -> Void
    @State private var start = Date()
    @State private var finished = false
    @State private var soundtrack: LaunchSoundtrack? = nil

    public init(onFinished: @escaping (Double) -> Void) { self.onFinished = onFinished }

    private var timeline: LaunchTimeline { reduceMotion ? .reduced : .standard }

    public var body: some View {
        let timeline = self.timeline
        TimelineView(.animation(minimumInterval: 1.0 / 60.0, paused: finished)) { context in
            LaunchFrame(t: context.date.timeIntervalSince(start), timeline: timeline)
        }
        .background(ThroColor.throGreen.ignoresSafeArea())
        .ignoresSafeArea()
        .contentShape(Rectangle())
        .onTapGesture { finish(fade: Self.skipFade) }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("THRØ")
        .accessibilityHint("Opening. Tap to skip.")
        .accessibilityAddTraits(.isButton)
        .onAppear {
            let now = Date()
            start = now
            let track = LaunchSoundtrack(sound: soundOn, haptics: hapticsOn)
            track.schedule(timeline.cues, from: now)
            soundtrack = track
            DispatchQueue.main.asyncAfter(deadline: .now() + timeline.finishAt) { finish(fade: timeline.exit.duration) }
        }
    }

    /// How long the cross-fade takes when a tap skips the opening.
    static let skipFade = 0.22

    private func finish(fade: Double) {
        guard !finished else { return }
        finished = true
        soundtrack?.stop()
        onFinished(fade)
    }
}

/// One frame of the opening at time `t`.
struct LaunchFrame: View {
    let t: Double
    let timeline: LaunchTimeline

    var body: some View {
        Canvas { context, size in
            draw(in: &context, size: size)
        }
    }

    /// The numbers that are taste rather than measurement, in one place.
    enum Tune {
        static let dustAlpha = 0.42                      // chalk on the wall, at its strongest
        static let dustCount = 420
        static let dustSpread: CGFloat = 3.2             // how far the dust reaches across the wall, in dart-lengths
        static let lightRadius: CGFloat = 1.90           // the pool of light, of the ring's outer radius
        static let beamAlpha = 0.075                     // the stage light's beam, at its brightest
        static let beamLift: Double = 2.6                // how much brighter the dust is inside the beam
        static let rollTurns = 0.5                       // over the whole flight, at a steady rate
        static let sway: CGFloat = 2.6                   // the camera breathes as a carried camera does
        static let swayHertz = 0.45
        static let driveSeconds = 0.09                   // the board gives, and holds
        static let drive: CGFloat = 0.020                // of the dart's length
        static let shakeSeconds = 0.22
        static let flashSeconds = 0.13                   // the light of the strike, brightest on its first frame
        static let stampSeconds = 0.05                   // a letter is struck on, not faded in
        static let settleSeconds = 0.20
        static let shockRunOn: Double = 1.15             // how fast the shock leaves the mark behind, per second
        static let shockAlpha = 0.60                     // the shock at its brightest, out of the point
        static let hotDegrees = 9.0                      // how far behind its front the set chalk is still hot
        static let frontDegrees = 11.0                   // the leading edge, which falls off in strength, never in width
        static let frontSteps = 5
        static let shockMotes = 74                       // the chalk the shock throws off the board
        static let shockInner = 0.72                     // it is only drawn out near the ring, in ring radii
        static let shockScatter = 0.34                   // how ragged its front is
        static let closeFlash = 0.17                     // the light of the ring becoming whole
        static let taglineSeconds = LaunchTimeline.taglineSeconds
        static let tagline = "FROM THE PUB BOARD TO THE WORLD STAGE"
    }

    /// One speck of chalk at a fixed place on the wall, in dart-lengths from the spot being aimed at.
    /// `tier` is how brightly it takes the light — its own grain, times the falloff away from the lit
    /// spot — quantised so the whole field can be drawn as a handful of paths rather than one per speck.
    struct Speck { let u, v, r: CGFloat; let tier: Int }
    static let dustTiers = 5
    static func dustWeight(_ tier: Int) -> Double { (Double(tier) + 0.5) / Double(dustTiers) }
    /// The dust on the wall: a fixed scatter, the same every run, drawn through the wall's perspective.
    static let wallDust: [Speck] = {
        var rng = Grain(seed: 0x9E37_79B9)
        let tiers = LaunchFrame.dustTiers
        return (0..<LaunchFrame.Tune.dustCount).map { _ in
            let angle = Double(rng.next()) * 2 * Double.pi
            let radius = LaunchFrame.Tune.dustSpread * CGFloat(Double(rng.next()).squareRoot())
            let u = CGFloat(cos(angle)) * radius, v = CGFloat(sin(angle)) * radius
            let size = 0.5 + 0.7 * rng.next(), grain = 0.35 + 0.65 * rng.next()
            let fall = 1 / (1 + 2.1 * (u * u + v * v))
            let tier = min(tiers - 1, max(0, Int(grain * fall * CGFloat(tiers))))
            return Speck(u: u, v: v, r: size, tier: tier)
        }
    }()

    private func draw(in context: inout GraphicsContext, size: CGSize) {
        let chalk = ThroColor.throChalk
        let animated = timeline.isAnimated
        let pField = timeline.field.progress(at: t)
        let tau = timeline.flight.progress(at: t)
        let pRing = Easing.chalk(timeline.ring.progress(at: t))
        let pWord = Easing.resolve(timeline.word.progress(at: t))
        let pHold = timeline.hold.progress(at: t)
        let sinceImpact = t - timeline.impact.start
        let sinceRing = t - timeline.ring.end
        let axis = MarkGeometry.axis
        let across = CGVector(dx: -axis.dy, dy: axis.dx)

        // The camera: it breathes through the flight as a carried camera does, and the strike shakes it,
        // mostly along the line of the throw, dying in a fifth of a second.
        if animated && tau > 0 && tau < 1 {
            let s = Tune.sway * CGFloat(1 - tau * 0.4)
            context.translateBy(x: s * CGFloat(sin(2 * Double.pi * Tune.swayHertz * t)),
                                y: s * 0.7 * CGFloat(sin(2 * Double.pi * Tune.swayHertz * 0.63 * t + 1.1)))
        }
        if animated && sinceImpact >= 0 && sinceImpact < Tune.shakeSeconds {
            let along = CGFloat(Easing.damped(sinceImpact, amplitude: 5, hertz: 11, decay: 0.075))
            let side = CGFloat(Easing.damped(sinceImpact, amplitude: 1.8, hertz: 17, decay: 0.06))
            context.translateBy(x: axis.dx * along + across.dx * side, y: axis.dy * along + across.dy * side)
        }
        let canvas = CGRect(origin: .zero, size: size).insetBy(dx: -12, dy: -12)

        // The field, in screen space: the launch screen's flat green on the first frame, then a vignette
        // that closes a little further as the name settles, to put the frame around what is to be read.
        let vignette = 0.38 * pField + 0.06 * (animated ? Easing.resolve(pHold) : 1)
        let field = Gradient(colors: [ThroColor.throInk.opacity(0), ThroColor.throInk.opacity(vignette)])
        context.fill(Path(canvas),
                     with: .radialGradient(field, center: CGPoint(x: size.width / 2, y: size.height / 2),
                                           startRadius: min(size.width, size.height) * 0.3, endRadius: max(size.width, size.height) * 0.72))

        // Layout: the mark large and central through the throw; the name across the width with the mark as
        // its Ø, which is also the finished composition; the tagline beneath it.
        func lerp(_ a: CGPoint, _ b: CGPoint, _ s: CGFloat) -> CGPoint { CGPoint(x: a.x + (b.x - a.x) * s, y: a.y + (b.y - a.y) * s) }
        let (perCap, extra) = typeMetrics(context)
        let bigTip = min(size.width * 0.84, 380)
        let big = MarkGeometry(tipToTip: bigTip)
        let bigCentre = CGPoint(x: size.width / 2, y: size.height * 0.44)
        let wordC = bigTip / (perCap + extra)
        let wordThr = perCap * wordC
        let wordLeft = (size.width - bigTip) / 2
        let baseline = bigCentre.y + wordC / 2
        let oCentre = CGPoint(x: wordLeft + wordThr + (WordmarkGeometry.gap + WordmarkGeometry.ringOuter) * wordC, y: bigCentre.y)

        // The mark's state: big and central through the throw and the chalk; then into the name's last
        // slot, taking the letters' weight — and home before the first letter is struck beside it.
        let pMove = CGFloat(Easing.resolve(Easing.unit(timeline.word.progress(at: t) / LaunchTimeline.markHomeBy)))
        let q = CGFloat(Easing.unit(Double((pMove - 0.5) / 0.5)))
        let geo = MarkGeometry.mix(MarkGeometry(unit: big.unit + (wordC - big.unit) * pMove), MarkGeometry(unit: wordC, ratios: .wordmark), q)
        let centre = lerp(bigCentre, oCentre, pMove)
        let landed = big.onAxis(bigCentre, big.tip)
        let L = big.tipToTip

        // The wall, coming: the throw is aimed at the spot the point will enter — between the mark's
        // centre and that spot, because the pool is far wider than a dart — and once the point is in, the
        // light that lit the spot becomes the light the chalk is drawn in, sliding back to the ring.
        let off = animated ? Throw.targetOffset(tau) : CGVector(dx: 0, dy: 0)
        let aim = lerp(lerp(bigCentre, landed, 0.45), centre, animated ? CGFloat(Easing.resolve(Easing.unit(Double(pRing) / 0.7))) : 1)
        let lightC = CGPoint(x: aim.x + off.dx * L, y: aim.y + off.dy * L)
        let scale = animated ? Throw.targetScale(tau) : 1
        let prevScale = animated ? Throw.targetScale(timeline.flight.progress(at: t - 2.0 / 60.0)) : 1
        let near = animated ? Throw.approach(tau) : 1
        let poolR = big.ringOuter * Tune.lightRadius * scale
        let wallFade = 1 - pRing            // the wall's light and dust give way to the chalk ring
        func beamHalf(_ y: CGFloat) -> CGFloat {
            poolR * (0.16 + 0.94 * CGFloat(pow(Easing.unit(Double((y - canvas.minY) / (lightC.y - canvas.minY))), 1.35)))
        }
        let beamLit = animated && wallFade > 0
        func inBeam(_ x: CGFloat, _ y: CGFloat) -> Bool { beamLit && abs(x - lightC.x) < beamHalf(y) && y < lightC.y + poolR * 0.4 }

        // The beam: a cone from a lamp above the frame, narrow at the lamp, opening onto the spot it lights.
        if beamLit {
            let strength = (0.55 + 0.45 * near) * pField * wallFade
            let yTop = canvas.minY - 40
            var beam = Path()
            beam.move(to: CGPoint(x: lightC.x - beamHalf(yTop), y: yTop))
            beam.addLine(to: CGPoint(x: lightC.x + beamHalf(yTop), y: yTop))
            beam.addLine(to: CGPoint(x: lightC.x + poolR * 1.15, y: lightC.y + poolR * 0.30))
            beam.addLine(to: CGPoint(x: lightC.x - poolR * 1.15, y: lightC.y + poolR * 0.30))
            beam.closeSubpath()
            let column = Gradient(stops: [.init(color: chalk.opacity(Tune.beamAlpha * 1.25 * strength), location: 0),
                                          .init(color: chalk.opacity(Tune.beamAlpha * 0.85 * strength), location: 0.5),
                                          .init(color: chalk.opacity(Tune.beamAlpha * 0.45 * strength), location: 1)])
            context.drawLayer { soft in
                soft.addFilter(.blur(radius: 16))
                soft.fill(beam, with: .linearGradient(column, startPoint: CGPoint(x: lightC.x, y: yTop), endPoint: CGPoint(x: lightC.x, y: lightC.y)))
            }
        }

        // The pool of light on the wall, breathing once at the strike, spent as the chalk takes its place.
        if animated && wallFade > 0 {
            let breath = (sinceImpact >= 0 && sinceImpact < 0.55) ? sin(Double.pi * sinceImpact / 0.55) : 0
            let strength = (0.55 + 0.45 * near) * pField * wallFade * (1 + 1.9 * breath)
            let r = poolR * (1 + 0.14 * CGFloat(breath))
            let light = Gradient(stops: [.init(color: chalk.opacity(0.055 * strength), location: 0),
                                         .init(color: ThroColor.throGreenDeep.opacity(0.50 * strength), location: 0.28),
                                         .init(color: ThroColor.throGreenDeep.opacity(0.30 * strength), location: 0.62),
                                         .init(color: ThroColor.throGreenDeep.opacity(0), location: 1)])
            context.fill(Path(ellipseIn: CGRect(x: lightC.x - r, y: lightC.y - r, width: 2 * r, height: 2 * r)),
                         with: .radialGradient(light, center: lightC, startRadius: 0, endRadius: r))
        }

        // The dust on the wall, through the wall's own perspective.
        if pField > 0 {
            drawDust(&context, in: canvas, centre: lightC, scale: scale, previousScale: prevScale, unit: L,
                     alpha: pField * Tune.dustAlpha * (0.45 + 0.55 * near) * (animated ? Double(wallFade) : 0.5),
                     colour: chalk, lit: inBeam)
        }

        // The ring, struck into being rather than drawn. The shock leaves the point on the frame of the
        // thud and is stretched along the dart's own line, so it reaches the mark's radius first where
        // the dart crosses it — exactly as the ring's segment begins — and last square to that. Where it
        // crosses, the chalk is set at full width on the frame it arrives, so the ring lights up from
        // the dart's line and races round both ways until two lit fronts merge. Nothing tapers, so there
        // is no pinch at 45° or 225° for the ring to break on.
        let toRing = timeline.ring.start - timeline.impact.start
        var shock = MarkGeometry.shockClears
        if animated {
            if sinceImpact <= 0 { shock = 0 }
            else if sinceImpact < toRing { shock = MarkGeometry.shockTouches * Easing.impact(sinceImpact / toRing) }
            else {
                shock = MarkGeometry.shockTouches
                    + (MarkGeometry.shockClears - MarkGeometry.shockTouches) * Double(pRing)
                    + Tune.shockRunOn * max(0, t - timeline.ring.end)
            }
        }
        let lit = MarkGeometry.litDegrees(shock: shock)
        let pulse = animated ? 1 + CGFloat(Easing.damped(sinceRing, amplitude: 0.035, hertz: 5.5, decay: 0.16)) : 1

        // The leading edge closes up as the two fronts come together, so the ring arrives whole rather
        // than popping from four soft ends to one hard band.
        let frontFade = 1 - Easing.unit((lit - 74) / 16)
        let front = min(lit, Tune.frontDegrees * frontFade)

        if lit > 0 {
            let rough = 0.055 * (1 - pMove)
            if lit >= 90 {
                context.fill(geo.ringShape(at: centre, radiusScale: pulse, roughness: rough), with: .color(chalk))
            } else {
                // Solid chalk behind, and a leading edge that falls off in STRENGTH over `front` degrees
                // — never in width. A width taper is exactly what pinched the old ring shut at 45° and
                // 225°, and nothing here may bring it back: every step below spans the ring from inner
                // to outer radius, so two fronts merging can only ever overlap.
                let solid = max(0, lit - front)
                if solid > 0 {
                    var behind = Path()
                    for angle in MarkGeometry.crossingAngles {
                        behind.addPath(geo.ringBand(at: centre, fromDegrees: angle - solid, sweepDegrees: 2 * solid,
                                                    taperDegrees: 0, radiusScale: pulse, roughness: rough))
                    }
                    context.fill(behind, with: .color(chalk))
                }
                if front > 0 {
                    for k in 0..<Tune.frontSteps {
                        let span = front / Double(Tune.frontSteps)
                        let a0 = solid + span * Double(k)
                        var edge = Path()
                        for angle in MarkGeometry.crossingAngles {
                            edge.addPath(geo.ringBand(at: centre, fromDegrees: angle + a0, sweepDegrees: span,
                                                      taperDegrees: 0, radiusScale: pulse, roughness: rough))
                            edge.addPath(geo.ringBand(at: centre, fromDegrees: angle - a0 - span, sweepDegrees: span,
                                                      taperDegrees: 0, radiusScale: pulse, roughness: rough))
                        }
                        context.fill(edge, with: .color(chalk.opacity(1 - 0.86 * Double(k) / Double(Tune.frontSteps))))
                    }
                }
            }

            // the chalk is hot where it has just been set, and cools behind the front
            if lit < 90 && animated {
                let hot = min(Tune.hotDegrees, max(1, front))
                var glowing = Path()
                for angle in MarkGeometry.crossingAngles {
                    glowing.addPath(geo.ringBand(at: centre, fromDegrees: angle + lit - hot, sweepDegrees: hot,
                                                 taperDegrees: 0, radiusScale: pulse, roughness: rough))
                    glowing.addPath(geo.ringBand(at: centre, fromDegrees: angle - lit, sweepDegrees: hot,
                                                 taperDegrees: 0, radiusScale: pulse, roughness: rough))
                }
                context.fill(glowing, with: .color(ThroColor.throChalkRaised.opacity(0.9 * frontFade)))

                let fronts = MarkGeometry.crossingAngles.flatMap { [$0 + lit, $0 - lit] }
                context.drawLayer { glow in
                    glow.addFilter(.blur(radius: geo.ringWidth * 0.26))
                    for a in fronts {
                        let c = geo.onRing(centre, degrees: a, radiusScale: pulse)
                        glow.fill(Path(ellipseIn: CGRect(x: c.x - geo.ringWidth * 0.26, y: c.y - geo.ringWidth * 0.26,
                                                         width: geo.ringWidth * 0.52, height: geo.ringWidth * 0.52)),
                                  with: .color(ThroColor.throChalkRaised.opacity(0.55)))
                    }
                }
                // and the dust the shock lifts off the board as it passes, thrown outward
                for (i, a) in fronts.enumerated() {
                    let phi = a * Double.pi / 180
                    puff(&context, at: geo.onRing(centre, degrees: a, radiusScale: pulse), since: 0.05,
                         count: 2, seed: 60 + i, life: 0.30,
                         direction: CGVector(dx: CGFloat(cos(phi)), dy: CGFloat(sin(phi))),
                         spread: 150, speed: 30 * geo.unit / 260, size: 0.7, colour: chalk)
                }
            }
        }

        // The shock itself, seen as what it throws: chalk off the board, flung outward from the point and
        // riding exactly the front that sets the ring, so the dust reaching the mark's radius on the
        // dart's line and the chalk lighting there are one event. It is dust rather than a drawn wave
        // because a stroked ring at these radii traces the dart's own barrel and reads as an outline
        // around it, which is a worse thing than no wave at all.
        if animated && shock > 0.02 && shock < MarkGeometry.shockClears * 1.5 {
            let age = shock / MarkGeometry.shockClears
            let alpha = Tune.shockAlpha * max(0, 1 - age * age * 0.72) * min(1, shock / 0.10)
            var rng = Grain(seed: 4177)
            let r0 = geo.ringCentreRadius * pulse
            for _ in 0..<Tune.shockMotes {
                let deg = 360 * Double(rng.next())
                let jitter = 1 + Tune.shockScatter * (Double(rng.next()) - 0.72)
                let reach = shock * MarkGeometry.shockReach(deg, at: shock) * jitter
                // only out where the shock is doing its work. Closer in it draws a fan of short
                // strokes against the barrel and reads as bristles on the dart rather than chalk off
                // the board — and there is nothing being made in there anyway.
                guard reach > Tune.shockInner else { continue }
                let phi = deg * .pi / 180
                let rr = r0 * CGFloat(reach)
                let head = CGPoint(x: centre.x + rr * CGFloat(cos(phi)), y: centre.y + rr * CGFloat(sin(phi)))
                let back = rr - max(geo.ringWidth * 0.95, rr * 0.20)
                let tail = CGPoint(x: centre.x + back * CGFloat(cos(phi)), y: centre.y + back * CGFloat(sin(phi)))
                var streak = Path()
                streak.move(to: tail); streak.addLine(to: head)
                let bright = alpha * (0.35 + 0.65 * Double(rng.next()))
                context.stroke(streak, with: .color(ThroColor.throChalkRaised.opacity(bright)),
                               style: StrokeStyle(lineWidth: max(0.5, geo.ringWidth * 0.10 * CGFloat(1 - 0.4 * age)),
                                                  lineCap: .round))
            }
        }

        // The ring closing is the beat the strike has been building to, so it lands as light: a flare
        // around the whole ring on the frame it becomes whole, gone in a sixth of a second. Without it
        // the ring simply stops arriving, which is the difference between a mark appearing and a mark
        // being made.
        if animated && sinceRing >= 0 && sinceRing < Tune.closeFlash {
            let q = 1 - sinceRing / Tune.closeFlash
            context.drawLayer { flare in
                flare.addFilter(.blur(radius: geo.ringWidth * CGFloat(0.35 + 0.9 * (1 - q))))
                flare.fill(geo.ringShape(at: centre, radiusScale: pulse),
                           with: .color(ThroColor.throChalkRaised.opacity(0.55 * q * q)))
            }
        }

        // The dart: one angle throughout. It crosses the frame as the camera's aim catches it, smeared by
        // its own speed; holds while the wall closes, bobbing once across its line and its flights
        // waggling; drives in at the strike, where the board gives and holds and the shaft and flights
        // whip while the tungsten does not; then folds into the bar as the mark becomes type.
        let morph = CGFloat(Easing.resolve(Easing.unit(Double(pMove) / 0.6)))
        let detailAlpha = 1 - Easing.unit(Double((pMove - 0.52) / 0.20))
        let barAlpha = Easing.unit(Double((pMove - 0.52) / 0.20))
        if barAlpha > 0 {
            context.fill(geo.bar(at: centre), with: .color(chalk.opacity(barAlpha)))
        }
        if tau > 0 && detailAlpha > 0 {
            let anatomy = DartAnatomy(length: geo.tipToTip)
            let heading = -Double.pi / 4
            let tipPoint: CGPoint
            if tau < 1 {
                let back = -Throw.travel(tau) * L
                let bob = Throw.bobPoints * CGFloat(Throw.bob(tau))
                let c = CGPoint(x: bigCentre.x - axis.dx * back - across.dx * bob, y: bigCentre.y - axis.dy * back - across.dy * bob)
                tipPoint = CGPoint(x: c.x + axis.dx * L / 2, y: c.y + axis.dy * L / 2)
            } else {
                tipPoint = geo.onAxis(centre, geo.tip)
            }
            var bendShaft = 0.0, bendFlights = 0.0, drive: CGFloat = 0
            if animated && tau > 0 && tau < 1 {     // the flights waggle in the air; the barrel's line never moves
                bendShaft = 1.1 * Double.pi / 180 * sin(2 * Double.pi * 3.1 * tau)
                bendFlights = 2.4 * Double.pi / 180 * sin(2 * Double.pi * 3.1 * tau - 0.8)
            }
            if animated && sinceImpact >= 0 {
                if sinceImpact < Tune.driveSeconds { drive = Tune.drive * L * CGFloat(sin(Double.pi * sinceImpact / Tune.driveSeconds)) }
                bendShaft = Easing.damped(sinceImpact, amplitude: 5.5 * Double.pi / 180, hertz: 8, decay: 0.22)
                bendFlights = Easing.damped(sinceImpact - 0.025, amplitude: 7 * Double.pi / 180, hertz: 8, decay: 0.22)
            }
            let parts = anatomy.parts(spin: 2 * Double.pi * Tune.rollTurns * tau, morph: morph)
            let fine = max(0.8, geo.unit * 0.004), groove = max(1.2, geo.unit * 0.007)
            // The dart at an alpha, offset along its own line; the shaft pivots where it meets the barrel and the
            // flights pivot again where they meet the shaft, a beat behind. `shaded` draws the material; a
            // `tint` draws the whole silhouette in one colour, which is what a shadow is.
            func dart(into base: GraphicsContext, alpha: Double, offset: CGFloat, shaded: Bool, tint: Color? = nil) {
                var d = base
                d.translateBy(x: tipPoint.x + axis.dx * (offset + drive), y: tipPoint.y + axis.dy * (offset + drive))
                d.rotate(by: .radians(heading))
                if let tint {
                    for path in [parts.farFlights, parts.shaft, parts.barrel, parts.point, parts.nearFlights] {
                        d.fill(path, with: .color(tint.opacity(alpha)))
                    }
                    return
                }
                var shaft = d
                shaft.translateBy(x: anatomy.barrelEnd, y: 0); shaft.rotate(by: .radians(bendShaft)); shaft.translateBy(x: -anatomy.barrelEnd, y: 0)
                var flights = shaft
                flights.translateBy(x: anatomy.shaftEnd, y: 0); flights.rotate(by: .radians(bendFlights)); flights.translateBy(x: -anatomy.shaftEnd, y: 0)
                // the far pair is the shaded side of an opaque flight, not a see-through one: the field's
                // deep green with chalk over it, which at full strength is exactly 0.54 chalk to 0.46 green
                flights.fill(parts.farFlights, with: .color(ThroColor.throGreenDeep.opacity(alpha)))
                flights.fill(parts.farFlights, with: .color(chalk.opacity(0.54 * alpha)))
                shaft.fill(parts.shaft, with: .color(chalk.opacity(0.9 * alpha)))
                shaft.fill(parts.collar, with: .color(ThroColor.throChalkHairline.opacity(alpha)))
                d.fill(parts.barrel, with: .color(chalk.opacity(alpha)))
                d.fill(parts.point, with: .color(chalk.opacity(alpha)))
                if shaded {
                    let solid = alpha * Double(1 - morph)
                    d.fill(parts.shade, with: .color(ThroColor.throChalkHairline.opacity(0.95 * solid)))
                    d.stroke(parts.highlight, with: .color(ThroColor.throChalkRaised.opacity(0.9 * solid)), style: StrokeStyle(lineWidth: fine, lineCap: .round))
                    d.stroke(parts.pointCore, with: .color(ThroColor.throChalkRaised.opacity(0.9 * solid)), style: StrokeStyle(lineWidth: fine, lineCap: .round))
                    d.stroke(parts.knurl, with: .color(ThroColor.throGreen.opacity(0.42 * solid)), lineWidth: max(0.7, geo.unit * 0.0035))
                    d.stroke(parts.grooves, with: .color(ThroColor.throInk.opacity(0.28 * solid)), lineWidth: groove)
                }
                flights.fill(parts.nearFlights, with: .color(chalk.opacity(0.97 * alpha)))
                if shaded {
                    flights.fill(parts.logo, with: .color(ThroColor.throGreen.opacity(0.38 * alpha * Double(parts.nearScale))))
                }
            }
            // once it is in the board the dart stands off it, and casts a shadow down and away from the light
            if animated && sinceImpact >= 0 {
                let lift = Easing.unit(sinceImpact / 0.05) * detailAlpha * Double(1 - pMove * 0.6)
                if lift > 0.01 {
                    context.drawLayer { shadow in
                        shadow.addFilter(.blur(radius: max(2, geo.unit * 0.014)))
                        shadow.translateBy(x: geo.unit * 0.022, y: geo.unit * 0.030)
                        dart(into: shadow, alpha: 0.26 * lift, offset: 0, shaded: false, tint: ThroColor.throInk)
                    }
                }
            }
            // the smear: the dart's own speed, drawn as the frames a shutter would have caught
            let smear = (animated && tau < 1) ? Throw.smear(tau) * L : 0
            if smear > 2 {
                for i in 1...7 {
                    let f = CGFloat(i) / 7
                    dart(into: context, alpha: 0.16 * Double(1 - f) * detailAlpha, offset: -smear * f, shaded: false)
                    dart(into: context, alpha: 0.06 * Double(1 - f) * detailAlpha, offset: smear * f * 0.45, shaded: false)
                }
            }
            let sharp = smear > 2 ? min(1, max(0.58, 1 - 0.42 * Double(smear / (0.45 * L)))) : 1
            dart(into: context, alpha: detailAlpha * sharp, offset: 0, shaded: true)
        }

        // The strike, where the point went in: the scuff it leaves on the board, a flash of the light on
        // the spot that is at its brightest on the frame of the thud, and chalk knocked off at once and
        // falling — dust with grit in it, not a firework, and not eased in a tenth of a second late.
        if animated && sinceImpact >= 0 && pMove < 1 {
            let scuff = Easing.unit(sinceImpact / 0.06) * Double(1 - pMove)
            if scuff > 0 {
                context.drawLayer { smudge in
                    smudge.addFilter(.blur(radius: 6))
                    smudge.translateBy(x: landed.x, y: landed.y)
                    smudge.rotate(by: .radians(-Double.pi / 4))
                    let mark = Path(ellipseIn: CGRect(x: -big.unit * 0.070, y: -big.unit * 0.038,
                                                      width: big.unit * 0.140, height: big.unit * 0.076))
                    smudge.fill(mark, with: .color(chalk.opacity(0.20 * scuff)))
                }
            }
        }
        if animated && sinceImpact >= 0 && sinceImpact < Tune.flashSeconds {
            let f = pow(1 - sinceImpact / Tune.flashSeconds, 2.2)
            let r = big.ringOuter * 2.2
            let flash = Gradient(stops: [.init(color: chalk.opacity(0.30 * f), location: 0),
                                         .init(color: chalk.opacity(0.09 * f), location: 0.45),
                                         .init(color: chalk.opacity(0), location: 1)])
            context.fill(Path(ellipseIn: CGRect(x: landed.x - r, y: landed.y - r, width: 2 * r, height: 2 * r)),
                         with: .radialGradient(flash, center: landed, startRadius: 0, endRadius: r))
        }
        if animated {
            cloud(&context, at: landed, since: sinceImpact, life: 0.45, radius: big.unit * 0.10, colour: chalk, alpha: 0.32)
            puff(&context, at: landed, since: sinceImpact, count: 18, seed: 3, life: 0.70,
                 direction: CGVector(dx: -axis.dx, dy: -axis.dy), spread: 170, speed: 230 * big.unit / 260, size: 0.75, colour: chalk)
            puff(&context, at: landed, since: sinceImpact, count: 9, seed: 11, life: 0.50,
                 direction: across, spread: 260, speed: 140 * big.unit / 260, size: 0.55, colour: ThroColor.throChalkHairline)
        }

        // The name, with the mark as its Ø: T, H and R are struck onto the board, a puff of chalk each;
        // the tagline tracks in beneath as the last letter sets, and this is the finished composition.
        if pWord > 0 {
            func stampAt(_ i: Int) -> Double { timeline.word.start + timeline.word.duration * LaunchTimeline.stampFractions[i] }
            func hit(_ i: Int) -> Double { animated ? Easing.unit((t - stampAt(i)) / Tune.stampSeconds) : 1 }
            func settle(_ i: Int) -> Double { animated ? Easing.unit((t - stampAt(i)) / Tune.settleSeconds) : 1 }
            let alphas = (0..<3).map { hit($0) }
            let scales = (0..<3).map { animated ? 1 + 0.26 * CGFloat(1 - Easing.set(settle($0))) : 1 }
            let centres = word(&context, capHeight: wordC, left: wordLeft, baseline: baseline, alphas: alphas, scales: scales, colour: chalk)
            if animated {
                for (i, c) in centres.enumerated() {
                    puff(&context, at: CGPoint(x: c.x, y: baseline), since: t - stampAt(i), count: 5, seed: 21 + i, life: 0.5,
                         direction: CGVector(dx: 0, dy: 1), spread: 170, speed: 44 * wordC / 84, size: 0.9, colour: chalk)
                }
            }
            let tagQ = animated ? Easing.unit((t - timeline.taglineAt) / Tune.taglineSeconds) : 1
            if tagQ > 0 {
                let ts = Self.taglineSize(context, width: size.width, capHeight: wordC)
                var tag = context.resolve(Text(Tune.tagline)
                    .font(.custom("Archivo-SemiBold", fixedSize: ts)).kerning(ts * (0.09 + 0.07 * (1 - tagQ))))
                tag.shading = .color(chalk.opacity(0.82 * tagQ))
                context.draw(tag, at: CGPoint(x: size.width / 2, y: baseline + 0.45 * wordC), anchor: .top)
            }
        }

        // The last of the chalk, hanging in the light and settling while the name is read, so the end of
        // the film is quiet rather than frozen.
        if animated && pHold > 0 {
            var rng = Grain(seed: 0x51ED_270B)
            for _ in 0..<9 {
                let x = size.width * (0.12 + 0.76 * rng.next())
                let y0 = size.height * (0.30 + 0.45 * rng.next())
                let v = 8 + 14 * rng.next(), phase = rng.next()
                let y = y0 + v * CGFloat(t - timeline.hold.start)
                let a = 0.10 * (1 - pHold) * Double(0.4 + 0.6 * phase)
                guard a > 0.002 else { continue }
                let r = 0.9 + 0.6 * phase
                let cx = x + 3 * CGFloat(sin(1.7 * t + 6 * Double(phase)))
                context.fill(Path(ellipseIn: CGRect(x: cx - r, y: y - r, width: 2 * r, height: 2 * r)), with: .color(chalk.opacity(a)))
            }
        }
    }

    /// A seventeenth of the name's cap height, but never wider than the screen will hold at the widest
    /// tracking the track-in reaches — so the line cannot run off the edge of a narrow phone.
    static func taglineSize(_ context: GraphicsContext, width: CGFloat, capHeight: CGFloat) -> CGFloat {
        let probe = context.resolve(Text(Tune.tagline).font(.custom("Archivo-SemiBold", fixedSize: 100)))
        let per = probe.measure(in: CGSize(width: 100_000, height: 10_000)).width / 100 + 0.16 * CGFloat(Tune.tagline.count)
        return min(0.17 * capHeight, 0.88 * width / per)
    }

    /// T, H, R at a cap height, each letter where it sits in the whole word so the pairs keep the face's
    /// kerning, each drawn at its own alpha and scaled about its own centre. Returns the letters' centres.
    private func word(_ context: inout GraphicsContext, capHeight C: CGFloat, left: CGFloat, baseline: CGFloat,
                      alphas: [Double], scales: [CGFloat], colour: Color) -> [CGPoint] {
        let fontSize = C / WordmarkGeometry.capHeightPerEm
        // fixedSize, not size: the wordmark's geometry is measured against the letters, so a Dynamic Type
        // scale applied to the letters alone would tear the composition apart.
        let font = Font.custom("Archivo-ExtraBold", fixedSize: fontSize)
        let box = CGSize(width: 10_000, height: 10_000)
        let letters = ["T", "H", "R"]
        var centres: [CGPoint] = []
        for (i, letter) in letters.enumerated() {
            var glyph = context.resolve(Text(letter).font(font))
            let upTo = context.resolve(Text(letters[...i].joined()).font(font)).measure(in: box).width
            let width = glyph.measure(in: box).width
            let cx = left + upTo - width / 2, cy = baseline - C / 2
            centres.append(CGPoint(x: cx, y: cy))
            guard alphas[i] > 0 else { continue }
            var g = context
            g.translateBy(x: cx, y: cy)
            g.scaleBy(x: scales[i], y: scales[i])
            glyph.shading = .color(colour.opacity(alphas[i]))
            g.draw(glyph, at: CGPoint(x: -width / 2, y: C / 2 - fontSize * WordmarkGeometry.ascenderPerEm), anchor: .topLeading)
        }
        return centres
    }

    /// A burst of chalk: `count` specks fanned `spread` degrees about `direction`, thrown, slowed by the
    /// air and pulled down, each drawn as a short streak along its own motion; gone after `life` seconds.
    /// The spread of speeds is wide on purpose — most of what a board gives up barely leaves it and a
    /// little of it flies, and that is the difference between chalk dust and a firework.
    private func puff(_ context: inout GraphicsContext, at origin: CGPoint, since: Double, count: Int, seed: Int, life: Double,
                      direction: CGVector, spread: Double, speed: CGFloat, size: CGFloat, colour: Color) {
        guard since >= 0, since < life else { return }
        let q = CGFloat(since), fade = 1 - since / life
        let base = atan2(Double(direction.dy), Double(direction.dx))
        var rng = Grain(seed: UInt32(truncatingIfNeeded: seed &* 7919 &+ 17))
        for _ in 0..<count {
            let a = base + (Double(rng.next()) - 0.5) * spread * .pi / 180
            let u = rng.next()
            let v = speed * (0.18 + 1.5 * u * u)
            let r = size * (0.6 + 1.1 * rng.next())
            func at(_ q: CGFloat) -> CGPoint {
                let travel = v * q * (1 - q * 0.45)
                return CGPoint(x: origin.x + CGFloat(cos(a)) * travel, y: origin.y + CGFloat(sin(a)) * travel + 300 * q * q)
            }
            var streak = Path()
            streak.move(to: at(max(0, q - 0.022)))
            streak.addLine(to: at(q))
            context.stroke(streak, with: .color(colour.opacity(0.75 * fade * fade)),
                           style: StrokeStyle(lineWidth: 2 * r * (0.4 + 0.6 * CGFloat(fade)), lineCap: .round))
        }
    }

    /// The soft body of a burst: a cloud off the board that swells and thins away.
    private func cloud(_ context: inout GraphicsContext, at origin: CGPoint, since: Double, life: Double,
                       radius: CGFloat, colour: Color, alpha: Double) {
        guard since >= 0, since < life else { return }
        let u = since / life
        let r = radius * CGFloat(0.25 + 1.5 * u)
        context.drawLayer { soft in
            soft.addFilter(.blur(radius: radius * 0.45))
            soft.fill(Path(ellipseIn: CGRect(x: origin.x - r, y: origin.y - r, width: 2 * r, height: 2 * r)),
                      with: .color(colour.opacity(alpha * pow(1 - u, 1.8))))
        }
    }

    /// The chalk dust on the wall, drawn through the wall's own perspective: every speck sits at a fixed
    /// place on the board, so as the board closes each one slides outward from the spot being aimed at and
    /// draws itself into a streak — which is what flying at a surface looks like, and what nothing else
    /// looks like. The moment the point lands the growth stops and the streaks collapse to specks: the
    /// world has stopped with it. Dust falls away from the lit spot, as light on a wall does, so the
    /// corners of the frame stay dark instead of filling with what would read as rain.
    private func drawDust(_ context: inout GraphicsContext, in rect: CGRect, centre: CGPoint, scale: CGFloat,
                          previousScale: CGFloat, unit L: CGFloat, alpha: Double, colour: Color, lit: (CGFloat, CGFloat) -> Bool) {
        let tiers = Self.dustTiers
        var streaks = [Path](repeating: Path(), count: 2 * tiers)
        var dots = [Path](repeating: Path(), count: 2 * tiers)
        for speck in Self.wallDust {
            let x = centre.x + speck.u * L * scale, y = centre.y + speck.v * L * scale
            guard x > rect.minX - 40, x < rect.maxX + 40, y > rect.minY - 40, y < rect.maxY + 40 else { continue }
            let px = centre.x + speck.u * L * previousScale, py = centre.y + speck.v * L * previousScale
            let dx = x - px, dy = y - py
            let slot = speck.tier + (lit(x, y) ? tiers : 0)
            if (dx * dx + dy * dy).squareRoot() > 1.2 {
                streaks[slot].move(to: CGPoint(x: px, y: py)); streaks[slot].addLine(to: CGPoint(x: x, y: y))
            } else {
                dots[slot].addEllipse(in: CGRect(x: x - speck.r, y: y - speck.r, width: 2 * speck.r, height: 2 * speck.r))
            }
        }
        let style = StrokeStyle(lineWidth: 1.6, lineCap: .round)
        for slot in 0..<(2 * tiers) {
            let a = alpha * Self.dustWeight(slot % tiers) * (slot >= tiers ? Tune.beamLift : 1)
            let shading = GraphicsContext.Shading.color(colour.opacity(min(1, a)))
            context.stroke(streaks[slot], with: shading, style: style)
            context.fill(dots[slot], with: shading)
        }
    }

    /// The face's measure: the width of THR per unit of cap height, and what the Ø adds after it.
    private func typeMetrics(_ context: GraphicsContext) -> (perCap: CGFloat, extra: CGFloat) {
        let probe = context.resolve(Text("THR").font(.custom("Archivo-ExtraBold", fixedSize: 100)))
        let width = probe.measure(in: CGSize(width: 10_000, height: 10_000)).width
        return (width / 100 / WordmarkGeometry.capHeightPerEm, WordmarkGeometry.tailPerCap)
    }
}

/// A small deterministic generator, so every speck is where it was on the last frame.
struct Grain {
    private var state: UInt32
    init(seed: UInt32) { state = seed }
    /// Uniform in 0..<1.
    mutating func next() -> CGFloat {
        state = state &* 1_664_525 &+ 1_013_904_223
        return CGFloat(state >> 8) / CGFloat(1 << 24)
    }
}
