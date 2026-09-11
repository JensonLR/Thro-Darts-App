import XCTest
@testable import ThroApp
import ThroDesign
import ThroNet

/// What the leagues board says (PD-046): how much it holds, a chosen team's league and division and
/// night, whether anybody plays for it on THRØ, a league's spread — and your own team, on Discover,
/// saying its league. Tested here so that none of it is only looked at.
final class LeagueBoardTests: XCTestCase {

    private func leagues() throws -> [PublicLeague] {
        struct Envelope: Decodable { let leagues: [PublicLeague] }
        return try Wire.decoder.decode(Envelope.self, from: Data(LeagueAtlasTests.wire.utf8)).leagues
    }

    private func atlas() throws -> LeagueAtlas { LeagueAtlas(try leagues()) }
    private func id(_ n: Int) -> UUID { UUID(uuidString: "44444444-4444-4444-4444-44444444444\(n)")! }

    func testTheBoardCountsWhatItHoldsAndWhatItDoesNot() throws {
        let a = try atlas()
        XCTAssertEqual(LeagueBoardWords.census(a, bare: 326),
                       "8 teams at 4 pubs in 2 leagues. 326 more leagues are on the map with no teams listed yet.")
        XCTAssertEqual(LeagueBoardWords.census(a, bare: 1),
                       "8 teams at 4 pubs in 2 leagues. 1 more league is on the map with no teams listed yet.")
        XCTAssertEqual(LeagueBoardWords.census(LeagueAtlas([]), bare: 0), "No league has its teams on THRØ yet.")
    }

    func testAChosenTeamIsHeadedWithItsLeagueAndSaysWhereAndWhen() throws {
        let a = try atlas()
        let sheratonB = try XCTUnwrap(a.entry(id(3)))
        XCTAssertEqual(LeagueBoardWords.teamEyebrow(sheratonB), "Stockton Thursday · Division One")
        XCTAssertEqual(LeagueBoardWords.teamWhere(sheratonB, distance: "0.4 mi"),
                       "The Thomas Sheraton · Thursday nights · 2025-2026 · 0.4 mi")
        XCTAssertEqual(LeagueBoardWords.division(sheratonB, teams: 3), "Division One · 3 teams")
        let cafe = try XCTUnwrap(a.entry(id(8)))
        XCTAssertEqual(LeagueBoardWords.teamEyebrow(cafe), "Redcar Monday Darts League", "one division is not named twice")
        XCTAssertEqual(LeagueBoardWords.teamWhere(cafe, distance: nil), "Its pub is not known yet · Monday nights · 2025-2026")
        XCTAssertEqual(LeagueBoardWords.division(cafe, teams: 3), "The league · 3 teams")
    }

    func testTheBoardSaysWhetherAnybodyPlaysForTheTeamOnTHRO() throws {
        func front(_ roster: String, you: String?) throws -> TeamFront {
            let role = you.map { "\"\($0)\"" } ?? "null"
            let json = #"{"teamId":"44444444-4444-4444-4444-444444444443","name":"Sheraton B","locality":null,"venue":null,"seasons":[],"roster":[\#(roster)],"yourRole":\#(role)}"#
            return try Wire.decoder.decode(TeamFront.self, from: Data(json.utf8))
        }
        XCTAssertNil(LeagueBoardWords.onThro(nil), "nothing is said while the front is still being read")
        XCTAssertEqual(LeagueBoardWords.onThro(try front("", you: nil)), "Nobody plays for it on THRØ yet.")
        XCTAssertEqual(LeagueBoardWords.onThro(try front(#"{"name":null,"role":"admin"}"#, you: nil)), "1 of its players is on THRØ.")
        XCTAssertEqual(LeagueBoardWords.onThro(try front(#"{"name":"Ethan T.","role":"admin"},{"name":null,"role":"player"}"#, you: "player")),
                       "You play for it on THRØ.")
    }

    func testALeagueSaysItsNightItsPlaceAndItsSpread() throws {
        let stockton = try XCTUnwrap(try leagues().first)
        XCTAssertEqual(LeagueBoardWords.leagueMeta(stockton, teams: 5, divisions: 2, distance: "3.2 mi"),
                       "Thursday nights · Stockton-on-Tees · 5 teams in 2 divisions · 3.2 mi")
        XCTAssertEqual(LeagueBoardWords.leagueMeta(stockton, teams: 0, divisions: 0, distance: nil),
                       "Thursday nights · Stockton-on-Tees · no teams listed yet")
    }

    func testYourTeamOnDiscoverSaysItsLeagueWhenItIsInOne() throws {
        let a = try atlas()
        func team(_ id: String) throws -> TeamSummary {
            let json = #"{"teamId":"\#(id)","name":"X","locality":"Stockton-on-Tees","role":"admin","members":3}"#
            return try Wire.decoder.decode(TeamSummary.self, from: Data(json.utf8))
        }
        XCTAssertEqual(DiscoverScreen.teamMeta(try team("44444444-4444-4444-4444-444444444443"), atlas: a),
                       "Stockton Thursday · Division One · Thursday nights · 3 members")
        XCTAssertEqual(DiscoverScreen.teamMeta(try team("5c4ee45e-0000-4000-8000-0000000000c1"), atlas: a),
                       "Stockton-on-Tees · 3 members", "a team in no league THRØ lists says its town")
    }

    func testASeasonIsNamedOnlyWhereItsLabelReadsAsADate() {
        XCTAssertEqual(LeagueBoardWords.season("2025-2026"), "2025-2026")
        XCTAssertNil(LeagueBoardWords.season("Redcar Darts League 2026"), "a label that repeats the league's name is left out")
        XCTAssertNil(LeagueBoardWords.season(nil))
    }

    func testATeamNamedForItsPubSaysItsTownInsteadOfTheSameNameTwice() throws {
        let a = try atlas()
        XCTAssertEqual(LeagueTeamRow.pubUnder(try XCTUnwrap(a.entry(id(5)))), "Stockton-on-Tees", "the Kings Head, at The Kings Head")
        XCTAssertEqual(LeagueTeamRow.pubUnder(try XCTUnwrap(a.entry(id(3)))), "The Thomas Sheraton")
        XCTAssertEqual(LeagueTeamRow.pubUnder(try XCTUnwrap(a.entry(id(4)))), "Its pub is not known yet")
    }

    func testEveryChalkTheAtlasDealsHasAToken() {
        XCTAssertEqual(LeagueAtlas.chalks, LeagueChalk.all.count, "one league-chalk token for every chalk the atlas deals")
        XCTAssertEqual(LeagueChalk.color(-1), LeagueChalk.all[5], "any place is a place: round again")
        XCTAssertEqual(LeagueChalk.color(6), LeagueChalk.all[0])
    }
}
