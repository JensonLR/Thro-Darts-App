import Foundation
import XCTest
@testable import ThroApp

/// The knockout draw (PD-021).
///
/// **A draw is either right or quietly wrong**, and a plausible-looking bracket is the worst kind of
/// wrong: nobody checks a seeding by eye. So these assert the identities a bracket has to satisfy
/// rather than one worked example — the seed order sums, the halves, the meeting round of any two
/// seeds — and then they play a whole tournament through and check who comes out.
final class BracketTests: XCTestCase {

    private func entrants(_ n: Int) -> [Team] {
        (1...n).map { Team(id: "t\($0)", name: "Seed \($0)") }
    }

    private func played(round: Int, slot: Int, _ home: Team, _ away: Team,
                        _ h: Int, _ a: Int) -> Fixture {
        Fixture(id: "\(round)-\(slot)", title: "\(home.name) v \(away.name)", when: "Tue", venue: "",
                state: .played, homeTeamId: home.id, awayTeamId: away.id,
                result: MatchResult(home: h, away: a, source: .recorded(by: "Pat")),
                round: round, slot: slot)
    }

    // MARK: - the seeding itself

    /// The identities that make a seeded bracket a seeded bracket, for every size THRØ can draw.
    func testTheSeedOrderIsAPermutationWhosePairsAllSumTheSame() {
        for power in 1...8 {
            let size = 1 << power
            let order = Draw.seedOrder(size: size)
            XCTAssertEqual(order.count, size, "a bracket of \(size) has \(size) positions")
            XCTAssertEqual(Set(order), Set(1...size), "every seed appears exactly once")

            // The property that makes it seeded: in round one, each pair sums to size + 1 — so the
            // top seed meets the bottom one, the second meets the second-bottom, and so on.
            for slot in stride(from: 0, to: size, by: 2) {
                XCTAssertEqual(order[slot] + order[slot + 1], size + 1,
                               "\(order[slot]) v \(order[slot + 1]) in a bracket of \(size)")
            }
            // And the top two seeds are in opposite halves, so they can only meet in the final.
            let first = order.firstIndex(of: 1)!, second = order.firstIndex(of: 2)!
            XCTAssertNotEqual(first < size / 2, second < size / 2,
                              "seeds 1 and 2 must not share a half of a \(size) bracket")
        }
    }

    /// A field is fitted into the next power of two, and the difference is the byes — the same
    /// arithmetic the tournament page puts on the screen before anybody draws anything.
    func testTheBracketIsTheNextPowerOfTwoAndTheGapIsTheByes() {
        for n in 2...64 {
            let size = Draw.size(forEntrants: n)
            XCTAssertEqual(size & (size - 1), 0, "\(n) gives \(size), which must be a power of two")
            XCTAssertGreaterThanOrEqual(size, n)
            XCTAssertLessThan(size / 2, n, "and it must be the NEXT one, not a larger one")
            XCTAssertEqual(size - n, TournamentShape.byes(forEntrants: n),
                           "the page's number and the draw's are the same number")
        }
        XCTAssertEqual(Draw.size(forEntrants: 1), 0, "one entrant is not a tournament")
        XCTAssertEqual(Draw.rounds(forSize: 8), 3)
        XCTAssertEqual(Draw.rounds(forSize: 2), 1)
    }

    /// **Byes go to the top of the entry order.** With no rating (OD-001) the entry order is the
    /// only seeding there is, and the page says so — but it must actually be what happens.
    func testTheByesGoToTheEntrantsWhoWentInFirst() {
        let draw = Draw.of(entrants: entrants(5), fixtures: [])
        XCTAssertEqual(draw.size, 8)
        XCTAssertEqual(draw.byes, 3)

        let walkovers = draw.rounds[0].filter(\.isWalkover)
        XCTAssertEqual(walkovers.count, 3)
        XCTAssertEqual(Set(walkovers.compactMap { $0.winner?.id }), ["t1", "t2", "t3"],
                       "the first three entered are the three who do not play in round one")

        // Seeds 4 and 5 play each other, which is the only real match in the round.
        let real = draw.rounds[0].filter { !$0.isWalkover }
        XCTAssertEqual(real.count, 1)
        XCTAssertEqual(Set([real[0].home.team?.id, real[0].away.team?.id]), ["t4", "t5"])
    }

    /// A bye is not a win. It advances somebody and appears in no record of results.
    func testAByeAdvancesSomebodyAndIsNotAResult() {
        let draw = Draw.of(entrants: entrants(3), fixtures: [])
        let walkover = draw.rounds[0].first { $0.isWalkover }
        XCTAssertNotNil(walkover?.winner, "somebody goes through")
        XCTAssertNil(walkover?.fixture, "and there is no fixture, because nobody played")
        XCTAssertNil(walkover?.playable, "so there is nothing to draw")
        XCTAssertTrue(draw.readyToDraw(round: 1).allSatisfy { !$0.isWalkover })
    }

    // MARK: - playing one through

    /// A whole tournament, played out. Eight entrants, seven matches, one winner — and the winner is
    /// the one who actually won, not the one the seeding expected.
    func testAWholeKnockoutResolvesToTheEntrantWhoWonIt() {
        let field = entrants(8)
        func team(_ n: Int) -> Team { field[n - 1] }

        var draw = Draw.of(entrants: field, fixtures: [])
        XCTAssertEqual(draw.rounds.count, 3)
        XCTAssertEqual(draw.rounds.map(\.count), [4, 2, 1])
        XCTAssertEqual(draw.byes, 0)
        XCTAssertNil(draw.champion)

        // Round one, as the seeding lays it out: 1v8, 4v5, 2v7, 3v6. The 8 seed wins theirs.
        var fixtures = [played(round: 1, slot: 1, team(1), team(8), 2, 5),
                        played(round: 1, slot: 2, team(4), team(5), 5, 1),
                        played(round: 1, slot: 3, team(2), team(7), 5, 0),
                        played(round: 1, slot: 4, team(3), team(6), 3, 5)]
        draw = Draw.of(entrants: field, fixtures: fixtures)
        XCTAssertTrue(draw.isComplete(round: 1))
        XCTAssertEqual(draw.rounds[1].map { $0.home.team?.id }, ["t8", "t2"])
        XCTAssertEqual(draw.rounds[1].map { $0.away.team?.id }, ["t4", "t6"])
        XCTAssertEqual(draw.readyToDraw(round: 2).count, 2)
        XCTAssertFalse(draw.isComplete(round: 2))

        fixtures += [played(round: 2, slot: 1, team(8), team(4), 5, 3),
                     played(round: 2, slot: 2, team(2), team(6), 1, 5)]
        draw = Draw.of(entrants: field, fixtures: fixtures)
        XCTAssertEqual(draw.rounds[2][0].home.team?.id, "t8")
        XCTAssertEqual(draw.rounds[2][0].away.team?.id, "t6")

        fixtures += [played(round: 3, slot: 1, team(8), team(6), 6, 4)]
        draw = Draw.of(entrants: field, fixtures: fixtures)
        XCTAssertEqual(draw.champion?.id, "t8", "the bottom seed won it, and the draw says so")
        XCTAssertTrue(draw.isComplete(round: 3))
        XCTAssertEqual(draw.readyToDraw(round: 3).count, 0, "nothing left to draw")
    }

    /// Until a round is played, the next one holds **where its players will come from** rather than a
    /// blank — so the page can say "winner of round 1 match 2" instead of showing an empty row.
    func testAnUnplayedRoundIsHeldAsWhereItsPlayersComeFrom() {
        let draw = Draw.of(entrants: entrants(4), fixtures: [])
        XCTAssertEqual(draw.rounds[1][0].home, .winnerOf(round: 1, slot: 1))
        XCTAssertEqual(draw.rounds[1][0].away, .winnerOf(round: 1, slot: 2))
        XCTAssertNil(draw.rounds[1][0].playable, "and there is nothing to draw yet")
        XCTAssertEqual(draw.readyToDraw(round: 2).count, 0)
    }

    /// A match already drawn is not offered again, which is what stops a second tap creating a
    /// second fixture for the same slot.
    func testAMatchThatIsAlreadyDrawnIsNotOfferedAgain() {
        let field = entrants(4)
        let drawn = Fixture(id: "f", title: "x", when: "Tue", venue: "", state: .scheduled,
                            homeTeamId: field[0].id, awayTeamId: field[3].id, round: 1, slot: 1)
        let draw = Draw.of(entrants: field, fixtures: [drawn])
        XCTAssertEqual(draw.readyToDraw(round: 1).map(\.slot), [2],
                       "slot 1 has a fixture already; only slot 2 is left")
        XCTAssertNotNil(draw.rounds[0][0].fixture)
    }

    /// **A knockout match cannot end level.** The result screen accepts a draw, because a league
    /// fixture may legitimately be one — so the tournament has to notice rather than quietly produce
    /// a round nobody advances from.
    func testADrawnKnockoutMatchIsNamedAsAProblemAndAdvancesNobody() {
        let field = entrants(2)
        let level = played(round: 1, slot: 1, field[0], field[1], 3, 3)
        let draw = Draw.of(entrants: field, fixtures: [level])
        XCTAssertNil(draw.rounds[0][0].winner, "nobody goes through")
        XCTAssertNil(draw.champion)
        XCTAssertFalse(draw.isComplete(round: 1))
        XCTAssertEqual(draw.problems.count, 1)
        XCTAssertTrue(draw.problems[0].contains("cannot end level"))

        // And a decided one is not a problem.
        let decided = played(round: 1, slot: 1, field[0], field[1], 3, 1)
        XCTAssertTrue(Draw.of(entrants: field, fixtures: [decided]).problems.isEmpty)
    }

    /// Only a knockout is a bracket. A round robin is a table and a groups tournament needs its
    /// group sizes set first, so neither is handed a draw it did not ask for.
    func testOnlyAKnockoutHasADraw() {
        func tournament(_ shape: TournamentShape?, entrants n: Int = 4) -> Club {
            Club(id: "t", name: "The Feathers Open", kind: .tournament, meta: "", yourRole: .admin,
                 teams: entrants(n), shape: shape)
        }
        XCTAssertNotNil(tournament(.knockout).draw)
        XCTAssertNil(tournament(.roundRobin).draw)
        XCTAssertNil(tournament(.groups).draw)
        XCTAssertNil(tournament(.doubleElimination).draw)
        XCTAssertNil(tournament(nil).draw)
        XCTAssertNil(tournament(.knockout, entrants: 1).draw, "one entrant is not a tournament")
        // And a league never has one, whatever is in it.
        XCTAssertNil(Club(id: "l", name: "A league", kind: .league, meta: "", teams: entrants(4)).draw)
    }

    /// The names people actually use. A page that told somebody watching a final it was "round 3 of
    /// 3" would be right and useless.
    func testTheLastRoundsAreCalledWhatPeopleCallThem() {
        XCTAssertEqual(TournamentScreen.roundName(3, of: 3), "Final")
        XCTAssertEqual(TournamentScreen.roundName(2, of: 3), "Semi-finals")
        XCTAssertEqual(TournamentScreen.roundName(1, of: 3), "Quarter-finals")
        XCTAssertEqual(TournamentScreen.roundName(1, of: 5), "Round 1")
        XCTAssertEqual(TournamentScreen.roundName(1, of: 1), "Final", "a two-entrant draw is a final")
    }
}
