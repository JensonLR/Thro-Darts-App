import SwiftUI
import ThroTokens
import ThroDesign

// PD-007, fifth version, after the founder's fourth look: "The angle needs to be consistent throughout for
// darts flight path it looks awkward how it changes angle mid flight in an unnatural direction. It's much
// better though, let's upgrade & improve it even more to be as engaging & utterly beautiful as possible
// including the design of the dart & every other detail too." The opening is a tracking shot. The dart
// flies at the mark's angle from the first frame to the strike — no roll, no pitch. The camera catches it
// mid-flight: it resolves out of a motion smear along its own line, holds in the middle of the frame in
// profile — a real dart: a fine point, a tapered tungsten barrel with grip rings and grooves, a collar, a
// slim shaft, standard flights carrying the mark — rolling at a steady rate, bobbing once, drifting forward
// into the strike, while the wall comes to it: a stage light from above onto where the dart is going,
// with the chalk dust streaming past and lit in its beam, growing as an approaching thing does. Then the
// world stops dead: thud, the heavy haptic, the light breathing, the frame shaking, a burst of dust, the
// dart squashing for a few frames and its flights whipping while the barrel stays still. From the strike,
// four strokes of chalk run round the light until the ring is whole and the light is spent. Then the mark
// becomes the name: it shrinks and slides into the last slot of THRØ while T, H, R stamp in beside it,
// and its ring takes the letters' weight; the tagline tracks in beneath; Home fades up. The first frame is
// the launch screen's flat green. Cold launch only; a tap skips; Reduce Motion shows the name, still.

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

    /// The field and the far light to 400 ms; the flight to 1600; the strike's beat to 2000; the ring to
    /// 2550; the word to 3400; the hold, with the tagline, to 4300; the cross-fade to 4700.
    public static let standard = LaunchTimeline(cuts: [0, 0.40, 1.60, 2.00, 2.55, 3.40, 4.30, 4.70])
    /// Reduce Motion: the finished composition from the first frame, a moment to read it, the fade.
    public static let reduced = LaunchTimeline(cuts: [0, 0, 0, 0, 0, 0, 0.60, 0.90])
    /// When T, H and R stamp in, as fractions of the word segment.
    public static let stampFractions: [Double] = [0.30, 0.45, 0.60]

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
    /// The exit curve accelerates into its end.
    public static func exit(_ x: Double) -> Double { cubicBezier(ThroMotion.motionEasingExit, x) }
    /// 0...1 clamped.
    public static func unit(_ x: Double) -> Double { min(1, max(0, x)) }

    /// A struck thing settling: a damped sine that starts at zero, in the units of `amplitude`.
    public static func damped(_ t: Double, amplitude: Double, hertz: Double, decay: Double) -> Double {
        guard t > 0 else { return 0 }
        return amplitude * exp(-t / decay) * sin(2 * .pi * hertz * t)
    }
}

/// The mark's proportions against its frame, measured from the founder's artwork
/// (docs/design/brand/README.md): ring outer 0.364, inner 0.250, dart half-width 0.040, tips 0.643, the
/// axis at 45° lower-left to upper-right. The wordmark's Ø has the letters' weight instead, against the
/// cap height: ring 0.53 / 0.30, half-width 0.067, tips 0.95 (docs/design/brand/render_wordmark.py). The
/// mark becomes the Ø by mixing one set of ratios into the other.
public struct MarkGeometry: Equatable, Sendable {
    public struct Ratios: Equatable, Sendable {
        public let ringOuter: CGFloat
        public let ringInner: CGFloat
        public let halfWidth: CGFloat
        public let tip: CGFloat
        public static let mark = Ratios(ringOuter: 0.364, ringInner: 0.250, halfWidth: 0.040, tip: 0.643)
        public static let wordmark = Ratios(ringOuter: 0.53, ringInner: 0.30, halfWidth: 0.067, tip: 0.95)
    }
    public static let ringOuterRatio = Ratios.mark.ringOuter
    public static let ringInnerRatio = Ratios.mark.ringInner
    public static let halfWidthRatio = Ratios.mark.halfWidth
    public static let tipRatio = Ratios.mark.tip

    public let unit: CGFloat
    public let ratios: Ratios
    public init(unit: CGFloat, ratios: Ratios = .mark) { self.unit = unit; self.ratios = ratios }
    public init(tipToTip span: CGFloat, ratios: Ratios = .mark) { unit = span / (2 * ratios.tip); self.ratios = ratios }

    /// Part way from one geometry to another, size and proportions together.
    public static func mix(_ a: MarkGeometry, _ b: MarkGeometry, _ t: CGFloat) -> MarkGeometry {
        let t = min(1, max(0, t))
        func m(_ x: CGFloat, _ y: CGFloat) -> CGFloat { x + (y - x) * t }
        return MarkGeometry(unit: m(a.unit, b.unit),
                            ratios: Ratios(ringOuter: m(a.ratios.ringOuter, b.ratios.ringOuter), ringInner: m(a.ratios.ringInner, b.ratios.ringInner),
                                           halfWidth: m(a.ratios.halfWidth, b.ratios.halfWidth), tip: m(a.ratios.tip, b.ratios.tip)))
    }

    public var ringOuter: CGFloat { ratios.ringOuter * unit }
    public var ringInner: CGFloat { ratios.ringInner * unit }
    public var ringCentreRadius: CGFloat { (ringOuter + ringInner) / 2 }
    public var ringWidth: CGFloat { ringOuter - ringInner }
    public var halfWidth: CGFloat { ratios.halfWidth * unit }
    public var tip: CGFloat { ratios.tip * unit }
    public var tipToTip: CGFloat { 2 * tip }

    /// The unit vector along the axis, lower-left to upper-right, in a y-down frame.
    public static let axis = CGVector(dx: CGFloat(0.5).squareRoot(), dy: -CGFloat(0.5).squareRoot())
    /// Where the dart's line meets the ring, as screen angles, lower left and upper right: the chalk
    /// strokes that form the ring start from the dart, both ways round.
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

/// The throw as the camera sees it, over the flight's time `tau` (0...1), in dart-lengths. The dart flies
/// at the mark's angle throughout. The camera catches it mid-flight — it resolves out of a motion smear
/// along its own line over the first quarter — then holds it mid-frame, bobbing once across its line and
/// drifting forward into the strike, while the wall comes to it: the light where the dart is going — far
/// and small — grows along a power curve, slow and then fast, as an approaching thing does, and stops dead.
public enum Throw {
    public static let approachStart = 0.25, approachPower = 2.4
    public static let farScale: CGFloat = 0.20
    /// Where the light waits, from the dart's centre, in dart-lengths.
    public static let farOffset = CGVector(dx: 0.22, dy: -0.36)
    public static let catchEnd = 0.25
    /// The smear's length when the camera first has the dart, in dart-lengths.
    public static let smearLength: CGFloat = 0.9
    /// How far behind its landed place the dart holds, in dart-lengths, closing as it arrives.
    public static let driftLength: CGFloat = 0.06
    public static let bobPoints: CGFloat = 14

    /// How far the wall has come, 0 far to 1 arrived: nothing until the dart has been caught, then a power
    /// curve, slow and then fast, which is how an approaching thing grows.
    public static func approach(_ tau: Double) -> Double {
        pow(Easing.unit((tau - approachStart) / (1 - approachStart)), approachPower)
    }
    /// The motion smear along the dart's line, in dart-lengths, as the camera catches up: gone by a quarter.
    public static func smear(_ tau: Double) -> CGFloat {
        smearLength * CGFloat(pow(1 - Easing.unit(tau / catchEnd), 3))
    }
    /// Where the dart is along its line relative to its landed place, in dart-lengths: a little behind,
    /// closing to nothing at the strike.
    public static func drift(_ tau: Double) -> CGFloat {
        let u = CGFloat(Easing.unit(tau))
        return -driftLength * (1 - u * u)
    }
    /// One rise and fall across the line of flight, 0...1...0.
    public static func bob(_ tau: Double) -> Double { sin(.pi * Easing.unit(tau)) }
    /// Where the light's centre is, from the dart's centre, in dart-lengths.
    public static func targetOffset(_ tau: Double) -> CGVector {
        let p = CGFloat(approach(tau))
        return CGVector(dx: farOffset.dx * (1 - p), dy: farOffset.dy * (1 - p))
    }
    /// How large the light is, of its size at the strike.
    public static func targetScale(_ tau: Double) -> CGFloat { farScale + (1 - farScale) * CGFloat(approach(tau)) }
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
    public static let shaftHalf: CGFloat = 0.011
    public static let collarHalf: CGFloat = 0.015
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
        let ch = mix(Self.collarHalf, Self.barHalf) * L, cl = 0.022 * L
        if m < 1 {
            parts.collar.addRoundedRect(in: CGRect(x: sEnd, y: -ch, width: cl, height: 2 * ch), cornerSize: CGSize(width: ch * 0.3, height: ch * 0.3))
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
                p.addCurve(to: CGPoint(x: fEnd + 0.13 * fl, y: sign * h),
                           control1: CGPoint(x: sEnd - 0.30 * fl, y: sign * h * 0.30),
                           control2: CGPoint(x: fEnd + 0.42 * fl, y: sign * h * 1.02))
                p.addQuadCurve(to: CGPoint(x: fEnd, y: sign * h * 0.84), control: CGPoint(x: fEnd + 0.015 * fl, y: sign * h))
                p.addLine(to: CGPoint(x: fEnd, y: sign * sh))
                p.closeSubpath()
            }
            return p
        }
        let nearScale = CGFloat(abs(cos(spin))) * (1 - m), farScale = CGFloat(abs(sin(spin))) * (1 - m)
        parts.nearFlights = fins(nearScale)
        parts.farFlights = fins(farScale)
        parts.nearScale = nearScale
        // the mark, small, on each near flight, as flights carry a maker's mark
        if nearScale > 0.35 && m < 0.05 {
            let logo = MarkGeometry(unit: fh * nearScale * 0.38)
            for sign in [CGFloat(1), CGFloat(-1)] {
                let c = CGPoint(x: fEnd + 0.42 * fl, y: sign * fh * nearScale * 0.56)
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
        static let grainAlpha = 0.08
        static let grainRun: CGFloat = 900               // how far the wall's dust streams past over the approach, points
        static let lightRadius: CGFloat = 1.45           // the pool of light, of the ring's outer radius
        static let beamAlpha = 0.05                      // the stage light's beam, at its brightest
        static let beamLift = 2.4                        // how much brighter the dust is inside the beam
        static let rollTurns = 1.6                       // over the whole flight, at a steady rate
        static let squashSeconds = 0.07
        static let squash: CGFloat = 0.035
        static let shakeSeconds = 0.22
        static let stampSeconds = 0.18
        static let taglineSeconds = 0.35                 // into the hold
    }

    private func draw(in context: inout GraphicsContext, size: CGSize) {
        let chalk = ThroColor.throChalk
        let animated = timeline.isAnimated
        let pField = timeline.field.progress(at: t)
        let tau = timeline.flight.progress(at: t)
        let pRing = Easing.resolve(timeline.ring.progress(at: t))
        let pWord = Easing.resolve(timeline.word.progress(at: t))
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

        // The field, in screen space: the launch screen's flat green on the first frame, then a vignette.
        let vignette = Gradient(colors: [ThroColor.throInk.opacity(0), ThroColor.throInk.opacity(0.38 * pField)])
        context.fill(Path(canvas),
                     with: .radialGradient(vignette, center: CGPoint(x: size.width / 2, y: size.height / 2),
                                           startRadius: min(size.width, size.height) * 0.3, endRadius: max(size.width, size.height) * 0.72))

        // Layout: the mark large and central through the throw; the name across the width with the mark as
        // its Ø, which is also the finished composition; the tagline beneath it.
        let (perCap, extra) = typeMetrics(context)
        let bigTip = min(size.width * 0.84, 380)
        let big = MarkGeometry(tipToTip: bigTip)
        let bigCentre = CGPoint(x: size.width / 2, y: size.height * 0.44)
        let wordC = bigTip / (perCap + extra)
        let wordThr = perCap * wordC
        let wordLeft = (size.width - bigTip) / 2
        let baseline = bigCentre.y + wordC / 2
        let oCentre = CGPoint(x: wordLeft + wordThr + (WordmarkGeometry.gap + WordmarkGeometry.ringOuter) * wordC, y: bigCentre.y)
        func lerp(_ a: CGPoint, _ b: CGPoint, _ s: CGFloat) -> CGPoint { CGPoint(x: a.x + (b.x - a.x) * s, y: a.y + (b.y - a.y) * s) }

        // The mark's state: big and central through the throw and the bloom; then into the name's last
        // slot, taking the letters' weight.
        let q = CGFloat(Easing.unit((pWord - 0.5) / 0.5))
        let geo = MarkGeometry.mix(MarkGeometry(unit: big.unit + (wordC - big.unit) * CGFloat(pWord)), MarkGeometry(unit: wordC, ratios: .wordmark), q)
        let centre = lerp(bigCentre, oCentre, CGFloat(pWord))
        let landed = big.onAxis(bigCentre, big.tip)
        let L = big.tipToTip

        // The throw: where the light is on its way in, and how big.
        let p = animated ? Throw.approach(tau) : 1
        let targetOff = animated ? Throw.targetOffset(tau) : CGVector(dx: 0, dy: 0)
        let lightC = CGPoint(x: bigCentre.x + targetOff.dx * L, y: bigCentre.y + targetOff.dy * L)
        let lightS = animated ? Throw.targetScale(tau) : 1

        let world = canvas
        // The stage light's beam, from above onto where the dart is going: a soft column, and the dust is lit inside it.
        let poolR = big.ringOuter * Tune.lightRadius * lightS
        func beamHalf(_ y: CGFloat) -> CGFloat { poolR * (0.55 + 0.55 * CGFloat(Easing.unit(Double((y - world.minY) / (lightC.y - world.minY))))) }
        let beamLit = animated && pRing < 1
        func inBeam(_ x: CGFloat, _ y: CGFloat) -> Bool { beamLit && abs(x - lightC.x) < beamHalf(y) && y < lightC.y + poolR * 0.4 }

        // Chalk dust settled on the wall, streaming past while the camera flies, stopping dead with it.
        if pField > 0 {
            let run = Tune.grainRun * CGFloat(p)
            let before = Tune.grainRun * CGFloat(animated ? Throw.approach(timeline.flight.progress(at: t - 1.0 / 60.0)) : 1)
            let speed = max(0, (run - before) * 60)
            grain(&context, in: world, run: run, speed: speed, alpha: pField * (Tune.grainAlpha + 0.04 * Easing.unit(Double(speed) / 900)), colour: chalk, lit: inBeam)
        }
        if beamLit {
            let strength = (0.55 + 0.45 * p) * pField * (1 - pRing)
            let yTop = world.minY - 40
            var beam = Path()
            beam.move(to: CGPoint(x: lightC.x - beamHalf(yTop), y: yTop))
            beam.addLine(to: CGPoint(x: lightC.x + beamHalf(yTop), y: yTop))
            beam.addLine(to: CGPoint(x: lightC.x + poolR * 1.1, y: lightC.y + poolR * 0.3))
            beam.addLine(to: CGPoint(x: lightC.x - poolR * 1.1, y: lightC.y + poolR * 0.3))
            beam.closeSubpath()
            let column = Gradient(colors: [chalk.opacity(Tune.beamAlpha * 0.25 * strength), chalk.opacity(Tune.beamAlpha * strength)])
            context.drawLayer { soft in
                soft.addFilter(.blur(radius: 18))
                soft.fill(beam, with: .linearGradient(column, startPoint: CGPoint(x: lightC.x, y: yTop), endPoint: CGPoint(x: lightC.x, y: lightC.y)))
            }
        }

        // The light: a pool on the wall where the dart is going, far and small at first, growing as the
        // camera nears, breathing at the strike, spent as the chalk ring takes its place.
        if animated && pRing < 1 {
            let breath = (sinceImpact >= 0 && sinceImpact < 0.55) ? sin(.pi * sinceImpact / 0.55) : 0
            let strength = (0.55 + 0.45 * p) * pField * (1 - pRing) * (1 + 1.6 * breath)
            let r = big.ringOuter * Tune.lightRadius * lightS * (1 + 0.5 * CGFloat(breath))
            let light = Gradient(stops: [.init(color: chalk.opacity(0.10 * strength), location: 0),
                                         .init(color: ThroColor.throGreenDeep.opacity(0.55 * strength), location: 0.35),
                                         .init(color: ThroColor.throGreenDeep.opacity(0), location: 1)])
            context.fill(Path(ellipseIn: CGRect(x: lightC.x - r, y: lightC.y - r, width: 2 * r, height: 2 * r)),
                         with: .radialGradient(light, center: lightC, startRadius: 0, endRadius: r))
        }

        // The ring: from the strike, two strokes of chalk run both ways from each side of the dart until the
        // four meet and the ring is whole; it glows while it blooms and pulses once as it closes; the glow is
        // gone as the mark sets as type.
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
            if pWord < 1 {
                context.drawLayer { glow in
                    glow.addFilter(.blur(radius: geo.ringWidth * 0.55))
                    glow.fill(ring, with: .color(chalk.opacity(0.32 * (1 - pWord))))
                    glow.stroke(ring, with: .color(chalk.opacity(0.32 * (1 - pWord))), lineWidth: geo.ringWidth * 0.5)
                }
            }
            context.fill(ring, with: .color(chalk))
        }

        // The dart: at the mark's angle throughout. Caught mid-flight, it resolves out of a motion smear along
        // its own line; it holds mid-frame, rolling at a steady rate, bobbing once, drifting forward into the
        // strike; at the strike it squashes for a few frames and its shaft and flights whip while the barrel
        // stays dead still; then it folds into the bar as the mark becomes type.
        let morph = CGFloat(Easing.resolve(Easing.unit(pWord / 0.6)))
        let detailAlpha = 1 - Easing.unit((pWord - 0.45) / 0.3)
        let barAlpha = Easing.unit((pWord - 0.35) / 0.3)
        if barAlpha > 0 {
            context.fill(geo.bar(at: centre), with: .color(chalk.opacity(barAlpha)))
        }
        if tau > 0 && detailAlpha > 0 {
            let anatomy = DartAnatomy(length: geo.tipToTip)
            let heading = -Double.pi / 4
            let tipPoint: CGPoint
            if tau < 1 {
                let back = -Throw.drift(tau) * L
                let bob = Throw.bobPoints * CGFloat(Throw.bob(tau))
                let c = CGPoint(x: bigCentre.x - axis.dx * back - across.dx * bob, y: bigCentre.y - axis.dy * back - across.dy * bob)
                tipPoint = CGPoint(x: c.x + axis.dx * L / 2, y: c.y + axis.dy * L / 2)
            } else {
                tipPoint = geo.onAxis(centre, geo.tip)
            }
            var bendShaft = 0.0, bendFlights = 0.0
            var squash: CGFloat = 1
            if animated && sinceImpact >= 0 {
                if sinceImpact < Tune.squashSeconds { squash = 1 - Tune.squash * CGFloat(sin(.pi * sinceImpact / Tune.squashSeconds)) }
                bendShaft = Easing.damped(sinceImpact, amplitude: 5.5 * .pi / 180, hertz: 8, decay: 0.22)
                bendFlights = Easing.damped(sinceImpact - 0.025, amplitude: 4 * .pi / 180, hertz: 8, decay: 0.22)
            }
            let parts = anatomy.parts(spin: 2 * .pi * Tune.rollTurns * tau, morph: morph)
            let fine = max(0.8, geo.unit * 0.004), groove = max(1.2, geo.unit * 0.007)
            // The dart at an alpha, offset along its own line; the shaft pivots where it meets the barrel and the
            // flights pivot again where they meet the shaft, a beat behind. `shaded` draws the material.
            func dart(alpha: Double, offset: CGFloat, shaded: Bool) {
                var d = context
                d.translateBy(x: tipPoint.x + axis.dx * offset, y: tipPoint.y + axis.dy * offset)
                d.rotate(by: .radians(heading))
                d.scaleBy(x: squash, y: 1)
                var shaft = d
                shaft.translateBy(x: anatomy.barrelEnd, y: 0); shaft.rotate(by: .radians(bendShaft)); shaft.translateBy(x: -anatomy.barrelEnd, y: 0)
                var flights = shaft
                flights.translateBy(x: anatomy.shaftEnd, y: 0); flights.rotate(by: .radians(bendFlights)); flights.translateBy(x: -anatomy.shaftEnd, y: 0)
                flights.fill(parts.farFlights, with: .color(ThroColor.throChalkHairline.opacity(0.62 * alpha)))
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
            // the catch: as the camera catches up, the dart resolves out of a smear along its own line
            let smear = (animated && tau < 1) ? Throw.smear(tau) * L : 0
            if smear > 1 {
                for i in 1...6 {
                    let f = CGFloat(i) / 6
                    dart(alpha: 0.09 * Double(1 - f) * detailAlpha, offset: -smear * f, shaded: false)
                    dart(alpha: 0.05 * Double(1 - f) * detailAlpha, offset: smear * f * 0.6, shaded: false)
                }
            }
            let sharp = smear > 1 ? 0.45 + 0.55 * Double(1 - smear / (Throw.smearLength * L)) : 1
            dart(alpha: detailAlpha * sharp, offset: 0, shaded: true)
        }

        // Dust: a burst of chalk off the wall where the point struck, thrown forward and falling.
        if animated {
            puff(&context, at: landed, since: sinceImpact, count: 14, seed: 3, life: 0.9,
                 direction: axis, spread: 150, speed: 130 * big.unit / 260, size: 1.2, colour: chalk)
        }

        // The name, with the mark as its Ø: T, H, R stamp in beside it, a puff of chalk each; then the
        // tagline tracks in beneath, and this is the finished composition.
        if pWord > 0 {
            func stampAt(_ i: Int) -> Double { timeline.word.start + timeline.word.duration * LaunchTimeline.stampFractions[i] }
            func stampQ(_ i: Int) -> Double { animated ? Easing.unit((t - stampAt(i)) / Tune.stampSeconds) : 1 }
            let alphas = (0..<3).map { stampQ($0) }
            let scales = (0..<3).map { animated ? 1 + 0.3 * CGFloat(1 - Easing.set(stampQ($0))) : 1 }
            let centres = word(&context, capHeight: wordC, left: wordLeft, baseline: baseline, alphas: alphas, scales: scales, colour: chalk)
            if animated {
                for (i, c) in centres.enumerated() {
                    puff(&context, at: CGPoint(x: c.x, y: baseline), since: t - stampAt(i), count: 4, seed: 21 + i, life: 0.5,
                         direction: CGVector(dx: 0, dy: 1), spread: 170, speed: 40 * wordC / 84, size: 0.9, colour: chalk)
                }
            }
            let tagQ = animated ? Easing.unit((t - timeline.hold.start) / Tune.taglineSeconds) : 1
            if tagQ > 0 {
                var tag = context.resolve(Text("FROM THE PUB BOARD TO THE WORLD STAGE")
                    .font(.custom("Archivo-SemiBold", size: 13)).kerning(13 * (0.09 + 0.07 * (1 - tagQ))))
                tag.shading = .color(chalk.opacity(0.72 * tagQ))
                context.draw(tag, at: CGPoint(x: size.width / 2, y: baseline + 0.45 * wordC), anchor: .top)
            }
        }
    }

    /// T, H, R at a cap height, each letter where it sits in the whole word so the pairs keep the face's
    /// kerning, each drawn at its own alpha and scaled about its own centre. Returns the letters' centres.
    private func word(_ context: inout GraphicsContext, capHeight C: CGFloat, left: CGFloat, baseline: CGFloat,
                      alphas: [Double], scales: [CGFloat], colour: Color) -> [CGPoint] {
        let fontSize = C / WordmarkGeometry.capHeightPerEm
        let font = Font.custom("Archivo-ExtraBold", size: fontSize)
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

    /// Chalk dust settled on the wall: a fixed scatter of faint specks that streams back along the line of
    /// the throw as the camera flies (`run` points so far, `speed` points a second), each speck a streak
    /// in proportion to the speed and a dot at rest, and brighter where the beam lights it.
    private func grain(_ context: inout GraphicsContext, in rect: CGRect, run: CGFloat, speed: CGFloat, alpha: Double, colour: Color,
                       lit: (CGFloat, CGFloat) -> Bool) {
        let axis = MarkGeometry.axis
        func wrap(_ x: CGFloat, _ lo: CGFloat, _ hi: CGFloat) -> CGFloat {
            let span = hi - lo
            var y = (x - lo).truncatingRemainder(dividingBy: span)
            if y < 0 { y += span }
            return lo + y
        }
        var rng = Grain(seed: 0x9E37_79B9)
        let count = min(420, Int(rect.width * rect.height / 900))
        let trail = min(22, speed / 60 * 1.1)
        var dim = Path(), bright = Path()
        for _ in 0..<count {
            let u = rng.next(), v = rng.next(), r = 0.55 + 0.55 * rng.next()
            let x = wrap(rect.minX + rect.width * u - axis.dx * run, rect.minX, rect.maxX)
            let y = wrap(rect.minY + rect.height * v - axis.dy * run, rect.minY, rect.maxY)
            if trail > 1 {
                if lit(x, y) {
                    bright.move(to: CGPoint(x: x, y: y)); bright.addLine(to: CGPoint(x: x + axis.dx * trail, y: y + axis.dy * trail))
                } else {
                    dim.move(to: CGPoint(x: x, y: y)); dim.addLine(to: CGPoint(x: x + axis.dx * trail, y: y + axis.dy * trail))
                }
            } else {
                let dot = CGRect(x: x - r, y: y - r, width: 2 * r, height: 2 * r)
                if lit(x, y) { bright.addEllipse(in: dot) } else { dim.addEllipse(in: dot) }
            }
        }
        let litAlpha = min(1, alpha * Tune.beamLift)
        if trail > 1 {
            let style = StrokeStyle(lineWidth: 1.4, lineCap: .round)
            context.stroke(dim, with: .color(colour.opacity(alpha)), style: style)
            context.stroke(bright, with: .color(colour.opacity(litAlpha)), style: style)
        } else {
            context.fill(dim, with: .color(colour.opacity(alpha)))
            context.fill(bright, with: .color(colour.opacity(litAlpha)))
        }
    }

    /// The face's measure: the width of THR per unit of cap height, and what the Ø adds after it.
    private func typeMetrics(_ context: GraphicsContext) -> (perCap: CGFloat, extra: CGFloat) {
        let probe = context.resolve(Text("THR").font(.custom("Archivo-ExtraBold", size: 100)))
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
