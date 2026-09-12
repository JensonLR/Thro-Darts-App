import Foundation
import XCTest
@testable import ThroApp

/// Double elimination (PD-021): lose once and you drop, lose twice and you are out.
///
/// **The losers' bracket is the part that looks right and is not**, so what is asserted here is the
/// structure rather than one bracket somebody eyeballed. The strongest of these plays a whole
/// tournament through and then checks the thing the format is *defined* by: every entrant but the
/// champion lost exactly twice, and nobody played after their second loss.
final class DoubleEliminationTests: XCTestCase {

    private func entrants(_ n: Int) -> [Team] {
        (1...n).map { Team(id: "t\($0)", name: "Seed \($0)") }
    }

    private func fixture(_ bracket: Bracket, _ round: Int, _ slot: Int,
                         _ home: Team, _ away: Team, _ h: Int, _ a: Int) -> Fixture {
        Fixture(id: "\(bracket.rawValue)-\(round)-\(slot)", title: "\(home.name) v \(away.name)",
                when: "Tue", venue: "", state: .played,
                homeTeamId: home.id, awayTeamId: away.id,
                result: MatchResult(home: h, away: a, source: .recorded(by: "Pat")),
                round: round, slot: slot, bracket: bracket.rawValue)
    }

    /// Plays every drawable match to a decision, always letting the **home** side win, until nothing
    /// is left to draw. Returns the fixtures created, so the structure can be interrogated after.
    private func playItOut(_ field: [Team]) -> (DoubleElimination, [Fixture]) {
        var fixtures: [Fixture] = []
        var draw = DoubleElimination.of(entrants: field, fixtures: fixtures)
        // A generous bound: the format needs 2n − 1 matches, so this can only spin if the draw
        // stops making progress — which is itself the failure worth catching.
        for _ in 0..<(4 * field.count + 8) {
            var next: DrawMatch?
            for bracket in [Bracket.winners, .losers, .final] {
                let rounds = bracket == .winners ? draw.winners.count
                           : bracket == .losers ? draw.losers.count : 2
                for round in 1...max(rounds, 1) {
                    if let match = draw.readyToDraw(bracket: bracket, round: round).first {
                        next = match
                        break
                    }
                }
                if next != nil { break }
            }
            guard let match = next, let sides = match.playable else { break }
            fixtures.append(fixture(match.bracket ?? .winners, match.round, match.slot,
                                    sides.home, sides.away, 5, 3))
            draw = DoubleElimination.of(entrants: field, fixtures: fixtures)
        }
        return (draw, fixtures)
    }

    // MARK: - the shape of it

    /// The losers' side has two rounds for every winners' round after the first: one that pairs its
    /// own survivors, one that absorbs the players who have just dropped.
    func testTheLosersSideHasTwoRoundsForEveryWinnersRoundAfterTheFirst() {
        XCTAssertEqual(DoubleElimination.loserRounds(forSize: 2), 0, "nobody has anywhere to drop to")
        XCTAssertEqual(DoubleElimination.loserRounds(forSize: 4), 2)
        XCTAssertEqual(DoubleElimination.loserRounds(forSize: 8), 4)
        XCTAssertEqual(DoubleElimination.loserRounds(forSize: 16), 6)
    }

    /// **The count arithmetic demands.** Every match produces exactly one loss; everybody but the
    /// champion goes out on their second. So a field of n needs 2n − 2 matches, or 2n − 1 when the
    /// losers' side wins the first grand final and the reset is played.
    func testTheMatchCountIsTheOneTheFormatDemands() {
        for n in [2, 4, 8, 16] {
            let draw = DoubleElimination.of(entrants: entrants(n), fixtures: [])
            let scheduled = draw.winners.flatMap { $0 }.filter { !$0.isWalkover }.count
                          + draw.losers.flatMap { $0 }.filter { !$0.isWalkover }.count
                          + 1   // the grand final
            XCTAssertEqual(scheduled, 2 * n - 2,
                           "\(n) entrants: \(draw.winners.flatMap { $0 }.count) winners' matches, "
                           + "\(draw.losers.flatMap { $0 }.count) losers'")
            XCTAssertEqual(draw.matchesForEntrants, TournamentShape.doubleElimination.matches(forEntrants: n),
                           "and the page's number is the draw's number")
        }
    }

    /// **The property the format is defined by**, checked by playing a whole one out: everybody but
    /// the champion lost exactly twice, and nobody appeared in a match after their second loss.
    func testEverybodyButTheChampionLosesExactlyTwice() {
        for n in [4, 8] {
            let field = entrants(n)
            let (draw, fixtures) = playItOut(field)
            XCTAssertNotNil(draw.champion, "\(n) entrants must resolve to a champion")

            var losses: [String: Int] = [:]
            for f in fixtures {
                guard let result = f.result, let home = f.homeTeamId, let away = f.awayTeamId else { continue }
                let loser = result.home > result.away ? away : home
                losses[loser, default: 0] += 1
            }
            for entrant in field where entrant.id != draw.champion?.id {
                XCTAssertEqual(losses[entrant.id], 2,
                               "\(entrant.name) went out with \(losses[entrant.id] ?? 0) losses, not 2")
            }
            XCTAssertLessThanOrEqual(losses[draw.champion!.id] ?? 0, 1,
                                     "a champion has lost at most once")
            XCTAssertGreaterThanOrEqual(fixtures.count, 2 * n - 2)
            XCTAssertLessThanOrEqual(fixtures.count, 2 * n - 1)
        }
    }

    /// **The cross-over.** Losers dropping out of the winners' side are inserted into the losers'
    /// side reversed, so somebody is not put straight back against the player who has just knocked
    /// them out. Dropping them in the order they fell is the plausible version, and it is wrong.
    func testTheDropInIsReversedSoNobodyMeetsTheirConquerorImmediately() {
        let field = entrants(8)
        func team(_ n: Int) -> Team { field[n - 1] }
        // Winners' round one, as the seeding lays it out: 1v8, 4v5, 2v7, 3v6 — favourites through.
        var fixtures = [fixture(.winners, 1, 1, team(1), team(8), 5, 1),
                        fixture(.winners, 1, 2, team(4), team(5), 5, 1),
                        fixture(.winners, 1, 3, team(2), team(7), 5, 1),
                        fixture(.winners, 1, 4, team(3), team(6), 5, 1)]
        // Losers' round one pairs those four: (8 v 5) and (7 v 6). 8 and 7 go through.
        fixtures += [fixture(.losers, 1, 1, team(8), team(5), 5, 1),
                     fixture(.losers, 1, 2, team(7), team(6), 5, 1)]
        // Winners' round two: 1v4 and 2v3. The losers are 4 (from match 1) and 3 (from match 2).
        fixtures += [fixture(.winners, 2, 1, team(1), team(4), 5, 1),
                     fixture(.winners, 2, 2, team(2), team(3), 5, 1)]

        let draw = DoubleElimination.of(entrants: field, fixtures: fixtures)
        let second = draw.losers[1]
        XCTAssertEqual(second.count, 2)
        // Reversed: seed 3 (who fell in winners' match 2) meets the survivor of losers' match 1.
        XCTAssertEqual(second[0].away.team?.id, "t3")
        XCTAssertEqual(second[1].away.team?.id, "t4")
        // 8 lost to 1 and 5 lost to 4; neither is put back against the one who beat them.
        XCTAssertEqual(second[0].home.team?.id, "t8")
        XCTAssertEqual(second[1].home.team?.id, "t7")
        for match in second {
            XCTAssertNotEqual(match.home.team?.id, match.away.team?.id)
        }
    }

    /// A winners' match nobody has played yet produces a **loser who is coming**, not a bye. Reading
    /// the first as the second would draw a whole losers' round as walkovers and advance the wrong
    /// people through it.
    func testAnUnplayedWinnersMatchProducesALoserToCome() {
        let draw = DoubleElimination.of(entrants: entrants(8), fixtures: [])
        XCTAssertEqual(draw.losers[0][0].home, .loserOf(round: 1, slot: 1))
        XCTAssertEqual(draw.losers[0][0].away, .loserOf(round: 1, slot: 2))
        XCTAssertFalse(draw.losers[0][0].isWalkover, "nobody has a bye here — they have an opponent coming")
        XCTAssertEqual(draw.readyToDraw(bracket: .losers, round: 1).count, 0, "and nothing to draw yet")
    }

    /// A bye in the winners' side produces **no** loser, so that losers' position is genuinely empty
    /// and whoever faces it goes through.
    func testAByeInTheWinnersSideDropsNobody() {
        let draw = DoubleElimination.of(entrants: entrants(5), fixtures: [])
        XCTAssertEqual(draw.byes, 3)
        let first = draw.losers[0]
        let empty = first.flatMap { [$0.home, $0.away] }.filter { $0 == .bye }
        XCTAssertEqual(empty.count, 3, "three winners' walkovers drop nobody into the losers' side")
    }

    /// **The losers' side has to win the final twice**, because they arrive with a loss already and
    /// this is a competition you leave on your second one.
    func testTheLosersSideMustWinTheFinalTwice() {
        let field = entrants(4)
        func team(_ n: Int) -> Team { field[n - 1] }
        // 1 and 2 come through the winners' side; 4 comes through the losers'.
        var fixtures = [fixture(.winners, 1, 1, team(1), team(4), 5, 1),
                        fixture(.winners, 1, 2, team(2), team(3), 5, 1),
                        fixture(.losers, 1, 1, team(4), team(3), 5, 1),
                        fixture(.winners, 2, 1, team(1), team(2), 5, 1),
                        fixture(.losers, 2, 1, team(4), team(2), 5, 1)]

        // The losers' survivor wins the grand final. That only levels it — no champion yet.
        fixtures.append(fixture(.final, 1, 1, team(1), team(4), 1, 5))
        var draw = DoubleElimination.of(entrants: field, fixtures: fixtures)
        XCTAssertNil(draw.champion, "one win from the losers' side is not enough")
        XCTAssertNotNil(draw.reset, "so a second final is drawn")
        XCTAssertEqual(draw.readyToDraw(bracket: .final, round: 2).count, 1)

        fixtures.append(fixture(.final, 2, 1, team(1), team(4), 1, 5))
        draw = DoubleElimination.of(entrants: field, fixtures: fixtures)
        XCTAssertEqual(draw.champion?.id, "t4", "and winning it twice takes it")

        // Whereas the winners' side needs one, because they arrive unbeaten.
        let straight = fixtures.dropLast(2) + [fixture(.final, 1, 1, team(1), team(4), 5, 1)]
        let decided = DoubleElimination.of(entrants: field, fixtures: Array(straight))
        XCTAssertEqual(decided.champion?.id, "t1")
        XCTAssertNil(decided.reset, "and no second final is drawn")
    }

    /// Two entrants have no losers' side to drop into, so the challenger in the grand final is the
    /// loser of the winners' final itself. A bracket built for eight gets this wrong by reaching for
    /// a losers' round that does not exist.
    func testTwoEntrantsHaveNoLosersSideAndStillResolve() {
        let field = entrants(2)
        let draw = DoubleElimination.of(entrants: field, fixtures: [])
        XCTAssertTrue(draw.losers.isEmpty)
        XCTAssertEqual(draw.grandFinal?.away, .loserOf(round: 1, slot: 1))

        let (played, fixtures) = playItOut(field)
        XCTAssertNotNil(played.champion)
        XCTAssertEqual(fixtures.count, 2, "2n − 2 is two matches")
    }

    /// Only a double-elimination tournament has one of these.
    func testOnlyADoubleEliminationTournamentHasOne() {
        func tournament(_ shape: TournamentShape) -> Club {
            Club(id: "t", name: "The Feathers Open", kind: .tournament, meta: "", yourRole: .admin,
                 teams: entrants(4), shape: shape)
        }
        XCTAssertNotNil(tournament(.doubleElimination).doubleElimination)
        XCTAssertNil(tournament(.knockout).doubleElimination)
        XCTAssertNil(tournament(.roundRobin).doubleElimination)
        XCTAssertNil(tournament(.doubleElimination).draw, "and it is not a knockout either")
    }

    /// A match here cannot end level any more than a knockout's can.
    func testADrawnMatchIsNamedAsAProblem() {
        let field = entrants(4)
        let level = fixture(.winners, 1, 1, field[0], field[3], 3, 3)
        let draw = DoubleElimination.of(entrants: field, fixtures: [level])
        XCTAssertEqual(draw.problems.count, 1)
        XCTAssertTrue(draw.problems[0].contains("Nobody goes out on a draw"))
    }
}
