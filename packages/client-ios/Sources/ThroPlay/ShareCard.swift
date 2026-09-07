import Foundation
import SwiftUI
import ThroDesign
import ThroJournal
import ThroTokens

// The picture of a result that goes into a group chat.
//
// **This is the one surface that leaves the phone.** Everywhere else, a figure THRØ shows is one a
// player can tap for its basis and its sample. An image cannot be tapped, cannot be corrected, and
// outlives the app that made it — so everything the honesty layer normally puts one tap away has to
// be *on the card itself*, or the card is a claim with no basis, which is the one thing this product
// has said from the start it will not ship.
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

    /// Every word on the card. A value type with no view in it, because the words are the part that
    /// can be wrong and a view is a bad place to test them from.
    public struct Copy: Equatable, Sendable {
        /// "Ann wins", or "No result" when nobody did.
        public let headline: String
        /// "3–1". **Nil when there is no result**, and the card draws nothing in its place.
        public let score: String?
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
        /// "501 · Best of 5 · Double out"
        public let format: String
        /// "7 September 2026"
        public let date: String

        public init(headline: String, score: String?, homeName: String, awayName: String,
                    winner: Seat?, caveat: String?, figures: [Figure], sample: String,
                    provenance: String, format: String, date: String) {
            self.headline = headline
            self.score = score
            self.homeName = homeName
            self.awayName = awayName
            self.winner = winner
            self.caveat = caveat
            self.figures = figures
            self.sample = sample
            self.provenance = provenance
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
            homeName: session.name(.home),
            awayName: session.name(.away),
            winner: session.hasResult ? session.winner : nil,
            caveat: session.resultDetail,
            figures: figures(home: session.statistics(for: .home), away: session.statistics(for: .away)),
            sample: sample(visits: visits, legs: session.legsWon(.home) + session.legsWon(.away)),
            provenance: provenance(for: session),
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

/// The card itself.
///
/// **Every colour here is a brand token, and every one of them is the same value in light and dark.**
/// A card rendered on a phone in dark mode must be the same picture as one rendered in light mode:
/// two people in the same group chat comparing cards that do not match would have no way to tell a
/// theme from a defect. `tools/check_share_card_tokens.py` holds it, because the failure is silent
/// and only visible side by side.
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

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("THRØ")
                .font(face(.ui, 15, .black))
                .tracking(4)
                .foregroundStyle(ThroColor.throChalk.opacity(0.5))

            Text(copy.headline)
                .font(face(.ui, 40, .black))
                .foregroundStyle(ThroColor.throChalk)
                .lineLimit(2)
                .minimumScaleFactor(0.6)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 14)

            if let caveat = copy.caveat {
                Text(caveat)
                    .font(face(.ui, 11, .regular))
                    .foregroundStyle(ThroColor.throChalk.opacity(0.7))
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 6)
            }

            scoreline.padding(.top, 22)

            if !copy.figures.isEmpty {
                rule.padding(.top, 20)
                VStack(spacing: 9) {
                    ForEach(copy.figures, id: \.label) { figure in
                        HStack(spacing: 8) {
                            Text(figure.home)
                                .font(face(.sport, 19, .bold))
                                .monospacedDigit()
                                .frame(maxWidth: .infinity, alignment: .leading)
                            Text(figure.label.uppercased())
                                .font(face(.ui, 10, .medium))
                                .tracking(1.2)
                                .foregroundStyle(ThroColor.throChalk.opacity(0.5))
                                .lineLimit(1)
                            Text(figure.away)
                                .font(face(.sport, 19, .bold))
                                .monospacedDigit()
                                .frame(maxWidth: .infinity, alignment: .trailing)
                        }
                        .foregroundStyle(ThroColor.throChalk)
                    }
                }
                .padding(.top, 16)

                Text(copy.sample)
                    .font(face(.ui, 10, .regular))
                    .foregroundStyle(ThroColor.throChalk.opacity(0.5))
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.top, 12)
            }

            Spacer(minLength: 12)

            rule
            Text(copy.provenance)
                .font(face(.ui, 11, .medium))
                .foregroundStyle(ThroColor.throChalk.opacity(0.8))
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 12)
            Text("\(copy.format) · \(copy.date)")
                .font(face(.ui, 10, .regular))
                .foregroundStyle(ThroColor.throChalk.opacity(0.45))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .padding(.top, 6)
        }
        .padding(28)
        .frame(width: ThroShareCard.size.width, height: ThroShareCard.size.height, alignment: .topLeading)
        .background(ThroColor.throGreen)
    }

    /// The two names and the legs between them, or — when nobody won — the two names and nothing
    /// between them, because there is no number that would be true there.
    private var scoreline: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            name(copy.homeName, winner: copy.winner == .home, alignment: .leading)
            if let score = copy.score {
                Text(score)
                    .font(face(.sport, 54, .black))
                    .monospacedDigit()
                    .foregroundStyle(ThroColor.throChalk)
                    .lineLimit(1)
            }
            name(copy.awayName, winner: copy.winner == .away, alignment: .trailing)
        }
        .frame(maxWidth: .infinity)
    }

    private func name(_ text: String, winner: Bool, alignment: Alignment) -> some View {
        Text(text.uppercased())
            .font(face(.ui, 17, winner ? .black : .medium))
            .tracking(1)
            .foregroundStyle(winner ? ThroColor.throGreenOnink : ThroColor.throChalk.opacity(0.75))
            .lineLimit(2)
            .minimumScaleFactor(0.5)
            .multilineTextAlignment(alignment == .leading ? .leading : .trailing)
            .frame(maxWidth: .infinity, alignment: alignment)
    }

    private var rule: some View {
        Rectangle()
            .fill(ThroColor.throChalkHairline.opacity(0.25))
            .frame(height: 1)
    }
}
