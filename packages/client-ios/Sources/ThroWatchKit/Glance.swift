import SwiftUI
import ThroLiveKit
import ThroTokens

// A leg on a wrist (PD-077, PD-078).
//
// **Nothing here is a new model.** `ThroLiveState` already answers "what does a leg look like from outside
// the app" — it is what the Lock Screen, the Dynamic Island, the widgets and an external display all draw,
// it is Codable and Sendable because ActivityKit made it cross a process boundary under a 4 KB budget, and
// WatchConnectivity wants exactly the same thing. A watch that invented a fifth shape for two numbers and a
// checkout would be a fifth thing to keep true.
//
// **What is new is the arrangement, because a wrist is not a banner.** The Lock Screen puts the two players
// side by side, which suits something wider than it is tall; a watch is nearly square and read at arm's
// length with a dart in the other hand. So the sides stack, the thrower's score is the largest thing on the
// screen, and the checkout — the one fact a player at the oche actually wants — gets a line of its own.
//
// **And because the arrangement is different, the words are.** The Lock Screen writes *"Jenson R. to throw ·
// checkout T19 D12"* because its two numerals are the same size and it has one line to spend; here the
// thrower is already twice the size of the other player and the route already has its own line, so the same
// sentence would be captioning a picture with the picture. What the drawing cannot say — that the leg is
// decided, that the link has gone quiet, that nobody is on the oche — is what the words are spent on, and
// **in the same order of precedence** `ThroLiveCopy` uses, held by a test.
//
// Its own module rather than a view inside `ThroLiveKit`, because that target is deliberately the lightest
// in the package: a widget extension links it, and an extension that pulled in a watch layout would be
// carrying code it can never run.

/// A leg at a glance, for a watch.
public struct ThroWatchGlance: View {
    private let state: ThroLiveState
    private let stale: Bool

    public init(state: ThroLiveState, stale: Bool = false) {
        self.state = state
        self.stale = stale
    }

    /// **The subject of the screen**: the winner once there is one, the thrower while there is not, and
    /// home between legs so that the order is stable rather than arbitrary.
    ///
    /// The winner comes first even though they are no longer throwing. Reading a decided match top-down
    /// and finding the loser in the large numeral is the wrong answer to the only question left.
    /// Internal rather than private so a test can hold it: which seat is the subject is a rule, and a
    /// rule nothing checks is a rule that comes back.
    var leading: LiveSeat { state.winner ?? state.thrower ?? .home }
    var trailing: LiveSeat { leading == .home ? .away : .home }

    /// Who is drawn bright. Between legs neither is: there is no subject, and the note says so, so the
    /// difference in size is reading order and not a claim about who matters.
    func emphasised(_ seat: LiveSeat) -> Bool {
        state.winner == seat || ThroLiveCopy.isThrowing(state, seat)
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            side(leading, leadingSide: true)
            side(trailing, leadingSide: false)

            let route = ThroLiveCopy.route(state, stale: stale)
            if !route.isEmpty {
                // The route, when there is one. A player at the oche is not reading a caption; they want
                // the three darts. Marked with the finish colour the scoring screen uses for the same fact.
                //
                // `ThroLiveCopy.route` and not `state.checkout`: a finish is only as true as the number it
                // was worked out from, so it goes when the leg is decided **and when the score may have
                // stopped being current**. That rule used to live inside the caption's sentence, where a
                // surface drawing the route on its own line could not see it.
                Text(route.joined(separator: " · "))
                    .font(.system(size: 19, weight: .bold))
                    .foregroundStyle(ThroColor.throGreenOnink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .padding(.top, 4)
                    .accessibilityLabel("Checkout: " + route.joined(separator: ", "))
            }

            Spacer(minLength: 2)

            HStack(alignment: .firstTextBaseline, spacing: 6) {
                // The legs once, as a scoreline, because that is how a darts match is read — and not
                // twice, beside each player, where two small digits are noise rather than a score.
                Text(ThroLiveCopy.legs(state))
                    .font(.system(size: 13, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(ThroColor.throChalk.opacity(0.55))
                    .accessibilityLabel("Legs, \(state.homeLegs) to \(state.awayLegs)")
                if let note = ThroWatchWords.note(state, stale: stale) {
                    Text(note)
                        .font(.system(size: 12, weight: stale ? .semibold : .regular))
                        .foregroundStyle(stale ? ThroColor.throBronzeOnink : ThroColor.throChalk.opacity(0.8))
                        .lineLimit(2)
                        .minimumScaleFactor(0.8)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(.horizontal, 6)
        .background(ThroColor.colorBackgroundBrand.ignoresSafeArea())
    }

    /// One player. The thrower's numeral is the biggest thing on the screen; the other is present and
    /// quieter, because a darts score is only meaningful against the other one.
    @ViewBuilder private func side(_ seat: LiveSeat, leadingSide: Bool) -> some View {
        let throwing = emphasised(seat)
        HStack(alignment: .firstTextBaseline, spacing: 7) {
            Text("\(state.remaining(seat))")
                .font(.system(size: leadingSide ? 54 : 32, weight: .heavy))
                .monospacedDigit()
                .foregroundStyle(ThroColor.throChalk.opacity(throwing ? 1 : 0.7))
                .lineLimit(1)
                .minimumScaleFactor(0.5)
            Text(state.name(seat))
                .font(.system(size: leadingSide ? 14 : 12, weight: throwing ? .semibold : .regular))
                .foregroundStyle(ThroColor.throChalk.opacity(throwing ? 0.95 : 0.6))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(ThroWatchWords.spoken(state, seat))
    }
}

/// What the wrist says, apart from the drawing so it is tested rather than looked at.
public enum ThroWatchWords {
    /// One side, read aloud. The leg count is said as a word because "2" alone after a score is heard as
    /// part of the score — the same reason the table speaks its figures rather than showing them.
    public static func spoken(_ state: ThroLiveState, _ seat: LiveSeat) -> String {
        let legs = state.legs(seat)
        var said = "\(state.name(seat)), \(state.remaining(seat)) remaining, "
            + "\(legs) \(legs == 1 ? "leg" : "legs")"
        if ThroLiveCopy.isThrowing(state, seat) { said += ", throwing" }
        return said
    }

    /// The one line of words on the wrist, or **nothing at all** when the drawing has already said it.
    ///
    /// The precedence is `ThroLiveCopy`'s, deliberately and identically: a decided leg outranks staleness,
    /// because *"Ann wins"* does not go out of date, and staleness outranks everything under it, because a
    /// number that may have stopped being true must not be captioned as though it were current. What is
    /// different is only the bottom of the list — where the Lock Screen names the thrower and appends the
    /// route, a wrist has already drawn both, so it says nothing rather than repeat itself.
    public static func note(_ state: ThroLiveState, stale: Bool) -> String? {
        if let winner = state.winner { return "\(state.name(winner)) wins" }
        if stale { return "May be out of date" }
        if state.thrower == nil { return "Between legs" }
        return nil
    }

    /// What a watch with nothing live says. In a type rather than inside a `Text` for the reason the
    /// rest of this project's copy is: the words are the part that can be wrong, and a screen nobody
    /// can reach in a test is a screen nobody checks.
    public static let nothingOn = "No leg on"
    public static let nothingOnHint = "Start a match on your phone and it appears here."
}
