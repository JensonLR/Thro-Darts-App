import SwiftUI
import ThroTokens

// SLATE, B.4 — the honesty layer's furniture.
//
// THRØ's statistics layer produces three kinds of figure — a fact, an interval, and a thing that
// cannot be computed — and the scoring engine produces three more states of the one number the
// product exists to move. Until now all six were drawn the same: `58.4`, `58.4–61.2` and `—` were
// one weight, one colour and one size, so **the one thing the honesty layer exists to communicate
// was the one thing the screen did not show.** A reader had to notice the shape of a string.
//
// A basis is a property of a FIGURE. It is not a property of a result, which is what verification
// is: the eight `VerificationLabel` cases keep their eight distinct words, their explanations, their
// tone and their hint, and gain nothing from this. Drawing eight labels as six forms would assert
// that two of them are the same thing, and they are not.

/// How far a figure can be trusted, drawn as a shape under it.
///
/// `CaseIterable` with a distinct spoken string per case, so the accessibility walk-tests — which
/// hold that no two states sound alike — cover every form written after them.
public enum ThroBasis: String, CaseIterable, Sendable, Equatable {
    /// Current and computable.
    case exact
    /// The operative figure: on a finish.
    case calledOut
    /// An interval.
    case bounded
    /// Cannot be computed, or has not started.
    case reference
    /// Superseded by the record itself: a bust, a retraction.
    case struck
    /// No measurement exists here at all.
    case absent

    /// What a screen reader adds after the figure. `exact` adds nothing: labelling the common case
    /// would make every number in the app look qualified, which is the opposite of the point.
    ///
    /// Each string is distinct, and a test walks `allCases` to hold that, because the compiler makes
    /// sure every case is *handled* and cannot see a new case handled by speaking an old one's line.
    /// Two states a listener cannot tell apart are one state.
    public var spoken: String {
        switch self {
        case .exact: return ""
        case .calledOut: return "on a finish"
        case .bounded: return "a range"
        case .reference: return "not available"
        case .struck: return "struck from the record"
        case .absent: return "no result recorded"
        }
    }

    /// Whether this basis is drawn at all. `exact` is the common case and draws a plain rule; the
    /// ones that qualify a figure draw something a reader can tell apart at a glance.
    public var qualifies: Bool { self != .exact }
}

/// The mark under a figure that says how far it can be trusted.
///
/// **Drawn only at `heading2` (25 pt) and above.** Below that, the basis is carried by the
/// `Tag(shape: .basis)` word and the note beside it. Six rule forms at 13 pt in a fixture list is a
/// distinction of a few points of ink, which is a distinction nobody makes.
public struct BasisRule: Shape {
    private let basis: ThroBasis
    private let figureWidth: CGFloat
    private let capHeight: CGFloat
    private let seedAngle: Double

    public init(_ basis: ThroBasis, figureWidth: CGFloat, capHeight: CGFloat, seedAngle: Double = 0) {
        self.basis = basis
        self.figureWidth = figureWidth
        self.capHeight = capHeight
        self.seedAngle = seedAngle
    }

    /// The smallest role this vocabulary is drawn at, in points.
    public static let readableFrom: CGFloat = 25

    public func path(in rect: CGRect) -> Path {
        guard figureWidth > 0 else { return Path() }
        let weight = ThroSpacing.spaceChalkRuleWeight
        let gap = ThroSpacing.spaceChalkRuleWeight
        let width = min(figureWidth, rect.width)
        let x0 = rect.midX - width / 2, x1 = rect.midX + width / 2
        let y = rect.minY + weight / 2
        var path = Path()
        switch basis {
        case .exact:
            path.addPath(rule(from: x0, to: x1, y: y, weight: weight))
        case .calledOut:
            // The board's own double ring, reduced to two rules. A finish is the one thing a player
            // wants to know before they look up, and it is the only figure that gets two of anything.
            path.addPath(rule(from: x0, to: x1, y: y, weight: weight))
            path.addPath(rule(from: x0, to: x1, y: y + weight + gap, weight: weight, seed: 71))
        case .bounded:
            // A span with an end-stop turned inward at each end: an interval has two ends and the
            // ticks are what stop it reading as a rule that happens to be short.
            let thin = max(2, weight - 1)
            path.addPath(rule(from: x0, to: x1, y: y, weight: thin))
            let tick: CGFloat = 8
            for x in [x0 + thin / 2, x1 - thin / 2] {
                path.addRect(CGRect(x: x - thin / 2, y: y - thin / 2, width: thin, height: tick))
            }
        case .reference:
            // Dashed, 4 on 4 off. Not available and not yet started are the same statement — the
            // figure has no value *here*, and the reason is written beside it.
            var x = x0
            while x < x1 {
                path.addPath(rule(from: x, to: min(x + 4, x1), y: y, weight: weight,
                                  seed: Double(x)))
                x += 8
            }
        case .struck:
            // Two segments with the bar through the gap, drawn in the board's own colour by the
            // caller: chalk scraped off, not chalk added. Adding a bright line over a number is a
            // different statement from taking one away, and the record still shows what was written.
            let inset = width * 0.18
            path.addPath(rule(from: x0, to: rect.midX - inset, y: y, weight: weight))
            path.addPath(rule(from: rect.midX + inset, to: x1, y: y, weight: weight, seed: 113))
        case .absent:
            // Nothing at all. There is no measurement here to qualify.
            break
        }
        return path
    }

    private func rule(from x0: CGFloat, to x1: CGFloat, y: CGFloat,
                      weight: CGFloat, seed: Double = 0) -> Path {
        guard x1 > x0 else { return Path() }
        return ChalkRule.band(from: CGPoint(x: x0, y: y), to: CGPoint(x: x1, y: y),
                              weight: weight, roughness: ChalkRule.roughness,
                              seedAngle: seedAngle + seed, trim: 1)
    }

    /// How tall the rule is, so a caller can reserve the space without measuring a path.
    public static func height(_ basis: ThroBasis) -> CGFloat {
        switch basis {
        case .absent: return 0
        case .calledOut: return 2 * ThroSpacing.spaceChalkRuleWeight + ThroSpacing.spaceChalkRuleWeight
        case .bounded: return 8
        default: return ThroSpacing.spaceChalkRuleWeight
        }
    }
}
