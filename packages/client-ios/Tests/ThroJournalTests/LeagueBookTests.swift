import XCTest
@testable import ThroJournal

/// Teams, results and shapes in the book (PD-019, PD-020, PD-021).
///
/// **What these hold is what the database refuses.** A result whose provenance cannot be shown is
/// the one thing PD-020 says must never reach a table, and the way to guarantee that is not for
/// every screen to remember — it is for the row to be unwritable. So the rules are asserted here,
/// against a real SQLite file, in the same place the durability configuration is proved.
final class LeagueBookTests: XCTestCase {

    private var path: String!

    override func setUpWithError() throws {
        try super.setUpWithError()
        path = NSTemporaryDirectory() + "thro-league-\(UUID().uuidString).sqlite"
    }

    override func tearDown() {
        try? FileManager.default.removeItem(atPath: path)
        super.tearDown()
    }

    private func league(_ book: ClubBook) throws -> String {
        try book.createClub(name: "Crediton & District", kind: "league").id
    }

    /// A league's competitors are teams, and they survive being written (PD-019).
    func testALeagueKeepsItsTeams() throws {
        let book = try ClubBook(path: path)
        let id = try league(book)
        try book.addTeam(to: id, name: "The Feathers A")
        try book.addTeam(to: id, name: "The Feathers B")

        let teams = try book.teams(of: id)
        XCTAssertEqual(teams.map(\.name), ["The Feathers A", "The Feathers B"])
        // Reopened, because a roster that only exists in memory is not a roster.
        XCTAssertEqual(try ClubBook(path: path).teams(of: id).count, 2)
    }

    /// **Half a team fixture is not one.** Everything that reads one — the table, the result, the
    /// screen — needs both sides, so a row with one is refused where it is written rather than
    /// breaking something later.
    func testAFixtureWithOneTeamIsRefused() throws {
        let book = try ClubBook(path: path)
        let id = try league(book)
        let home = try book.addTeam(to: id, name: "The Feathers").id

        XCTAssertThrowsError(try book.addFixture(to: id, title: "x", when: Date(), venue: "",
                                                 homeTeam: home, awayTeam: nil))
        XCTAssertThrowsError(try book.addFixture(to: id, title: "x", when: Date(), venue: "",
                                                 homeTeam: nil, awayTeam: home))
        XCTAssertThrowsError(try book.addFixture(to: id, title: "x", when: Date(), venue: "",
                                                 homeTeam: home, awayTeam: home),
                             "and a team does not play itself")
        XCTAssertThrowsError(try book.addFixture(to: id, title: "x", when: Date(), venue: "",
                                                 homeTeam: home, awayTeam: "nobody"),
                             "nor a team this league has never heard of")
        // A club's fixture, with neither, is the ordinary case and is untouched.
        XCTAssertNoThrow(try book.addFixture(to: id, title: "Home to The Bell", when: Date(), venue: ""))
    }

    /// A result carries where it came from, both ways, and it survives the round trip (PD-020).
    func testAResultKeepsItsSource() throws {
        let book = try ClubBook(path: path)
        let id = try league(book)
        let a = try book.addTeam(to: id, name: "A").id
        let b = try book.addTeam(to: id, name: "B").id
        let one = try book.addFixture(to: id, title: "A v B", when: Date(), venue: "",
                                      homeTeam: a, awayTeam: b).id
        let two = try book.addFixture(to: id, title: "B v A", when: Date(), venue: "",
                                      homeTeam: b, awayTeam: a).id

        try book.recordResult(fixture: one, in: id, home: 7, away: 2, source: "scored", matchId: "m1")
        try book.recordResult(fixture: two, in: id, home: 5, away: 5, source: "recorded", recordedBy: "Pat")

        let results = try ClubBook(path: path).results(of: id)
        let scored = results.first(where: { $0.fixtureId == one })
        XCTAssertEqual(scored?.source, "scored")
        XCTAssertEqual(scored?.matchId, "m1")
        XCTAssertNil(scored?.recordedBy, "a scored result is nobody's word")
        XCTAssertEqual(scored?.home, 7)

        let word = results.first(where: { $0.fixtureId == two })
        XCTAssertEqual(word?.source, "recorded")
        XCTAssertEqual(word?.recordedBy, "Pat")
        XCTAssertNil(word?.matchId, "and somebody's word points at no match")
    }

    /// **The rule the CHECK exists for.** A result that cannot say where it came from is not a
    /// result, and there is no combination of arguments that writes one.
    func testAResultThatCannotSayWhereItCameFromIsRefused() throws {
        let book = try ClubBook(path: path)
        let id = try league(book)
        let a = try book.addTeam(to: id, name: "A").id
        let b = try book.addTeam(to: id, name: "B").id
        let f = try book.addFixture(to: id, title: "A v B", when: Date(), venue: "",
                                    homeTeam: a, awayTeam: b).id

        XCTAssertThrowsError(try book.recordResult(fixture: f, in: id, home: 1, away: 0,
                                                   source: "scored"),
                             "scored, with no match to point at")
        XCTAssertThrowsError(try book.recordResult(fixture: f, in: id, home: 1, away: 0,
                                                   source: "recorded"),
                             "somebody's word, with nobody's name on it")
        XCTAssertThrowsError(try book.recordResult(fixture: f, in: id, home: 1, away: 0,
                                                   source: "recorded", recordedBy: "   "),
                             "nor a name that is only spaces")
        XCTAssertThrowsError(try book.recordResult(fixture: f, in: id, home: 1, away: 0,
                                                   source: "scored", matchId: "m", recordedBy: "Pat"),
                             "nor both at once, which would be two answers to one question")
        XCTAssertThrowsError(try book.recordResult(fixture: f, in: id, home: 1, away: 0,
                                                   source: "invented", recordedBy: "Pat"))
        XCTAssertThrowsError(try book.recordResult(fixture: f, in: id, home: -1, away: 0,
                                                   source: "recorded", recordedBy: "Pat"))
        XCTAssertEqual(try book.results(of: id).count, 0, "and none of them wrote anything")
    }

    /// Recording a result means the fixture was played. A cancelled one is refused: nobody threw, so
    /// there is nothing to record and a result on it would be a claim about a match that never was.
    func testARecordedResultPlaysTheFixtureAndACancelledOneRefusesIt() throws {
        let book = try ClubBook(path: path)
        let id = try league(book)
        let a = try book.addTeam(to: id, name: "A").id
        let b = try book.addTeam(to: id, name: "B").id
        let played = try book.addFixture(to: id, title: "A v B", when: Date(), venue: "",
                                         homeTeam: a, awayTeam: b).id
        let off = try book.addFixture(to: id, title: "B v A", when: Date(), venue: "",
                                      homeTeam: b, awayTeam: a).id

        try book.recordResult(fixture: played, in: id, home: 3, away: 1,
                              source: "recorded", recordedBy: "Pat")
        XCTAssertEqual(try book.fixtures(of: id).first(where: { $0.id == played })?.state, "played")

        try book.moveFixture(off, in: id, to: "cancelled")
        XCTAssertThrowsError(try book.recordResult(fixture: off, in: id, home: 3, away: 1,
                                                   source: "recorded", recordedBy: "Pat"))
        // And a fixture that is not between teams has no team result to record.
        let typed = try book.addFixture(to: id, title: "Home to The Bell", when: Date(), venue: "").id
        XCTAssertThrowsError(try book.recordResult(fixture: typed, in: id, home: 3, away: 1,
                                                   source: "recorded", recordedBy: "Pat"))
    }

    /// Removing a team takes its fixtures and their results with it. Deliberate: a fixture whose
    /// home side no longer exists is a row the table would have to guess about.
    func testRemovingATeamTakesItsFixturesAndResults() throws {
        let book = try ClubBook(path: path)
        let id = try league(book)
        let a = try book.addTeam(to: id, name: "A").id
        let b = try book.addTeam(to: id, name: "B").id
        let c = try book.addTeam(to: id, name: "C").id
        let ab = try book.addFixture(to: id, title: "A v B", when: Date(), venue: "",
                                     homeTeam: a, awayTeam: b).id
        _ = try book.addFixture(to: id, title: "B v C", when: Date(), venue: "",
                                homeTeam: b, awayTeam: c)
        try book.recordResult(fixture: ab, in: id, home: 4, away: 4,
                              source: "recorded", recordedBy: "Pat")

        XCTAssertEqual(try book.fixtureCount(forTeam: b, in: id), 2, "said before it happens")
        try book.removeTeam(b, from: id)

        XCTAssertEqual(try book.teams(of: id).map(\.name), ["A", "C"])
        XCTAssertEqual(try book.fixtures(of: id).count, 0, "both of B's fixtures go with it")
        XCTAssertEqual(try book.results(of: id).count, 0, "and the result recorded against one")
    }

    /// A tournament's shape is asked once and belongs to a tournament (PD-021). A shape on anything
    /// else is refused rather than quietly dropped, and one that reaches a read anyway is not shown.
    func testAShapeBelongsToATournamentAndOnlyToOne() throws {
        let book = try ClubBook(path: path)
        let open = try book.createClub(name: "The Feathers Open", kind: "tournament",
                                       shape: "doubleElimination")
        XCTAssertEqual(open.shape, "doubleElimination")
        XCTAssertEqual(try ClubBook(path: path).clubs().first(where: { $0.id == open.id })?.shape,
                       "doubleElimination")

        XCTAssertThrowsError(try book.createClub(name: "A league", kind: "league", shape: "knockout"),
                             "a league has no shape, and asking for one is a mistake worth saying")
        XCTAssertThrowsError(try book.createClub(name: "A tournament", kind: "tournament",
                                                 shape: "swiss"),
                             "and a shape this build does not know is refused rather than stored")

        // A row that got a shape some other way reads back without one: a read never guesses, and a
        // shape decides what every round means.
        let plain = try book.createClub(name: "A club", kind: "team")
        try book.forTests("UPDATE club SET shape = 'knockout' WHERE club_id = '\(plain.id)';")
        XCTAssertNil(try book.clubs().first(where: { $0.id == plain.id })?.shape)
    }

    /// What a win is worth belongs to the league (OD-022), and a league written before points were
    /// stored reads back with the common ones rather than with zero.
    func testPointsAreTheLeaguesAndDefaultRatherThanReadingAsZero() throws {
        let book = try ClubBook(path: path)
        let id = try league(book)
        XCTAssertEqual(try book.clubs().first(where: { $0.id == id })?.pointsForWin, 2)
        XCTAssertEqual(try book.clubs().first(where: { $0.id == id })?.pointsForDraw, 1)

        try book.setPoints(win: 3, draw: 0, on: id)
        XCTAssertEqual(try ClubBook(path: path).clubs().first(where: { $0.id == id })?.pointsForWin, 3)
        XCTAssertEqual(try ClubBook(path: path).clubs().first(where: { $0.id == id })?.pointsForDraw, 0)
        XCTAssertThrowsError(try book.setPoints(win: -1, draw: 0, on: id))

        // The migration case: a league from before this column existed.
        try book.forTests("UPDATE club SET points_win = NULL, points_draw = NULL WHERE club_id = '\(id)';")
        let old = try book.clubs().first(where: { $0.id == id })
        XCTAssertEqual(old?.pointsForWin, 2, "null is not nought — it is a league that never said")
        XCTAssertEqual(old?.pointsForDraw, 1)
    }

    /// What a league's results are counted in (PD-022), and the one moment it can be changed.
    ///
    /// **This is the decision that could not be made retroactively**, which is why it was asked
    /// before any league data existed: a stored `3–1` with no unit on it cannot be reinterpreted.
    func testAUnitIsChosenOnceAndSettlesTheMomentThereIsAResult() throws {
        let book = try ClubBook(path: path)
        let id = try book.createClub(name: "Crediton & District", kind: "league", unit: "legs").id
        XCTAssertEqual(try ClubBook(path: path).clubs().first(where: { $0.id == id })?.unit, "legs")

        // Changeable while nothing depends on it: an admin who picked wrong on day one can fix it.
        try book.setUnit("matches", on: id)
        XCTAssertEqual(try book.clubs().first(where: { $0.id == id })?.unit, "matches")

        let a = try book.addTeam(to: id, name: "A").id
        let b = try book.addTeam(to: id, name: "B").id
        let f = try book.addFixture(to: id, title: "A v B", when: Date(), venue: "",
                                    homeTeam: a, awayTeam: b).id
        try book.recordResult(fixture: f, in: id, home: 5, away: 4,
                              source: "recorded", recordedBy: "Pat")

        // And settled the moment there is a number it would reinterpret.
        XCTAssertThrowsError(try book.setUnit("points", on: id)) { error in
            XCTAssertEqual(error as? ClubBookError, .unitIsSettled(1),
                           "and the refusal says how many results are in the way")
        }
        XCTAssertEqual(try book.clubs().first(where: { $0.id == id })?.unit, "matches")
    }

    /// A unit belongs to something that has a table. A club has no results to count, and a unit this
    /// build does not know is refused rather than stored — and one that reaches a row is not shown.
    func testAUnitBelongsToACompetitionAndIsNeverGuessedAt() throws {
        let book = try ClubBook(path: path)
        XCTAssertThrowsError(try book.createClub(name: "The Feathers", kind: "team", unit: "legs"))
        XCTAssertThrowsError(try book.createClub(name: "A league", kind: "league", unit: "frames"))

        // A league from before this was asked has no unit, and nothing invents one for it.
        let old = try book.createClub(name: "Old league", kind: "league").id
        XCTAssertNil(try book.clubs().first(where: { $0.id == old })?.unit,
                     "nil is a real answer — the screens say so rather than labelling numbers")
        try book.forTests("UPDATE club SET result_unit = 'frames' WHERE club_id = '\(old)';")
        XCTAssertNil(try book.clubs().first(where: { $0.id == old })?.unit,
                     "and a unit this build cannot read is not shown either")
    }

    /// A result row that lost its provenance — from an edited file, or a build that should not have
    /// written it — is **dropped on read**, not handed over with the source missing.
    func testAResultRowWithNoProvenanceIsDroppedOnRead() throws {
        let book = try ClubBook(path: path)
        let id = try league(book)
        let a = try book.addTeam(to: id, name: "A").id
        let b = try book.addTeam(to: id, name: "B").id
        let f = try book.addFixture(to: id, title: "A v B", when: Date(), venue: "",
                                    homeTeam: a, awayTeam: b).id
        try book.recordResult(fixture: f, in: id, home: 6, away: 1,
                              source: "recorded", recordedBy: "Pat")
        XCTAssertEqual(try book.results(of: id).count, 1)

        // **The CHECK will not even let it be broken**, which is the stronger of the two guarantees
        // and is asserted first. This started as a test that planted the row directly and failed on
        // CI, because the constraint is tighter than I had assumed when I wrote the test.
        XCTAssertThrowsError(try book.forTests(
            "UPDATE fixture_result SET source = 'guessed' WHERE fixture_id = '\(f)';"))
        XCTAssertEqual(try book.results(of: id).count, 1, "and the row it protected is untouched")

        // A file some other build wrote — an older schema, a newer one, or an edited copy — carries
        // no such promise. Rebuilt without the CHECK, which is the only honest way to reach the read
        // and prove it drops what this build's write could never have made.
        try book.forTests("""
            DROP TABLE fixture_result;
            CREATE TABLE fixture_result (
              club_id TEXT NOT NULL, fixture_id TEXT NOT NULL,
              home_score INTEGER NOT NULL, away_score INTEGER NOT NULL,
              source TEXT NOT NULL, match_id TEXT, recorded_by TEXT, recorded_at TEXT NOT NULL,
              PRIMARY KEY (club_id, fixture_id));
            INSERT INTO fixture_result VALUES
              ('\(id)', '\(f)', 6, 1, 'guessed', NULL, NULL, '2026-01-01T00:00:00Z'),
              ('\(id)', 'other', 3, 0, 'scored', NULL, NULL, '2026-01-01T00:00:00Z'),
              ('\(id)', 'third', 2, 2, 'recorded', NULL, NULL, '2026-01-01T00:00:00Z');
            """)
        XCTAssertEqual(try book.results(of: id).count, 0,
                       "a source nobody knows, a scored result with no match, and somebody's word "
                       + "with nobody's name — a result nobody can attribute is the one thing a "
                       + "table must not contain")
    }
}
