import XCTest
@testable import ThroVenueKit
import ThroNet

/// Games in play, on a screen nobody is holding (PD-088).
///
/// Built by decoding the wire the server actually sends, as `RotaTests` is and for the same reason: the
/// interesting property here is *what the server chose not to send*, and only a decode can show that a
/// missing key stays missing rather than becoming an empty string somewhere on the way to a wall.
final class LiveTests: XCTestCase {

    /// One game as the server writes it. A name passed as nil is **absent from the JSON**, exactly as the
    /// server omits it for a player who may not be named — not `null`, not `""`.
    private func game(homeName: String? = nil, awayName: String? = nil,
                      homeTeam: String? = "The Sun Inn", awayTeam: String? = "Ship B",
                      homeRemaining: Int = 301, awayRemaining: Int = 180,
                      homeLegs: Int = 1, awayLegs: Int = 2,
                      thrower: String? = "home") -> String {
        var parts = ["\"matchId\":\"\(UUID().uuidString.lowercased())\""]
        homeTeam.map { parts.append("\"homeTeam\":\"\($0)\"") }
        awayTeam.map { parts.append("\"awayTeam\":\"\($0)\"") }
        homeName.map { parts.append("\"homeName\":\"\($0)\"") }
        awayName.map { parts.append("\"awayName\":\"\($0)\"") }
        parts.append("\"homeRemaining\":\(homeRemaining)")
        parts.append("\"awayRemaining\":\(awayRemaining)")
        parts.append("\"homeLegs\":\(homeLegs)")
        parts.append("\"awayLegs\":\(awayLegs)")
        thrower.map { parts.append("\"thrower\":\"\($0)\"") }
        return "{\(parts.joined(separator: ","))}"
    }

    private func games(_ bodies: [String]) throws -> [LiveGame] {
        struct Envelope: Decodable { let games: [LiveGame] }
        let json = "{\"games\":[\(bodies.joined(separator: ","))]}"
        return try Wire.decoder.decode(Envelope.self, from: Data(json.utf8)).games
    }

    private func standings(divisions: Int = 1, teams: Int = 4) throws -> LeagueStandings {
        let rows = (1...teams).map { i in
            """
            {"position":\(i),"separatedBy":null,"teamId":"\(UUID().uuidString.lowercased())",
             "name":"Team \(i)","played":\(i),"won":\(i),"drawn":0,"lost":0,"legsFor":10,"legsAgainst":4,
             "legDifference":6,"points":\(i * 2),"awardedFor":0,"awardedAgainst":0,"evidenced":\(i)}
            """
        }.joined(separator: ",")
        let body = (1...max(1, divisions)).map { d in
            """
            {"divisionId":"\(UUID().uuidString.lowercased())","name":"Division \(d)","ordinal":\(d),
             "awaitingResults":0,"rows":[\(rows)]}
            """
        }.joined(separator: ",")
        let json = """
        {"leagueSeasonId":"\(UUID().uuidString.lowercased())","leagueId":"\(UUID().uuidString.lowercased())",
         "league":"Wigan & District","label":"2026/27","state":"running",
         "rules":{"policyId":null,"version":null,"whose":"thro",
                  "says":"THRØ's standard","orderedBy":["points"]},
         "divisions":[\(body)]}
        """
        return try Wire.decoder.decode(LeagueStandings.self, from: Data(json.utf8))
    }

    // MARK: what reaches the wall

    func testAPlayerTheServerDidNotNameIsNotNamedHere() throws {
        let all = try games([game(homeName: "Ann Shaw", awayName: nil)])
        let one = try XCTUnwrap(all.first)

        XCTAssertEqual(one.homeName, "Ann Shaw")
        // The whole rule, at the last place it could go wrong. The server omitted the key because
        // `identity.player_may_be_shown_live` said no; nothing on the way here may turn that into a name.
        XCTAssertNil(one.awayName)
        XCTAssertFalse(one.teamsOnly, "one named side is not a teams-only game")
    }

    func testAnUnnamedSideShowsItsTeamRatherThanAGap() throws {
        let one = try XCTUnwrap(try games([game(homeName: "Ann Shaw", awayName: nil)]).first)

        XCTAssertEqual(ThroVenueWords.side(name: one.homeName, team: one.homeTeam), "Ann Shaw")
        // Not "Not named", not blank. The team is published anyway, and a person who has not agreed to be
        // named should not be the one row on a pub wall that looks redacted.
        XCTAssertEqual(ThroVenueWords.side(name: one.awayName, team: one.awayTeam), "Ship B")
    }

    func testWhenTheTeamIsPrivateTooTheWallSaysSoRatherThanGuessing() throws {
        let one = try XCTUnwrap(try games([game(awayName: nil, awayTeam: nil)]).first)
        XCTAssertEqual(ThroVenueWords.side(name: one.awayName, team: one.awayTeam), "Not named")
    }

    func testAGameWithNobodyNamedIsStillOnTheWall() throws {
        let all = try games([game(), game()])
        XCTAssertTrue(all.allSatisfy(\.teamsOnly))

        let panels = ThroVenueRota.panels(standings: nil, fixtures: nil, live: all)
        // "All games should be live shown" is met by the game being there. What varies is the names.
        guard case let .live(_, _, shown)? = panels.first else { return XCTFail("no live panel") }
        XCTAssertEqual(shown.count, 2)
    }

    func testTheReasonIsSaidOncePerPageAndOnlyWhenItIsTheWholePage() throws {
        let anonymous = try games([game(), game()])
        XCTAssertNotNil(ThroVenueWords.whyTeams(anonymous))

        // One named player on the page and the sentence goes: it would read as an explanation of the
        // person beside it, which is the opposite of the point.
        let mixed = try games([game(homeName: "Ann Shaw"), game()])
        XCTAssertNil(ThroVenueWords.whyTeams(mixed))

        XCTAssertNil(ThroVenueWords.whyTeams([]), "and an empty page explains nothing")
    }

    func testWhoseThrowItIsIsReadFromTheGameAndNotAssumed() throws {
        let home = try XCTUnwrap(try games([game(thrower: "home")]).first)
        XCTAssertTrue(ThroVenueWords.atTheOche(home, home: true))
        XCTAssertFalse(ThroVenueWords.atTheOche(home, home: false))

        // Between legs nobody is at the oche, and the wall must not brighten a side that is not throwing.
        let between = try XCTUnwrap(try games([game(thrower: nil)]).first)
        XCTAssertFalse(ThroVenueWords.atTheOche(between, home: true))
        XCTAssertFalse(ThroVenueWords.atTheOche(between, home: false))
    }

    // MARK: the rotation

    func testALivePageIsNeverMoreThanOnePanelAway() throws {
        let panels = ThroVenueRota.panels(standings: try standings(divisions: 3), fixtures: nil,
                                          live: try games([game()]))
        XCTAssertGreaterThan(panels.count, 3)

        // At twenty seconds a dwell, this is the difference between waiting forty seconds to see a live
        // leg and waiting for two pages of last week's results to turn.
        var sinceLive = 0
        for panel in panels {
            if case .live = panel { sinceLive = 0 } else { sinceLive += 1 }
            XCTAssertLessThanOrEqual(sinceLive, 1, "a live page must never be two panels away")
        }
        guard case .live = panels[0] else { return XCTFail("the rotation opens on the darts") }
    }

    func testWithNothingInPlayTheRotationIsExactlyWhatItWasBefore() throws {
        let table = try standings(divisions: 2)
        // The PD-088 change must be invisible on a quiet afternoon, or it is a change to PD-079's order
        // rather than an addition to it.
        XCTAssertEqual(ThroVenueRota.panels(standings: table, fixtures: nil, live: []),
                       ThroVenueRota.panels(standings: table, fixtures: nil))
    }

    func testEveryGameGetsOnEvenWhenThereIsNothingElseToRotateThrough() throws {
        // Nine games is three pages, and an empty league has no other panels to interleave between.
        let all = try games((0..<9).map { _ in game() })
        let panels = ThroVenueRota.panels(standings: nil, fixtures: nil, live: all)
        XCTAssertEqual(panels.count, 3)

        var seen = 0
        for panel in panels { if case let .live(_, _, page) = panel { seen += page.count } }
        XCTAssertEqual(seen, 9, "a busy night with an empty table must still show every game")
    }

    func testMoreGamesThanPanelsStillAllReachTheScreen() throws {
        // Three live pages against one table panel: the interleave places one, and the other two would be
        // dropped by a naive zip. They go on the end instead.
        let all = try games((0..<9).map { _ in game() })
        let panels = ThroVenueRota.panels(standings: try standings(divisions: 1), fixtures: nil, live: all)

        var pages = Set<Int>()
        for panel in panels { if case let .live(page, _, _) = panel { pages.insert(page) } }
        XCTAssertEqual(pages, [1, 2, 3], "every live page reaches the wall, not just the first")
    }

    func testTheLiveClockIsMuchShorterThanTheTablesAndDeliberately() {
        // A league table changes on the night it changes; a leg changes while somebody is looking at it.
        // A single cadence would mean either a stale board or a table read twelve times too often.
        XCTAssertEqual(ThroVenueWall.liveRefresh, 10)
        XCTAssertLessThan(ThroVenueWall.liveRefresh, ThroVenueWall.refresh / 10)
    }
}
