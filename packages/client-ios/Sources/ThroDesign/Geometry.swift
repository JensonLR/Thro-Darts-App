import SwiftUI
import ThroTokens

// SLATE, B.0 — the move. `Easing` and `MarkGeometry` were written for the opening (PD-007) and have
// lived in `ThroApp/LaunchSequence.swift` since. Nothing about them is the opening's: one evaluates
// the token layer's own cubic-beziers, the other is the founder's mark measured off the artwork.
// SLATE's chalk terminations are drawn from the same geometry — a chalk rule's rough edge is
// `MarkGeometry.chalkEdge`, and the one diagonal in the product is `MarkGeometry.bar` — so the
// design layer cannot go on reaching up into the app layer to draw its own furniture.
//
// **This is a move and not a rewrite.** Both types were already `public` and both arrive here byte
// for byte. `LaunchSequence.swift` already imports `ThroDesign`, so the opening's thirteen tests
// hold with no change to a single assertion — only an import added to the test file, because
// `ThroAppTests` had no reason to import `ThroDesign` before today.
//
// The first version of this file said the two types "depend on nothing but SwiftUI". They do not:
// `Easing` evaluates `ThroMotion`'s cubic-beziers, which is the whole reason it is called the token
// layer's easings. It compiled where it used to live because that file imports `ThroTokens`, and
// the claim went in unchecked. CI found it in four minutes on a macOS runner;
// `check_tokens_exist.py` now finds it in under a second on any machine, because it already reads
// every token reference in every file and had never asked whether the file could see them.
//
// Two things B.0 named do NOT move yet, because the spec was wrong about them and moving them would
// have been an access change dressed as a move. `Grain` is `internal`, and `Speck` is nested inside
// `LaunchFrame`; both would have to be made `public` and lifted out of their enclosing type to live
// here. They are wanted by `ChalkField`, which is the board's background and lands with the board.
// They move then, as a change that says what it is.

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
    /// Chalk leaves the stick at full speed the moment it touches the board and slows as the stroke runs
    /// out. It never eases in, because there is nothing to ease in from — and a stroke that eased in
    /// would put a tenth of a second of silence between the thud and the first mark on the board.
    public static func chalk(_ x: Double) -> Double { 1 - pow(1 - unit(x), 1.7) }

    /// A struck thing settling: a damped sine that starts at zero, in the units of `amplitude`.
    public static func damped(_ t: Double, amplitude: Double, hertz: Double, decay: Double) -> Double {
        guard t > 0 else { return 0 }
        return amplitude * exp(-t / decay) * sin(2 * .pi * hertz * t)
    }
}

/// The mark's proportions against its frame, measured from the founder's artwork
/// (docs/design/brand/README.md): ring outer 0.364, inner 0.250, dart half-width 0.040, tips 0.643, the
/// axis at 45° lower-left to upper-right. The wordmark's Ø has the letters' own weight instead, against
/// the cap height, and those numbers are measured off Archivo ExtraBold rather than chosen: rendered at
/// 300 pt its cap is 206 px, its H stem 0.261 cap, its O 0.524 cap in outer radius with a side stroke of
/// 0.269 cap, and its Ø's slash 0.130 cap thick. So: ring 0.524 / 0.255, half-width 0.065. The tips stay
/// at 0.95 — the bar runs well past the ring because it is a dart, which is the mark and not the
/// typeface's Ø. The mark becomes the Ø by mixing one set of ratios into the other.
public struct MarkGeometry: Equatable, Sendable {
    public struct Ratios: Equatable, Sendable {
        public let ringOuter: CGFloat
        public let ringInner: CGFloat
        public let halfWidth: CGFloat
        public let tip: CGFloat
        public static let mark = Ratios(ringOuter: 0.364, ringInner: 0.250, halfWidth: 0.040, tip: 0.643)
        public static let wordmark = Ratios(ringOuter: 0.524, ringInner: 0.255, halfWidth: 0.065, tip: 0.95)
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
    /// Where the dart's line meets the ring, as screen angles, lower left and upper right: the ring is
    /// set from the dart, both ways round.
    public static let crossingAngles: [Double] = [135, 315]

    // MARK: - the strike's shock, and the ring it sets
    //
    // The mark is not drawn on. Earlier versions ran a chalk stroke out from each crossing and let the
    // two meet — and because a stroke thins to a point where it leads, the ring closed on two hairline
    // pinches, at 45° and 225°, which never filled. The founder saw the one at the bottom right. That
    // is structural: two tapered ends cannot meet in a whole ring.
    //
    // So the ring is not drawn now. The strike sends a shock out through the board, and it is not
    // round: it is stretched along the dart's own line, so it reaches the mark's radius first exactly
    // where the dart crosses it and last square to that. Where the shock crosses the radius the chalk
    // is SET — at full width, on the frame it arrives — so the ring lights up from the dart's line and
    // races round both ways until it closes. Two lit fronts merge. Nothing tapers, so there is no seam
    // that can break.

    /// How much further the shock reaches along the dart's line than square to it.
    public static let shockStretch: Double = 0.30
    /// The shock's reach at a screen angle, as a multiple of its scalar size. A shock leaves the point
    /// round and is shaped by the board as it travels, so the stretch comes in over the first part of
    /// the journey and is complete by the time the front reaches the ring — where it is the whole point.
    /// Without that it draws a lozenge around the dart's own body instead of a wave leaving it.
    public static func shockReach(_ degrees: Double, at size: Double = 1) -> Double {
        let shaping = min(1, max(0, size / shockTouches))
        return 1 + shockStretch * shaping * cos(2 * (degrees - crossingAngles[0]) * .pi / 180)
    }
    /// The shock size at which its front first touches the ring — on the dart's line.
    public static var shockTouches: Double { 1 / (1 + shockStretch) }
    /// The shock size at which it has passed every part of the ring — square to the dart's line.
    public static var shockClears: Double { 1 / (1 - shockStretch) }
    /// How far, in degrees either way from each crossing, a shock of size `s` has set the ring.
    /// Zero when the front first touches; ninety — a closed ring — when it has passed all of it.
    public static func litDegrees(shock s: Double) -> Double {
        guard s > shockTouches else { return 0 }
        guard s < shockClears else { return 90 }
        return acos(min(1, max(-1, (1 / s - 1) / shockStretch))) * 90 / .pi
    }

    /// A point on the ring's centreline at a screen angle.
    public func onRing(_ c: CGPoint, degrees: Double, radiusScale s: CGFloat = 1) -> CGPoint {
        let phi = degrees * .pi / 180, r = ringCentreRadius * s
        return CGPoint(x: c.x + r * CGFloat(cos(phi)), y: c.y + r * CGFloat(sin(phi)))
    }

    /// A point `d` along the axis from the centre, offset `v` across it.
    public func onAxis(_ c: CGPoint, _ d: CGFloat, _ v: CGFloat = 0) -> CGPoint {
        let k = CGFloat(0.5).squareRoot()
        return CGPoint(x: c.x + d * k - v * k, y: c.y - d * k - v * k)
    }

    /// The mark's own dart: the plain bar with a point at each end.
    public func bar(at c: CGPoint) -> Path {
        var p = Path()
        let pts = barPoints(at: c)
        p.move(to: pts[0]); for pt in pts.dropFirst() { p.addLine(to: pt) }
        p.closeSubpath()
        return p
    }

    /// The bar's six corners, tip, shoulder, shoulder, tip, shoulder, shoulder.
    public func barPoints(at c: CGPoint) -> [CGPoint] {
        let L = tip, R = ringOuter, w = halfWidth
        return [onAxis(c, L), onAxis(c, R, w), onAxis(c, -R, w), onAxis(c, -L), onAxis(c, -R, -w), onAxis(c, R, -w)]
    }

    /// The whole mark — ring and dart — as ONE path that fills solid under the non-zero rule.
    ///
    /// **Why this exists.** `ringShape` runs its outer edge one way round and `bar` runs the other,
    /// so a path made by adding one to the other has opposite windings where the dart crosses the
    /// ring, the winding sums to zero there, and the fill leaves a hole: the founder saw the mark
    /// with two darker bites where the bar met the ring. Here the bar is wound the same way as the
    /// ring (its corners reversed when their signed area disagrees), so the crossing is filled once
    /// and the mark is one solid thing whatever colour it is drawn in.
    public func mark(at c: CGPoint, roughness: CGFloat = 0) -> Path {
        var path = ringShape(at: c, roughness: roughness)
        let ringSign = Self.signedArea([onRing(c, degrees: 0), onRing(c, degrees: 90), onRing(c, degrees: 180), onRing(c, degrees: 270)])
        var pts = barPoints(at: c)
        if Self.signedArea(pts) * ringSign < 0 { pts.reverse() }
        path.move(to: pts[0]); for pt in pts.dropFirst() { path.addLine(to: pt) }
        path.closeSubpath()
        return path
    }

    /// Shoelace, in whatever frame the points are in: the sign says which way round they run.
    static func signedArea(_ pts: [CGPoint]) -> CGFloat {
        var a: CGFloat = 0
        for i in pts.indices { let j = (i + 1) % pts.count; a += pts[i].x * pts[j].y - pts[j].x * pts[i].y }
        return a / 2
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

    /// How much wider or narrower the chalk is at a given angle of the ring: a slow wobble, the same at
    /// the same angle on every frame, so the edge never crawls.
    public static func chalkEdge(_ degrees: Double) -> CGFloat {
        CGFloat(0.5 + 0.5 * (0.62 * sin(degrees * 0.129 + 1.7) + 0.38 * sin(degrees * 0.317 + 4.1)))
    }

    /// A stroke of chalk along the ring: a band of the ring's width from `fromDegrees` sweeping `sweep`
    /// degrees clockwise, thinning to a point over its last `taper` degrees (or its first, when the
    /// stroke's leading end is at its start), as chalk thins where the stick lifts, and roughened at the
    /// edges by `roughness` (a fraction of the width) as chalk on a board is. A closed shape.
    public func ringBand(at c: CGPoint, fromDegrees from: Double, sweepDegrees sweep: Double, taperDegrees taper: Double,
                         taperAtStart: Bool = false, radiusScale s: CGFloat = 1, roughness: CGFloat = 0) -> Path {
        var p = Path()
        guard sweep > 0 else { return p }
        let r = ringCentreRadius * s, half = ringWidth / 2
        let steps = max(2, Int(sweep / 2))
        var outer: [CGPoint] = [], inner: [CGPoint] = []
        for i in 0...steps {
            let along = sweep * Double(i) / Double(steps)
            let toLeadingEnd = taperAtStart ? along : sweep - along
            var h: CGFloat = (taper > 0 && toLeadingEnd < taper) ? half * CGFloat(pow(toLeadingEnd / taper, 0.6)) : half
            if roughness > 0 { h *= 1 + roughness * (Self.chalkEdge(from + along) - 0.5) }
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
    public func ringShape(at c: CGPoint, radiusScale s: CGFloat = 1, roughness: CGFloat = 0) -> Path {
        ringBand(at: c, fromDegrees: 0, sweepDegrees: 360, taperDegrees: 0, radiusScale: s, roughness: roughness)
    }
}
