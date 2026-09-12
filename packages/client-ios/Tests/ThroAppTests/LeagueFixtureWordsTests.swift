import XCTest
@testable import ThroApp
import ThroNet

/// What the fixtures beside a table say (PD-056, PD-062). The scoreline is the server's; these are the
/// sentences around it, and the ones that carry a rule the drawing cannot: an award never shows legs, a
/// declared result says it was somebody's word, and a team THRØ may not name is still a side in a fixture.
final class LeagueFixtureWordsTests: XCTestCase {

    private func fixture(home: String? = "Grange A", away: String? = "Riverside A",
                         venue: String? = "The Grange", state: String = "scheduled",
                         decided: String = "null") throws -> LeagueFixtures.Fixture {
        let json = """
        {"fixtureId":"55555555-5555-5555-5555-555555555551","divisionId":null,"division":"Division One",
         "scheduledAt":"2026-09-24T19:00:00Z","state":"\(state)",
         "home":\(home.map { "\"\($0)\"" } ?? "null"),"away":\(away.map { "\"\($0)\"" } ?? "null"),
         "venue":\(venue.map { "\"\($0)\"" } ?? "null"),"locality":"Stockton","decided":\(decided)}
        """
        return try Wire.decoder.decode(LeagueFixtures.Fixture.self, from: Data(json.utf8))
    }

    private let played = """
        {"outcomeId":"66666666-6666-6666-6666-666666666661","kind":"played","legsHome":5,"legsAway":2,
         "awardedToHome":null}
        """
    private let declared = """
        {"outcomeId":"66666666-6666-6666-6666-666666666662","kind":"declared","legsHome":5,"legsAway":2,
         "awardedToHome":null}
        """
    private let awarded = """
        {"outcomeId":"66666666-6666-6666-6666-666666666663","kind":"awarded","legsHome":null,
         "legsAway":null,"awardedToHome":true}
        """

    func testAFixtureToComeIsTwoSidesAndNoScore() throws {
        XCTAssertEqual(LeagueTableWords.sides(try fixture()), "Grange A v Riverside A")
    }

    func testAPlayedFixtureCarriesItsScoreline() throws {
        XCTAssertEqual(LeagueTableWords.sides(try fixture(decided: played)), "Grange A 5–2 Riverside A")
    }

    func testAnAwardNeverInventsAScoreline() throws {
        // ADR-012: legs an award invented would reward an unplayed match in every leg-difference tie-break
        // beneath it. The words must not put one back that the data refused to hold.
        let said = LeagueTableWords.sides(try fixture(decided: awarded))
        XCTAssertEqual(said, "Grange A awarded, Riverside A")
        XCTAssertFalse(said.contains("–"), "an awarded fixture must not read as a scoreline")
    }

    func testADeclaredResultSaysItWasSomebodysWord() throws {
        // PD-055: a declared result counts in the table exactly as a played one does and is never evidence.
        // "5–2" cannot carry that difference, so the line beneath it has to.
        let f = try fixture(decided: declared)
        XCTAssertEqual(LeagueTableWords.sides(f), "Grange A 5–2 Riverside A", "it reads as the result it is")
        XCTAssertTrue(LeagueTableWords.when(f).contains("the league's word"))
        // And a played one does not say it, or the distinction means nothing.
        XCTAssertFalse(LeagueTableWords.when(try fixture(decided: played)).contains("the league's word"))
    }

    func testATeamTHROMayNotNameIsStillASide() throws {
        // PD-056: the fixture is listed and the private side is unnamed. A blank reads as a bug.
        XCTAssertEqual(LeagueTableWords.sides(try fixture(home: nil)), "A team v Riverside A")
        XCTAssertEqual(LeagueTableWords.sides(try fixture(away: nil, decided: played)), "Grange A 5–2 A team")
    }

    func testAFixtureThatIsNotSimplyScheduledSaysSo() throws {
        XCTAssertTrue(LeagueTableWords.when(try fixture(state: "postponed")).contains("postponed"))
        XCTAssertFalse(LeagueTableWords.when(try fixture()).contains("scheduled"),
                       "the ordinary case does not need saying")
    }

    func testAVenueTHROMayNotNameIsLeftOutRatherThanGuessed() throws {
        let said = LeagueTableWords.when(try fixture(venue: nil))
        XCTAssertFalse(said.contains("The Grange"))
        XCTAssertTrue(said.contains("Thu"), "the date is still there")
    }

    func testAScorelineIsSpokenAsAScoreAndNotAsANumber() throws {
        // An en dash between two numerals is not a word: read out, "5–2" is the same sound as fifty-two.
        let said = LeagueTableWords.spokenFixture(try fixture(decided: played))
        XCTAssertTrue(said.contains("5 to 2"), said)
        XCTAssertFalse(said.contains("–"), said)
    }

    func testTheCountOfWhatIsLeftReadsAsEnglish() {
        XCTAssertEqual(LeagueTableWords.andMore(1), "And one more after those.")
        XCTAssertEqual(LeagueTableWords.andMore(4), "And 4 more after those.")
    }
}
