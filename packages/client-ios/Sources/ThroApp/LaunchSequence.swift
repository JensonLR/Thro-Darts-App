import SwiftUI
import ThroTokens
import ThroDesign

// PD-007, second version after the founder's first look. The app opens on a throw: a real dart —
// needle, knurled barrel, shaft, flights — spins in from the lower left on a gentle arc that
// straightens onto the mark's axis, grows as it closes, and hits at full speed. Thud, a heavy haptic,
// dust, a shockwave; the flights quiver and settle as a dart's do in a board. Then the ring blooms
// around the strike as its echo, chalk under it. The dart's detail dissolves into the mark's plain
// bar as the mark shrinks and rises to its place, THRØ arrives beneath it letter by letter, the
// tagline follows, and Home fades up. The static launch screen is the same empty green, so nothing
// jumps. Cold launch only; a tap skips; Reduce Motion shows the finished composition and fades.

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

    /// Field to 350 ms; the flight to 1150; the strike's beat to 1550; the ring to 2350; the resolve to
    /// 3250; the hold to 4100; the cross-fade to 4500.
    public static let standard = LaunchTimeline(cuts: [0, 0.35, 1.15, 1.55, 2.35, 3.25, 4.10, 4.50])
    /// Reduce Motion: the finished composition from the first frame, a moment to read it, the fade.
    public static let reduced = LaunchTimeline(cuts: [0, 0, 0, 0, 0, 0, 0.60, 0.90])

    /// Sound and haptic cues, by name and time. None under Reduce Motion: no motion, nothing to score.
    public var cues: [LaunchCue] {
        guard flight.duration > 0 else { return [] }
        return [LaunchCue(name: "whoosh", at: flight.start),
                LaunchCue(name: "thud", at: impact.start),
                LaunchCue(name: "haptic", at: impact.start),
                LaunchCue(name: "chalk", at: ring.start)]
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

    /// The ring's centreline from screen angle `fromDegrees` sweeping `sweep` degrees clockwise on screen.
    public func ringArc(at c: CGPoint, fromDegrees from: Double, sweepDegrees sweep: Double, radiusScale s: CGFloat = 1) -> Path {
        var p = Path()
        guard sweep > 0 else { return p }
        let r = ringCentreRadius * s
        let steps = max(2, Int(sweep / 2))
        for i in 0...steps {
            let phi = (from + sweep * Double(i) / Double(steps)) * .pi / 180
            let pt = CGPoint(x: c.x + r * CGFloat(cos(phi)), y: c.y + r * CGFloat(sin(phi)))
            if i == 0 { p.move(to: pt) } else { p.addLine(to: pt) }
        }
        return p
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

    /// The dart's length tip to tail.
    public let length: CGFloat
    public init(length: CGFloat) { self.length = length }

    /// Points along the dart from the tip (0) back to the tail (length), in a frame where the dart
    /// points along +x; `spin` is the roll about its own axis, which foreshortens the flights.
    public struct Parts {
        public var needle = Path()
        public var barrel = Path()
        public var knurl = Path()
        public var shaft = Path()
        public var nearFlights = Path()
        public var farFlights = Path()
    }

    public func parts(spin: Double) -> Parts {
        let L = length
        let nEnd = -Self.needle * L, bEnd = nEnd - Self.barrel * L, sEnd = bEnd - Self.shaft * L, fEnd = sEnd - Self.flight * L
        var parts = Parts()
        // needle: a point tapering back to the barrel
        parts.needle.move(to: CGPoint(x: 0, y: 0))
        parts.needle.addLine(to: CGPoint(x: nEnd, y: -Self.needleHalf * L))
        parts.needle.addLine(to: CGPoint(x: nEnd, y: Self.needleHalf * L))
        parts.needle.closeSubpath()
        // barrel: a capsule
        let bh = Self.barrelHalf * L
        parts.barrel.addRoundedRect(in: CGRect(x: bEnd, y: -bh, width: nEnd - bEnd, height: 2 * bh), cornerSize: CGSize(width: bh, height: bh))
        // knurl: three grooves across the barrel
        for i in 1...3 {
            let x = bEnd + (nEnd - bEnd) * CGFloat(i) / 4
            parts.knurl.move(to: CGPoint(x: x, y: -bh * 0.8)); parts.knurl.addLine(to: CGPoint(x: x, y: bh * 0.8))
        }
        // shaft
        let sh = Self.shaftHalf * L
        parts.shaft.addRect(CGRect(x: sEnd, y: -sh, width: bEnd - sEnd, height: 2 * sh))
        // flights: two pairs at right angles, seen edge-on to face-on as the dart rolls
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
        parts.nearFlights = fins(CGFloat(abs(cos(spin))))
        parts.farFlights = fins(CGFloat(abs(sin(spin))))
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

    private func draw(in context: inout GraphicsContext, size: CGSize) {
        let chalk = ThroColor.throChalk
        let pField = timeline.field.progress(at: t)
        let pFlight = Easing.exit(timeline.flight.progress(at: t))
        let pRing = Easing.resolve(timeline.ring.progress(at: t))
        let pResolve = Easing.resolve(timeline.resolve.progress(at: t))
        let sinceImpact = t - timeline.impact.start
        let sinceRing = t - timeline.ring.end

        // The field: a vignette that deepens the green toward the edges, arriving with the first frame.
        let vignette = Gradient(colors: [ThroColor.throInk.opacity(0), ThroColor.throInk.opacity(0.38 * min(1, pField + 0.3))])
        context.fill(Path(CGRect(origin: .zero, size: size)),
                     with: .radialGradient(vignette, center: CGPoint(x: size.width / 2, y: size.height / 2),
                                           startRadius: min(size.width, size.height) * 0.3, endRadius: max(size.width, size.height) * 0.72))

        // Where the mark is: large and central through the throw, then up to the Splash's place.
        let big = MarkGeometry(tipToTip: min(size.width * 0.84, 380))
        let small = MarkGeometry(tipToTip: 104)
        let (wordC, wordSize, wordWidth) = wordmark(context: context)
        let wordHeight = 2 * WordmarkGeometry.tip * wordC * CGFloat(0.5).squareRoot()
        let groupHeight = small.tipToTip + 28 + wordHeight + 20 + 16
        let groupTop = (size.height - groupHeight) / 2
        let bigCentre = CGPoint(x: size.width / 2, y: size.height * 0.46)
        let smallCentre = CGPoint(x: size.width / 2, y: groupTop + small.tipToTip / 2)
        let geo = MarkGeometry(unit: big.unit + (small.unit - big.unit) * CGFloat(pResolve))
        let centre = CGPoint(x: bigCentre.x + (smallCentre.x - bigCentre.x) * CGFloat(pResolve),
                             y: bigCentre.y + (smallCentre.y - bigCentre.y) * CGFloat(pResolve))
        let axis = MarkGeometry.axis

        // Impact: a breath of lighter green behind the strike and a shockwave from the point.
        if sinceImpact >= 0 && sinceImpact < 0.55 {
            let q = sinceImpact / 0.55
            let breath = sin(.pi * q) * 0.9
            let flash = Gradient(colors: [ThroColor.throGreenDeep.opacity(breath), ThroColor.throGreenDeep.opacity(0)])
            let tipPoint = geo.onAxis(centre, geo.tip)
            context.fill(Path(CGRect(origin: .zero, size: size)),
                         with: .radialGradient(flash, center: tipPoint, startRadius: 0, endRadius: size.width * 0.75))
            let r = geo.ringOuter * (0.15 + 1.6 * CGFloat(Easing.impact(q)))
            context.stroke(Path(ellipseIn: CGRect(x: tipPoint.x - r, y: tipPoint.y - r, width: 2 * r, height: 2 * r)),
                           with: .color(chalk.opacity(0.35 * (1 - q))), lineWidth: 2.5 * (1 - CGFloat(q)) + 0.5)
        }

        // The ring: blooms clockwise from where the dart crossed it, glows, carries chalk grain, pulses once.
        if pRing > 0 {
            let pulse = 1 + CGFloat(Easing.damped(sinceRing, amplitude: 0.035, hertz: 5.5, decay: 0.16))
            let sweep = 360 * pRing
            let arc = geo.ringArc(at: centre, fromDegrees: 315, sweepDegrees: sweep, radiusScale: pulse)
            context.drawLayer { glow in
                glow.addFilter(.blur(radius: geo.ringWidth * 0.55))
                glow.stroke(arc, with: .color(chalk.opacity(0.32)), style: StrokeStyle(lineWidth: geo.ringWidth * 1.5, lineCap: .round))
            }
            context.stroke(arc, with: .color(chalk), style: StrokeStyle(lineWidth: geo.ringWidth, lineCap: .round))
            // grain: the chalk's own unevenness, fixed to the ring so it does not crawl
            for i in 0..<Int(sweep / 5) {
                let phi = (315 + Double(i) * 5 + 2.3) * .pi / 180
                let wobble = CGFloat([0.31, -0.22, 0.12, -0.36, 0.27, -0.08, 0.19, -0.29][i % 8]) * geo.ringWidth
                let rr = geo.ringCentreRadius * pulse + wobble
                let gx = centre.x + rr * CGFloat(cos(phi)), gy = centre.y + rr * CGFloat(sin(phi))
                let gr = geo.ringWidth * CGFloat([0.09, 0.06, 0.11, 0.05][i % 4])
                context.fill(Path(ellipseIn: CGRect(x: gx - gr, y: gy - gr, width: 2 * gr, height: 2 * gr)),
                             with: .color(ThroColor.throGreen.opacity(0.22)))
            }
        }

        // The dart. In flight it comes in on an arc that straightens onto the axis, grows as it closes,
        // spins, and streaks. Landed, its flights quiver and settle. Resolving, it dissolves into the bar.
        let detailAlpha = 1 - min(1, max(0, (pResolve - 0.05) / 0.55))
        let barAlpha = min(1, max(0, (pResolve - 0.1) / 0.5))
        if barAlpha > 0 {
            context.fill(geo.bar(at: centre), with: .color(chalk.opacity(barAlpha)))
        }
        if pFlight > 0 && detailAlpha > 0 {
            let landed = geo.onAxis(centre, geo.tip)
            let startTip = CGPoint(x: landed.x - axis.dx * (geo.tipToTip + size.width * 0.9),
                                   y: landed.y - axis.dy * (geo.tipToTip + size.width * 0.9) + size.height * 0.22)
            let control = CGPoint(x: landed.x - axis.dx * geo.tipToTip * 1.1, y: landed.y - axis.dy * geo.tipToTip * 1.1)
            func bezier(_ s: CGFloat) -> CGPoint {
                let u = 1 - s
                return CGPoint(x: u * u * startTip.x + 2 * u * s * control.x + s * s * landed.x,
                               y: u * u * startTip.y + 2 * u * s * control.y + s * s * landed.y)
            }
            func tangent(_ s: CGFloat) -> CGVector {
                let dx = 2 * (1 - s) * (control.x - startTip.x) + 2 * s * (landed.x - control.x)
                let dy = 2 * (1 - s) * (control.y - startTip.y) + 2 * s * (landed.y - control.y)
                let len = max(0.001, (dx * dx + dy * dy).squareRoot())
                return CGVector(dx: dx / len, dy: dy / len)
            }
            let s = CGFloat(pFlight)
            let tipPoint = pFlight < 1 ? bezier(s) : landed
            let heading = pFlight < 1 ? tangent(s) : axis
            let scale = 0.55 + 0.45 * s
            let spin = 2 * Double.pi * 2.6 * Double(s)                     // rolls in flight, stops in the board
            let quiver = Easing.damped(max(0, sinceImpact), amplitude: 3.6 * .pi / 180, hertz: 6.5, decay: 0.24)
            let angle = atan2(heading.dy, heading.dx) + CGFloat(pFlight < 1 ? 0 : quiver)
            let anatomy = DartAnatomy(length: geo.tipToTip)
            // streak: ghosts behind a dart in flight
            if pFlight < 1 {
                for (i, back) in [0.05, 0.11, 0.18].enumerated() {
                    let ghostTip = bezier(max(0, s - CGFloat(back)))
                    var g = context
                    g.translateBy(x: ghostTip.x, y: ghostTip.y)
                    g.rotate(by: .radians(Double(atan2(heading.dy, heading.dx))))
                    g.scaleBy(x: scale, y: scale)
                    let parts = anatomy.parts(spin: spin)
                    let a = [0.22, 0.13, 0.07][i] * Double(pFlight)
                    g.fill(parts.barrel, with: .color(chalk.opacity(a)))
                    g.fill(parts.nearFlights, with: .color(chalk.opacity(a)))
                }
            }
            var d = context
            d.translateBy(x: tipPoint.x, y: tipPoint.y)
            d.rotate(by: .radians(Double(angle)))
            d.scaleBy(x: scale, y: scale)
            let parts = anatomy.parts(spin: spin)
            d.fill(parts.farFlights, with: .color(chalk.opacity(0.55 * detailAlpha)))
            d.fill(parts.shaft, with: .color(chalk.opacity(0.85 * detailAlpha)))
            d.fill(parts.barrel, with: .color(chalk.opacity(detailAlpha)))
            d.stroke(parts.knurl, with: .color(ThroColor.throGreen.opacity(0.45 * detailAlpha)), lineWidth: max(1, geo.unit * 0.008))
            d.fill(parts.needle, with: .color(chalk.opacity(detailAlpha)))
            d.fill(parts.nearFlights, with: .color(chalk.opacity(0.95 * detailAlpha)))
        }

        // Dust off the point of impact: thrown outward and falling.
        if sinceImpact >= 0 && sinceImpact < 0.9 {
            let tipPoint = geo.onAxis(centre, geo.tip)
            for i in 0..<10 {
                let a = (-80 + Double(i) * 14) * .pi / 180 + atan2(Double(axis.dy), Double(axis.dx))   // a fan around the heading
                let speed = CGFloat(90 + 40 * Double(i % 3)) * (geo.unit / 260)
                let q = CGFloat(sinceImpact)
                let sx = tipPoint.x + CGFloat(cos(a)) * speed * q * (1 - q * 0.35)
                let sy = tipPoint.y + CGFloat(sin(a)) * speed * q * (1 - q * 0.35) + 260 * q * q       // gravity
                let r = 1.2 + CGFloat(i % 3) * 0.9
                context.fill(Path(ellipseIn: CGRect(x: sx - r, y: sy - r, width: 2 * r, height: 2 * r)),
                             with: .color(chalk.opacity(0.85 * (1 - Double(q) / 0.9))))
            }
        }

        // The name: T, H, R rise into place one after another; the Ø is the mark's own; then the tagline.
        if pResolve > 0.2 {
            let wordTop = groupTop + small.tipToTip + 28
            let left = (size.width - wordWidth) / 2
            let fontSize = wordC / WordmarkGeometry.capHeightPerEm
            let baseline = wordTop + wordHeight / 2 + wordC / 2
            let textTop = baseline - fontSize * WordmarkGeometry.ascenderPerEm
            let font = Font.custom("Archivo-ExtraBold", size: fontSize)
            var x = left
            for (i, letter) in ["T", "H", "R"].enumerated() {
                let q = min(1, max(0, (pResolve - (0.2 + 0.13 * Double(i))) / 0.4))
                let rise = CGFloat(1 - Easing.set(q)) * 16
                var glyph = context.resolve(Text(letter).font(font))
                glyph.shading = .color(chalk.opacity(q))
                context.draw(glyph, at: CGPoint(x: x, y: textTop + rise), anchor: .topLeading)
                x += glyph.measure(in: CGSize(width: 1000, height: 1000)).width
            }
            let oAlpha = min(1, max(0, (pResolve - 0.55) / 0.35))
            let oCentre = CGPoint(x: left + wordSize.width + WordmarkGeometry.gap * wordC + WordmarkGeometry.ringOuter * wordC,
                                  y: baseline - wordC / 2)
            let ro = WordmarkGeometry.ringOuter * wordC, ri = WordmarkGeometry.ringInner * wordC
            context.stroke(Path(ellipseIn: CGRect(x: oCentre.x - (ro + ri) / 2, y: oCentre.y - (ro + ri) / 2, width: ro + ri, height: ro + ri)),
                           with: .color(chalk.opacity(oAlpha)), lineWidth: ro - ri)
            let k = CGFloat(0.5).squareRoot()
            let L = WordmarkGeometry.tip * wordC, w = WordmarkGeometry.halfWidth * wordC
            let local: [(CGFloat, CGFloat)] = [(L, 0), (ro, w), (-ro, w), (-L, 0), (-ro, -w), (ro, -w)]
            var dart = Path()
            for (i, (u, v)) in local.enumerated() {
                let pt = CGPoint(x: oCentre.x + u * k - v * k, y: oCentre.y - u * k - v * k)
                if i == 0 { dart.move(to: pt) } else { dart.addLine(to: pt) }
            }
            dart.closeSubpath()
            context.fill(dart, with: .color(chalk.opacity(oAlpha)))
            let tagQ = min(1, max(0, (pResolve - 0.7) / 0.3))
            if tagQ > 0 {
                var tag = context.resolve(Text("FROM THE PUB BOARD TO THE WORLD STAGE")
                    .font(.custom("Archivo-SemiBold", size: 13)).kerning(13 * (0.09 + 0.07 * (1 - tagQ))))
                tag.shading = .color(chalk.opacity(0.72 * tagQ))
                context.draw(tag, at: CGPoint(x: size.width / 2, y: wordTop + wordHeight + 20), anchor: .top)
            }
        }
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
