import SwiftUI
import ThroLiveKit
import ThroTokens

// A leg on a wrist (PD-077).
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
// screen, and the checkout — the one fact a player at the oche actually wants — sits under it rather than
// being a detail on the end of a caption.
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

    /// The thrower's seat, or home between legs, so the screen always has a subject.
    private var leading: LiveSeat { state.thrower ?? .home }
    private var trailing: LiveSeat { leading == .home ? .away : .home }

    public var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            side(leading, leadingSide: true)
            side(trailing, leadingSide: false)
            if !state.checkout.isEmpty && state.winner == nil {
                // The route, when there is one. A player at the oche is not reading a caption; they want
                // the three darts. Marked with the finish colour the scoring screen uses for the same fact.
                Text(state.checkout.joined(separator: " · "))
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(ThroColor.throGreenOnink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .padding(.top, 2)
                    .accessibilityLabel("Checkout: " + state.checkout.joined(separator: ", "))
            }
            Spacer(minLength: 0)
            Text(ThroLiveCopy.caption(state, stale: stale))
                .font(.system(size: 11, weight: stale ? .semibold : .regular))
                .foregroundStyle(stale ? ThroColor.throBronzeOnink : ThroColor.throChalk.opacity(0.66))
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(.horizontal, 6)
        .background(ThroColor.colorBackgroundBrand.ignoresSafeArea())
    }

    /// One player. The thrower's numeral is the biggest thing on the screen; the other is present and
    /// quieter, because a darts score is only meaningful against the other one.
    @ViewBuilder private func side(_ seat: LiveSeat, leadingSide: Bool) -> some View {
        let throwing = ThroLiveCopy.isThrowing(state, seat)
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text("\(state.remaining(seat))")
                .font(.system(size: leadingSide ? 40 : 24, weight: .heavy))
                .monospacedDigit()
                .foregroundStyle(ThroColor.throChalk.opacity(throwing ? 1 : 0.7))
                .lineLimit(1)
                .minimumScaleFactor(0.5)
            VStack(alignment: .leading, spacing: 0) {
                Text(state.name(seat))
                    .font(.system(size: 11, weight: throwing ? .semibold : .regular))
                    .foregroundStyle(ThroColor.throChalk.opacity(throwing ? 0.95 : 0.6))
                    .lineLimit(1)
                Text("\(state.legs(seat))")
                    .font(.system(size: 10, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(ThroColor.throChalk.opacity(0.55))
            }
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
}
