import Foundation

// Double elimination (PD-021): lose once and you drop, lose twice and you are out.
//
// **The losers' bracket is the part that looks right and is not.** A winners' bracket is a knockout
// and its arithmetic is obvious; a losers' bracket has a shape most people have never had to write
// down — it alternates between rounds that pair its own survivors and rounds that absorb the players
// dropping out of the winners' side, and the order they drop in decides whether two players who have
// already met meet again immediately. Which is why what is asserted below is the *structure* — every
// entrant but one loses exactly twice, the match count is the one arithmetic demands, no rematch
// happens before it has to — rather than one bracket somebody eyeballed.

/// Which side of a double-elimination draw a match sits on.
public enum Bracket: String, Equatable, Sendable {
    case winners, losers, final
    /// The group stage of a groups tournament (PD-021). It is not a bracket in the knockout sense —
    /// it is a set of round robins — but it is the same question a stored fixture has to answer:
    /// *which part of this tournament are you?*
    case group
}

/// A double-elimination draw, computed from the entrants and whatever has been played.
///
/// Like the knockout, nothing is stored: the whole thing is derived every time from the entry order
/// and the fixtures that exist, so it cannot come to disagree with the results under it.
public struct DoubleElimination: Equatable, Sendable {
    /// The winners' side — a knockout, so it is exactly one.
    public let winners: [[DrawMatch]]
    /// The losers' side, round by round. Odd rounds pair its own survivors; even rounds absorb the
    /// players who have just dropped out of the winners' side.
    public let losers: [[DrawMatch]]
    /// The grand final, and the second one that is played only if the losers' side wins the first.
    public let grandFinal: DrawMatch?
    public let reset: DrawMatch?
    public let byes: Int
    public let size: Int

    /// How many rounds the losers' side has for a bracket of `size`: two for every winners' round
    /// after the first, less one — a minor round and a major round for each, and the first minor
    /// round has nobody to pair yet.
    public static func loserRounds(forSize size: Int) -> Int {
        let winnerRounds = Draw.rounds(forSize: size)
        return winnerRounds < 2 ? 0 : 2 * (winnerRounds - 1)
    }

    /// The draw for these entrants. `entrants` is in entry order, which is the seeding — THRØ has no
    /// rating to seed on (OD-001) and does not pretend otherwise.
    public static func of(entrants: [Team], fixtures: [Fixture]) -> DoubleElimination {
        let size = Draw.size(forEntrants: entrants.count)
        guard size >= 2 else {
            return DoubleElimination(winners: [], losers: [], grandFinal: nil, reset: nil,
                                     byes: 0, size: 0)
        }
        let drawn = DoubleElimination.index(fixtures)

        // The winners' side is a knockout, drawn by the code that already draws knockouts.
        let winnersOnly = fixtures.filter { $0.bracket == Bracket.winners.rawValue || $0.bracket == nil }
        let winnersDraw = Draw.of(entrants: entrants, fixtures: winnersOnly)
        let winners = winnersDraw.rounds

        // Whoever loses a winners' match.
        //
        // Three answers, and collapsing any two of them is a bug: a **walkover** produces nobody, so
        // that losers' position is empty and whoever it faces goes through; a match that has been
        // played produces the entrant who lost it; and a match nobody has played yet produces a
        // **loser who is coming** — which has to read as *loser of round 1 match 3* rather than as a
        // bye, or a whole losers' round is drawn as walkovers and the wrong people advance.
        func loser(_ match: DrawMatch) -> Side {
            if match.isWalkover { return .bye }
            guard let winner = match.winner,
                  let home = match.home.team, let away = match.away.team else {
                return .loserOf(round: match.round, slot: match.slot)
            }
            return .entrant(winner.id == home.id ? away : home)
        }

        var losers: [[DrawMatch]] = []
        let rounds = DoubleElimination.loserRounds(forSize: size)
        if rounds > 0 {
            // Round 1 pairs the losers of winners' round 1 with each other.
            var previous: [DrawMatch] = []
            for round in 1...rounds {
                let minor = round % 2 == 1          // pairs its own survivors
                var matches: [DrawMatch] = []
                if round == 1 {
                    let dropping = winners[0].map(loser)
                    for slot in 1...max(dropping.count / 2, 1) where dropping.count >= 2 {
                        matches.append(DrawMatch(round: 1, slot: slot,
                                                 home: dropping[(slot - 1) * 2],
                                                 away: dropping[(slot - 1) * 2 + 1],
                                                 fixture: drawn[key(.losers, 1, slot)],
                                                 bracket: .losers))
                    }
                } else if minor {
                    // Pair the survivors of the round before.
                    for slot in 1...max(previous.count / 2, 1) where previous.count >= 2 {
                        let a = previous[(slot - 1) * 2], b = previous[(slot - 1) * 2 + 1]
                        matches.append(DrawMatch(round: round, slot: slot,
                                                 home: through(a), away: through(b),
                                                 fixture: drawn[key(.losers, round, slot)],
                                                 bracket: .losers))
                    }
                } else {
                    // Absorb the winners' round that has just been played. **Reversed**, which is
                    // the whole point of the cross-over: dropping them in the order they fell would
                    // put a player straight back against somebody who has just knocked them out.
                    let winnersRound = round / 2 + 1
                    let dropping = winnersRound <= winners.count
                        ? winners[winnersRound - 1].map(loser).reversed().map { $0 } : []
                    for slot in 1...max(previous.count, 1) where !previous.isEmpty {
                        matches.append(DrawMatch(round: round, slot: slot,
                                                 home: through(previous[slot - 1]),
                                                 away: slot - 1 < dropping.count ? dropping[slot - 1] : .bye,
                                                 fixture: drawn[key(.losers, round, slot)],
                                                 bracket: .losers))
                    }
                }
                losers.append(matches)
                previous = matches
            }
        }

        // The grand final: the winners' side's survivor against the losers' side's.
        //
        // **A two-entrant draw has no losers' side at all** — there is nobody to drop against — so
        // the challenger is the loser of the winners' final itself. Two people playing double
        // elimination is a degenerate case, and it is the one a bracket built for eight quietly gets
        // wrong by reaching for a losers' round that does not exist.
        let winnersChampion = winnersDraw.champion
        let losersChampion: Team? = losers.isEmpty
            ? winners.last?.first.flatMap { loser($0).team }
            : losers.last?.first?.winner
        let challenger: Side = losersChampion.map(Side.entrant)
            ?? (losers.isEmpty ? .loserOf(round: winners.count, slot: 1)
                               : .winnerOf(round: losers.count, slot: 1))
        let grandFinal = size >= 2 ? DrawMatch(
            round: 1, slot: 1,
            home: winnersChampion.map(Side.entrant) ?? .winnerOf(round: winners.count, slot: 1),
            away: challenger,
            fixture: drawn[key(.final, 1, 1)], bracket: .final) : nil

        // And the second one, played **only** if the losers' side won the first: the winners' side
        // has not lost yet, and this is a competition where you go out on your second loss.
        var reset: DrawMatch?
        if let grandFinal, let champion = grandFinal.winner, let arrived = losersChampion,
           champion.id == arrived.id {
            reset = DrawMatch(round: 2, slot: 1,
                              home: grandFinal.home, away: grandFinal.away,
                              fixture: drawn[key(.final, 2, 1)], bracket: .final)
        }
        return DoubleElimination(winners: winners, losers: losers, grandFinal: grandFinal,
                                 reset: reset, byes: size - entrants.count, size: size)
    }

    /// Whoever came through a losers' match, held as a reference while it is unplayed.
    private static func through(_ match: DrawMatch) -> Side {
        match.winner.map(Side.entrant) ?? .winnerOf(round: match.round, slot: match.slot)
    }

    private static func key(_ bracket: Bracket, _ round: Int, _ slot: Int) -> String {
        "\(bracket.rawValue)-\(round)-\(slot)"
    }

    private static func index(_ fixtures: [Fixture]) -> [String: Fixture] {
        Dictionary(fixtures.compactMap { f -> (String, Fixture)? in
            guard let round = f.round, let slot = f.slot,
                  let bracket = f.bracket.flatMap(Bracket.init(rawValue:)) else { return nil }
            return (key(bracket, round, slot), f)
        }, uniquingKeysWith: { first, _ in first })
    }

    /// How many matches this draw actually schedules, before any reset.
    ///
    /// The number the tournament page puts on the screen has to be the number the bracket produces.
    /// They are computed two different ways — the page from *2n − 2*, this from counting the matches
    /// that exist — and a test holds them equal, because two numbers for one thing is how a page
    /// comes to promise a field something its own draw will not give it.
    public var matchesForEntrants: Int {
        winners.flatMap { $0 }.filter { !$0.isWalkover }.count
            + losers.flatMap { $0 }.filter { !$0.isWalkover }.count
            + (grandFinal == nil ? 0 : 1)
    }

    /// Every match in the draw, in the order it would be played.
    public var allMatches: [DrawMatch] {
        winners.flatMap { $0 } + losers.flatMap { $0 } + [grandFinal, reset].compactMap { $0 }
    }

    /// The matches on `bracket` and `round` that can be created as fixtures now.
    public func readyToDraw(bracket: Bracket, round: Int) -> [DrawMatch] {
        let source: [DrawMatch]
        switch bracket {
        case .winners: source = round >= 1 && round <= winners.count ? winners[round - 1] : []
        case .losers: source = round >= 1 && round <= losers.count ? losers[round - 1] : []
        case .final: source = [round == 1 ? grandFinal : reset].compactMap { $0 }
        // A double-elimination tournament has no group stage. Written out rather than left to a
        // `default`, so the day a fifth part of a tournament exists the compiler asks about this
        // function too — which is exactly what adding `.group` did, and it was right to.
        case .group: source = []
        }
        return source.filter { $0.fixture == nil && !$0.isWalkover && $0.playable != nil }
    }

    /// Who has won the whole thing, once somebody has.
    ///
    /// The winners' side's survivor takes it by winning the grand final. The losers' side's survivor
    /// has to win it **twice**, which is what the reset is for — they arrive with one loss already.
    public var champion: Team? {
        guard let grandFinal, let first = grandFinal.winner else { return nil }
        // The winners' side arrives unbeaten, so winning the grand final finishes it. The losers'
        // side arrives with a loss already, so winning it once only levels them: the reset decides.
        guard let arrived = grandFinal.away.team, first.id == arrived.id else { return first }
        return reset?.winner
    }

    /// What is wrong with the draw as it stands, in words. A match here cannot end level either.
    public var problems: [String] {
        allMatches.compactMap { match in
            guard let result = match.fixture?.result, result.isDraw,
                  let sides = match.playable else { return nil }
            return "\(match.bracket?.rawValue.capitalized ?? "Round \(match.round)") round "
                 + "\(match.round), match \(match.slot) — \(sides.home.name) v \(sides.away.name) — "
                 + "is recorded as a draw. Nobody goes out on a draw, and nobody goes through on one."
        }
    }
}
