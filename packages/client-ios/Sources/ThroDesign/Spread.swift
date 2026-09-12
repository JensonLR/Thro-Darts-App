import SwiftUI
import ThroTokens

// When a screen is two things, and when it is one (PD-062).
//
// `ThroReadable` holds a screen to 560 points because a paragraph 1,000 points wide is not a phone screen
// made bigger, it is a phone screen pulled apart. That is right for a screen that is ONE thing and it is the
// wrong answer for a screen that is two: a league's table and the fixtures it came from are separate objects
// that a reader compares, and stacking them on a tablet leaves half the glass empty and puts the next
// fixture below the fold of a screen with room for both.
//
// So: **one thing, one column; two things, two columns, once there is room for two readable ones.** The
// rule is arithmetic on the width available, in the same shape `ThroStage` chooses between a board above its
// keys and a board beside them.
//
// What counts as room is derived rather than picked, because a threshold chosen next to a justification it
// does not satisfy is a number nobody checked. A column must be at least `narrowestColumn` wide; the screen
// that spreads is the narrowest one that fits two of those with a gutter between. Below it the pair stacks
// and each half gets the full readable measure, so a phone is exactly what it was.

/// Whether a screen has room to put two things side by side, and how wide each gets.
public enum ThroSpread {

    /// The gap between them. Wider than a card's padding, because these are two objects and not two halves
    /// of one, and a reader has to see the seam without a rule being drawn down it.
    public static let gutter: CGFloat = ThroSpacing.spaceSectionGap

    public enum Arrangement: Equatable, Sendable {
        /// One under the other, each at the readable measure — every phone held upright.
        case stacked
        /// Beside each other — a tablet, and a phone on its side.
        case sideBySide
    }

    /// The narrowest a column may be and still be worth splitting for.
    ///
    /// An iPhone SE is 320 points wide and every component in THRØ is proven at its 280 points of content,
    /// so 340 is that with margin — comfortably enough for a table row or a fixture, neither of which is
    /// prose. A column narrower than this is two things crushed rather than two things shown.
    public static let narrowestColumn: CGFloat = 340

    /// The narrowest screen that gets two columns: two of `narrowestColumn`, with the gutter between them.
    ///
    /// This falls out of the two numbers above rather than being chosen. Where it lands: a phone upright is
    /// 320–440 and stacks; an SE on its side is 568 and stacks, which is right, because 568 does not fit
    /// two readable columns. A 13 mini on its side is 812 and a 17 Pro is 874, and both spread — a short
    /// screen gains most from not stacking. A tablet is 834 upright and 1194 on its side, and spreads
    /// either way.
    public static let narrowest: CGFloat = narrowestColumn * 2 + gutter

    /// The widest the pair is allowed to get, so two columns on a 13-inch tablet are two columns and not
    /// two rooms. 960 is two of 464 with the gutter between — each still inside a readable measure.
    public static let measure: CGFloat = 960

    public static func arrangement(forWidth width: CGFloat) -> Arrangement {
        width >= narrowest ? .sideBySide : .stacked
    }

    /// How wide one of the two columns is on a screen this wide. Meaningless when stacked, where each half
    /// gets `ThroReadable.measure` like any other page.
    public static func columnWidth(forWidth width: CGFloat) -> CGFloat {
        max(0, (min(width, measure) - gutter) / 2)
    }
}

/// Two things on a page: side by side where the screen has room, one under the other where it has not.
///
/// The width comes from the caller rather than a `GeometryReader` inside, because this usually lives in a
/// scroll view and a geometry reader in one takes all the height it can reach.
public struct ThroBeside<Lead: View, Aside: View>: View {
    private let width: CGFloat
    private let split: Bool
    private let lead: Lead
    private let aside: Aside

    /// [split] is the caller saying whether there really are two things right now.
    ///
    /// **A half with nothing in it is worse than no split at all** (PD-069). Splitting on width alone put
    /// the You tab's teams in the right-hand column with an empty left half on a tablet where nobody had
    /// played yet — a hole where content should be, which reads as a page that failed rather than as a page
    /// with one thing on it. SwiftUI cannot ask a view whether it is empty, so the caller answers: pass
    /// false when the condition that fills one half is not met, and the pair stacks as it does on a phone.
    public init(width: CGFloat, split: Bool = true,
                @ViewBuilder lead: () -> Lead, @ViewBuilder aside: () -> Aside) {
        self.width = width
        self.split = split
        self.lead = lead()
        self.aside = aside()
    }

    public var body: some View {
        switch split ? ThroSpread.arrangement(forWidth: width) : .stacked {
        case .sideBySide:
            HStack(alignment: .top, spacing: ThroSpread.gutter) {
                lead.frame(maxWidth: .infinity, alignment: .topLeading)
                aside.frame(maxWidth: .infinity, alignment: .topLeading)
            }
            .frame(maxWidth: ThroSpread.measure, alignment: .topLeading)
            .frame(maxWidth: .infinity)
        case .stacked:
            VStack(alignment: .leading, spacing: ThroSpread.gutter) {
                lead
                aside
            }
            .throReadable()
        }
    }
}
