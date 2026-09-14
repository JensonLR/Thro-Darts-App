import XCTest
@testable import ThroApp
import ThroNet

/// What a league's table says about itself (PD-054). The numbers are the server's; these are the sentences
/// printed beside them, and a table that cannot say why it reads as it does is a table nobody can check.
final class LeagueTableWordsTests: XCTestCase {

    private func row(played: Int = 14, won: Int = 10, drawn: Int = 1, lost: Int = 3,
                     difference: Int = 28, points: Int = 21, awardedFor: Int = 0, awardedAgainst: Int = 0,
                     evidenced: Int = 9) throws -> LeagueStandings.Row {
        let json = """
        {"position":1,"separatedBy":null,"teamId":"44444444-4444-4444-4444-444444444441","name":"Grange A",
         "played":\(played),"won":\(won),"drawn":\(drawn),"lost":\(lost),"legsFor":72,"legsAgainst":44,
         "legDifference":\(difference),"points":\(points),"awardedFor":\(awardedFor),
         "awardedAgainst":\(awardedAgainst),"evidenced":\(evidenced)}
        """
        return try Wire.decoder.decode(LeagueStandings.Row.self, from: Data(json.utf8))
    }

    private func rules(whose: String, orderedBy: [String]) throws -> LeagueStandings.Rules {
        let by = orderedBy.map { "\"\($0)\"" }.joined(separator: ",")
        let json = """
        {"policyId":null,"version":null,"whose":"\(whose)","says":"Two points a win, one a draw.",
         "orderedBy":[\(by)]}
        """
        return try Wire.decoder.decode(LeagueStandings.Rules.self, from: Data(json.utf8))
    }

    func testARowSaysWhatItPlayedAndWhatWasScoredOnThro() throws {
        let said = LeagueTableWords.detail(try row())
        XCTAssertEqual(said, "14 played · 10 won, 1 drawn, 3 lost · 9 scored on THRØ")
    }

    func testAFixtureNobodyPlayedIsSaidRatherThanHidden() throws {
        let one = LeagueTableWords.detail(try row(awardedFor: 1))
        XCTAssertTrue(one.contains("1 not played"), one)
        let two = LeagueTableWords.detail(try row(awardedFor: 1, awardedAgainst: 1))
        XCTAssertTrue(two.contains("2 not played"), two)
    }

    func testARowWithNothingScoredOnThroClaimsNothing() throws {
        let said = LeagueTableWords.detail(try row(evidenced: 0))
        XCTAssertFalse(said.contains("THRØ"), "nothing came from a match scored here, so nothing says it did: \(said)")
    }

    func testADifferenceCarriesItsSign() throws {
        XCTAssertEqual(LeagueTableWords.difference(28), "+28")
        XCTAssertEqual(LeagueTableWords.difference(-3), "-3")
        XCTAssertEqual(LeagueTableWords.difference(0), "0", "level is not +0")
    }

    func testTheOrderIsNamedInWordsAPlayerWouldUse() throws {
        let said = LeagueTableWords.ordered(try rules(whose: "thro", orderedBy: ["points", "leg_difference", "legs_for"]))
        XCTAssertEqual(said, "Ordered on points, then leg difference, then legs won.")
        let h2h = LeagueTableWords.ordered(try rules(whose: "league", orderedBy: ["points", "head_to_head"]))
        XCTAssertEqual(h2h, "Ordered on points, then who beat whom.")
    }

    func testAnOrderWithAStepThisBuildDoesNotKnowStillReads() throws {
        // A league may approve a step a later server understands; the phone prints it rather than dropping it.
        let said = LeagueTableWords.ordered(try rules(whose: "league", orderedBy: ["points", "goals_for"]))
        XCTAssertEqual(said, "Ordered on points, then goals for.")
    }

    func testWhoseRulesTheyAreIsReadableFromTheWire() throws {
        XCTAssertTrue(try rules(whose: "league", orderedBy: ["points"]).leagues)
        XCTAssertFalse(try rules(whose: "thro", orderedBy: ["points"]).leagues)
    }

    func testATableMissingResultsSaysSoRatherThanLookingFinished() {
        let one = LeagueTableWords.awaiting(1)
        XCTAssertTrue(one.contains("One fixture"), one)
        XCTAssertTrue(one.contains("not finished"), one)
        let many = LeagueTableWords.awaiting(4)
        XCTAssertTrue(many.contains("4 fixtures"), many)
    }

    func testARowIsSpokenWithoutItsColumns() throws {
        let said = LeagueTableWords.spoken(try row())
        XCTAssertEqual(said, "1. Grange A, 21 points, 14 played, leg difference +28.")
        let single = LeagueTableWords.spoken(try row(points: 1))
        XCTAssertTrue(single.contains("1 point,"), "one point, not one points: \(single)")
    }
}
