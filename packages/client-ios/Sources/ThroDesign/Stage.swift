import SwiftUI
import ThroTokens

// The scoring screen's shape, as a pure function of the room it has.
//
// **Why this is a value and not a view.** PD-005 made the scoring screen fit without scrolling, and the
// first way to guarantee that was to choose a portrait phone and lock the app to it — a decision the app
// could not re-examine at runtime. Turning those switches on without something behind them would have
// shipped a portrait layout squeezed into 390 points of height, which is worse than not offering landscape
// at all. **That something is this file**, so the switches are on: the project builds
// `TARGETED_DEVICE_FAMILY = "1,2"` with iPhone landscape and all four iPad orientations. This comment said
// the opposite until 2026-09-12, which is how thirty-three screens came to be written as though nobody
// would ever see them on a tablet (PD-052).
//
// So the shape is decided here, by arithmetic, from the width and height actually available and the
// player's own text size — and because it is a pure function it can be held to the one claim that
// matters on this screen: **on every device THRØ runs on, in every orientation, at every text size,
// the scoring screen fits without scrolling and every key is still big enough to hit.** A test
// enumerates the devices rather than trusting a preview.
//
// SLATE's D.3 chose the ledger's density from a measured height; this is the same idea applied to
// the whole screen, which is what the request for landscape and tablets actually needs.

/// How the scoring screen is arranged and at what density.
public struct ThroStage: Equatable, Sendable {

    /// Where the tray of keys sits relative to the board.
    public enum Arrangement: String, CaseIterable, Sendable {
        /// The board above, the keys below. A phone held upright, and a tablet held upright.
        case stacked
        /// The board beside the keys. A phone or a tablet turned on its side — which is the shape a
        /// scoreboard has always had, and the shape the oche gives you when the phone is propped up.
        case beside
    }

    /// What the ledger can show in the room it is left. Never a clipped list.
    public enum Ledger: Equatable, Sendable {
        /// Full rows of visit total and remainder, newest at the bottom.
        case rows(Int)
        /// One strip of the last five visit totals. Less than a ledger, still the running count.
        case tally
        /// Nothing. The screen is too short to say anything honest about the leg's history.
        /// Named `hidden` and not `none`: `.none` on an enum collides with `Optional.none` wherever
        /// the context is optional, and the compiler resolves it without saying which it picked.
        case hidden
    }

    public let arrangement: Arrangement
    /// The thrower's numeral, in points. Always a rung of `ThroTypography.ladder`.
    public let hero: CGFloat
    /// The opponent's numeral. One rung down, so it is legible without competing.
    public let opponent: CGFloat
    public let ledger: Ledger
    /// Whether the checkout route is drawn under the head.
    ///
    /// **The second thing to give way, after the ledger and before anything else.** The route is a
    /// suggestion; the number, the keys and the darts being entered are the product. It goes only
    /// where the board cannot hold its own furniture plus the smallest rung of the ladder — which,
    /// across eleven devices both ways up at every text size, is the iPhone SE upright while a
    /// player is entering darts, and nowhere else at all.
    public let checkout: Bool
    /// The height of one key in the tray.
    public let keyHeight: CGFloat
    /// How wide the tray is as a fraction of the screen, in `beside`. Zero when stacked.
    public let trayFraction: CGFloat

    // MARK: - The measurements the screen is built from

    /// The rail: 6 + a 44 pt control + 6.
    public static let rail: CGFloat = 52

    /// The line of three darts, when the player is scoring dart by dart: a 44 pt row and the gap
    /// above it.
    ///
    /// It is on the board rather than in the tray because it is what is being written, and because
    /// a player checks it against what they threw while they are still looking at the board. It is
    /// counted here rather than drawn hopefully: a row the arithmetic does not know about is a row
    /// that clips on the smallest phone, and this screen's one promise is that it never does.
    public static let dartLine: CGFloat = ThroSpacing.touchTargetMinimum + ThroSpacing.spacing2
    /// The head's fixed furniture — names, the gap, the basis rules, and its padding — everything
    /// except the numerals themselves, whose height is the cap box of whichever rung is chosen.
    public static let headFurniture: CGFloat = 63
    /// What a checkout route adds to the head when the thrower is on a finish.
    public static let checkoutRow: CGFloat = 39
    /// One ledger row.
    public static let ledgerRow: CGFloat = 24
    /// Below this the ledger becomes the tally strip.
    public static let ledgerFloor: CGFloat = 96
    /// The tally strip.
    public static let tallyHeight: CGFloat = 28
    /// Six rows of keys, five gaps, and the tray's own padding.
    public static let trayRows: CGFloat = 6
    public static let trayGap: CGFloat = 6
    public static let trayPadding: CGFloat = 20
    /// The tray at its intended size. `6 × 64 + 5 × 6 + 20`.
    public static let trayIdeal: CGFloat = trayRows * ThroSpacing.touchTargetScoring
        + (trayRows - 1) * trayGap + trayPadding

    /// The gutter each side, and the gap between the two score columns.
    public static let gutter: CGFloat = ThroSpacing.spaceScreenGutter
    public static let columnGap: CGFloat = ThroSpacing.spacing4
    /// The middle column of the head — the legs score and the format under it ("0–0", "BEST OF 5").
    /// It sits between the two registers and takes width the registers cannot have. The rung was
    /// chosen as if it were not there, and on a phone the away register ran off the right edge; the
    /// founder saw a 501 with its last digit missing. 76 points holds "BEST OF 5" at the eyebrow
    /// role; the head lets a wider format label ("BEST OF 11") shrink to fit rather than widen
    /// the column, because the number is the product and the label is furniture.
    public static let legsColumn: CGFloat = 76

    /// A screen is laid out beside its keys once it is this much wider than it is tall. Phone
    /// landscape (844 × 390) is 2.16 and a landscape tablet (1180 × 820) is 1.44; a tablet held
    /// upright (820 × 1180) is 0.69 and stays stacked, because a tall screen has room for the board
    /// above the keys and that is the better reading.
    public static let besideRatio: CGFloat = 1.2

    /// The widest the tray is allowed to get when it sits beside the board. A keypad that grows
    /// with a 13-inch tablet is a keypad whose keys are further apart than a hand.
    public static let trayMaximum: CGFloat = 420

    // MARK: - Choosing

    /// The shape for a given screen.
    ///
    /// `textScale` is the ratio the player's Dynamic Type setting applies to the type — 1.0 at the
    /// default, up to about 1.35 at the accessibility sizes this app supports. It is passed in
    /// rather than read, so this stays a pure function and a test can walk the range.
    public static func choose(width: CGFloat, height: CGFloat,
                              onAFinish: Bool = false,
                              perDart: Bool = false,
                              textScale: CGFloat = 1) -> ThroStage {
        let arrangement: Arrangement = width >= height * besideRatio ? .beside : .stacked
        let trayWidth = arrangement == .beside ? min(trayMaximum, width * 0.42) : width
        let boardWidth = arrangement == .beside ? width - trayWidth : width
        let dart = perDart ? dartLine : 0

        // **The least the board can honestly be drawn in**, and the tray may not take it.
        //
        // Its furniture, the line of darts when there is one, and the smallest rung of the ladder.
        // The checkout row is deliberately not in it. The order of sacrifice on this screen is
        // the ledger, then the route, then the tray's comfort — never the number — so reserving
        // room here for the thing that gives way second would take it from the number instead.
        //
        // The tray used to take `trayIdeal` unconditionally and the board took what was left, which
        // was right while the board's contents were fixed. Adding a row to the board broke it: on
        // the iPhone SE upright at the largest accessibility sizes, a player entering darts got a
        // board 5 points shorter than its own smallest layout — and `keysFit` would have reported a
        // comfortable 64 pt key sitting above a clipped board.
        let boardFloor = headFurniture + dart
            + capBox(ThroTypography.ladder.last ?? 40, textScale: textScale)

        // The tray's height. Stacked, it takes what it needs and no more than is left; beside, it
        // has the whole screen. A key never goes below the accessibility floor, and a tray that
        // still does not fit is a failure `keysFit` reports rather than one this hides.
        let trayRoom = arrangement == .beside ? height : min(trayIdeal, max(0, height - rail - boardFloor))
        let keyHeight = max(ThroSpacing.touchTargetMinimum,
                            min(ThroSpacing.touchTargetScoring,
                                ((trayRoom - trayPadding - (trayRows - 1) * trayGap) / trayRows).rounded(.down)))
        let trayHeight = arrangement == .beside
            ? height
            : trayRows * keyHeight + (trayRows - 1) * trayGap + trayPadding

        // What is left for the board: everything but the rail, and — when stacked — the tray.
        let boardHeight = height - rail - (arrangement == .stacked ? trayHeight : 0)

        // The route gives way where the board cannot hold it and the smallest rung together. It is
        // a suggestion; the number is the product.
        var checkout = onAFinish
        var headFixed = headFurniture + (checkout ? checkoutRow : 0) + dart
        if checkout, headFixed + capBox(ThroTypography.ladder.last ?? 40, textScale: textScale) > boardHeight {
            checkout = false
            headFixed = headFurniture + dart
        }

        // The largest rung whose two registers fit across the board AND whose head fits down it,
        // with the ledger's floor still standing. Largest first, so the first that fits wins.
        let usable = boardWidth - 2 * gutter - 2 * columnGap - legsColumn
        let hero = ladderRung(usable: usable, boardHeight: boardHeight,
                              headFixed: headFixed, textScale: textScale)
        let opponent = ThroTypography.ladder.first { $0 < hero } ?? hero

        let headHeight = headFixed + capBox(hero, textScale: textScale)
        let ledgerRoom = boardHeight - headHeight
        let ledger: Ledger
        if ledgerRoom >= ledgerFloor {
            ledger = .rows(min(6, Int(((ledgerRoom - 20) / ledgerRow).rounded(.down))))
        } else if ledgerRoom >= tallyHeight {
            ledger = .tally
        } else {
            ledger = .hidden
        }

        return ThroStage(arrangement: arrangement, hero: hero, opponent: opponent, ledger: ledger,
                         checkout: checkout, keyHeight: keyHeight,
                         trayFraction: arrangement == .beside ? trayWidth / width : 0)
    }

    /// The biggest rung that fits both ways. Falls to the smallest rather than off the end: a screen
    /// too small for any of them still has to draw a number, and the smallest rung is the honest
    /// floor rather than a crash or a `minimumScaleFactor`.
    static func ladderRung(usable: CGFloat, boardHeight: CGFloat,
                           headFixed: CGFloat, textScale: CGFloat) -> CGFloat {
        let fits = ThroTypography.ladder.first { rung in
            let register = 3 * (ThroFigure.cellRatio * rung * textScale).rounded()
            guard 2 * register <= usable else { return false }
            return headFixed + capBox(rung, textScale: textScale) <= boardHeight
        }
        return fits ?? ThroTypography.ladder.last ?? 40
    }

    /// The cap box for a rung at a given text scale, without touching UIKit — so the choice is a
    /// pure function and a test can walk every device at every text size on any machine.
    static func capBox(_ rung: CGFloat, textScale: CGFloat) -> CGFloat {
        (ThroTypography.capRatio(.sport) * rung * textScale).rounded() + 2
    }

    /// How many rows of visits the ledger will actually draw. Held here so a caller never has to
    /// ask a view what it decided.
    public var ledgerRows: Int {
        if case let .rows(n) = ledger { return n }
        return 0
    }

    /// The height the tray of keys actually takes.
    public var trayHeight: CGFloat {
        ThroStage.trayRows * keyHeight + (ThroStage.trayRows - 1) * ThroStage.trayGap + ThroStage.trayPadding
    }

    /// Whether every key clears the 44 pt target **and** the tray fits the height it was given.
    ///
    /// Both halves, because either alone is a lie. `keyHeight` is clamped at 44 so it never reports
    /// a key nobody could hit — which means on a screen too short for six 44 pt rows the clamp
    /// silently overflows instead, and a check that only read the height would call that fine. The
    /// first version of this did exactly that.
    public func keysFit(in height: CGFloat) -> Bool {
        keyHeight >= ThroSpacing.touchTargetMinimum && trayHeight <= height + 0.5
    }
}
