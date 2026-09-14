import SwiftUI
import ThroTokens

// SLATE, B.3 — how a surface ends.
//
// THRØ had one way of ending a surface: a 1 pt `colorBorderDefault` hairline, measured at **1.26:1
// to 1.42:1** against the surfaces it sits on. The contrast gate carries it as four exceptions
// reading "decorative rule" — which is an accurate description of a boundary nobody can see.
// WCAG 1.4.11 asks 3:1 of a control's boundary. The keypad is the clearest case: a player looking
// at the scoring screen was not seeing keys, they were seeing digits with gaps between them, and
// every "the buttons feel generic" reading starts there.
//
// SLATE's answer is that a boundary on a board is **chalk**, and chalk has three forms and no
// others: a rule, a box, and the strike. `colorMarkOnBoard` measures 4.12:1 at the worst point of
// the lamp and 6.71:1 at the darkest, with no exception recorded against it.
//
// Two corrections to B.3 as specified, both made because the spec's version could not be true:
//
//  - **`ChalkBox` is a `Shape`, not an `InsettableShape`.** `InsettableShape` exists so that
//    `.strokeBorder` can inset a stroke by half its width. A chalk rule is not a stroke — it is a
//    filled band whose own edges carry the roughness — and stroking a rough outline would double
//    the roughness and halve the weight. It is filled, so it is a `Shape`, and the type says so.
//  - **The overrun is drawn inside the frame.** Four rules whose ends run past each other need
//    somewhere to run to. The box is inset by `overrun` and each rule overruns by exactly that, so
//    the tails land on the frame's edge and nothing is ever clipped by the view that owns it.
//
// Nothing here animates on its own and nothing here uses alpha.

/// A stroke of chalk drawn straight, with the edge chalk actually has.
///
/// A filled band along the rect's horizontal midline, sampled every 4 pt. The half-width at each
/// sample is the nominal half-width modulated by `roughness`, read out of `MarkGeometry.chalkEdge`
/// — the same function that roughens the mark's own ring, so a rule under the wordmark and the
/// wordmark's ring are the same hand.
///
/// Deterministic in `seedAngle`, so a rule never crawls between frames, and two rules on one screen
/// differ because they are given different angles rather than different random draws.
public struct ChalkRule: Shape {
    public var weight: CGFloat
    public var roughness: CGFloat
    public var seedAngle: Double
    /// How much of the rule is drawn, left to right. Animating this draws the rule in.
    public var trim: CGFloat

    public init(weight: CGFloat = ThroSpacing.spaceChalkRuleWeight,
                roughness: CGFloat = ChalkRule.roughness,
                seedAngle: Double = 0,
                trim: CGFloat = 1) {
        self.weight = weight
        self.roughness = roughness
        self.seedAngle = seedAngle
        self.trim = trim
    }

    /// How rough chalk is. A **ratio**, so it is a constant here and not a token: `ThroSpacing`
    /// carries dimensions, and 0.055 is not a dimension. It is the fraction of the nominal width
    /// that the edge wanders by, and it was chosen so a 3 pt rule wanders by a sixth of a point —
    /// visible as texture at reading distance, never as a wobble.
    public static let roughness: CGFloat = 0.055

    /// The distance between samples along the rule. Coarser and the edge reads as a zigzag; finer
    /// and it costs path segments for a difference below a pixel.
    static let step: CGFloat = 4

    public var animatableData: CGFloat {
        get { trim }
        set { trim = newValue }
    }

    public func path(in rect: CGRect) -> Path {
        ChalkRule.band(from: CGPoint(x: rect.minX, y: rect.midY),
                       to: CGPoint(x: rect.maxX, y: rect.midY),
                       weight: weight, roughness: roughness, seedAngle: seedAngle, trim: trim)
    }

    /// The band between two points, at any angle. Held separately from `path(in:)` so `ChalkBox`
    /// can draw its four sides with the same edge without four nested shapes.
    static func band(from a: CGPoint, to b: CGPoint, weight: CGFloat, roughness: CGFloat,
                     seedAngle: Double, trim: CGFloat) -> Path {
        var path = Path()
        let cut = min(1, max(0, trim))
        guard weight > 0, cut > 0 else { return path }
        let dx = b.x - a.x, dy = b.y - a.y
        let length = (dx * dx + dy * dy).squareRoot()
        guard length > 0 else { return path }
        let drawn = length * cut
        // Unit vectors along the band and across it.
        let ux = dx / length, uy = dy / length
        let nx = -uy, ny = ux
        let samples = max(1, Int((drawn / ChalkRule.step).rounded(.up)))
        var upper: [CGPoint] = [], lower: [CGPoint] = []
        upper.reserveCapacity(samples + 1)
        lower.reserveCapacity(samples + 1)
        for i in 0...samples {
            let along = drawn * CGFloat(i) / CGFloat(samples)
            let wander = 2 * MarkGeometry.chalkEdge(seedAngle + Double(i) * 7.3) - 1
            let half = weight / 2 * (1 + roughness * wander)
            let px = a.x + ux * along, py = a.y + uy * along
            upper.append(CGPoint(x: px + nx * half, y: py + ny * half))
            lower.append(CGPoint(x: px - nx * half, y: py - ny * half))
        }
        path.move(to: upper[0])
        for point in upper.dropFirst() { path.addLine(to: point) }
        for point in lower.reversed() { path.addLine(to: point) }
        path.closeSubpath()
        return path
    }
}

/// A box drawn round something in four strokes, the way a box gets drawn on a board.
///
/// **Square corners.** Nothing on a board is rounded — a rounded rectangle is a thing a rendering
/// engine makes, not a thing a hand makes — so `radiusCard` and `radiusKeypad` survive on the paper
/// side of the app and nowhere else.
///
/// **Closed corners.** The first version ran each rule 3 pt past the corner as a "drawn, not
/// stamped" tell. Thirty keys on one screen turned the tell into a hundred and twenty small crosses,
/// and the founder called them what they were: clutter that is not the brand. The brand's forms —
/// the ring and the dart — are clean geometry, so the box is now clean geometry too: the four rules
/// meet square at the corners and stop there. `overrun` survives as a parameter defaulting to zero
/// for anything that still wants the tell, and a test holds the default at zero. Each side keeps
/// its own seed angle, so no two sides of one box wander identically.
public struct ChalkBox: Shape {
    public var weight: CGFloat
    public var overrun: CGFloat
    public var roughness: CGFloat
    public var seedAngle: Double

    public init(weight: CGFloat = ThroSpacing.spaceChalkRuleWeight,
                overrun: CGFloat = ChalkBox.defaultOverrun,
                roughness: CGFloat = ChalkRule.roughness,
                seedAngle: Double = 0) {
        self.weight = weight
        self.overrun = overrun
        self.roughness = roughness
        self.seedAngle = seedAngle
    }

    /// How far a rule runs past the corner. Zero: the corners close.
    public static let defaultOverrun: CGFloat = 0

    /// The weight animates, so a key can be pressed harder into the board. The ground under a key
    /// moves between two board stops that are 1.27:1 apart, which is a difference and not a signal;
    /// the boundary going from 3 pt to 5 pt is most of the ink on the key and is unmissable.
    public var animatableData: CGFloat {
        get { weight }
        set { weight = newValue }
    }

    public func path(in rect: CGRect) -> Path {
        var path = Path()
        // Inset so nothing lands outside the frame: half the weight (the band sits either side of
        // its centreline), the roughness's worst excursion, and any overrun. A box that drew outside
        // its own bounds would be clipped by whatever view it decorates, and it would look correct
        // in a preview, where nothing clips.
        let reach = weight / 2 * (1 + roughness)
        let box = rect.insetBy(dx: overrun + reach, dy: overrun + reach)
        guard box.width > 0, box.height > 0 else { return path }
        // Each rule runs to the far edge of the rule it meets, so the corner is a filled square and
        // not a notch; anything beyond that is the overrun.
        let over = overrun + reach
        let corners = [
            // top, running left to right, overrunning both ends
            (CGPoint(x: box.minX - over, y: box.minY), CGPoint(x: box.maxX + over, y: box.minY), 0.0),
            // bottom
            (CGPoint(x: box.minX - over, y: box.maxY), CGPoint(x: box.maxX + over, y: box.maxY), 61.0),
            // left, running top to bottom
            (CGPoint(x: box.minX, y: box.minY - over), CGPoint(x: box.minX, y: box.maxY + over), 127.0),
            // right
            (CGPoint(x: box.maxX, y: box.minY - over), CGPoint(x: box.maxX, y: box.maxY + over), 199.0),
        ]
        for (a, b, seed) in corners {
            path.addPath(ChalkRule.band(from: a, to: b, weight: weight, roughness: roughness,
                                        seedAngle: seedAngle + seed, trim: 1))
        }
        return path
    }
}

/// The one diagonal in the product.
///
/// `MarkGeometry.bar` — the founder's mark's own bar, pointed at both ends, at 45° lower-left to
/// upper-right — scaled to strike through a figure. Length 1.35× the figure's width so it clears
/// both ends; thickness 0.085 of the cap height so it reads at any size the vocabulary is drawn at.
///
/// It is drawn in `colorBoardField`, not in chalk: a strike is chalk **scraped off**, and adding a
/// bright line over a number is a different statement from taking one away. The record still shows
/// what was written, which is the whole point — a retraction in the journal is an `INSERT` carrying
/// `corrects_seq`, never a delete, and the screen now says the same thing the journal does.
public struct ChalkStrike: Shape {
    /// The width of what is struck. `nil` strikes whatever it is laid over: the shape takes the
    /// width of the rect it is given, so a ledger row of `180 321` and one of `26 475` each get a
    /// bar that clears their own ends, rather than a bar sized for a guessed width.
    public var figureWidth: CGFloat?
    public var capHeight: CGFloat
    /// The stroke's angle in degrees, anticlockwise from level, as it reads on the screen. **45 is
    /// the mark's own slash** — what a bust figure and the thrower's marker get. `boardAngle` is
    /// the other one.
    public var angle: Double

    public init(figureWidth: CGFloat? = nil, capHeight: CGFloat, angle: Double = 45) {
        self.figureWidth = figureWidth
        self.capHeight = capHeight
        self.angle = angle
    }

    /// A chalker's stroke through a remainder that has been written over: quick, nearly level,
    /// rising a little to the right. The Ø's 45° slash belongs to the mark and to a bust; laid
    /// through every old remainder in a 24 pt ledger column it climbs into the rows above and
    /// below, and a column of them reads as hatching, not as a scoreboard. Eight degrees is what a
    /// hand does.
    public static let boardAngle: Double = 8

    /// How far past the figure the bar runs, as a fraction of the figure's width.
    public static let span: CGFloat = 1.35
    /// The bar's thickness as a fraction of the cap height: **0.130**, which is what the wordmark's
    /// Ø measures — its dart's half-width is 0.065 of the cap (`MarkGeometry.Ratios.wordmark`,
    /// read off Archivo ExtraBold's own Ø slash). The first version chose 0.085 by eye, which drew
    /// a bar a third thinner than the Ø it claimed to be. A strike is the Ø's dart laid through a
    /// figure, so it takes the Ø's weight against the same cap.
    public static let thickness: CGFloat = 2 * MarkGeometry.Ratios.wordmark.halfWidth

    /// The geometry the strike is drawn from, at a given figure size. Separated from `path(in:)` so
    /// it can be measured in a test without a rendering context.
    public static func geometry(figureWidth: CGFloat, capHeight: CGFloat) -> MarkGeometry {
        let tipToTip = ChalkStrike.span * figureWidth
        let unit = tipToTip / (2 * MarkGeometry.Ratios.mark.tip)
        let halfWidth = unit > 0 ? (ChalkStrike.thickness / 2 * capHeight) / unit : 0
        return MarkGeometry(unit: unit,
                            ratios: MarkGeometry.Ratios(ringOuter: MarkGeometry.Ratios.mark.ringOuter,
                                                        ringInner: MarkGeometry.Ratios.mark.ringInner,
                                                        halfWidth: halfWidth,
                                                        tip: MarkGeometry.Ratios.mark.tip))
    }

    public func path(in rect: CGRect) -> Path {
        let width = figureWidth ?? rect.width
        guard width > 0, capHeight > 0 else { return Path() }
        let centre = CGPoint(x: rect.midX, y: rect.midY)
        let bar = ChalkStrike.geometry(figureWidth: width, capHeight: capHeight).bar(at: centre)
        guard angle != 45 else { return bar }
        // The geometry draws the mark's dart at 45°; any other angle is that dart turned about the
        // figure's centre. Screen y runs down, so a positive rotation here turns clockwise.
        let turn = CGFloat((45 - angle) * .pi / 180)
        return bar.applying(CGAffineTransform(translationX: centre.x, y: centre.y).rotated(by: turn)
                                .translatedBy(x: -centre.x, y: -centre.y))
    }
}

/// A key drawn on the board: a face, a chalk box round it, and a press that is visible.
///
/// **What this replaces, and why it is not a restyle.** `ScoreKeypad` used `ThroPressStyle(pressedFill:)`,
/// which draws the pressed colour with `.background` — *behind* the label. The label already carried
/// an opaque `.background(RoundedRectangle().fill(...))` of its own, so the pressed fill was drawn
/// underneath an opaque surface and **has never been visible**. The only press feedback the keypad
/// has ever given is a 2% scale and the haptic. A style that owns the whole key is the only way the
/// press state can reach the fill, because `isPressed` lives in the style and nowhere else.
///
/// Nothing here uses opacity. Availability is carried by **where the key sits in the light** and by
/// which ink is on it, never by fading a control towards its background — a faded control is a
/// control whose label has lost its contrast, and the resting Enter key measured 2.20:1 that way.
public struct ChalkKeyStyle: ButtonStyle {
    /// Where in the lamp's pool the key sits. The board's three stops are its only grounds.
    public enum Lighting: String, CaseIterable, Sendable {
        /// The ordinary key face.
        case field
        /// The key that is ready to be pressed — the brightest ground there is.
        case lit
        /// Out of the light: a key that is not available. Never dimmed.
        case sunken

        var ground: Color {
            switch self {
            case .field: return ThroColor.colorBoardField
            case .lit: return ThroColor.colorBoardLit
            case .sunken: return ThroColor.colorBoardSunken
            }
        }

        /// Where a press moves it. Down one stop, and from the bottom stop it stays: the board has
        /// no fourth ground, and inventing one would break the board law that makes the matrix true.
        var pressed: Lighting {
            switch self {
            case .lit: return .field
            case .field, .sunken: return .sunken
            }
        }
    }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private let lighting: Lighting
    private let minHeight: CGFloat
    private let seedAngle: Double

    /// How tall a key is unless it is told otherwise. `touchTargetScoring`, not
    /// `touchTargetMinimum`: the six quick totals used to take the accessibility floor while the
    /// digits beside them took the scoring target, so the most-pressed keys on the screen were the
    /// smallest ones on it. Held as a constant so a new key inherits the right one by default and a
    /// test can read what the default is.
    public static let defaultHeight: CGFloat = ThroSpacing.touchTargetScoring

    public init(_ lighting: Lighting = .field,
                minHeight: CGFloat = ChalkKeyStyle.defaultHeight,
                seedAngle: Double = 0) {
        self.lighting = lighting
        self.minHeight = minHeight
        self.seedAngle = seedAngle
    }

    /// The chalk box's weight at rest and pressed. Pressing a key presses the chalk harder into the
    /// board: the boundary carries the press, because the boundary is the part with contrast.
    public static let restingWeight: CGFloat = ThroSpacing.spaceChalkRuleWeight
    public static let pressedWeight: CGFloat = ThroSpacing.spaceChalkRuleWeight + 2

    public func makeBody(configuration: Configuration) -> some View {
        let pressed = configuration.isPressed
        return configuration.label
            .frame(maxWidth: .infinity, minHeight: minHeight)
            .background((pressed ? lighting.pressed : lighting).ground)
            .overlay(ChalkBox(weight: pressed ? ChalkKeyStyle.pressedWeight : ChalkKeyStyle.restingWeight,
                              seedAngle: seedAngle)
                        .fill(ThroColor.colorMarkOnBoard))
            .contentShape(Rectangle())
            .scaleEffect(pressed && !reduceMotion ? ThroPressStyle.pressedScale : 1)
            // The same curve and duration `ThroPressStyle` uses. Replacing Apple's easing with
            // THRØ's own across every control is a change of its own and is not smuggled in here.
            .animation(.easeOut(duration: ThroMotion.motionDurationInstant), value: pressed)
    }
}
