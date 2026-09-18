import SwiftUI
import ThroTokens

/// One set of numbers for a row, because there were three (PD-144).
///
/// **What was wrong.** THRØ has a generated token layer and the app obeys it, and yet a row — which is most
/// of this app — was built three times with three different sets of numbers. `CardRow` stood 56 points tall,
/// `LinkRow` 52, and `SettingsRow` set no height at all and used a bare `12` for its gap where every other
/// row used the token. Four points of difference between two screens is not seen and is felt: a player
/// going from Settings to their profile to a team meets three rhythms and reads it as three apps.
///
/// That is the diagnosis the design research landed on. The scale was never the problem — the *vocabulary*
/// was. There is no argument for 52 over 56; there was only nobody to ask.
///
/// **What this is, and what it is not.** It is the row's measurements, named once. It is deliberately not a
/// single `ThroRow` component: the three rows differ in what they *hold* — an icon tile and two lines, an
/// icon and a chevron, an icon and a value — and collapsing those into one view with three modes would
/// trade a felt inconsistency for a knot. The numbers are what a player feels. The contents are what the
/// screen means.
public enum ThroRowMetrics {
    /// How tall a row stands. 56, which is `CardRow`'s — the taller of the two, because it is the one that
    /// carries two lines of text, and a row that fits its contents at the largest text is worth four points.
    /// It is also Material's one-line list height, which is not why it was chosen but is a reassurance.
    public static let height: CGFloat = 56

    /// The gap between a row's icon and its words.
    public static let gap: CGFloat = ThroSpacing.spacing3

    /// The smallest a row may be when its contents are smaller than `height` — the touch target, never less.
    public static let minimum: CGFloat = ThroSpacing.touchTargetMinimum
}

/// One set of numbers for a card, because there were two (PD-144).
///
/// `DeskCard` padded itself 16 and `ContinueCard` 20, and both sit on the same screens — a match in
/// progress above a task waiting on you, four points apart, with nothing to say why. The same fault as the
/// rows and with the same answer: the numbers are named once, and a screen that wants a different one has
/// to say so out loud.
///
/// 20, which is `ContinueCard`'s. A card's padding is the space that makes it read as an object rather
/// than a boxed paragraph, and the more generous of the two is the one doing that job.
public enum ThroCardMetrics {
    /// The space between a card's edge and its words.
    public static let padding: CGFloat = ThroSpacing.spaceGutterIos

    /// The card's corner. Named here so the fill, the border and the press style cannot disagree.
    public static let radius: CGFloat = ThroSpacing.radiusCard
}

/// What a field stands at (PD-144). Not a row: a field is something a person types into and a row is
/// something they read or tap, and the two are allowed to differ — but each only once. 52, which is what
/// every field in the app was already using, with `LeagueScreens`' result field the one that had drifted
/// to 56.
public enum ThroFieldMetrics {
    public static let height: CGFloat = 52
}

/// Where a page's top ends, named once for each of its two faces (PD-145).
///
/// **THRØ has two faces and that is right.** *Paper* is the plain top a pushed screen uses — a hairline,
/// a back chevron, a title. *Board* is the green field with chalk on it, which is what makes the app look
/// like itself. The design research counted six ways to top a page and called that the fault; counted
/// again, three of the six are not vocabularies at all but **board-face headers carrying something
/// specific**: Home's wordmark, You's person, a match's scoreline. Each is deliberate and one of them is
/// the founder's own instruction — a large title in a system bar is what every app on the phone opens
/// with, and the word for that was *generic*.
///
/// **What was actually wrong was the measurement.** All three board headers agreed on the side gutter and
/// disagreed on the gap beneath them: 24 points under Home's masthead, 24 or 16 under You's, 20 under a
/// board header. So the green field ended a different distance above the first thing on the page
/// depending on which screen you were on, and a player moving between them felt the page shift without
/// being able to say why. That is the whole of "three different tops in three taps".
public enum ThroHeaderMetrics {
    /// The side gutter. The one thing all of them already agreed on, named so it stays that way.
    public static let gutter: CGFloat = ThroSpacing.spaceScreenGutter

    /// Above a board header's contents. Small when a back chevron is already occupying that space.
    public static func boardTop(hasBack: Bool, oneLine: Bool) -> CGFloat {
        if hasBack { return ThroSpacing.spacing1 }
        return oneLine ? ThroSpacing.spacing3 : ThroSpacing.spacing6
    }

    /// Beneath a board header, where the field meets the page. **One number**, because this is the one a
    /// player feels moving from screen to screen.
    public static func boardBottom(oneLine: Bool) -> CGFloat {
        oneLine ? ThroSpacing.spacing3 : ThroSpacing.spacing5
    }

    /// The paper bar's own insets. It is a bar rather than a field, so it sits tighter, and it carries a
    /// hairline instead of a colour change to say where it ends.
    public static let paperTop: CGFloat = ThroSpacing.spacing3
    public static let paperBottom: CGFloat = ThroSpacing.spacing4
}
