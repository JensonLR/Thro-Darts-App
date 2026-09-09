import Foundation
import XCTest
@testable import ThroApp

/// A league is teams, and a result always says where it came from (PD-019, PD-020, PD-021).
///
/// **These hold the arithmetic and the honesty, not the drawing.** The screens are drawn and not
/// tested — `tools/check_screens_reachable.py` holds that they can be opened at all. What is here is
/// the part that can be silently wrong: a table that adds up, an ordering that is total, a result
/// whose provenance survives to the row, and the shapes' counts.
final class LeagueTests: XCTestCase {

    private func team(_ id: String) -> Team { Team(id: id, name: id.capitalized) }

    private func fixture(_ id: String, _ home: String, _ away: String,
                         _ result: MatchResult? = nil) -> Fixture {
        Fixture(id: id, title: "\(home) v \(away)", when: "Tue 8pm", venue: "The Feathers",
                state: result == nil ? .scheduled : .played,
                homeTeamId: home, awayTeamId: away, result: result)
    }

    private func league(teams: [String], fixtures: [Fixture],
                        win: Int = 2, draw: Int = 1) -> Club {
        Club(id: "l", name: "Crediton & District", kind: .league, meta: "", yourRole: .admin,
             fixtures: fixtures, teams: teams.map(team), pointsForWin: win, pointsForDraw: draw)
    }

    private func scored(_ h: Int, _ a: Int) -> MatchResult {
        MatchResult(home: h, away: a, source: .scored(matchId: "m1"))
    }
    private func word(_ h: Int, _ a: Int) -> MatchResult {
        MatchResult(home: h, away: a, source: .recorded(by: "Pat"))
    }

    // MARK: - the table

    /// The whole point of a table: it adds up, and it is derived rather than stored so it cannot
    /// disagree with the fixtures under it.
    func testTheTableIsTheArithmeticOfItsResults() {
        let l = league(teams: ["feathers", "bell", "ship"],
                       fixtures: [fixture("1", "feathers", "bell", scored(7, 2)),
                                  fixture("2", "bell", "ship", word(5, 5)),
                                  fixture("3", "ship", "feathers", scored(4, 6))])
        let rows = Dictionary(uniqueKeysWithValues: l.table.map { ($0.team.id, $0) })

        XCTAssertEqual(rows["feathers"]?.played, 2)
        XCTAssertEqual(rows["feathers"]?.won, 2)
        XCTAssertEqual(rows["feathers"]?.points, 4)
        XCTAssertEqual(rows["feathers"]?.scoreFor, 13, "7 at home and 6 away")
        XCTAssertEqual(rows["feathers"]?.scoreAgainst, 6)
        XCTAssertEqual(rows["feathers"]?.difference, 7)

        XCTAssertEqual(rows["bell"]?.drawn, 1)
        XCTAssertEqual(rows["bell"]?.lost, 1)
        XCTAssertEqual(rows["bell"]?.points, 1, "a draw is worth one")
        XCTAssertEqual(rows["ship"]?.points, 1)
    }

    /// A fixture with no result is not a played fixture with a nil-nil in it. It is absent from the
    /// arithmetic entirely, which is why the screen has to say how many are missing.
    func testAFixtureWithNoResultCountsForNothing() {
        let l = league(teams: ["a", "b"], fixtures: [fixture("1", "a", "b")])
        XCTAssertEqual(l.table.first?.played, 0)
        XCTAssertEqual(l.table.first?.points, 0)
        XCTAssertFalse(l.tableIsWorthShowing, "a table of zeroes reads as a season nobody has won")
    }

    /// A played fixture nobody has entered a result for is the one row an admin must act on, and the
    /// league screen leads with it.
    func testAPlayedFixtureWithNoResultIsSurfacedRatherThanSwallowed() {
        let played = Fixture(id: "1", title: "a v b", when: "Tue 8pm", venue: "The Feathers",
                             state: .played, homeTeamId: "a", awayTeamId: "b", result: nil)
        let l = league(teams: ["a", "b"], fixtures: [played, fixture("2", "b", "a", scored(3, 1))])
        XCTAssertEqual(l.fixturesAwaitingResults.map(\.id), ["1"])
        XCTAssertTrue(played.awaitsResult)
        XCTAssertFalse(fixture("2", "b", "a", scored(3, 1)).awaitsResult, "this one has been said")
    }

    /// What a win is worth belongs to the league, not to THRØ (OD-022). The same results under
    /// different points produce different tables, which is the whole reason it is stored.
    func testThePointsBelongToTheLeague() {
        let results = [fixture("1", "a", "b", scored(5, 3)), fixture("2", "a", "c", word(4, 4))]
        let common = league(teams: ["a", "b", "c"], fixtures: results)
        let onePoint = league(teams: ["a", "b", "c"], fixtures: results, win: 1, draw: 0)
        XCTAssertEqual(common.table.first(where: { $0.team.id == "a" })?.points, 3, "2 + 1")
        XCTAssertEqual(onePoint.table.first(where: { $0.team.id == "a" })?.points, 1, "1 + 0")
    }

    /// **The ordering must be total.** Two teams level on everything have to come out in the same
    /// order every time, or a table reshuffles itself between draws for no reason a reader can see.
    func testTheOrderingIsTotalAndItsStepsAreInOrder() {
        // Level on points; separated by difference.
        let l = league(teams: ["a", "b"],
                       fixtures: [fixture("1", "a", "b", scored(9, 1)), fixture("2", "b", "a", scored(2, 0))])
        XCTAssertEqual(l.table.map(\.team.id), ["a", "b"], "one win each, a is +6 and b is −6")

        // Level on everything: the name decides, and it decides the same way twice.
        let level = league(teams: ["zeta", "alpha"],
                           fixtures: [fixture("1", "zeta", "alpha", scored(3, 3))])
        XCTAssertEqual(level.table.map(\.team.id), ["alpha", "zeta"])
        XCTAssertEqual(level.table.map(\.team.id), level.table.map(\.team.id))
    }

    // MARK: - where a result came from (PD-020)

    /// The count that lets a screen say which parts of a standing are backed by darts.
    func testEveryRowSaysHowMuchOfItIsEvidenced() {
        let l = league(teams: ["a", "b"],
                       fixtures: [fixture("1", "a", "b", scored(5, 1)),
                                  fixture("2", "b", "a", word(3, 2))])
        let a = l.table.first { $0.team.id == "a" }
        XCTAssertEqual(a?.played, 2)
        XCTAssertEqual(a?.evidenced, 1, "one of the two came from a match scored in THRØ")
        XCTAssertEqual(a?.unevidenced, 1)
    }

    /// **Both count, and neither is disguised as the other.** An official's word moves the table —
    /// a league that only worked when everybody used THRØ would not be a product — and it is never
    /// labelled as anything but somebody's word.
    func testAnOfficialsWordCountsForTheTableAndSaysSo() {
        let l = league(teams: ["a", "b"], fixtures: [fixture("1", "a", "b", word(6, 0))])
        XCTAssertEqual(l.table.first { $0.team.id == "a" }?.points, 2, "it counts")
        XCTAssertEqual(l.table.first { $0.team.id == "a" }?.evidenced, 0, "and nothing checked it")

        XCTAssertFalse(ResultSource.recorded(by: "Pat").isEvidenced)
        XCTAssertTrue(ResultSource.scored(matchId: "m1").isEvidenced)
        XCTAssertEqual(ResultSource.recorded(by: "Pat").label, "Recorded by Pat",
                       "whose word it is, on the row")
        XCTAssertTrue(ResultSource.recorded(by: "Pat").explanation.contains("cannot move a rating"))
    }

    /// A result for a team the league does not have is not counted into somebody else's row. It is
    /// dropped, because the alternative is a table with a phantom in it.
    func testAResultForATeamThatIsNotInTheLeagueIsNotCounted() {
        let l = league(teams: ["a", "b"], fixtures: [fixture("1", "a", "ghost", scored(5, 0))])
        XCTAssertEqual(l.table.first { $0.team.id == "a" }?.played, 0)
        XCTAssertEqual(l.table.count, 2, "and no row appears for the team that is not there")
    }

    // MARK: - the shapes (PD-021)

    /// The arithmetic each shape produces, against numbers anybody can check on paper.
    func testEachShapeCountsItsOwnMatches() {
        XCTAssertEqual(TournamentShape.knockout.matches(forEntrants: 8), 7, "everybody but the winner loses once")
        XCTAssertEqual(TournamentShape.knockout.matches(forEntrants: 6), 5, "byes are not matches")
        XCTAssertEqual(TournamentShape.roundRobin.matches(forEntrants: 6), 15, "6 × 5 ÷ 2")
        XCTAssertEqual(TournamentShape.roundRobin.matches(forEntrants: 2), 1)
        XCTAssertEqual(TournamentShape.doubleElimination.matches(forEntrants: 8), 14, "2n − 2, or one more")
        XCTAssertNil(TournamentShape.groups.matches(forEntrants: 16),
                     "a groups count follows from group sizes, which are set before it starts")
        XCTAssertEqual(TournamentShape.knockout.matches(forEntrants: 1), 0, "one entrant plays nobody")
    }

    /// Byes are the difference between the field and the next power of two, and a power of two has
    /// none. This is the number the tournament page puts on the screen.
    func testByesAreTheGapToTheNextPowerOfTwo() {
        XCTAssertEqual(TournamentShape.byes(forEntrants: 8), 0)
        XCTAssertEqual(TournamentShape.byes(forEntrants: 5), 3)
        XCTAssertEqual(TournamentShape.byes(forEntrants: 6), 2)
        XCTAssertEqual(TournamentShape.byes(forEntrants: 12), 4)
        XCTAssertEqual(TournamentShape.byes(forEntrants: 1), 0)
        // The identity that makes it right: field plus byes is a power of two, always.
        for n in 2...64 {
            let bracket = n + TournamentShape.byes(forEntrants: n)
            XCTAssertEqual(bracket & (bracket - 1), 0, "\(n) entrants gives a bracket of \(bracket)")
            XCTAssertGreaterThanOrEqual(bracket, n)
        }
    }

    /// A knockout has no table. Drawing it one would be drawing it a league, which is the mistake
    /// these three screens exist to stop making.
    func testOnlyARoundRobinHasStandings() {
        func tournament(_ shape: TournamentShape) -> Club {
            Club(id: "t", name: "The Feathers Open", kind: .tournament, meta: "", yourRole: .admin,
                 fixtures: [fixture("1", "a", "b", scored(3, 1))],
                 teams: [team("a"), team("b")], shape: shape)
        }
        XCTAssertEqual(tournament(.roundRobin).standings.count, 2)
        XCTAssertTrue(tournament(.knockout).standings.isEmpty)
        XCTAssertTrue(tournament(.groups).standings.isEmpty)
        XCTAssertTrue(tournament(.doubleElimination).standings.isEmpty)
        // And a league's table is a league's: a tournament never has one under that name.
        XCTAssertTrue(tournament(.roundRobin).table.isEmpty)
    }

    // MARK: - what the numbers are (PD-022)

    /// A result of `3–1` means nothing without a unit, so the unit is a value rather than a label
    /// somebody types — and it says itself correctly for one as well as for many.
    func testTheUnitSaysItselfForOneAndForMany() {
        XCTAssertEqual(ResultUnit.legs.counted(7), "7 legs")
        XCTAssertEqual(ResultUnit.legs.counted(1), "1 leg")
        XCTAssertEqual(ResultUnit.matches.counted(1), "1 match")
        XCTAssertEqual(ResultUnit.matches.counted(5), "5 matches", "not '5 matchs'")
        XCTAssertEqual(ResultUnit.points.counted(1), "1 point")
        XCTAssertEqual(ResultUnit.points.counted(0), "0 points")
        XCTAssertEqual(Set(ResultUnit.allCases.map(\.label)).count, 3)
    }

    /// **The moment the unit settles.** While a league has no results, changing it costs nothing;
    /// after the first one, changing it would turn every number already entered into a claim about
    /// something else — so the screen stops offering it and the store refuses it.
    func testTheUnitIsOpenUntilThereIsAResultToReinterpret() {
        let empty = league(teams: ["a", "b"], fixtures: [fixture("1", "a", "b")])
        XCTAssertTrue(empty.setupIsStillOpen)

        let played = league(teams: ["a", "b"], fixtures: [fixture("1", "a", "b", word(3, 1))])
        XCTAssertFalse(played.setupIsStillOpen)

        // A cancelled or postponed fixture is not a result, so it settles nothing.
        let scheduled = league(teams: ["a", "b"],
                               fixtures: [fixture("1", "a", "b"), fixture("2", "b", "a")])
        XCTAssertTrue(scheduled.setupIsStillOpen)
    }

    // MARK: - the three kinds are three things

    /// The founder's complaint, as an assertion: the three do not describe themselves the same way.
    func testTheThreeKindsAreCountedInTheirOwnUnits() {
        XCTAssertEqual(ClubStore.meta(.club, members: 12, teams: 0), "12 members")
        XCTAssertEqual(ClubStore.meta(.league, members: 3, teams: 8), "8 teams",
                       "a league of eight teams is not 'three members'")
        XCTAssertEqual(ClubStore.meta(.tournament, members: 0, teams: 6), "6 entrants")
        XCTAssertEqual(ClubStore.meta(.league, members: 3, teams: 1), "1 team")
        XCTAssertEqual(ClubStore.meta(.league, members: 3, teams: 0), "No teams yet")
    }

    /// Who may do what, per kind. A club has no teams to manage; a league's results are an
    /// official's to enter and not only an admin's.
    func testWhoMayDoWhatDiffersByKindAndByRole() {
        func org(_ kind: OrgKind, _ role: OrgRole?) -> Club {
            Club(id: "o", name: "X", kind: kind, meta: "", yourRole: role)
        }
        XCTAssertFalse(org(.club, .admin).mayManageTeams, "a club competes as itself")
        XCTAssertTrue(org(.league, .admin).mayManageTeams)
        XCTAssertTrue(org(.tournament, .admin).mayManageTeams)
        XCTAssertFalse(org(.league, .official).mayManageTeams, "the roster is an admin's")

        XCTAssertTrue(org(.league, .official).mayRecordResults,
                      "the person at the venue on the night is not usually the person who set it up")
        XCTAssertFalse(org(.league, .member).mayRecordResults)
        XCTAssertFalse(org(.league, nil).mayRecordResults, "a stranger says nothing about anything")

        XCTAssertEqual(org(.league, .admin).competitorNoun.many, "Teams")
        XCTAssertEqual(org(.tournament, .admin).competitorNoun.many, "Entrants")
    }

    /// **This screen was a dead end.** It said *add them first* and offered nothing but Back:
    /// somebody who came to add a fixture was told what was missing and left to find the list
    /// themselves. It carries the way there now — and the moment it does, the sentence has to know
    /// which reader it is talking to, because sending somebody without the right to a screen that
    /// refuses them is worse than the sentence on its own.
    func testTheNotEnoughNoteSaysSomethingDifferentToSomebodyWhoCannotFixIt() {
        let admin = NewTeamFixtureScreen.notEnoughNote(entered: 1, noun: "teams", kind: "league",
                                                       mayManage: true)
        let watcher = NewTeamFixtureScreen.notEnoughNote(entered: 1, noun: "teams", kind: "league",
                                                         mayManage: false)
        XCTAssertNotEqual(admin, watcher)
        XCTAssertTrue(admin.contains("Add them first"), admin)
        XCTAssertFalse(watcher.contains("Add them"),
                       "this tells somebody to do a thing they will be refused: \(watcher)")
        XCTAssertTrue(watcher.contains("An admin of this league"), watcher)

        // And it counts what is actually there, in the singular and the plural.
        XCTAssertTrue(admin.contains("is one"), admin)
        XCTAssertTrue(NewTeamFixtureScreen.notEnoughNote(entered: 0, noun: "teams", kind: "league",
                                                         mayManage: true).contains("are none"))
    }
}
