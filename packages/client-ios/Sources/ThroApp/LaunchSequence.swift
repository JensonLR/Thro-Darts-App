import SwiftUI
import ThroTokens
import ThroDesign

// PD-007: the app opens on the throw. One chalk dart comes in, loops once to leave the ring as its
// trail, cuts through the centre and lands; its whole path is the mark. Then the mark takes its place
// as the Ø of the name and Home fades up. The static launch screen iOS shows first is the same empty
// green, so nothing jumps. Cold launch only; a tap skips; Reduce Motion shows the finished composition
// and fades. Storyboard and spec: the "THRØ Launch Sequence" design canvas, Direction A.

/// The timeline in seconds from the first frame. Segments are contiguous; the last is the cross-fade
/// to Home, which the root performs.
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
    public let approach: Segment
    public let loop: Segment
    public let strike: Segment
    public let impact: Segment
    public let name: Segment
    public let hold: Segment
    public let exit: Segment

    public var segments: [Segment] { [field, approach, loop, strike, impact, name, hold, exit] }
    public var total: Double { exit.end }
    /// When the root begins the cross-fade to Home.
    public var finishAt: Double { exit.start }

    /// The spec board's timings: field to 150 ms, approach to 300, loop to 850, strike to 1030,
    /// impact to 1150, name to 1600, hold to 2000, cross-fade to 2300.
    public static let standard = LaunchTimeline(cuts: [0, 0.15, 0.30, 0.85, 1.03, 1.15, 1.60, 2.00, 2.30])
    /// Reduce Motion: the finished composition from the first frame, a moment to read it, the fade.
    public static let reduced = LaunchTimeline(cuts: [0, 0, 0, 0, 0, 0, 0, 0.60, 0.90])

    init(cuts c: [Double]) {
        precondition(c.count == 9, "eight segments need nine cuts")
        let names = ["field", "approach", "loop", "strike", "impact", "name", "hold", "exit"]
        let s = (0..<8).map { Segment(name: names[$0], start: c[$0], end: c[$0 + 1]) }
        field = s[0]; approach = s[1]; loop = s[2]; strike = s[3]
        impact = s[4]; name = s[5]; hold = s[6]; exit = s[7]
    }
}

/// The token layer's cubic-bezier easings, evaluated: `x` is time 0...1, the result progress 0...1.
public enum Easing {
    public static func cubicBezier(_ c: (CGFloat, CGFloat, CGFloat, CGFloat), _ x: Double) -> Double {
        let x = min(1, max(0, x))
        let (p1x, p1y, p2x, p2y) = (Double(c.0), Double(c.1), Double(c.2), Double(c.3))
        func bx(_ u: Double) -> Double { 3 * (1 - u) * (1 - u) * u * p1x + 3 * (1 - u) * u * u * p2x + u * u * u }
        func by(_ u: Double) -> Double { 3 * (1 - u) * (1 - u) * u * p1y + 3 * (1 - u) * u * u * p2y + u * u * u }
        func dbx(_ u: Double) -> Double { 3 * (1 - u) * (1 - u) * p1x + 6 * (1 - u) * u * (p2x - p1x) + 3 * u * u * (1 - p2x) }
        // Newton's method for the curve parameter at this x, then read the curve's y there.
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
}

/// The mark's proportions, measured against its frame (docs/design/brand/README.md): ring outer 0.364,
/// inner 0.250, dart half-width 0.040, tips 0.643, the axis at 45° lower-left to upper-right.
public struct MarkGeometry: Equatable, Sendable {
    public static let ringOuterRatio: CGFloat = 0.364
    public static let ringInnerRatio: CGFloat = 0.250
    public static let halfWidthRatio: CGFloat = 0.040
    public static let tipRatio: CGFloat = 0.643

    /// The frame unit in points.
    public let unit: CGFloat
    public init(unit: CGFloat) { self.unit = unit }
    /// Sized so the dart's two points are `span` apart.
    public init(tipToTip span: CGFloat) { unit = span / (2 * MarkGeometry.tipRatio) }

    public var ringOuter: CGFloat { Self.ringOuterRatio * unit }
    public var ringInner: CGFloat { Self.ringInnerRatio * unit }
    public var ringCentreRadius: CGFloat { (ringOuter + ringInner) / 2 }
    public var ringWidth: CGFloat { ringOuter - ringInner }
    public var halfWidth: CGFloat { Self.halfWidthRatio * unit }
    public var tip: CGFloat { Self.tipRatio * unit }
    public var tipToTip: CGFloat { 2 * tip }

    /// A point `d` along the axis from the centre (positive toward the upper-right), offset `v`
    /// across it, in a y-down frame.
    public func onAxis(_ c: CGPoint, _ d: CGFloat, _ v: CGFloat = 0) -> CGPoint {
        let k = CGFloat(0.5).squareRoot()
        return CGPoint(x: c.x + d * k - v * k, y: c.y - d * k - v * k)
    }

    /// The dart with its point at `headAt` along the axis; `tailAt` where the tail's point is. With
    /// headAt = tip and tailAt = -tip this is the mark's own hexagon.
    public func dart(at c: CGPoint, headAt d: CGFloat, tailAt tail: CGFloat) -> Path {
        let R = ringOuter, w = halfWidth
        let head = min(tip - R, max(0, d + R))          // the point grows to the mark's taper
        let base = d - head
        let shoulder = min(-R, base)                     // never ahead of the head's base
        var p = Path()
        p.move(to: onAxis(c, d))
        p.addLine(to: onAxis(c, base, w))
        p.addLine(to: onAxis(c, shoulder, w))
        p.addLine(to: onAxis(c, tail))
        p.addLine(to: onAxis(c, shoulder, -w))
        p.addLine(to: onAxis(c, base, -w))
        p.closeSubpath()
        return p
    }

    public func dart(at c: CGPoint) -> Path { dart(at: c, headAt: tip, tailAt: -tip) }

    /// The ring's centreline from screen angle 135° (lower-left) sweeping `sweep` degrees clockwise on
    /// screen, as a polyline fine enough to stroke round.
    public func ringArc(at c: CGPoint, sweepDegrees sweep: Double, radiusScale s: CGFloat = 1) -> Path {
        var p = Path()
        guard sweep > 0 else { return p }
        let r = ringCentreRadius * s
        let steps = max(2, Int(sweep / 2))
        for i in 0...steps {
            let phi = (135 + sweep * Double(i) / Double(steps)) * .pi / 180
            let pt = CGPoint(x: c.x + r * CGFloat(cos(phi)), y: c.y + r * CGFloat(sin(phi)))
            if i == 0 { p.move(to: pt) } else { p.addLine(to: pt) }
        }
        return p
    }

    /// Where the dart is and which way it heads at screen angle `phi` on the ring, travelling clockwise on screen.
    public func onRing(_ c: CGPoint, degrees: Double) -> (position: CGPoint, heading: CGVector) {
        let phi = degrees * .pi / 180
        let r = ringCentreRadius
        return (CGPoint(x: c.x + r * CGFloat(cos(phi)), y: c.y + r * CGFloat(sin(phi))),
                CGVector(dx: -CGFloat(sin(phi)), dy: CGFloat(cos(phi))))
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
    /// Archivo ExtraBold's vertical metrics, from the face's own tables, so the Ø sits on the letters'
    /// cap midline wherever the text lands.
    public static let capHeightPerEm: CGFloat = 687.0 / 1000.0
    public static let ascenderPerEm: CGFloat = 878.0 / 1000.0
    public static let descenderPerEm: CGFloat = 210.0 / 1000.0
}

/// The opening. Draws every frame as a function of time from a Canvas, so the whole sequence is one
/// pure drawing of `t`; a tap finishes it early.
public struct LaunchSequenceView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private let onFinished: () -> Void
    @State private var start = Date()
    @State private var finished = false

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
            start = Date()
            DispatchQueue.main.asyncAfter(deadline: .now() + timeline.finishAt) { finish() }
        }
    }

    private func finish() {
        guard !finished else { return }
        finished = true
        onFinished()
    }
}

/// One frame of the sequence at time `t`.
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
        let pApproach = Easing.set(timeline.approach.progress(at: t))
        let pLoop = Easing.resolve(timeline.loop.progress(at: t))
        let pStrike = Easing.throwCurve(timeline.strike.progress(at: t))
        let pImpact = timeline.impact.progress(at: t)
        let pName = Easing.resolve(timeline.name.progress(at: t))

        // Where the mark is: large and central during the throw, then up to the Splash's place.
        let big = MarkGeometry(tipToTip: min(size.width * 0.86, 388))
        let small = MarkGeometry(tipToTip: 104)
        let (wordC, wordSize, wordWidth) = wordmark(context: context)
        let wordHeight = 2 * WordmarkGeometry.tip * wordC * CGFloat(0.5).squareRoot()
        let groupHeight = small.tipToTip + 28 + wordHeight + 20 + 16
        let groupTop = (size.height - groupHeight) / 2
        let bigCentre = CGPoint(x: size.width / 2, y: size.height * 0.45)
        let smallCentre = CGPoint(x: size.width / 2, y: groupTop + small.tipToTip / 2)
        let geo = MarkGeometry(unit: big.unit + (small.unit - big.unit) * CGFloat(pName))
        let centre = CGPoint(x: bigCentre.x + (smallCentre.x - bigCentre.x) * CGFloat(pName),
                             y: bigCentre.y + (smallCentre.y - bigCentre.y) * CGFloat(pName))

        // Impact: a breath of lighter green behind the mark, an echo ring, the ring flexing once.
        if pImpact > 0 && pImpact < 1 {
            let breath = sin(.pi * pImpact)
            let gradient = Gradient(colors: [ThroColor.throGreenDeep.opacity(breath), ThroColor.throGreen.opacity(0)])
            context.fill(Path(CGRect(origin: .zero, size: size)),
                         with: .radialGradient(gradient, center: centre, startRadius: 0, endRadius: size.width * 0.6))
            let echo = Path(ellipseIn: CGRect(x: centre.x - geo.ringOuter * (1 + 0.35 * CGFloat(pImpact)),
                                              y: centre.y - geo.ringOuter * (1 + 0.35 * CGFloat(pImpact)),
                                              width: 2 * geo.ringOuter * (1 + 0.35 * CGFloat(pImpact)),
                                              height: 2 * geo.ringOuter * (1 + 0.35 * CGFloat(pImpact))))
            context.stroke(echo, with: .color(chalk.opacity(0.25 * (1 - pImpact))), lineWidth: 2)
        }
        let flex = 1 + (ThroMotion.motionScaleImpact - 1) * 2 * CGFloat(sin(.pi * pImpact))

        // Approach: the dart from off-screen lower-left to the ring's lower-left point, a fading trail behind.
        if pApproach > 0 && pLoop < 1 {
            let from = -(geo.ringCentreRadius + 520)
            let d = from + (-geo.ringCentreRadius - from) * CGFloat(pApproach)
            let trailFade = pLoop < 0.4 ? 1 - pLoop / 0.4 : 0
            if trailFade > 0 {
                var trail = Path()
                trail.move(to: geo.onAxis(centre, d - 260))
                trail.addLine(to: geo.onAxis(centre, d - 24, geo.halfWidth * 0.9))
                trail.addLine(to: geo.onAxis(centre, d - 24, -geo.halfWidth * 0.9))
                trail.closeSubpath()
                context.fill(trail, with: .color(chalk.opacity(0.85 * trailFade)))
            }
            if pLoop == 0 {
                context.fill(head(at: geo.onAxis(centre, d), heading: CGVector(dx: CGFloat(0.5).squareRoot(), dy: -CGFloat(0.5).squareRoot()),
                                  length: 0.26 * geo.unit, halfWidth: geo.halfWidth), with: .color(chalk))
            }
        }

        // Loop: the ring as the dart's trail, clockwise on screen from the lower-left point.
        if pLoop > 0 {
            let sweep = 360 * pLoop
            context.stroke(geo.ringArc(at: centre, sweepDegrees: sweep, radiusScale: flex), with: .color(chalk),
                           style: StrokeStyle(lineWidth: geo.ringWidth, lineCap: .round))
            if pLoop < 1 {
                let (pos, heading) = geo.onRing(centre, degrees: 135 + sweep)
                context.fill(head(at: pos, heading: heading, length: 0.26 * geo.unit, halfWidth: geo.halfWidth * 0.95), with: .color(chalk))
                // Chalk specks fall off the trail at fixed points of the loop and fade.
                for (i, at) in [0.18, 0.37, 0.55, 0.78].enumerated() where pLoop > at {
                    let age = (pLoop - at) / 0.35
                    guard age < 1 else { continue }
                    let (sp, _) = geo.onRing(centre, degrees: 135 + 360 * at)
                    let outward = CGVector(dx: sp.x - centre.x, dy: sp.y - centre.y)
                    let len = max(1, (outward.dx * outward.dx + outward.dy * outward.dy).squareRoot())
                    let drift = geo.ringWidth * (0.9 + 0.6 * CGFloat(i % 3)) * CGFloat(0.4 + age)
                    let sx = sp.x + outward.dx / len * drift, sy = sp.y + outward.dy / len * drift + CGFloat(age) * 6
                    let r = 1.2 + CGFloat(i % 2) * 1.4
                    context.fill(Path(ellipseIn: CGRect(x: sx - r, y: sy - r, width: 2 * r, height: 2 * r)),
                                 with: .color(chalk.opacity(0.7 * (1 - age))))
                }
            }
        }

        // Strike: straight through the centre to the tip; the bar is the trail, the tail taper what it left.
        if pStrike > 0 {
            let d = -geo.ringCentreRadius + (geo.tip + geo.ringCentreRadius) * CGFloat(pStrike)
            let tail = -geo.ringOuter - (geo.tip - geo.ringOuter) * CGFloat(min(1, pStrike * 1.5))
            context.fill(geo.dart(at: centre, headAt: d, tailAt: tail), with: .color(chalk))
        }

        // Impact specks off the tip.
        if pImpact > 0 && pImpact < 1 {
            let tipPoint = geo.onAxis(centre, geo.tip)
            for i in 0..<8 {
                let a = (-45 + Double(i) * 22 - 77) * .pi / 180          // a fan around the dart's heading
                let dist = CGFloat(8 + 34 * Easing.impact(pImpact)) * (1 + 0.15 * CGFloat(i % 3))
                let sx = tipPoint.x + CGFloat(cos(a)) * dist, sy = tipPoint.y + CGFloat(sin(a)) * dist
                let r = 1.3 + CGFloat(i % 3) * 0.9
                context.fill(Path(ellipseIn: CGRect(x: sx - r, y: sy - r, width: 2 * r, height: 2 * r)),
                             with: .color(chalk.opacity(0.8 * (1 - pImpact))))
            }
        }

        // Name: THR fades in beneath the mark, the Ø already in place; then the tagline.
        if pName > 0 {
            let lettersAlpha = min(1, max(0, (pName - 0.35) / 0.45))
            let tagAlpha = min(1, max(0, (pName - 0.6) / 0.4))
            let wordTop = groupTop + small.tipToTip + 28
            let left = (size.width - wordWidth) / 2
            let fontSize = wordC / WordmarkGeometry.capHeightPerEm
            let baseline = wordTop + wordHeight / 2 + wordC / 2
            let textTop = baseline - fontSize * WordmarkGeometry.ascenderPerEm
            var thr = context.resolve(Text("THR").font(.custom("Archivo-ExtraBold", size: fontSize)))
            thr.shading = .color(chalk.opacity(lettersAlpha))
            context.draw(thr, at: CGPoint(x: left, y: textTop), anchor: .topLeading)
            let oCentre = CGPoint(x: left + wordSize.width + WordmarkGeometry.gap * wordC + WordmarkGeometry.ringOuter * wordC,
                                  y: baseline - wordC / 2)
            let ro = WordmarkGeometry.ringOuter * wordC, ri = WordmarkGeometry.ringInner * wordC
            let ring = Path(ellipseIn: CGRect(x: oCentre.x - (ro + ri) / 2, y: oCentre.y - (ro + ri) / 2, width: ro + ri, height: ro + ri))
            context.stroke(ring, with: .color(chalk.opacity(lettersAlpha)), lineWidth: ro - ri)
            let k = CGFloat(0.5).squareRoot()
            let L = WordmarkGeometry.tip * wordC, w = WordmarkGeometry.halfWidth * wordC
            let local: [(CGFloat, CGFloat)] = [(L, 0), (ro, w), (-ro, w), (-L, 0), (-ro, -w), (ro, -w)]
            var dart = Path()
            for (i, (u, v)) in local.enumerated() {
                let pt = CGPoint(x: oCentre.x + u * k - v * k, y: oCentre.y - u * k - v * k)
                if i == 0 { dart.move(to: pt) } else { dart.addLine(to: pt) }
            }
            dart.closeSubpath()
            context.fill(dart, with: .color(chalk.opacity(lettersAlpha)))
            if tagAlpha > 0 {
                var tag = context.resolve(Text("FROM THE PUB BOARD TO THE WORLD STAGE")
                    .font(.custom("Archivo-SemiBold", size: 13)).kerning(13 * 0.09))
                tag.shading = .color(chalk.opacity(0.72 * tagAlpha))
                context.draw(tag, at: CGPoint(x: size.width / 2, y: wordTop + wordHeight + 20), anchor: .top)
            }
        }
    }

    /// A tapered wedge with its point at `tip`, pointing along `heading`.
    private func head(at tip: CGPoint, heading: CGVector, length: CGFloat, halfWidth: CGFloat) -> Path {
        let bx = tip.x - heading.dx * length, by = tip.y - heading.dy * length
        let px = -heading.dy, py = heading.dx
        var p = Path()
        p.move(to: tip)
        p.addLine(to: CGPoint(x: bx + px * halfWidth, y: by + py * halfWidth))
        p.addLine(to: CGPoint(x: bx - px * halfWidth, y: by - py * halfWidth))
        p.closeSubpath()
        return p
    }

    /// The cap height that makes the wordmark 150 points wide, with the measured width of THR at that size.
    private func wordmark(context: GraphicsContext) -> (capHeight: CGFloat, thrSize: CGSize, width: CGFloat) {
        let probe = context.resolve(Text("THR").font(.custom("Archivo-ExtraBold", size: 100)))
        let probeSize = probe.measure(in: CGSize(width: 10_000, height: 10_000))
        let perCap = probeSize.width / 100 / WordmarkGeometry.capHeightPerEm      // THR width per point of cap height
        let extra = WordmarkGeometry.gap + WordmarkGeometry.ringOuter + WordmarkGeometry.tip * CGFloat(0.5).squareRoot()
        let cap = 150 / (perCap + extra)
        return (cap, CGSize(width: perCap * cap, height: probeSize.height / 100 * cap / WordmarkGeometry.capHeightPerEm), 150)
    }
}
