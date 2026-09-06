import SwiftUI
import ThroTokens
import ThroDesign

// PD-007, third version, after the founder's second look ("better, but improve and upgrade it further;
// harshly critique it; no regressions"). The app opens on a throw. A faint chalk ring waits on the
// green as the target, so the eye has somewhere to be before anything moves. A real dart — needle,
// knurled barrel, shaft, flights — comes in from the lower left on a gentle arc that straightens onto
// the mark's axis, rolling at a steady rate, its streak stretching with its speed. Its point cuts the
// chalk ring twice, puffing chalk off it each time and leaving the ring lit where it was cut, and
// strikes: the frame shakes, the field breathes lighter, a shockwave leaves the point, dust flies, the
// dart squashes along its length for a few frames and its shaft and flights whip and settle while the
// barrel stays dead still. The lit cuts spread both ways round the ring until it is whole, glowing,
// with chalk grain, and it pulses once. Then the dart folds into the mark's bar — flights flat, every
// part to the bar's width, the shaft run on to the tail — as the mark shrinks and rises to its place;
// T, H, R rise beneath it one after another; the Ø's own ring draws itself as the big one did and its
// bar follows; the tagline tracks in; Home fades up. The first frame is the launch screen's flat green,
// so nothing jumps. Cold launch only; a tap skips; Reduce Motion shows the finished composition and
// fades, with nothing moving and nothing heard.

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
    public let resolve: Segment
    public let hold: Segment
    public let exit: Segment

    public var segments: [Segment] { [field, flight, impact, ring, resolve, hold, exit] }
    public var total: Double { exit.end }
    /// When the root begins the cross-fade to Home.
    public var finishAt: Double { exit.start }

    /// Field and target to 450 ms; the flight to 1350; the strike's beat to 1750; the ring to 2450;
    /// the resolve to 3350; the hold to 4200; the cross-fade to 4600.
    public static let standard = LaunchTimeline(cuts: [0, 0.45, 1.35, 1.75, 2.45, 3.35, 4.20, 4.60])
    /// Reduce Motion: the finished composition from the first frame, a moment to read it, the fade.
    public static let reduced = LaunchTimeline(cuts: [0, 0, 0, 0, 0, 0, 0.60, 0.90])

    /// Whether anything moves. False under Reduce Motion, where every effect is already at rest from
    /// the first frame: no flight, no strike, no dust, no pulse, no cue.
    public var isAnimated: Bool { flight.duration > 0 }

    /// Sound and haptic cues, by name and time: the whoosh with the flight, a light tick each time the
    /// point cuts the chalk ring, the thud and the heavy haptic at the strike, the chalk with the ring.
    /// None under Reduce Motion: no motion, nothing to score.
    public var cues: [LaunchCue] {
        guard isAnimated else { return [] }
        var cues = [LaunchCue(name: "whoosh", at: flight.start)]
        for s in FlightPath.nominalCuts {
            cues.append(LaunchCue(name: "tick", at: flight.start + Easing.flightTime(for: Double(s)) * flight.duration))
        }
        cues += [LaunchCue(name: "thud", at: impact.start),
                 LaunchCue(name: "haptic", at: impact.start),
                 LaunchCue(name: "chalk", at: ring.start)]
        return cues
    }

    init(cuts c: [Double]) {
        precondition(c.count == 8, "seven segments need eight cuts")
        let names = ["field", "flight", "impact", "ring", "resolve", "hold", "exit"]
        let s = (0..<7).map { Segment(name: names[$0], start: c[$0], end: c[$0 + 1]) }
        field = s[0]; flight = s[1]; impact = s[2]; ring = s[3]; resolve = s[4]; hold = s[5]; exit = s[6]
    }
}

public struct LaunchCue: Equatable, Sendable {
    public let name: String
    public let at: Double
}

/// The token layer's cubic-bezier easings, evaluated: `x` is time 0...1, the result progress 0...1.
public enum Easing {
    public static func cubicBezier(_ c: (CGFloat, CGFloat, CGFloat, CGFloat), _ x: Double) -> Double {
        let x = min(1, max(0, x))
        let (p1x, p1y, p2x, p2y) = (Double(c.0), Double(c.1), Double(c.2), Double(c.3))
        func bx(_ u: Double) -> Double { 3 * (1 - u) * (1 - u) * u * p1x + 3 * (1 - u) * u * u * p2x + u * u * u }
        func by(_ u: Double) -> Double { 3 * (1 - u) * (1 - u) * u * p1y + 3 * (1 - u) * u * u * p2y + u * u * u }
        func dbx(_ u: Double) -> Double { 3 * (1 - u) * (1 - u) * p1x + 6 * (1 - u) * u * (p2x - p1x) + 3 * u * u * (1 - p2x) }
        var u = x
        for _ in 0..<8 {
            let d = dbx(u)
            if abs(d) < 1e-6 { break }
            u = min(1, max(0, u - (bx(u) - x) / d))
        }
        return by(u)
    }
    public static func throwCurve(_ x: Double) -> Double { cubicBezier(ThroMotion.motionEasingThrow, x) }
    public static func impact(_ x: Double) -> Double { cubicBezier(ThroMotion.motionEasingImpact, x) }
    public static func resolve(_ x: Double) -> Double { cubicBezier(ThroMotion.motionEasingResolve, x) }
    public static func set(_ x: Double) -> Double { cubicBezier(ThroMotion.motionEasingSet, x) }
    /// The exit curve accelerates into its end — which is what a dart does into a board.
    public static func exit(_ x: Double) -> Double { cubicBezier(ThroMotion.motionEasingExit, x) }
    /// The flight: the exit curve with a third of it linear, so the dart is seen for the whole flight and
    /// still arrives at full speed.
    public static func flight(_ x: Double) -> Double { let x = min(1, max(0, x)); return 0.34 * x + 0.66 * exit(x) }
    /// The inverse of `flight`: the fraction of the flight's time at which the dart has covered `s` of
    /// its path. Found by bisection; the curve is monotone.
    public static func flightTime(for s: Double) -> Double {
        let s = min(1, max(0, s))
        var lo = 0.0, hi = 1.0
        for _ in 0..<40 {
            let mid = (lo + hi) / 2
            if flight(mid) < s { lo = mid } else { hi = mid }
        }
        return (lo + hi) / 2
    }

    /// A struck thing settling: a damped sine that starts at zero, in the units of `amplitude`.
    public static func damped(_ t: Double, amplitude: Double, hertz: Double, decay: Double) -> Double {
        guard t > 0 else { return 0 }
        return amplitude * exp(-t / decay) * sin(2 * .pi * hertz * t)
    }
}

/// The mark's proportions, measured against its frame (docs/design/brand/README.md): ring outer 0.364,
/// inner 0.250, dart half-width 0.040, tips 0.643, the axis at 45° lower-left to upper-right.
public struct MarkGeometry: Equatable, Sendable {
    public static let ringOuterRatio: CGFloat = 0.364
    public static let ringInnerRatio: CGFloat = 0.250
    public static let halfWidthRatio: CGFloat = 0.040
    public static let tipRatio: CGFloat = 0.643

    public let unit: CGFloat
    public init(unit: CGFloat) { self.unit = unit }
    public init(tipToTip span: CGFloat) { unit = span / (2 * MarkGeometry.tipRatio) }

    public var ringOuter: CGFloat { Self.ringOuterRatio * unit }
    public var ringInner: CGFloat { Self.ringInnerRatio * unit }
    public var ringCentreRadius: CGFloat { (ringOuter + ringInner) / 2 }
    public var ringWidth: CGFloat { ringOuter - ringInner }
    public var halfWidth: CGFloat { Self.halfWidthRatio * unit }
    public var tip: CGFloat { Self.tipRatio * unit }
    public var tipToTip: CGFloat { 2 * tip }

    /// The unit vector along the axis, lower-left to upper-right, in a y-down frame.
    public static let axis = CGVector(dx: CGFloat(0.5).squareRoot(), dy: -CGFloat(0.5).squareRoot())
    /// Where the dart's line meets the ring, as screen angles: it enters at the lower left and leaves
    /// at the upper right.
    public static let crossingAngles: [Double] = [135, 315]

    /// A point `d` along the axis from the centre, offset `v` across it.
    public func onAxis(_ c: CGPoint, _ d: CGFloat, _ v: CGFloat = 0) -> CGPoint {
        let k = CGFloat(0.5).squareRoot()
        return CGPoint(x: c.x + d * k - v * k, y: c.y - d * k - v * k)
    }

    /// The mark's own dart: the plain bar with a point at each end.
    public func bar(at c: CGPoint) -> Path {
        let L = tip, R = ringOuter, w = halfWidth
        var p = Path()
        p.move(to: onAxis(c, L)); p.addLine(to: onAxis(c, R, w)); p.addLine(to: onAxis(c, -R, w))
        p.addLine(to: onAxis(c, -L)); p.addLine(to: onAxis(c, -R, -w)); p.addLine(to: onAxis(c, R, -w))
        p.closeSubpath()
        return p
    }

    /// An arc as a polyline, from screen angle `from` sweeping `sweep` degrees clockwise on screen.
    /// Drawn point by point so that its direction is exactly what it says in every coordinate system.
    public static func arc(centre c: CGPoint, radius r: CGFloat, fromDegrees from: Double, sweepDegrees sweep: Double) -> Path {
        var p = Path()
        guard sweep > 0 else { return p }
        let steps = max(2, Int(sweep / 2))
        for i in 0...steps {
            let phi = (from + sweep * Double(i) / Double(steps)) * .pi / 180
            let pt = CGPoint(x: c.x + r * CGFloat(cos(phi)), y: c.y + r * CGFloat(sin(phi)))
            if i == 0 { p.move(to: pt) } else { p.addLine(to: pt) }
        }
        return p
    }

    /// The ring's centreline from screen angle `fromDegrees` sweeping `sweep` degrees clockwise on screen.
    public func ringArc(at c: CGPoint, fromDegrees from: Double, sweepDegrees sweep: Double, radiusScale s: CGFloat = 1) -> Path {
        Self.arc(centre: c, radius: ringCentreRadius * s, fromDegrees: from, sweepDegrees: sweep)
    }

    /// A stroke of chalk along the ring: a band of the ring's width from `fromDegrees` sweeping `sweep`
    /// degrees clockwise, thinning to a point over its last `taper` degrees (or its first, when the
    /// stroke's leading end is at its start), as chalk thins where the stick lifts. A closed shape.
    public func ringBand(at c: CGPoint, fromDegrees from: Double, sweepDegrees sweep: Double, taperDegrees taper: Double,
                         taperAtStart: Bool = false, radiusScale s: CGFloat = 1) -> Path {
        var p = Path()
        guard sweep > 0 else { return p }
        let r = ringCentreRadius * s, half = ringWidth / 2
        let steps = max(2, Int(sweep / 2))
        var outer: [CGPoint] = [], inner: [CGPoint] = []
        for i in 0...steps {
            let along = sweep * Double(i) / Double(steps)
            let toLeadingEnd = taperAtStart ? along : sweep - along
            let h: CGFloat = (taper > 0 && toLeadingEnd < taper) ? half * CGFloat(pow(toLeadingEnd / taper, 0.6)) : half
            let phi = (from + along) * .pi / 180
            let (cx, cy) = (CGFloat(cos(phi)), CGFloat(sin(phi)))
            outer.append(CGPoint(x: c.x + (r + h) * cx, y: c.y + (r + h) * cy))
            inner.append(CGPoint(x: c.x + (r - h) * cx, y: c.y + (r - h) * cy))
        }
        p.move(to: outer[0])
        for pt in outer.dropFirst() { p.addLine(to: pt) }
        for pt in inner.reversed() { p.addLine(to: pt) }
        p.closeSubpath()
        return p
    }

    /// The whole ring as one closed band.
    public func ringShape(at c: CGPoint, radiusScale s: CGFloat = 1) -> Path {
        ringBand(at: c, fromDegrees: 0, sweepDegrees: 360, taperDegrees: 0, radiusScale: s)
    }
}

/// The dart's path through the air: a quadratic curve from just off the lower-left corner that
/// straightens onto the mark's axis and ends where the point lands.
public struct FlightPath: Equatable, Sendable {
    public let start: CGPoint
    public let control: CGPoint
    public let end: CGPoint

    /// The point lands at `end` heading along `axis`. It starts 1.35 dart-lengths back along the axis
    /// and `drop` lower; the curve's control point sits 0.9 dart-lengths back on the axis itself.
    public init(end: CGPoint, axis: CGVector, tipToTip: CGFloat, drop: CGFloat) {
        self.end = end
        start = CGPoint(x: end.x - axis.dx * tipToTip * 1.35, y: end.y - axis.dy * tipToTip * 1.35 + drop)
        control = CGPoint(x: end.x - axis.dx * tipToTip * 0.9, y: end.y - axis.dy * tipToTip * 0.9)
    }

    /// The fractions of the path at which the point cuts the ring, for the nominal layout: a drop of
    /// 0.26 dart-lengths, which is what the phones this app targets give. The phone's own layout moves
    /// them by a few thousandths; the haptic ticks use these, the drawing uses its own.
    public static let nominalCuts: [CGFloat] = {
        let unit = 1 / (2 * MarkGeometry.tipRatio)
        let axis = MarkGeometry.axis
        let centre = CGPoint(x: -axis.dx * MarkGeometry.tipRatio * unit, y: -axis.dy * MarkGeometry.tipRatio * unit)
        let radius = (MarkGeometry.ringOuterRatio + MarkGeometry.ringInnerRatio) / 2 * unit
        return FlightPath(end: .zero, axis: axis, tipToTip: 1, drop: 0.26).crossings(centre: centre, radius: radius)
    }()

    public func point(_ s: CGFloat) -> CGPoint {
        let u = 1 - s
        return CGPoint(x: u * u * start.x + 2 * u * s * control.x + s * s * end.x,
                       y: u * u * start.y + 2 * u * s * control.y + s * s * end.y)
    }

    /// The unit tangent: the way the dart points.
    public func heading(_ s: CGFloat) -> CGVector {
        let dx = 2 * (1 - s) * (control.x - start.x) + 2 * s * (end.x - control.x)
        let dy = 2 * (1 - s) * (control.y - start.y) + 2 * s * (end.y - control.y)
        let len = max(0.001, (dx * dx + dy * dy).squareRoot())
        return CGVector(dx: dx / len, dy: dy / len)
    }

    /// Where the path crosses a circle, as fractions of the path in order: the point enters the circle,
    /// then leaves it. Sampled, then refined by bisection.
    public func crossings(centre: CGPoint, radius: CGFloat, samples: Int = 96) -> [CGFloat] {
        func outside(_ s: CGFloat) -> Bool {
            let p = point(s)
            return ((p.x - centre.x) * (p.x - centre.x) + (p.y - centre.y) * (p.y - centre.y)).squareRoot() > radius
        }
        var out: [CGFloat] = []
        var prev = outside(0)
        for i in 1...samples {
            let s = CGFloat(i) / CGFloat(samples)
            let now = outside(s)
            if now != prev {
                var lo = CGFloat(i - 1) / CGFloat(samples), hi = s
                for _ in 0..<14 {
                    let mid = (lo + hi) / 2
                    if outside(mid) == prev { lo = mid } else { hi = mid }
                }
                out.append((lo + hi) / 2)
            }
            prev = now
        }
        return out
    }
}

/// A dart as a dart: needle, knurled barrel, shaft, flights. Lengths are fractions of the whole, which
/// is the mark's bar tip to tip, so the landed dart lies exactly where the mark's bar will be.
public struct DartAnatomy: Equatable, Sendable {
    public static let needle: CGFloat = 0.28
    public static let barrel: CGFloat = 0.24
    public static let shaft: CGFloat = 0.20
    public static let flight: CGFloat = 0.28
    /// Half-widths as fractions of the whole length.
    public static let needleHalf: CGFloat = 0.010
    public static let barrelHalf: CGFloat = 0.036
    public static let shaftHalf: CGFloat = 0.012
    public static let flightHalf: CGFloat = 0.085
    /// The mark's bar half-width as a fraction of the dart's length: what every part's half-width
    /// becomes as the dart resolves into the bar.
    public static let barHalf: CGFloat = MarkGeometry.halfWidthRatio / (2 * MarkGeometry.tipRatio)

    /// The dart's length tip to tail.
    public let length: CGFloat
    public init(length: CGFloat) { self.length = length }

    /// Where each part ends, measured back from the point along the dart (negative x).
    public var needleEnd: CGFloat { -Self.needle * length }
    public var barrelEnd: CGFloat { needleEnd - Self.barrel * length }
    public var shaftEnd: CGFloat { barrelEnd - Self.shaft * length }
    public var tailEnd: CGFloat { shaftEnd - Self.flight * length }

    /// Paths in a frame where the dart points along +x with its point at the origin. `shade` is the
    /// shadow side of the barrel and shaft, for a cylinder's roundness.
    public struct Parts {
        public var needle = Path()
        public var barrel = Path()
        public var knurl = Path()
        public var shaft = Path()
        public var shade = Path()
        public var nearFlights = Path()
        public var farFlights = Path()
    }

    /// `spin` is the roll about the dart's own axis, which foreshortens the flights. `morph`, 0...1,
    /// resolves the dart into the mark's bar: the flights fold flat, every half-width becomes the bar's,
    /// and the shaft runs on to the tail and tapers to the bar's point.
    public func parts(spin: Double, morph: CGFloat = 0) -> Parts {
        let m = min(1, max(0, morph))
        func mix(_ a: CGFloat, _ b: CGFloat) -> CGFloat { a + (b - a) * m }
        let L = length
        let nEnd = needleEnd, bEnd = barrelEnd, sEnd = shaftEnd, fEnd = tailEnd
        var parts = Parts()
        // needle: a point tapering back to the barrel
        let nh = mix(Self.needleHalf, Self.barHalf) * L
        parts.needle.move(to: CGPoint(x: 0, y: 0))
        parts.needle.addLine(to: CGPoint(x: nEnd, y: -nh))
        parts.needle.addLine(to: CGPoint(x: nEnd, y: nh))
        parts.needle.closeSubpath()
        // barrel: a capsule
        let bh = mix(Self.barrelHalf, Self.barHalf) * L
        parts.barrel.addRoundedRect(in: CGRect(x: bEnd, y: -bh, width: nEnd - bEnd, height: 2 * bh), cornerSize: CGSize(width: bh, height: bh))
        // knurl: three grooves across the barrel
        for i in 1...3 {
            let x = bEnd + (nEnd - bEnd) * CGFloat(i) / 4
            parts.knurl.move(to: CGPoint(x: x, y: -bh * 0.8)); parts.knurl.addLine(to: CGPoint(x: x, y: bh * 0.8))
        }
        // shaft: a rod at rest; resolving, it runs on to the tail and tapers to the bar's point
        let sh = mix(Self.shaftHalf, Self.barHalf) * L
        let tail = mix(sEnd, fEnd)
        let tailHalf = sh * (1 - m)
        parts.shaft.move(to: CGPoint(x: bEnd, y: -sh))
        parts.shaft.addLine(to: CGPoint(x: tail, y: -tailHalf))
        parts.shaft.addLine(to: CGPoint(x: tail, y: tailHalf))
        parts.shaft.addLine(to: CGPoint(x: bEnd, y: sh))
        parts.shaft.closeSubpath()
        // shade: the lower half of the barrel and the shaft, for roundness; gone when the dart is the bar
        if m < 1 {
            parts.shade.addRoundedRect(in: CGRect(x: bEnd + bh * 0.5, y: bh * 0.25, width: nEnd - bEnd - bh, height: bh * 0.55),
                                       cornerSize: CGSize(width: bh * 0.27, height: bh * 0.27))
            parts.shade.addRect(CGRect(x: sEnd, y: sh * 0.2, width: bEnd - sEnd, height: sh * 0.6))
        }
        // flights: two pairs at right angles, seen edge-on to face-on as the dart rolls; folded flat by the morph
        let fh = Self.flightHalf * L
        func fins(_ scale: CGFloat) -> Path {
            var p = Path()
            guard scale > 0.02 else { return p }
            let h = fh * scale
            for sign in [CGFloat(1), CGFloat(-1)] {
                p.move(to: CGPoint(x: sEnd, y: sign * sh))
                p.addQuadCurve(to: CGPoint(x: fEnd + 0.12 * (sEnd - fEnd), y: sign * h), control: CGPoint(x: fEnd + 0.55 * (sEnd - fEnd), y: sign * h * 0.9))
                p.addLine(to: CGPoint(x: fEnd, y: sign * h * 0.55))
                p.addLine(to: CGPoint(x: fEnd, y: sign * sh))
                p.closeSubpath()
            }
            return p
        }
        parts.nearFlights = fins(CGFloat(abs(cos(spin))) * (1 - m))
        parts.farFlights = fins(CGFloat(abs(sin(spin))) * (1 - m))
        return parts
    }
}

/// The wordmark's Ø has the letters' weight: ring 0.53 / 0.30 of the cap height, dart half-width 0.067,
/// tips 0.95, 0.10 of the cap height after the R (docs/design/brand/render_wordmark.py).
public enum WordmarkGeometry {
    public static let ringOuter: CGFloat = 0.53
    public static let ringInner: CGFloat = 0.30
    public static let halfWidth: CGFloat = 0.067
    public static let tip: CGFloat = 0.95
    public static let gap: CGFloat = 0.10
    /// Archivo ExtraBold's vertical metrics, from the face's own tables.
    public static let capHeightPerEm: CGFloat = 687.0 / 1000.0
    public static let ascenderPerEm: CGFloat = 878.0 / 1000.0
    public static let descenderPerEm: CGFloat = 210.0 / 1000.0
}

/// The opening. Draws every frame from a Canvas as a pure function of time; scores it with the
/// soundtrack and a haptic; a tap finishes it early.
public struct LaunchSequenceView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage(OpeningPreferences.soundKey) private var soundOn: Bool = true
    @AppStorage(OpeningPreferences.hapticsKey) private var hapticsOn: Bool = true
    private let onFinished: () -> Void
    @State private var start = Date()
    @State private var finished = false
    @State private var soundtrack: LaunchSoundtrack? = nil

    public init(onFinished: @escaping () -> Void) { self.onFinished = onFinished }

    private var timeline: LaunchTimeline { reduceMotion ? .reduced : .standard }

    public var body: some View {
        let timeline = self.timeline
        TimelineView(.animation(minimumInterval: 1.0 / 60.0, paused: finished)) { context in
            LaunchFrame(t: context.date.timeIntervalSince(start), timeline: timeline)
        }
        .background(ThroColor.throGreen.ignoresSafeArea())
        .ignoresSafeArea()
        .contentShape(Rectangle())
        .onTapGesture { finish() }
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
            DispatchQueue.main.asyncAfter(deadline: .now() + timeline.finishAt) { finish() }
        }
    }

    private func finish() {
        guard !finished else { return }
        finished = true
        soundtrack?.stop()
        onFinished()
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
        static let ghostRingWidth: CGFloat = 0.30       // of the ring's width
        static let ghostRingAlpha = 0.22
        static let grainAlpha = 0.08
        static let scaleAtEntry: CGFloat = 0.55          // the dart's size where it enters, of its landed size
        static let rollTurns = 1.6                       // over the whole flight, at a steady rate
        static let streakLags: [Double] = [0.018, 0.036, 0.054]      // one, two, three frames behind
        static let streakAlphas: [Double] = [0.26, 0.16, 0.08]
        static let squashSeconds = 0.07
        static let squash: CGFloat = 0.035
        static let shakeSeconds = 0.22
        static let flareHalfSweep = 14.0                 // degrees lit either side of a cut before the bloom
    }

    private func draw(in context: inout GraphicsContext, size: CGSize) {
        let chalk = ThroColor.throChalk
        let animated = timeline.isAnimated
        let pField = timeline.field.progress(at: t)
        let flightTime = timeline.flight.progress(at: t)
        let pFlight = Easing.flight(flightTime)
        let pRing = Easing.resolve(timeline.ring.progress(at: t))
        let pResolve = Easing.resolve(timeline.resolve.progress(at: t))
        let sinceImpact = t - timeline.impact.start
        let sinceRing = t - timeline.ring.end
        let axis = MarkGeometry.axis
        let across = CGVector(dx: -axis.dy, dy: axis.dx)

        // The camera: the strike shakes the whole frame, mostly along the line of the throw, and it dies in a fifth of a second.
        if animated && sinceImpact >= 0 && sinceImpact < Tune.shakeSeconds {
            let along = CGFloat(Easing.damped(sinceImpact, amplitude: 4, hertz: 16, decay: 0.07))
            let side = CGFloat(Easing.damped(sinceImpact, amplitude: 1.5, hertz: 23, decay: 0.06))
            context.translateBy(x: axis.dx * along + across.dx * side, y: axis.dy * along + across.dy * side)
        }
        let canvas = CGRect(origin: .zero, size: size).insetBy(dx: -12, dy: -12)

        // The field: the launch screen's flat green on the first frame, then a vignette deepening the
        // edges and chalk dust settled on the board, both arriving with the target.
        let vignette = Gradient(colors: [ThroColor.throInk.opacity(0), ThroColor.throInk.opacity(0.38 * pField)])
        context.fill(Path(canvas),
                     with: .radialGradient(vignette, center: CGPoint(x: size.width / 2, y: size.height / 2),
                                           startRadius: min(size.width, size.height) * 0.3, endRadius: max(size.width, size.height) * 0.72))
        if pField > 0 {
            context.fill(grain(in: canvas), with: .color(chalk.opacity(Tune.grainAlpha * pField)))
        }

        // Where the mark is: large and central through the throw, then up to the Splash's place.
        let big = MarkGeometry(tipToTip: min(size.width * 0.84, 380))
        let small = MarkGeometry(tipToTip: 104)
        let (wordC, wordSize, wordWidth) = wordmark(context: context)
        let wordHeight = 2 * WordmarkGeometry.tip * wordC * CGFloat(0.5).squareRoot()
        let groupHeight = small.tipToTip + 28 + wordHeight + 20 + 16
        let groupTop = (size.height - groupHeight) / 2
        let bigCentre = CGPoint(x: size.width / 2, y: size.height * 0.44)
        let smallCentre = CGPoint(x: size.width / 2, y: groupTop + small.tipToTip / 2)
        let geo = MarkGeometry(unit: big.unit + (small.unit - big.unit) * CGFloat(pResolve))
        let centre = CGPoint(x: bigCentre.x + (smallCentre.x - bigCentre.x) * CGFloat(pResolve),
                             y: bigCentre.y + (smallCentre.y - bigCentre.y) * CGFloat(pResolve))
        let landed = geo.onAxis(centre, geo.tip)
        let path = FlightPath(end: landed, axis: axis, tipToTip: geo.tipToTip, drop: size.height * 0.10)
        // Where and when the point cuts the chalk ring, on the way in and on the way out.
        var cuts: [(at: CGPoint, when: Double)] = []
        if animated {
            for s in path.crossings(centre: centre, radius: geo.ringCentreRadius) {
                cuts.append((at: path.point(s), when: timeline.flight.start + Easing.flightTime(for: Double(s)) * timeline.flight.duration))
            }
        }

        // The target: a faint chalk ring, there before the throw so the eye has somewhere to be.
        if animated && pRing < 1 {
            context.stroke(geo.ringArc(at: centre, fromDegrees: 0, sweepDegrees: 360),
                           with: .color(chalk.opacity(Tune.ghostRingAlpha * pField)),
                           style: StrokeStyle(lineWidth: geo.ringWidth * Tune.ghostRingWidth, lineCap: .round))
            // Where the point cut it, the thin chalk line lights at once; the bloom thickens from exactly here.
            for (i, angle) in MarkGeometry.crossingAngles.enumerated() where i < cuts.count && t >= cuts[i].when {
                let lit = min(1, (t - cuts[i].when) / 0.12)
                context.stroke(geo.ringArc(at: centre, fromDegrees: angle - Tune.flareHalfSweep, sweepDegrees: 2 * Tune.flareHalfSweep),
                               with: .color(chalk.opacity(lit)), style: StrokeStyle(lineWidth: geo.ringWidth * Tune.ghostRingWidth, lineCap: .butt))
            }
        }

        // Impact: a breath of lighter green behind the strike and a shockwave from the point.
        if animated && sinceImpact >= 0 && sinceImpact < 0.55 {
            let q = sinceImpact / 0.55
            let breath = sin(.pi * q) * 0.9
            let flash = Gradient(colors: [ThroColor.throGreenDeep.opacity(breath), ThroColor.throGreenDeep.opacity(0)])
            context.fill(Path(canvas), with: .radialGradient(flash, center: landed, startRadius: 0, endRadius: size.width * 0.75))
            let r = geo.ringOuter * (0.15 + 1.6 * CGFloat(Easing.impact(q)))
            context.stroke(Path(ellipseIn: CGRect(x: landed.x - r, y: landed.y - r, width: 2 * r, height: 2 * r)),
                           with: .color(chalk.opacity(0.35 * (1 - q))), lineWidth: 2.5 * (1 - CGFloat(q)) + 0.5)
        }

        // The ring: from each cut, two strokes of chalk run both ways round the ring, thinning to a point
        // at their leading ends, until the four meet and the ring is whole; it glows while it blooms and
        // pulses once as it closes.
        if pRing > 0 {
            let pulse = animated ? 1 + CGFloat(Easing.damped(sinceRing, amplitude: 0.035, hertz: 5.5, decay: 0.16)) : 1
            var ring = Path()
            if pRing < 1 {
                let half = 90 * pRing, taper = 30 * (1 - pRing), overlap = 1.5
                for angle in MarkGeometry.crossingAngles {
                    ring.addPath(geo.ringBand(at: centre, fromDegrees: angle - overlap, sweepDegrees: half + overlap, taperDegrees: taper, radiusScale: pulse))
                    ring.addPath(geo.ringBand(at: centre, fromDegrees: angle - half, sweepDegrees: half + overlap, taperDegrees: taper, taperAtStart: true, radiusScale: pulse))
                }
            } else {
                ring = geo.ringShape(at: centre, radiusScale: pulse)
            }
            // the glow is the bloom's; it fades as the mark settles, so the finished mark is crisp
            if pResolve < 1 {
                context.drawLayer { glow in
                    glow.addFilter(.blur(radius: geo.ringWidth * 0.55))
                    glow.fill(ring, with: .color(chalk.opacity(0.32 * (1 - pResolve))))
                    glow.stroke(ring, with: .color(chalk.opacity(0.32 * (1 - pResolve))), lineWidth: geo.ringWidth * 0.5)
                }
            }
            context.fill(ring, with: .color(chalk))
        }

        // The dart. In flight it comes in on the arc, grows as it closes, rolls at a steady rate, and streaks
        // in proportion to its speed. At the strike it squashes for a few frames and its shaft and flights
        // whip and settle while the barrel stays dead still. Resolving, it folds into the bar.
        let morph = CGFloat(Easing.resolve(min(1, max(0, pResolve / 0.6))))
        let detailAlpha = 1 - min(1, max(0, (pResolve - 0.45) / 0.3))
        let barAlpha = min(1, max(0, (pResolve - 0.35) / 0.3))
        if barAlpha > 0 {
            context.fill(geo.bar(at: centre), with: .color(chalk.opacity(barAlpha)))
        }
        if pFlight > 0 && detailAlpha > 0 {
            let anatomy = DartAnatomy(length: geo.tipToTip)
            func pose(_ s: CGFloat) -> (point: CGPoint, angle: Double, scale: CGFloat) {
                let p = s < 1 ? path.point(s) : landed
                let h = s < 1 ? path.heading(s) : axis
                return (p, Double(atan2(h.dy, h.dx)), Tune.scaleAtEntry + (1 - Tune.scaleAtEntry) * s)
            }
            // streak: ghosts one, two and three frames behind in time — far apart at speed, bunched when
            // slow, and catching the dart up in the frames after it stops
            if animated {
                for (i, lag) in Tune.streakLags.enumerated() {
                    let ghostTime = timeline.flight.progress(at: t - lag)
                    let gs = CGFloat(Easing.flight(ghostTime))
                    guard gs > 0, gs < 1 else { continue }
                    let ghost = pose(gs)
                    var g = context
                    g.translateBy(x: ghost.point.x, y: ghost.point.y)
                    g.rotate(by: .radians(ghost.angle))
                    g.scaleBy(x: ghost.scale, y: ghost.scale)
                    let parts = anatomy.parts(spin: 2 * .pi * Tune.rollTurns * ghostTime)
                    let a = Tune.streakAlphas[i] * Double(pFlight)
                    g.fill(parts.barrel, with: .color(chalk.opacity(a)))
                    g.fill(parts.nearFlights, with: .color(chalk.opacity(a)))
                }
            }
            let here = pose(CGFloat(pFlight))
            var d = context
            d.translateBy(x: here.point.x, y: here.point.y)
            d.rotate(by: .radians(here.angle))
            d.scaleBy(x: here.scale, y: here.scale)
            var bendShaft = 0.0, bendFlights = 0.0
            if animated && sinceImpact >= 0 {
                if sinceImpact < Tune.squashSeconds {
                    let bump = CGFloat(sin(.pi * sinceImpact / Tune.squashSeconds))
                    d.scaleBy(x: 1 - Tune.squash * bump, y: 1)
                }
                bendShaft = Easing.damped(sinceImpact, amplitude: 5.5 * .pi / 180, hertz: 8, decay: 0.22)
                bendFlights = Easing.damped(sinceImpact - 0.025, amplitude: 4 * .pi / 180, hertz: 8, decay: 0.22)
            }
            let parts = anatomy.parts(spin: 2 * .pi * Tune.rollTurns * flightTime, morph: morph)
            // The shaft pivots where it meets the barrel; the flights pivot again where they meet the shaft, a beat behind.
            var shaft = d
            shaft.translateBy(x: anatomy.barrelEnd, y: 0); shaft.rotate(by: .radians(bendShaft)); shaft.translateBy(x: -anatomy.barrelEnd, y: 0)
            var flights = shaft
            flights.translateBy(x: anatomy.shaftEnd, y: 0); flights.rotate(by: .radians(bendFlights)); flights.translateBy(x: -anatomy.shaftEnd, y: 0)
            flights.fill(parts.farFlights, with: .color(chalk.opacity(0.55 * detailAlpha)))
            shaft.fill(parts.shaft, with: .color(chalk.opacity(0.85 * detailAlpha)))
            d.fill(parts.barrel, with: .color(chalk.opacity(detailAlpha)))
            d.fill(parts.needle, with: .color(chalk.opacity(detailAlpha)))
            let roundness = 0.30 * detailAlpha * Double(1 - morph)
            d.fill(parts.shade, with: .color(ThroColor.throGreen.opacity(roundness)))
            d.stroke(parts.knurl, with: .color(ThroColor.throGreen.opacity(0.45 * detailAlpha * Double(1 - morph))), lineWidth: max(1, geo.unit * 0.008))
            flights.fill(parts.nearFlights, with: .color(chalk.opacity(0.95 * detailAlpha)))
        }

        // Dust: chalk off the ring where the point cut it, sideways off the line of the throw; and off the
        // wall where the point struck, thrown forward and falling.
        if animated {
            for (i, cut) in cuts.enumerated() {
                for (j, side) in [across, CGVector(dx: -across.dx, dy: -across.dy)].enumerated() {
                    puff(&context, at: cut.at, since: t - cut.when, count: 3, seed: 11 + 2 * i + j, life: 0.6,
                         direction: side, spread: 70, speed: 55 * geo.unit / 260, size: 0.9, colour: chalk)
                }
            }
            puff(&context, at: landed, since: sinceImpact, count: 9, seed: 3, life: 0.9,
                 direction: axis, spread: 120, speed: 110 * geo.unit / 260, size: 1.2, colour: chalk)
        }

        // The name: T, H, R rise into place one after another; the Ø's ring draws itself and its bar
        // follows; then the tagline.
        if pResolve > 0.5 {
            let wordTop = groupTop + small.tipToTip + 28
            let left = (size.width - wordWidth) / 2
            let fontSize = wordC / WordmarkGeometry.capHeightPerEm
            let baseline = wordTop + wordHeight / 2 + wordC / 2
            let textTop = baseline - fontSize * WordmarkGeometry.ascenderPerEm
            let font = Font.custom("Archivo-ExtraBold", size: fontSize)
            let box = CGSize(width: 10_000, height: 10_000)
            let word = ["T", "H", "R"]
            for (i, letter) in word.enumerated() {
                let q = min(1, max(0, (pResolve - (0.5 + 0.1 * Double(i))) / 0.25))
                let rise = CGFloat(1 - Easing.set(q)) * 16
                var glyph = context.resolve(Text(letter).font(font))
                // The letter sits where it sits in the whole word, so each pair keeps the face's kerning:
                // its origin is the width of the word up to and including it, less its own width.
                let upTo = context.resolve(Text(word[...i].joined()).font(font)).measure(in: box).width
                let x = left + upTo - glyph.measure(in: box).width
                glyph.shading = .color(chalk.opacity(q))
                context.draw(glyph, at: CGPoint(x: x, y: textTop + rise), anchor: .topLeading)
            }
            let oQ = min(1, max(0, (pResolve - 0.7) / 0.25))
            let oCentre = CGPoint(x: left + wordSize.width + WordmarkGeometry.gap * wordC + WordmarkGeometry.ringOuter * wordC,
                                  y: baseline - wordC / 2)
            let ro = WordmarkGeometry.ringOuter * wordC, ri = WordmarkGeometry.ringInner * wordC
            if oQ > 0 {
                // the Ø's ring draws itself from the top, clockwise, as the big ring bloomed
                let oRing = MarkGeometry.arc(centre: oCentre, radius: (ro + ri) / 2, fromDegrees: -90, sweepDegrees: 360 * Easing.set(oQ))
                context.stroke(oRing, with: .color(chalk), style: StrokeStyle(lineWidth: ro - ri, lineCap: .round))
            }
            let oBar = min(1, max(0, (oQ - 0.55) / 0.45))
            if oBar > 0 {
                let k = CGFloat(0.5).squareRoot()
                let L = WordmarkGeometry.tip * wordC, w = WordmarkGeometry.halfWidth * wordC
                let local: [(CGFloat, CGFloat)] = [(L, 0), (ro, w), (-ro, w), (-L, 0), (-ro, -w), (ro, -w)]
                var dart = Path()
                for (i, (u, v)) in local.enumerated() {
                    let pt = CGPoint(x: oCentre.x + u * k - v * k, y: oCentre.y - u * k - v * k)
                    if i == 0 { dart.move(to: pt) } else { dart.addLine(to: pt) }
                }
                dart.closeSubpath()
                context.fill(dart, with: .color(chalk.opacity(oBar)))
            }
            let tagQ = min(1, max(0, (pResolve - 0.85) / 0.15))
            if tagQ > 0 {
                var tag = context.resolve(Text("FROM THE PUB BOARD TO THE WORLD STAGE")
                    .font(.custom("Archivo-SemiBold", size: 13)).kerning(13 * (0.09 + 0.07 * (1 - tagQ))))
                tag.shading = .color(chalk.opacity(0.72 * tagQ))
                context.draw(tag, at: CGPoint(x: size.width / 2, y: wordTop + wordHeight + 20), anchor: .top)
            }
        }
    }

    /// A puff of chalk: `count` specks fanned `spread` degrees about `direction`, thrown, slowed by the
    /// air and pulled down, each drawn as a short streak along its own motion; gone after `life` seconds.
    private func puff(_ context: inout GraphicsContext, at origin: CGPoint, since: Double, count: Int, seed: Int, life: Double,
                      direction: CGVector, spread: Double, speed: CGFloat, size: CGFloat, colour: Color) {
        guard since >= 0, since < life else { return }
        let q = CGFloat(since)
        let base = atan2(Double(direction.dy), Double(direction.dx))
        var rng = Grain(seed: UInt32(truncatingIfNeeded: seed &* 7919 &+ 17))
        for _ in 0..<count {
            let a = base + (Double(rng.next()) - 0.5) * spread * .pi / 180
            let v = speed * (0.6 + 0.8 * rng.next())
            let r = size * (0.7 + 0.8 * rng.next())
            func at(_ q: CGFloat) -> CGPoint {
                let travel = v * q * (1 - q * 0.35)
                return CGPoint(x: origin.x + CGFloat(cos(a)) * travel, y: origin.y + CGFloat(sin(a)) * travel + 260 * q * q)
            }
            var streak = Path()
            streak.move(to: at(max(0, q - 0.03)))
            streak.addLine(to: at(q))
            context.stroke(streak, with: .color(colour.opacity(0.85 * (1 - since / life))), style: StrokeStyle(lineWidth: 2 * r, lineCap: .round))
        }
    }

    /// Chalk dust settled on the board: a fixed scatter of faint specks, the same on every frame.
    private func grain(in rect: CGRect) -> Path {
        var p = Path()
        var rng = Grain(seed: 0x9E37_79B9)
        let count = min(600, Int(rect.width * rect.height / 900))
        for _ in 0..<count {
            let x = rect.minX + rect.width * rng.next(), y = rect.minY + rect.height * rng.next()
            let r = 0.55 + 0.55 * rng.next()
            p.addEllipse(in: CGRect(x: x - r, y: y - r, width: 2 * r, height: 2 * r))
        }
        return p
    }

    /// The cap height that makes the wordmark 150 points wide, with the measured width of THR at that size.
    private func wordmark(context: GraphicsContext) -> (capHeight: CGFloat, thrSize: CGSize, width: CGFloat) {
        let probe = context.resolve(Text("THR").font(.custom("Archivo-ExtraBold", size: 100)))
        let probeSize = probe.measure(in: CGSize(width: 10_000, height: 10_000))
        let perCap = probeSize.width / 100 / WordmarkGeometry.capHeightPerEm
        let extra = WordmarkGeometry.gap + WordmarkGeometry.ringOuter + WordmarkGeometry.tip * CGFloat(0.5).squareRoot()
        let cap = 150 / (perCap + extra)
        return (cap, CGSize(width: perCap * cap, height: probeSize.height / 100 * cap / WordmarkGeometry.capHeightPerEm), 150)
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
