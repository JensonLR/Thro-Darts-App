import SwiftUI
import ThroTokens

// What the masthead does when the screen is short (PD-061).
//
// THRØ's mastheads were drawn for a phone held upright, where a wordmark stacked over its line costs
// about a seventh of the screen. Turned on its side the same phone is 402 points tall and that masthead
// takes 29% of it before the first card; the You tab's sign-in prompt takes 61%. Those are portrait
// proportions on a screen that is not portrait, and on the screen where THRØ is most likely to be propped
// on a table beside a board.
//
// So on a short screen the masthead folds to one line — the mark and its sentence side by side, at a
// smaller cap — and the page starts where the reader is looking. The rule is arithmetic on the screen, in
// the same shape `ThroStage` chooses between a board above its keys and a board beside them, because a
// number that can be tested is a design decision that cannot quietly drift.

/// How the top of a page introduces itself, given the room it has.
public enum ThroMasthead {

    public enum Shape: Equatable, Sendable {
        /// The mark over its line: what every portrait phone and every tablet gets.
        case stacked
        /// The mark and its line on one row: a phone on its side.
        case oneLine
    }

    /// The shortest screen that still gets the full masthead.
    ///
    /// Every phone THRØ runs on is between 320 and 440 points tall on its side, and between 568 and 956
    /// upright; a tablet is 834 on its side. 500 sits in the gap with room either way, so no portrait
    /// phone folds and no tablet does — a tablet has the height for the full mark and there is nothing
    /// to buy by taking it away.
    public static let shortestTallScreen: CGFloat = 500

    /// The rule.
    public static func shape(forHeight height: CGFloat) -> Shape {
        height < shortestTallScreen ? .oneLine : .stacked
    }

    /// The same rule, as the platform reports it.
    ///
    /// A compact vertical size class is iOS's own name for "a phone on its side", and it is what a view
    /// can read without measuring the window. It agrees with the height rule on every device THRØ runs on
    /// — which is asserted rather than assumed, because two ways of saying one thing is how a rule drifts.
    public static func shape(verticalSizeClassIsCompact compact: Bool) -> Shape {
        compact ? .oneLine : .stacked
    }
}
