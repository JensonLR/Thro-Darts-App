import Foundation

// A knockout draw (PD-021).
//
// The tournament page said "the draw is not built yet" and named this as the next thing. It is the
// arithmetic half — pure functions over entrants and results, no view and no store — because a draw
// is the kind of thing that is either right or quietly wrong, and the only way to know which is to
// be able to check it against the identities a bracket has to satisfy.
//
// **Seeding is entry order, and that is a statement rather than a shortcut.** THRØ has no rating
// (OD-001), so it has nothing else to seed on. PD-021 says byes go to the strongest seeds; with no
// strength to read, the strongest seed is whoever was entered first, the screen says so, and nobody
// is left thinking a computed ranking put them there.

/// One side of a match in the draw.
public enum Side: Equatable, Sendable {
    /// A known entrant.
    case entrant(Team)
    /// Nobody: this position is a bye, and the other side goes through.
    case bye
    /// Whoever wins an earlier match. Held rather than resolved, so a page can say *winner of match
    /// 3* instead of a blank where a name will be.
    case winnerOf(round: Int, slot: Int)
    /// Whoever **loses** an earlier match — the losers' bracket under double elimination is built
    /// out of these. Distinct from `.bye` on purpose: a match nobody has played yet has a loser
    /// coming, and a walkover never will. Reading the first as the second would draw a losers' round
    /// as a set of walkovers and advance the wrong people through it.
    case loserOf(round: Int, slot: Int)

    public var team: Team? { if case let .entrant(t) = self { return t }; return nil }
    public var isBye: Bool { self == .bye }
}

/// One match in the draw: where it sits, who is in it, and what happened.
public struct DrawMatch: Identifiable, Equatable, Sendable {
    public let round: Int
    public let slot: Int
    public let home: Side
    public let away: Side
    /// The fixture this match has become, once somebody has drawn it. Nil until then.
    public let fixture: Fixture?
    /// Which side of a double-elimination draw this sits on. Nil in a knockout, which has one
    /// bracket — naming it would be naming the only thing there is.
    public var bracket: Bracket?

    /// The bracket is part of the identity, because the winners' and the losers' sides both have a
    /// round 2 match 1 and they are different matches.
    public var id: String { "\(bracket?.rawValue ?? "k")-\(round)-\(slot)" }

    /// A match with a bye on one side is not played: the other side goes through, and **it is not a
    /// win**. Nothing about it reaches a record of results.
    public var isWalkover: Bool { home.isBye || away.isBye }

    /// Who goes through, when that is known. Nil while it is still to be played.
    public var winner: Team? {
        if case let .entrant(t) = home, away.isBye { return t }
        if case let .entrant(t) = away, home.isBye { return t }
        guard let result = fixture?.result else { return nil }
        if result.isDraw { return nil }   // a knockout match cannot end level; see `Draw.problems`
        return result.home > result.away ? home.team : away.team
    }

    /// Everything needed to draw this as a fixture, or nil when it is not a match anybody plays.
    public var playable: (home: Team, away: Team)? {
        guard let h = home.team, let a = away.team else { return nil }
        return (h, a)
    }
}

/// A knockout draw, computed from the entrants and whatever has been played.
///
/// Nothing here is stored. The rounds are derived every time, from the entry order and the fixtures
/// that exist, so a bracket cannot come to disagree with the results under it — the same rule the
/// league table follows and for the same reason.
public struct Draw: Equatable, Sendable {
    public let rounds: [[DrawMatch]]
    public let byes: Int
    /// The size of the bracket the field was fitted into: the next power of two at or above it.
    public let size: Int

    /// The seeding order for a bracket of `size`, as a draw sheet lays it out.
    ///
    /// Built by the standard doubling: a bracket of 2n is the bracket of n with each seed `s`
    /// replaced by the pair `(s, 2n + 1 − s)`. It is what makes the top seed meet the bottom one,
    /// the second seed sit in the other half, and the two best possible finalists only meet in the
    /// final — which is the whole point of seeding a draw at all.
    public static func seedOrder(size: Int) -> [Int] {
        guard size >= 2 else { return size == 1 ? [1] : [] }
        var order = [1, 2]
        var n = 2
        while n < size {
            n *= 2
            order = order.flatMap { [$0, n + 1 - $0] }
        }
        return order
    }

    /// The bracket a field of `n` is fitted into.
    public static func size(forEntrants n: Int) -> Int {
        guard n >= 2 else { return 0 }
        var size = 1
        while size < n { size *= 2 }
        return size
    }

    /// How many rounds a bracket of this size takes. 8 entrants is three rounds; 2 is one.
    public static func rounds(forSize size: Int) -> Int {
        guard size >= 2 else { return 0 }
        var rounds = 0, n = size
        while n > 1 { n /= 2; rounds += 1 }
        return rounds
    }

    /// The draw for these entrants, with the fixtures that have been drawn so far filled in.
    ///
    /// `entrants` is in **entry order**, which is the seeding — see the note at the top of this file.
    public static func of(entrants: [Team], fixtures: [Fixture]) -> Draw {
        let size = Draw.size(forEntrants: entrants.count)
        guard size >= 2 else { return Draw(rounds: [], byes: 0, size: 0) }
        let order = seedOrder(size: size)
        let drawn = Dictionary(fixtures.compactMap { f -> (String, Fixture)? in
            guard let r = f.round, let s = f.slot else { return nil }
            return ("\(r)-\(s)", f)
        }, uniquingKeysWith: { first, _ in first })

        // Round one: the seed order, two at a time. A seed past the end of the field is a bye.
        func side(_ seed: Int) -> Side {
            seed <= entrants.count ? .entrant(entrants[seed - 1]) : .bye
        }
        var rounds: [[DrawMatch]] = []
        var first: [DrawMatch] = []
        for slot in 1...(size / 2) {
            let home = side(order[(slot - 1) * 2])
            let away = side(order[(slot - 1) * 2 + 1])
            first.append(DrawMatch(round: 1, slot: slot, home: home, away: away,
                                   fixture: drawn["1-\(slot)"]))
        }
        rounds.append(first)

        // Every later round: the winners of the two matches that feed each slot, resolved where they
        // are known and held as `winnerOf` where they are not.
        var round = 2
        while rounds[round - 2].count > 1 {
            var next: [DrawMatch] = []
            let previous = rounds[round - 2]
            for slot in 1...(previous.count / 2) {
                let a = previous[(slot - 1) * 2], b = previous[(slot - 1) * 2 + 1]
                next.append(DrawMatch(round: round, slot: slot,
                                      home: a.winner.map(Side.entrant) ?? .winnerOf(round: a.round, slot: a.slot),
                                      away: b.winner.map(Side.entrant) ?? .winnerOf(round: b.round, slot: b.slot),
                                      fixture: drawn["\(round)-\(slot)"]))
            }
            rounds.append(next)
            round += 1
        }
        return Draw(rounds: rounds, byes: size - entrants.count, size: size)
    }

    /// The matches in `round` that can be created as fixtures now: both sides known, and no fixture
    /// yet. A walkover is not among them, because nobody plays it.
    public func readyToDraw(round: Int) -> [DrawMatch] {
        guard round >= 1, round <= rounds.count else { return [] }
        return rounds[round - 1].filter { $0.fixture == nil && !$0.isWalkover && $0.playable != nil }
    }

    /// Whether `round` is finished: every match in it either played or a walkover.
    public func isComplete(round: Int) -> Bool {
        guard round >= 1, round <= rounds.count else { return false }
        return rounds[round - 1].allSatisfy { $0.winner != nil }
    }

    /// The winner of the whole thing, once there is one.
    public var champion: Team? { rounds.last?.first?.winner }

    /// What is wrong with the draw as it stands, in words. Empty when nothing is.
    ///
    /// The one that matters: **a knockout match cannot end level.** The result screen will take a
    /// draw, because a league fixture may legitimately be one, so a tournament has to notice it
    /// rather than silently produce a round nobody advances from.
    public var problems: [String] {
        rounds.flatMap { round in
            round.compactMap { match -> String? in
                guard let result = match.fixture?.result, result.isDraw,
                      let sides = match.playable else { return nil }
                return "Round \(match.round), match \(match.slot) — \(sides.home.name) v "
                     + "\(sides.away.name) — is recorded as a draw, and a knockout match cannot end "
                     + "level. Nobody goes through until it says who won."
            }
        }
    }
}
