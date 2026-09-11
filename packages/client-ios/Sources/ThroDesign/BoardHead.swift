import SwiftUI
import ThroTokens

// SLATE D.2 and D.3 — what a board actually shows: both scores, and the leg so far.
//
// The scoring screen shows the thrower's remaining at 96 pt and the opponent's at 13 pt inside a
// row of chrome. **The opponent's score is the second-most-asked question in darts** and it is the
// smallest text on the screen. And there is no running column of visit totals at all — the
// century-old affordance every paper scoresheet has, and the only way a player catches a mis-key
// without replaying the leg in their head.
//
// The founder, relaying a player in a local league: *"Just make what's needed big — that's the main
// hiccup u see."* This is that, arithmetically: two registers at the rung `ThroStage` chose, side by
// side, on the same baseline, with the leg's visits beneath them.

/// One column of the head: a player, their remaining, and how the app knows it.
public struct ThroBoardColumn: Equatable, Sendable {
    public let name: String
    public let remaining: Int
    public let basis: ThroBasis
    /// Whether this is the player about to throw.
    public let throwing: Bool

    public init(name: String, remaining: Int, basis: ThroBasis, throwing: Bool) {
        self.name = name
        self.remaining = remaining
        self.basis = basis
        self.throwing = throwing
    }
}

/// The head of the board: two players, two numbers, and the legs between them.
///
/// **Whose throw it is, carried three ways and none of them colour.** The `calledOut` double rule
/// under the thrower's column is a shape 150 points wide; the 45° marker beside their name is the
/// founder's own mark; and the word says it. Nothing here depends on telling green from red.
public struct ThroBoardHead: View {
    private let home: ThroBoardColumn
    private let away: ThroBoardColumn
    private let legs: String
    private let format: String?
    private let stage: ThroStage

    public init(home: ThroBoardColumn, away: ThroBoardColumn, legs: String,
                format: String?, stage: ThroStage) {
        self.home = home
        self.away = away
        self.legs = legs
        self.format = format
        self.stage = stage
    }

    /// The role each column's figure takes. The thrower gets the rung the stage chose; the opponent
    /// gets one rung down — legible without competing, rather than legible-only-if-you-look.
    func role(throwing: Bool) -> ThroTypeRole {
        ThroTypography.boardHero.sized(throwing ? stage.hero : stage.opponent)
    }

    public var body: some View {
        HStack(alignment: .top, spacing: ThroStage.columnGap) {
            column(home, alignment: .leading)
            VStack(spacing: 2) {
                Text(legs)
                    .thro(ThroTypography.heading1.family(.sport).weight(.bold).tracking(em: 0))
                    .foregroundStyle(ThroColor.colorTextOnBoard)
                if let format {
                    Text(format)
                        .thro(ThroTypography.eyebrow)
                        .foregroundStyle(ThroColor.colorTextOnBoardSecondary)
                        .multilineTextAlignment(.center)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
            }
            .frame(width: ThroStage.legsColumn)
            .accessibilityElement(children: .combine)
            column(away, alignment: .trailing)
        }
        .padding(.horizontal, ThroStage.gutter)
    }

    @ViewBuilder
    private func column(_ player: ThroBoardColumn, alignment: HorizontalAlignment) -> some View {
        VStack(alignment: alignment, spacing: ThroSpacing.spacing1) {
            HStack(spacing: ThroSpacing.spacing1) {
                if player.throwing {
                    // The founder's own bar, at the size of a word. Not a dot, not a chevron.
                    ChalkStrike(figureWidth: 8, capHeight: 12)
                        .fill(ThroColor.colorTextOnBoard)
                        .frame(width: 14, height: 14)
                }
                Text(player.name)
                    .thro(ThroTypography.label.weight(.bold).uppercase(true).tracking(em: 0.06))
                    .foregroundStyle(player.throwing ? ThroColor.colorTextOnBoard
                                                     : ThroColor.colorTextOnBoardSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            ThroFigure("\(player.remaining)", role: role(throwing: player.throwing), cells: 3,
                       basis: player.basis,
                       ink: player.throwing ? ThroColor.colorTextOnBoard
                                            : ThroColor.colorTextOnBoardSecondary)
        }
        .frame(maxWidth: .infinity, alignment: alignment == .leading ? .leading : .trailing)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(ThroBoardHead.spoken(player))
    }

    /// What a screen reader is told about one column. The throw is spoken, because a listener gets
    /// no marker and no double rule.
    static func spoken(_ player: ThroBoardColumn) -> String {
        let basis = player.basis.spoken
        let throwing = player.throwing ? ", to throw" : ""
        return basis.isEmpty
            ? "\(player.name) requires \(player.remaining)\(throwing)"
            : "\(player.name) requires \(player.remaining), \(basis)\(throwing)"
    }
}

// MARK: - The ledger

/// One line of the leg: what was scored, and what was left.
public struct ThroLedgerRow: Identifiable, Equatable, Sendable {
    public let id: String
    public let seat: Int
    public let legOrdinal: Int
    public let visitTotal: Int
    /// What stood on the board after it. **Optional**, because a struck visit the engine can no
    /// longer apply has no remainder this build can reproduce — and a dash there is the honest
    /// answer, where a zero would be a score nobody threw.
    public let remainingAfter: Int?
    /// Superseded by the record itself — a retraction. **Drawn struck and left where it is**, never
    /// removed: a retraction in the journal is an `INSERT` carrying `corrects_seq`, and a screen
    /// that made it disappear would be saying something the record does not.
    public let struck: Bool

    public init(id: String, seat: Int, legOrdinal: Int, visitTotal: Int,
                remainingAfter: Int?, struck: Bool) {
        self.id = id
        self.seat = seat
        self.legOrdinal = legOrdinal
        self.visitTotal = visitTotal
        self.remainingAfter = remainingAfter
        self.struck = struck
    }
}

/// The running column of visit totals, newest at the bottom, growing upward.
///
/// **Three declared states and no fourth**, chosen by `ThroStage` from measured height: rows, a
/// tally strip, or nothing. A list that is cut off at the bottom is the one outcome that makes a
/// player doubt what is on the board, so it is not one of the three.
public struct ThroLedger: View {
    private let rows: [ThroLedgerRow]
    private let stage: ThroStage
    private let names: (Int) -> String

    public init(rows: [ThroLedgerRow], stage: ThroStage, names: @escaping (Int) -> String) {
        self.rows = rows
        self.stage = stage
        self.names = names
    }

    /// The rows for one seat, most recent last, cut to what the stage said would fit. The cut is
    /// from the FRONT: a leg's oldest visits are the ones a player has stopped needing.
    static func visible(_ rows: [ThroLedgerRow], seat: Int, limit: Int) -> [ThroLedgerRow] {
        let mine = rows.filter { $0.seat == seat }
        guard limit > 0, mine.count > limit else { return mine }
        return Array(mine.suffix(limit))
    }

    /// The row whose remainder is what stands on the board for this seat: the last one no
    /// retraction struck. Every earlier remainder was written over, and is drawn the way a chalker
    /// draws it — **one line through it, still legible under the line** — because the column is a
    /// chalkboard and that is what a chalkboard does when a new figure goes under an old one. The
    /// standing figure is the one number in the column with no line through it, which is how a
    /// player at the oche finds it without reading.
    static func standing(_ rows: [ThroLedgerRow], seat: Int) -> String? {
        rows.last { $0.seat == seat && !$0.struck }?.id
    }

    /// Written over by a later visit. A retracted row is not superseded — it is scraped, which is
    /// a different mark for a different thing, and a row never carries both.
    static func isSuperseded(_ row: ThroLedgerRow, in rows: [ThroLedgerRow]) -> Bool {
        !row.struck && standing(rows, seat: row.seat) != row.id
    }

    /// The last five visit totals, for the strip that stands in when there is no room for rows.
    static func tally(_ rows: [ThroLedgerRow], seat: Int) -> [Int] {
        rows.filter { $0.seat == seat && !$0.struck }.suffix(5).map(\.visitTotal)
    }

    /// **One accessibility element, not one per row.** Six rows between the score and the keypad on
    /// the highest-traffic screen in the product is six swipes a player pays on every visit.
    static func spoken(_ rows: [ThroLedgerRow], names: (Int) -> String) -> String {
        let seats = Set(rows.map(\.seat)).sorted()
        let parts = seats.map { seat -> String in
            let mine = rows.filter { $0.seat == seat }
            let said = mine.map { row -> String in
                guard !row.struck else { return "\(row.visitTotal) struck" }
                guard let left = row.remainingAfter else { return "\(row.visitTotal), not recorded" }
                return "\(row.visitTotal), \(left)"
            }
            return "\(names(seat)): " + (said.isEmpty ? "nothing yet" : said.joined(separator: ". "))
        }
        return parts.joined(separator: ". ")
    }

    public var body: some View {
        Group {
            switch stage.ledger {
            case let .rows(limit):
                HStack(alignment: .bottom, spacing: ThroStage.columnGap) {
                    ForEach([0, 1], id: \.self) { seat in
                        column(seat: seat, limit: limit)
                    }
                }
            case .tally:
                HStack(spacing: ThroStage.columnGap) {
                    ForEach([0, 1], id: \.self) { seat in
                        Text(ThroLedger.tally(rows, seat: seat).map(String.init).joined(separator: "  "))
                            .thro(ThroTypography.metadata.family(.sport))
                            .foregroundStyle(ThroColor.colorTextOnBoardSecondary)
                            .lineLimit(1)
                            .frame(maxWidth: .infinity, alignment: seat == 0 ? .leading : .trailing)
                    }
                }
                .frame(height: ThroStage.tallyHeight)
            case .hidden:
                EmptyView()
            }
        }
        .padding(.horizontal, ThroStage.gutter)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Visits this leg")
        .accessibilityValue(ThroLedger.spoken(rows, names: names))
    }

    @ViewBuilder
    private func column(seat: Int, limit: Int) -> some View {
        let role = ThroTypography.heading3.family(.sport)
        VStack(alignment: seat == 0 ? .leading : .trailing, spacing: 0) {
            ForEach(ThroLedger.visible(rows, seat: seat, limit: limit)) { row in
                let superseded = ThroLedger.isSuperseded(row, in: rows)
                HStack(spacing: ThroSpacing.spacing3) {
                    Text("\(row.visitTotal)")
                        .thro(role.tracking(em: 0))
                        .foregroundStyle(ThroColor.colorTextOnBoardSecondary)
                    Text(row.remainingAfter.map { "\($0)" } ?? "—")
                        .thro(role.weight(.bold).tracking(em: 0))
                        // The figure on the board is the bright one; the ones written over step
                        // back, so the column reads bottom-up without being read.
                        .foregroundStyle(superseded ? ThroColor.colorTextOnBoardSecondary : ThroColor.colorTextOnBoard)
                        .overlay {
                            if superseded {
                                // The chalker's line: fresh chalk through an old remainder, at a
                                // hand's angle, sized to the figure it strikes.
                                ChalkStrike(capHeight: role.capHeight, angle: ChalkStrike.boardAngle)
                                    .fill(ThroColor.colorTextOnBoard)
                            }
                        }
                }
                .frame(height: ThroStage.ledgerRow)
                .overlay {
                    if row.struck {
                        // A retraction: chalk scraped off, in the board's own colour, across the
                        // whole row. The row stays where it is.
                        ChalkStrike(capHeight: role.capHeight, angle: ChalkStrike.boardAngle)
                            .fill(ThroColor.colorBoardField)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: seat == 0 ? .leading : .trailing)
    }
}

// MARK: - The confirmation

/// What the board says back when a score goes on it.
///
/// The founder: *"We need cool pop up notifications/banners on screen when scores are entered to
/// confirm them."* Today a committed visit produces a haptic and the number changes, and nothing
/// states what was recorded — so a player who half-saw the screen has to work backwards from the
/// remainder to check their own entry.
///
/// It is **not** an iOS toast. On a board, a score is chalked: the total appears where the chalk
/// would land, holds long enough to read, and goes. Three kinds, because the three things that can
/// happen to an entry already have three distinct haptics and need three distinct sights.
public struct ThroChalkMark: Equatable, Sendable {
    public enum Kind: String, CaseIterable, Sendable {
        /// It went on the board.
        case scored
        /// It could not: a bust. The score is restored and the darts did not count.
        case bust
        /// It was refused before it reached the board — a total no three darts can make, or one
        /// that cannot open under double-in.
        case refused
    }

    public let kind: Kind
    public let figure: String
    public let detail: String?

    public init(kind: Kind, figure: String, detail: String? = nil) {
        self.kind = kind
        self.figure = figure
        self.detail = detail
    }

    /// How long the mark stays. Long enough to read a three-digit number and glance away; short
    /// enough that the next visit is never waiting behind it.
    public static let dwell: Double = 1.1

    /// The basis each kind is drawn with. A bust is `struck` because that is what the record did to
    /// it, and a refusal is `absent` because nothing was ever written.
    public var basis: ThroBasis {
        switch kind {
        case .scored: return .exact
        case .bust: return .struck
        case .refused: return .absent
        }
    }

    /// The ink. All three are on the contrast matrix against every board ground.
    public var ink: Color {
        switch kind {
        case .scored: return ThroColor.colorTextOnBoard
        case .bust: return ThroColor.colorStatusErrorOnBoard
        case .refused: return ThroColor.colorStatusWarningOnBoard
        }
    }

    /// One sentence, spoken once. The keypad already announces what was typed, so this announces
    /// what became of it and never repeats the entry back.
    public var spoken: String {
        switch kind {
        case .scored: return detail.map { "\(figure) scored. \($0)" } ?? "\(figure) scored"
        case .bust: return detail.map { "Bust. \($0)" } ?? "Bust. Score restored"
        case .refused: return detail ?? "Not accepted"
        }
    }

    /// The haptic that goes with it — the vocabulary that already exists, so what is felt and what
    /// is seen cannot drift apart.
    public var haptic: ThroHaptics.Event {
        switch kind {
        case .scored: return .commit
        case .bust, .refused: return .refused
        }
    }
}

/// The mark, drawn. Sits over the board, takes no layout height, and never covers the numerals it
/// is confirming — it lands under the head, where a scorer's hand would be.
public struct ThroChalkMarkView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private let mark: ThroChalkMark

    public init(_ mark: ThroChalkMark) { self.mark = mark }

    public var body: some View {
        HStack(spacing: ThroSpacing.spacing3) {
            Text(mark.figure)
                .thro(ThroTypography.heading1.family(.sport).weight(.bold).tracking(em: 0))
                .foregroundStyle(mark.ink)
            if let detail = mark.detail {
                Text(detail)
                    .thro(ThroTypography.label.uppercase(true).tracking(em: 0.06))
                    .foregroundStyle(ThroColor.colorTextOnBoardSecondary)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, ThroSpacing.spacing2)
        .padding(.horizontal, ThroSpacing.spacing4)
        .background(ThroColor.colorBoardSunken)
        .overlay(ChalkBox().fill(ThroColor.colorMarkOnBoard))
        .overlay {
            if mark.kind == .bust {
                ChalkStrike(capHeight: ThroTypography.heading1.family(.sport).capHeight).fill(ThroColor.colorBoardField)
            }
        }
        .transition(reduceMotion
                    ? .opacity
                    : .asymmetric(insertion: .scale(scale: 1.12).combined(with: .opacity),
                                  removal: .opacity))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(mark.spoken)
    }
}
