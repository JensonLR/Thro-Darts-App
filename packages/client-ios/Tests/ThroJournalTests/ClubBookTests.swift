import XCTest
import SQLite3
@testable import ThroJournal

/// The book a captain keeps on their phone (PD-009). Every test here holds a rule the Kotlin domain
/// also states, or a way the store could lie to a screen.
final class ClubBookTests: XCTestCase {

    private var path: String!

    override func setUp() {
        super.setUp()
        path = NSTemporaryDirectory() + "thro-clubs-\(UUID().uuidString).sqlite"
    }

    override func tearDown() {
        for suffix in ["", "-wal", "-shm", "-journal"] {
            try? FileManager.default.removeItem(atPath: path + suffix)
        }
        super.tearDown()
    }

    private func open() throws -> ClubBook { try ClubBook(path: path) }

    /// The roster is written as carefully as a leg. There is no reason for it not to be, and a book
    /// that lost a member on a power cut would be a book nobody trusts with their team.
    func testTheMeasuredConfigurationIsInForceHereToo() throws {
        let book = try open()
        XCTAssertEqual(book.configuration, DurabilityConfiguration.measured)
        // Proved by the open succeeding: `Journal.configure` reads every pragma back and throws
        // when the database reports something else.
        XCTAssertNoThrow(try book.createClub(name: "The Feathers", kind: "team"))
    }

    func testAClubIsWrittenAndReadBackAcrossAReopen() throws {
        let made = try open().createClub(name: "  The Feathers  ", kind: "team", accentHex: "#0f3d2e")
        XCTAssertEqual(made.name, "The Feathers", "a typed name is trimmed, because people type spaces")
        XCTAssertEqual(made.accentHex, "0F3D2E", "a hash is accepted and dropped; the digits are stored")

        let reopened = try open()
        let clubs = try reopened.clubs()
        XCTAssertEqual(clubs.count, 1)
        XCTAssertEqual(clubs[0].id, made.id)
        XCTAssertEqual(clubs[0].name, "The Feathers")
        XCTAssertEqual(clubs[0].kind, "team")
        XCTAssertEqual(clubs[0].accentHex, "0F3D2E")
    }

    /// `an organisation needs a name it can be called by`, the same refusal the Kotlin domain makes.
    func testAClubWithoutANameIsRefused() throws {
        let book = try open()
        XCTAssertThrowsError(try book.createClub(name: "   ", kind: "team")) { error in
            XCTAssertEqual(error as? ClubBookError, .blankName)
        }
        XCTAssertEqual(try book.clubs().count, 0, "nothing was written")
    }

    /// Six hex digits or nothing — the shape `Colour` refuses in Kotlin. A colour that is not a
    /// colour must not reach the contrast rule, which would then have nothing to measure.
    func testAnAccentIsSixHexDigitsOrNothing() throws {
        let book = try open()
        for bad in ["green", "#12345", "0f3d2eff", "#gggggg"] {
            XCTAssertThrowsError(try book.createThrowaway(bad), "accepted \(bad)") { error in
                XCTAssertEqual(error as? ClubBookError, .badAccent(bad))
            }
        }
        XCTAssertNoThrow(try book.createClub(name: "No accent", kind: "team", accentHex: nil))
        XCTAssertNoThrow(try book.createClub(name: "Blank accent", kind: "team", accentHex: "  "))
        XCTAssertEqual(try book.clubs().compactMap(\.accentHex), [], "both wear the brand's own")
    }

    func testAKindRoleOrStateThisBuildDoesNotKnowIsRefusedOnTheWayIn() throws {
        let book = try open()
        XCTAssertThrowsError(try book.createClub(name: "Society", kind: "society")) { error in
            XCTAssertEqual(error as? ClubBookError, .unknownValue(field: "kind", value: "society"))
        }
        let club = try book.createClub(name: "The Feathers", kind: "team")
        XCTAssertThrowsError(try book.addMember(to: club.id, name: "Sam", role: "captain", ageBand: "adult")) { error in
            XCTAssertEqual(error as? ClubBookError, .unknownValue(field: "role", value: "captain"))
        }
        XCTAssertThrowsError(try book.addMember(to: club.id, name: "Sam", role: "member", ageBand: "18+")) { error in
            XCTAssertEqual(error as? ClubBookError, .unknownValue(field: "age band", value: "18+"))
        }
    }

    /// The safeguarding direction of the fallback. A row this build cannot read must come back as
    /// `unknown`, which is withheld, and never as `adult`, which is listed and messaged.
    func testAnUnreadableAgeBandReadsBackAsUnknownAndNeverAsAdult() throws {
        let book = try open()
        let club = try book.createClub(name: "The Feathers", kind: "team")
        try book.addMember(to: club.id, name: "Alex", role: "member", ageBand: "adult")
        // A row written by some future version, or corrupted: the store's own guard refuses this on
        // the way in, so it is put there behind the guard's back on purpose.
        try book.forTests("UPDATE club_member SET age_band = 'over-18' WHERE club_id = '\(club.id)';")

        let members = try book.members(of: club.id)
        XCTAssertEqual(members.count, 1)
        XCTAssertEqual(members[0].ageBand, "unknown",
                       "an age band that does not parse is treated as unknown, never as adult")
    }

    func testMembersAndFixturesComeBackInTheirOwnOrderAndSurviveAReopen() throws {
        let book = try open()
        let club = try book.createClub(name: "Feathers A", kind: "league")
        let day = TimeInterval(86_400)
        let base = Date(timeIntervalSince1970: 1_700_000_000)
        try book.addMember(to: club.id, name: "Chris", role: "admin", ageBand: "adult", joinedAt: base)
        try book.addMember(to: club.id, name: "Alex", role: "member", ageBand: "minor", joinedAt: base + day)
        try book.addFixture(to: club.id, title: "Away at The Crown", when: base + 3 * day, venue: "The Crown")
        try book.addFixture(to: club.id, title: "Home to The Bell", when: base + day, venue: "The Feathers")

        let reopened = try open()
        XCTAssertEqual(try reopened.members(of: club.id).map(\.name), ["Chris", "Alex"], "oldest joiner first")
        XCTAssertEqual(try reopened.fixtures(of: club.id).map(\.title),
                       ["Home to The Bell", "Away at The Crown"], "soonest first, not entry order")
        XCTAssertEqual(try reopened.fixtures(of: club.id).map(\.state), ["scheduled", "scheduled"])
    }

    /// The Kotlin `Fixture.moveTo` refuses to move out of a terminal state. The client keeps the same
    /// rule, so it cannot offer a move the domain would refuse.
    func testAFixtureMovesUntilItIsCancelledOrPlayedAndThenNeverAgain() throws {
        let book = try open()
        let club = try book.createClub(name: "The Feathers", kind: "team")
        let f = try book.addFixture(to: club.id, title: "Home to The Bell", when: Date(), venue: "The Feathers")

        try book.moveFixture(f.id, in: club.id, to: "postponed")
        XCTAssertEqual(try book.fixtures(of: club.id)[0].state, "postponed")
        try book.moveFixture(f.id, in: club.id, to: "played")

        XCTAssertThrowsError(try book.moveFixture(f.id, in: club.id, to: "scheduled")) { error in
            XCTAssertEqual(error as? ClubBookError, .fixtureIsFinished("played"))
        }
        XCTAssertEqual(try book.fixtures(of: club.id)[0].state, "played", "and it did not move")
    }

    /// Removing a club must not leave a roster behind with nothing to belong to — which is only true
    /// because `PRAGMA foreign_keys = ON` is in force, and that is what this asserts.
    func testDeletingAClubTakesItsRosterAndItsFixturesWithIt() throws {
        let book = try open()
        let club = try book.createClub(name: "The Feathers", kind: "team")
        let other = try book.createClub(name: "The Bell", kind: "team")
        try book.addMember(to: club.id, name: "Alex", role: "member", ageBand: "adult")
        try book.addFixture(to: club.id, title: "Home to The Bell", when: Date(), venue: "The Feathers")
        try book.addMember(to: other.id, name: "Sam", role: "member", ageBand: "adult")

        try book.deleteClub(id: club.id)

        XCTAssertEqual(try book.clubs().map(\.name), ["The Bell"])
        XCTAssertEqual(try book.members(of: club.id).count, 0)
        XCTAssertEqual(try book.fixtures(of: club.id).count, 0)
        XCTAssertEqual(try book.members(of: other.id).map(\.name), ["Sam"], "and the other club is untouched")
    }

    func testAMemberOrFixtureForAClubThatIsNotHereIsRefusedRatherThanOrphaned() throws {
        let book = try open()
        XCTAssertThrowsError(try book.addMember(to: "nope", name: "Alex", role: "member", ageBand: "adult")) { error in
            XCTAssertEqual(error as? ClubBookError, .noSuchClub("nope"))
        }
        XCTAssertThrowsError(try book.addFixture(to: "nope", title: "Somewhere", when: Date(), venue: "")) { error in
            XCTAssertEqual(error as? ClubBookError, .noSuchClub("nope"))
        }
    }

    func testARenameKeepsTheClubAndItsRoster() throws {
        let book = try open()
        let club = try book.createClub(name: "Feathrs", kind: "team")
        try book.addMember(to: club.id, name: "Alex", role: "member", ageBand: "adult")

        try book.updateClub(id: club.id, name: "The Feathers", accentHex: "8B1E3F")

        let read = try book.clubs()
        XCTAssertEqual(read.map(\.name), ["The Feathers"])
        XCTAssertEqual(read[0].id, club.id, "the same club, corrected — not a new one")
        XCTAssertEqual(read[0].accentHex, "8B1E3F")
        XCTAssertEqual(try book.members(of: club.id).map(\.name), ["Alex"])
    }
}

extension ClubBookTests {

    // MARK: - the book of people (ADR-016)

    /// A name typed differently is the same player. A book that treated "jenson" and "Jenson" as two
    /// people would split one person's history in half with nothing anywhere saying it had.
    func testTheSamePersonTypedDifferentlyIsTheSamePerson() throws {
        let book = try open()
        let first = try book.person(named: "Jenson")
        let again = try book.person(named: "  jenson  ")
        let spaced = try book.person(named: "jenson")
        XCTAssertEqual(first.id, again.id)
        XCTAssertEqual(first.id, spaced.id)
        XCTAssertEqual(first.name, "Jenson", "and the first spelling is the one kept")
        XCTAssertEqual(try book.people().count, 1)

        let other = try book.person(named: "Alex")
        XCTAssertNotEqual(first.id, other.id)
        XCTAssertEqual(try book.people().map(\.name), ["Alex", "Jenson"], "listed by name")
    }

    func testARenameKeepsTheSamePersonSoTheirMatchesFollow() throws {
        let book = try open()
        let person = try book.person(named: "Jensn")
        try book.renamePerson(person.id, to: "Jenson")
        XCTAssertEqual(try book.people().map(\.name), ["Jenson"])
        XCTAssertEqual(try book.people().map(\.id), [person.id], "the same person, corrected")

        // And the corrected spelling is now what matches to.
        XCTAssertEqual(try book.person(named: "jenson").id, person.id)
    }

    func testAPersonNeedsAName() throws {
        let book = try open()
        XCTAssertThrowsError(try book.person(named: " ")) { error in
            XCTAssertEqual(error as? ClubBookError, .blankName)
        }
        XCTAssertEqual(try book.people().count, 0)
    }
}

private extension ClubBook {
    /// A club whose only interesting property is its accent, for the accent refusals.
    func createThrowaway(_ accent: String) throws {
        try createClub(name: "Accent test", kind: "team", accentHex: accent)
    }

}

extension ClubBookTests {
    // MARK: - ADR-017 / PD-028: the standing organisation is the team, whatever the row called it

    /// A row written before 2026-09-09 says `club`. It was always a team, and it reads as one the
    /// next time the book opens — a vocabulary token normalised in place, no row touched otherwise.
    func testARowWrittenAsAClubReadsBackAsATeamAfterMigration() throws {
        _ = try open()   // creates the schema
        var raw: OpaquePointer?
        XCTAssertEqual(sqlite3_open(path, &raw), SQLITE_OK)
        defer { sqlite3_close(raw) }
        XCTAssertEqual(sqlite3_exec(raw, """
            INSERT INTO club (club_id, name, kind, accent_hex, created_at)
            VALUES ('legacy-1', 'The Feathers', 'club', NULL, '2026-09-01T18:00:00Z');
            """, nil, nil, nil), SQLITE_OK)
        let reopened = try open()
        let feathers = try XCTUnwrap(reopened.clubs().first { $0.id == "legacy-1" })
        XCTAssertEqual(feathers.kind, "team")
        XCTAssertEqual(feathers.name, "The Feathers", "nothing but the token changed")
    }

    /// The legacy word is still accepted on write, and normalised, so a caller that has not caught
    /// up cannot write the old vocabulary back into the book.
    func testTheLegacyWordIsAcceptedOnWriteAndStoredAsTeam() throws {
        let made = try open().createClub(name: "The Bell", kind: "club")
        XCTAssertEqual(made.kind, "team")
        XCTAssertEqual(try open().clubs().first?.kind, "team")
    }

    /// A team a league fields is a Team in its own right: adding one to a league creates an
    /// organisation with the SAME identifier, so the league's fixtures keep their meaning and the
    /// team appears among the teams this phone keeps.
    func testALeaguesTeamIsATeamInItsOwnRight() throws {
        let book = try open()
        let league = try book.createClub(name: "Tuesday League", kind: "league", unit: "legs")
        let side = try book.addTeam(to: league.id, name: "The Feathers A", id: "side-a")
        let orgs = try book.clubs()
        let asOrganisation = try XCTUnwrap(orgs.first { $0.id == "side-a" })
        XCTAssertEqual(asOrganisation.kind, "team")
        XCTAssertEqual(asOrganisation.name, "The Feathers A")
        XCTAssertEqual(side.id, "side-a")
        // Renaming the team renames it everywhere the league lists it.
        try book.updateClub(id: "side-a", name: "The Feathers Arrows", accentHex: nil)
        XCTAssertEqual(try book.teams(of: league.id).map(\.name), ["The Feathers Arrows"])
        // Removing it from the league removes the affiliation, not the team.
        try book.removeTeam("side-a", from: league.id)
        XCTAssertTrue(try book.teams(of: league.id).isEmpty)
        XCTAssertNotNil(try book.clubs().first { $0.id == "side-a" }, "a team's identity outlives any one league")
    }

    /// A league team written before teams were organisations gains its organisation on open — with
    /// its identifier, never by matching a name against an existing team.
    func testAPreExistingLeagueTeamGainsItsOrganisationOnMigration() throws {
        let league = try open().createClub(name: "Old League", kind: "league", unit: "legs")
        var raw: OpaquePointer?
        XCTAssertEqual(sqlite3_open(path, &raw), SQLITE_OK)
        defer { sqlite3_close(raw) }
        // A standing team called The Feathers already exists; the league's "The Feathers" must NOT be merged into it.
        XCTAssertEqual(sqlite3_exec(raw, """
            INSERT INTO club (club_id, name, kind, accent_hex, created_at)
            VALUES ('standing', 'The Feathers', 'club', NULL, '2026-09-01T18:00:00Z');
            INSERT INTO club_team (club_id, team_id, name, added_at)
            VALUES ('\(league.id)', 'old-side', 'The Feathers', '2026-09-02T18:00:00Z');
            """, nil, nil, nil), SQLITE_OK)
        let reopened = try open()
        let ids = Set(try reopened.clubs().map(\.id))
        XCTAssertTrue(ids.contains("old-side"), "the league's team became a team with its own id")
        XCTAssertTrue(ids.contains("standing"), "and the standing team is untouched")
        XCTAssertEqual(try reopened.clubs().filter { $0.name == "The Feathers" }.count, 2, "two teams, never merged on a name")
    }
}
