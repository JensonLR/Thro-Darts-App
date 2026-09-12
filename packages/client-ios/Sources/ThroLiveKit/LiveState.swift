import Foundation

// What a leg looks like from outside the app.
//
// **This type has no ActivityKit in it on purpose.** The state a Live Activity carries is the part
// that can be wrong — a remainder attributed to the wrong player, a checkout shown for somebody who
// is not throwing, a score that has gone stale without saying so — and none of that needs a system
// framework to test. ActivityKit wraps it next door, behind `#if canImport`, so the whole of this
// file compiles and is exercised on a Linux-shaped build as well as on a phone.
//
// It is also small on purpose. ActivityKit caps the attributes and the state **together** at 4 KB,
// for local updates and pushed ones alike, so this carries what a scoreboard shows and nothing more.

/// The two players, as a Live Activity names them.
public enum LiveSeat: String, Codable, Hashable, Sendable {
    case home, away
}

/// A leg, as the Lock Screen and the Dynamic Island show it.
public struct ThroLiveState: Codable, Hashable, Sendable {
    public var homeName: String
    public var awayName: String
    public var homeRemaining: Int
    public var awayRemaining: Int
    public var homeLegs: Int
    public var awayLegs: Int
    /// Whose throw it is, or nil between legs and once the match is over.
    public var thrower: LiveSeat?
    /// The route THRØ would show, when the thrower is on a finish. Empty otherwise.
    ///
    /// Carried rather than derived, because the rule tables live in the engine and an extension that
    /// linked the engine to work out a checkout would be linking a scoring engine into a widget.
    public var checkout: [String]
    /// Set once the match is decided, so the surface can stop pretending a leg is in play.
    public var winner: LiveSeat?

    public init(homeName: String, awayName: String,
                homeRemaining: Int, awayRemaining: Int,
                homeLegs: Int, awayLegs: Int,
                thrower: LiveSeat?, checkout: [String] = [], winner: LiveSeat? = nil) {
        self.homeName = homeName
        self.awayName = awayName
        self.homeRemaining = homeRemaining
        self.awayRemaining = awayRemaining
        self.homeLegs = homeLegs
        self.awayLegs = awayLegs
        self.thrower = thrower
        self.checkout = checkout
        self.winner = winner
    }

    public func name(_ seat: LiveSeat) -> String { seat == .home ? homeName : awayName }
    public func remaining(_ seat: LiveSeat) -> Int { seat == .home ? homeRemaining : awayRemaining }
    public func legs(_ seat: LiveSeat) -> Int { seat == .home ? homeLegs : awayLegs }
}

/// The words the surface shows, decided here rather than in a view.
///
/// **The staleness rule is the reason this is a type and not a string in a `Text`.** A Live Activity
/// keeps drawing after the app stops running, and nothing updates it while the app is in the
/// background: the score on the Lock Screen can be minutes old and look exactly as authoritative as
/// one from a second ago. Every other figure in THRØ says what it is — a bounded average shows a
/// range, an uncomputable one shows why — and this is the same rule on a new surface. When the
/// system says the content is stale, the caption says so, and the numbers stop claiming to be now.
public enum ThroLiveCopy {
    /// The line under the score.
    public static func caption(_ state: ThroLiveState, stale: Bool) -> String {
        if let winner = state.winner {
            return "\(state.name(winner)) wins"
        }
        if stale {
            return "Score may be out of date — open THRØ"
        }
        if let thrower = state.thrower {
            let route = route(state, stale: stale)
            if !route.isEmpty {
                return "\(state.name(thrower)) to throw · checkout \(route.joined(separator: " "))"
            }
            return "\(state.name(thrower)) to throw"
        }
        return "Between legs"
    }

    /// The finish to show, or nothing.
    ///
    /// **A route belongs to whoever is on the oche, and is only as true as the number it was worked out
    /// from.** So it is empty when there is no finish, when the leg is decided, when nobody is throwing,
    /// and when the score may have stopped being current — telling somebody to throw treble nineteen,
    /// double twelve at a remainder that has moved is worse than telling them nothing, and the surface
    /// most likely to be acted on is the one on their wrist.
    ///
    /// The caption has always obeyed all of that, inside its own control flow, which meant a surface
    /// that drew the route on a line of its own silently got none of it. Now both ask.
    public static func route(_ state: ThroLiveState, stale: Bool) -> [String] {
        guard state.winner == nil, state.thrower != nil, !stale else { return [] }
        return state.checkout
    }

    /// The legs, as a scoreline. Never a running average or any other figure: this surface cannot
    /// carry a basis or a sample, so it carries no statistic at all.
    public static func legs(_ state: ThroLiveState) -> String {
        "\(state.homeLegs)–\(state.awayLegs)"
    }

    /// The compact line the Dynamic Island shows when it is not expanded — two remainders, and
    /// nothing that needs reading.
    public static func compact(_ state: ThroLiveState) -> String {
        "\(state.homeRemaining) · \(state.awayRemaining)"
    }

    /// Whether a seat should be drawn as the one throwing. False for both once there is a winner,
    /// so a decided match never shows somebody still on the oche.
    public static func isThrowing(_ state: ThroLiveState, _ seat: LiveSeat) -> Bool {
        state.winner == nil && state.thrower == seat
    }
}
