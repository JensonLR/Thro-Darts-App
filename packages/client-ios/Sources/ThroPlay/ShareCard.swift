import Foundation
import SwiftUI
import ThroDesign
import ThroJournal
import ThroTokens

// The picture of a result that goes into a group chat.
//
// **This is the one surface that leaves the phone.** Everywhere else, a figure THRØ shows stands
// beside the words that qualify it: a bounded one is marked as a range, an unavailable one is a dash
// with the reason printed under it, and the screen is still there to look at again. An image carries
// nothing but what was drawn into it — it cannot be corrected once it is in somebody's group chat,
// and it outlives the app that made it. So everything the honesty layer normally puts beside a
// figure has to be *on the card itself*, or the card is a claim with no basis, which is the one
// thing this product has said from the start it will not ship.
//
// Four rules follow, and `ShareCardTests` holds each of them:
//
//  1. **The card carries how the result is verified.** Self-reported, both players confirmed, or
//     disputed — never nothing. A shared scoreline with no provenance is exactly the artefact PD-002
//     exists to prevent.
//  2. **The card carries its sample.** Every figure on it is drawn from the visits in this one
//     match, and the card says how many. A number without a sample is a claim.
//  3. **A figure appears only when it is known for both players.** A row where one side is a dash
//     invites the reader to fill it in, and a shared image is read by people who cannot ask. A
//     bounded figure shows its range rather than a point value, the same as everywhere else.
//  4. **A match with no result carries no scoreline.** An abandoned match says nobody won, in the
//     same words the Result screen uses.
//
// Rendered on device with `ImageRenderer` — no server, nothing uploaded, no account. The player
// shares it or does not; nothing is sent either way.

public enum ThroShareCard {

    /// The card in points. Rendered at scale 3, so the image is 1080 × 1350 — 4:5, which is what
    /// iMessage, WhatsApp and Instagram all show without cropping.
    public static let size = CGSize(width: 360, height: 450)
    public static let scale: CGFloat = 3

    /// One line of figures: the label, and the two players' values.
    public struct Figure: Equatable, Sendable {
        public let label: String
        public let home: String
        public let away: String

        public init(label: String, home: String, away: String) {
            self.label = label
            self.home = home
            self.away = away
        }
    }

    /// The legs each side won, drawn under their names on the scoreboard.
    public struct Legs: Equatable, Sendable {
        public let home: Int
        public let away: Int

        public init(home: Int, away: Int) {
            self.home = home
            self.away = away
        }
    }

    /// What kind of evidence stands behind the result, in the words of the card's tag. The sentence
    /// under the tag says the same thing in full; the tag is what an eye lands on first.
    public enum Standing: String, Equatable, Sendable {
        case selfReported = "Self-reported"
        case confirmed = "Confirmed by both players"
        case disputed = "Disputed"
        case noResult = "No result claimed"
    }

    /// Every word on the card. A value type with no view in it, because the words are the part that
    /// can be wrong and a view is a bad place to test them from.
    public struct Copy: Equatable, Sendable {
        /// "Ann wins", or "No result" when nobody did.
        public let headline: String
        /// "3–1". **Nil when there is no result**, and the card draws nothing in its place.
        public let score: String?
        /// The same legs, a side each. Nil exactly when [score] is.
        public let legs: Legs?
        public let homeName: String
        public let awayName: String
        /// Which side won, for the mark beside their name. Nil when nobody did.
        public let winner: Seat?
        /// The retirement or abandonment sentence, when there is one.
        public let caveat: String?
        public let figures: [Figure]
        /// How many visits the figures are drawn from — the sample, on the card.
        public let sample: String
        /// How this result is verified, in a sentence a stranger can weigh.
        public let provenance: String
        /// The same, as the tag over the sentence.
        public let standing: Standing
        /// "501 · Best of 5 · Double out"
        public let format: String
        /// "7 September 2026"
        public let date: String

        public init(headline: String, score: String?, legs: Legs?, homeName: String, awayName: String,
                    winner: Seat?, caveat: String?, figures: [Figure], sample: String,
                    provenance: String, standing: Standing, format: String, date: String) {
            self.headline = headline
            self.score = score
            self.legs = legs
            self.homeName = homeName
            self.awayName = awayName
            self.winner = winner
            self.caveat = caveat
            self.figures = figures
            self.sample = sample
            self.provenance = provenance
            self.standing = standing
            self.format = format
            self.date = date
        }
    }

    /// What the card says about this match.
    ///
    /// Deliberately derived from the session rather than stored, and derived here rather than in the
    /// view, so the four rules above are testable without rendering anything.
    public static func copy(for session: MatchSession) -> Copy {
        let home = session.visits.filter { $0.seat == .home }
        let away = session.visits.filter { $0.seat == .away }
        let visits = home.count + away.count

        return Copy(
            headline: session.resultHeadline,
            // Rule 4. `hasResult` is false for an abandoned match, and there is no scoreline to
            // print for one — the legs stand in the journal, but nobody won them.
            score: session.hasResult ? "\(session.legsWon(.home))–\(session.legsWon(.away))" : nil,
            legs: session.hasResult ? Legs(home: session.legsWon(.home), away: session.legsWon(.away)) : nil,
            homeName: session.name(.home),
            awayName: session.name(.away),
            winner: session.hasResult ? session.winner : nil,
            caveat: session.resultDetail,
            figures: figures(home: session.statistics(for: .home), away: session.statistics(for: .away)),
            sample: sample(visits: visits, legs: session.legsWon(.home) + session.legsWon(.away)),
            provenance: provenance(for: session),
            standing: standing(for: session),
            format: "\(session.record.startingScore) · \(session.lengthLabel) · \(session.outRuleLabel)"
                + (session.inRuleLabel.map { " · \($0)" } ?? ""),
            date: Self.day.string(from: session.record.startedAt))
    }

    /// The figures the card is allowed to show, in the order it shows them.
    ///
    /// Rule 3: a row survives only when **both** players' figures are available. The alternative —
    /// a dash on one side — reads as a zero to somebody who has only the image, and unlike the app
    /// there is nothing to tap for the reason. Where a figure is bounded, the range is what goes on
    /// the card, because a range collapsed to a point value is the exact lie the statistics layer
    /// was built to make impossible.
    static func figures(home: [StatLine], away: [StatLine]) -> [Figure] {
        let wanted = ["3-dart average", "Checkout %", "180s"]
        var out: [Figure] = []
        for label in wanted {
            guard let h = home.first(where: { $0.label == label }),
                  let a = away.first(where: { $0.label == label }),
                  h.confidence != .unavailable, a.confidence != .unavailable else { continue }
            out.append(Figure(label: label, home: h.value, away: a.value))
        }
        return out
    }

    /// Rule 2, in one sentence. Named in visits rather than darts because a visit is what the
    /// journal actually stores; inferring darts from it would be arithmetic the card cannot show.
    static func sample(visits: Int, legs: Int) -> String {
        let v = "\(visits) visit\(visits == 1 ? "" : "s")"
        guard legs > 0 else { return "From \(v) recorded in this match." }
        return "From \(v) across \(legs) leg\(legs == 1 ? "" : "s") recorded in this match."
    }

    /// Rule 1. The sentence says what kind of evidence this is, not how confident anybody feels
    /// about it — the same distinction `VerificationState` draws inside the app.
    ///
    /// An abandoned match gets no verification sentence at all: there is no result for anybody to
    /// stand behind, and "self-reported" on a match nobody won would be attesting to nothing.
    static func provenance(for session: MatchSession) -> String {
        guard session.hasResult else {
            return "Nothing is claimed about who won. The darts thrown are recorded; the match counts for nobody."
        }
        switch session.verification {
        case .disputed:
            return "Disputed — one of the players says this is not right. Nothing has been deleted; the result stands as recorded and is marked."
        case .participantConfirmed:
            return "Both players confirmed this on the phone it was scored on. Two people agreeing, not two devices."
        default:
            return "Self-reported. One phone recorded this and nobody else has confirmed it."
        }
    }

    /// Rule 1 again, as the tag. Decided by exactly the branches the sentence is, so the two can
    /// never say different things.
    static func standing(for session: MatchSession) -> Standing {
        guard session.hasResult else { return .noResult }
        switch session.verification {
        case .disputed: return .disputed
        case .participantConfirmed: return .confirmed
        default: return .selfReported
        }
    }

    private static let day: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .long
        f.timeStyle = .none
        return f
    }()

    /// The card, drawn.
    ///
    /// `cgImage` rather than a platform image so this compiles and is exercised wherever the tests
    /// run, and `Image(decorative:)` because the picture is handed straight to the share sheet —
    /// the button that produced it carries the label.
    @MainActor public static func image(for copy: Copy) -> Image? {
        let renderer = ImageRenderer(content: ThroShareCardView(copy: copy))
        renderer.scale = scale
        guard let cg = renderer.cgImage else { return nil }
        return Image(decorative: cg, scale: scale)
    }
}

/// The card itself: a board with the result chalked on it.
///
/// **The logo is the logo.** The first card set "THRØ" in a font, letterspaced — a word that looked
/// like the name, where the app everywhere else draws the wordmark from the mark's own geometry. The
/// card carries `ThroWordmark`, and the mark again as the stamp in its corner.
///
/// **It is a board, drawn in brand pigments.** The lamp, the field and the chalk dust are the app's
/// board — but the board's own tokens flip with the phone's appearance, and a card must be one picture
/// whoever drew it, so the same three stops are made from pigments that do not: `throGreenDeep` is the
/// lamp, `throGreen` the field, and the edge is the field mixed towards ink. The dust is `throGreenDeep`
/// at the board's own alphas, so it is never lighter than the lamp. `tools/check_share_card_tokens.py`
/// holds every colour here to one value in both traits, because that failure is silent and only
/// visible side by side.
///
/// **A scoreboard, not a sentence.** Each name stands over its own legs, the winner's in chalk and
/// underlined as a scorer underlines a winner, the loser's rubbed back. The figures sit in a chalk
/// box whose labels are never cut short, and how the result is verified is a tag an eye lands on, with
/// the sentence that says it in full under it.
///
/// **Sizes are fixed, not Dynamic Type.** Everywhere else in THRØ text scales with the reader's
/// setting, which is right for a screen and wrong for a raster: the card is read by whoever it is
/// sent to, at whatever size their phone shows an image, and a layout that reflowed with the
/// *sender's* accessibility setting would clip on their friend's screen instead of theirs.
public struct ThroShareCardView: View {
    private let copy: ThroShareCard.Copy

    public init(copy: ThroShareCard.Copy) {
        self.copy = copy
    }

    private func face(_ family: ThroFont.Family, _ size: CGFloat, _ weight: Font.Weight) -> Font {
        ThroFont.customFacesRegistered
            ? .custom(ThroFont.faceName(family, weight: weight), fixedSize: size)
            : .system(size: size, weight: weight)
    }

    /// How tall a leg count is: smaller when a retirement or abandonment sentence needs the room.
    ///
    /// The first draft drew them at 88, and the footer fell off the bottom of the card — outside the
    /// frame the ground is drawn in, so the format line rendered on transparency in the shared picture.
    /// Everything below is sized to fit 450 points with the longest sentences the card can carry.
    private var digit: CGFloat { copy.caveat == nil ? 74 : 58 }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center) {
                ThroWordmark(capHeight: 13, color: ThroColor.throChalk)
                Spacer(minLength: 8)
                Text(copy.date.uppercased())
                    .font(face(.ui, 9.5, .semibold))
                    .tracking(1.4)
                    .foregroundStyle(ThroColor.throChalk.opacity(0.55))
                    .lineLimit(1)
            }

            Text(copy.headline)
                .font(face(.sport, 26, .black))
                .foregroundStyle(ThroColor.throChalk)
                .lineLimit(2)
                .minimumScaleFactor(0.6)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 16)

            if let caveat = copy.caveat {
                Text(caveat)
                    .font(face(.ui, 11, .regular))
                    .foregroundStyle(ThroColor.throChalk.opacity(0.72))
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 4)
            }

            scoreboard.padding(.top, 10)

            if !copy.figures.isEmpty {
                figuresBox.padding(.top, 14)
                Text(copy.sample)
                    .font(face(.ui, 9.5, .regular))
                    .foregroundStyle(ThroColor.throChalk.opacity(0.5))
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.top, 6)
            }

            Spacer(minLength: 8)

            standingTag
            Text(copy.provenance)
                .font(face(.ui, 10.5, .medium))
                .foregroundStyle(ThroColor.throChalk.opacity(0.8))
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 7)
            HStack(alignment: .center, spacing: 8) {
                Text(copy.format)
                    .font(face(.ui, 9.5, .regular))
                    .foregroundStyle(ThroColor.throChalk.opacity(0.5))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Spacer(minLength: 8)
                ThroMark().fill(ThroColor.throChalk.opacity(0.38)).frame(width: 16, height: 16)
            }
            .padding(.top, 6)
        }
        .padding(24)
        .frame(width: ThroShareCard.size.width, height: ThroShareCard.size.height, alignment: .topLeading)
        .background(board)
    }

    // MARK: the board

    private var board: some View {
        GeometryReader { geo in
            ZStack {
                RadialGradient(stops: [Gradient.Stop(color: ThroColor.throGreenDeep, location: 0),
                                       Gradient.Stop(color: ThroColor.throGreen, location: 0.55),
                                       Gradient.Stop(color: ThroColor.throGreen.mix(with: ThroColor.throInkSunken, by: 0.45), location: 1)],
                               center: UnitPoint(x: 0.5, y: 0.28), startRadius: 0,
                               endRadius: max(geo.size.width, geo.size.height) * 0.86)
                Canvas(rendersAsynchronously: false) { context, size in
                    // The board's own dust: a fixed scatter, five tiers of one pigment.
                    var grain = Grain(seed: 0x5448_5243)
                    var tiers = Array(repeating: Path(), count: 5)
                    for _ in 0..<260 {
                        let x = grain.next() * size.width, y = grain.next() * size.height
                        let r = 0.4 + 0.9 * grain.next()
                        let tier = min(4, Int(grain.next() * 5))
                        tiers[tier].addEllipse(in: CGRect(x: x - r, y: y - r, width: 2 * r, height: 2 * r))
                    }
                    for (tier, path) in tiers.enumerated() {
                        context.fill(path, with: .color(ThroColor.throGreenDeep.opacity(0.1 * Double(tier + 1))))
                    }
                }
            }
        }
    }

    // MARK: the scoreboard

    /// The two names with their legs under them, or — when nobody won — the two names and nothing
    /// under them, because there is no number that would be true there.
    private var scoreboard: some View {
        HStack(alignment: .lastTextBaseline, spacing: 12) {
            side(copy.homeName, legs: copy.legs?.home, won: copy.winner == .home, leading: true)
            if copy.legs != nil {
                Text("–")
                    .font(face(.sport, digit * 0.5, .black))
                    .foregroundStyle(ThroColor.throChalk.opacity(0.35))
                    // The legs sit on one baseline; the dash between them belongs at their middle.
                    .baselineOffset(digit * 0.26)
            }
            side(copy.awayName, legs: copy.legs?.away, won: copy.winner == .away, leading: false)
        }
        .frame(maxWidth: .infinity)
    }

    private func side(_ name: String, legs: Int?, won: Bool, leading: Bool) -> some View {
        VStack(alignment: leading ? .leading : .trailing, spacing: 0) {
            HStack(spacing: 5) {
                if won && leading { winnerMark }
                Text(name.uppercased())
                    .font(face(.ui, 13, .black))
                    .tracking(1.6)
                    .foregroundStyle(won ? ThroColor.throGreenOnink : ThroColor.throChalk.opacity(0.7))
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                if won && !leading { winnerMark }
            }
            if let legs {
                Text("\(legs)")
                    .font(face(.sport, digit, .black))
                    .monospacedDigit()
                    .foregroundStyle(won ? ThroColor.throChalk : ThroColor.throChalk.opacity(0.42))
                    .lineLimit(1)
                ChalkRule(weight: 4, seedAngle: leading ? 7 : 19)
                    .fill(won ? ThroColor.throGreenOnink : Color.clear)
                    .frame(width: 56, height: 6)
            }
        }
        .frame(maxWidth: .infinity, alignment: leading ? .leading : .trailing)
    }

    private var winnerMark: some View {
        ThroMark().fill(ThroColor.throGreenOnink).frame(width: 13, height: 13)
    }

    // MARK: the figures

    private var figuresBox: some View {
        VStack(spacing: 0) {
            ForEach(Array(copy.figures.enumerated()), id: \.element.label) { i, figure in
                if i > 0 {
                    ChalkRule(weight: 1.5, seedAngle: Double(31 * i))
                        .fill(ThroColor.throChalk.opacity(0.16))
                        .frame(height: 3)
                }
                HStack(spacing: 10) {
                    Text(figure.home)
                        .font(face(.sport, 21, .bold))
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    // Never cut short: the label keeps its own width and the figures share the rest.
                    Text(figure.label.uppercased())
                        .font(face(.ui, 9.5, .semibold))
                        .tracking(1.3)
                        .foregroundStyle(ThroColor.throChalk.opacity(0.55))
                        .fixedSize()
                    Text(figure.away)
                        .font(face(.sport, 21, .bold))
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
                .foregroundStyle(ThroColor.throChalk)
                .padding(.vertical, 7)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 4)
        .background(ThroColor.throInkSunken.opacity(0.22))
        .overlay(ChalkBox(weight: 2, seedAngle: 23).fill(ThroColor.throChalk.opacity(0.3)))
    }

    // MARK: how it is verified

    private var standingTag: some View {
        let look: (icon: ThroIcon, ink: Color) = {
            switch copy.standing {
            case .confirmed: return (.circleCheck, ThroColor.throGreenOnink)
            case .disputed: return (.triangleAlert, ThroColor.throBronzeOnink)
            case .selfReported: return (.smartphone, ThroColor.throPewterLight)
            case .noResult: return (.circleX, ThroColor.throPewterLight)
            }
        }()
        return HStack(spacing: 6) {
            Icon(look.icon, size: 12)
            Text(copy.standing.rawValue.uppercased())
                .font(face(.ui, 9.5, .bold))
                .tracking(1.3)
        }
        .foregroundStyle(look.ink)
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .overlay(ChalkBox(weight: 1.5, seedAngle: 41).fill(look.ink))
    }
}
