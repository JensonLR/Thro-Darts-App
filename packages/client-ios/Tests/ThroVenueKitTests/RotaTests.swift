import XCTest
@testable import ThroVenueKit
import ThroNet

/// What a screen nobody is holding shows, and in what order (PD-079).
///
/// Everything here is built by decoding the wire the server actually sends, rather than by constructing
/// the types — which is not only closer to the truth but the only way, since these types are `Decodable`
/// and have no public memberwise init. It means a change to the payload's shape fails here too.
final class RotaTests: XCTestCase {

    // MARK: the wire

    private func standings(divisions: [(String, Int)]) throws -> LeagueStandings {
        let body = divisions.map { name, teams in
            let rows = (1...max(1, teams)).map { i in
                """
                {"position":\(i),"separatedBy":null,"teamId":"\(UUID().uuidString.lowercased())",
                 "name":"Team \(i)","played":\(i),"won":\(i),"drawn":0,"lost":0,"legsFor":10,"legsAgainst":4,
                 "legDifference":6,"points":\(i * 2),"awardedFor":0,"awardedAgainst":0,"evidenced":\(i)}
                """
            }.joined(separator: ",")
            return """
            {"divisionId":"\(UUID().uuidString.lowercased())","name":"\(name)","ordinal":1,
             "awaitingResults":0,"rows":[\(teams == 0 ? "" : rows)]}
            """
        }.joined(separator: ",")
        let json = """
        {"leagueSeasonId":"\(UUID().uuidString.lowercased())","leagueId":"\(UUID().uuidString.lowercased())",
         "league":"Wigan & District","label":"2026/27","state":"running",
         "rules":{"policyId":null,"version":null,"whose":"thro",
                  "says":"THRØ's standard: two points a win, one a draw","orderedBy":["points"]},
         "divisions":[\(body)]}
        """
        return try Wire.decoder.decode(LeagueStandings.self, from: Data(json.utf8))
    }

    /// `toPlay` fixtures then `decided` ones, as one payload.
    private func fixtures(toPlay: Int, decided: Int, home: String? = "Crown A") throws -> LeagueFixtures {
        var rows: [String] = []
        for i in 0..<toPlay {
            rows.append("""
            {"fixtureId":"\(UUID().uuidString.lowercased())","divisionId":null,"division":"Premier",
             "scheduledAt":"2027-01-0\(min(9, i + 1))T20:00:00Z","state":"scheduled",
             "home":\(home.map { "\"\($0) \(i)\"" } ?? "null"),"away":"Ship B","venue":"The Crown",
             "locality":"Wigan","decided":null,"annulled":null}
            """)
        }
        for i in 0..<decided {
            rows.append("""
            {"fixtureId":"\(UUID().uuidString.lowercased())","divisionId":null,"division":"Premier",
             "scheduledAt":"2026-09-0\(min(9, i + 1))T20:00:00Z","state":"scheduled",
             "home":"Crown A","away":"Ship B","venue":"The Crown","locality":"Wigan",
             "decided":{"outcomeId":"\(UUID().uuidString.lowercased())","kind":"played",
                        "legsHome":6,"legsAway":3,"awardedToHome":null},"annulled":null}
            """)
        }
        let json = "{\"fixtures\":[\(rows.joined(separator: ","))]}"
        return try Wire.decoder.decode(LeagueFixtures.self, from: Data(json.utf8))
    }

    // MARK: the rotation

    func testTheOrderIsWhereWeAreThenAreWeOnThenHowLastWeekWent() throws {
        // Somebody looking up wants their position, then whether they are playing, and only then results.
        // A rotation that opened on results would show the least urgent thing to the most people.
        let panels = ThroVenueRota.panels(standings: try standings(divisions: [("Premier", 4)]),
                                          fixtures: try fixtures(toPlay: 2, decided: 2))
        XCTAssertEqual(panels.count, 3)
        guard case .table = panels[0] else { return XCTFail("the table comes first") }
        guard case .toPlay = panels[1] else { return XCTFail("then what is still to play") }
        guard case .results = panels[2] else { return XCTFail("then what has just been played") }
    }

    func testAPanelWithNothingOnItIsNotInTheRotationAtAll() throws {
        // Twenty seconds of "no fixtures" on a wall is twenty seconds of a screen that looks broken.
        let panels = ThroVenueRota.panels(standings: try standings(divisions: [("Premier", 4)]),
                                          fixtures: try fixtures(toPlay: 0, decided: 0))
        XCTAssertEqual(panels.count, 1, "only the table, because only the table has anything on it")
    }

    func testADivisionWithNoTeamsIsNotAPanel() throws {
        let panels = ThroVenueRota.panels(standings: try standings(divisions: [("Premier", 3), ("Division Two", 0)]),
                                          fixtures: nil)
        XCTAssertEqual(panels.count, 1)
    }

    func testATableThatDoesNotFitIsPagedAndNeverScrolled() throws {
        // Nobody can scroll a wall screen. Fourteen teams is two pages, and both say which they are.
        let panels = ThroVenueRota.panels(standings: try standings(divisions: [("Premier", 14)]), fixtures: nil)
        XCTAssertEqual(panels.count, 2)
        guard case let .table(_, page1, of1, rows1) = panels[0],
              case let .table(_, page2, of2, rows2) = panels[1] else { return XCTFail("two table pages") }
        XCTAssertEqual([page1, of1, rows1.count], [1, 2, ThroVenueRota.tableRows])
        XCTAssertEqual([page2, of2, rows2.count], [2, 2, 14 - ThroVenueRota.tableRows])
        XCTAssertEqual(rows1.first?.position, 1, "and the pages are in order")
        XCTAssertEqual(rows2.last?.position, 14)
    }

    func testTheRotationTurnsAndComesBack() throws {
        let panels = ThroVenueRota.panels(standings: try standings(divisions: [("Premier", 4)]),
                                          fixtures: try fixtures(toPlay: 2, decided: 2))
        let start = Date(timeIntervalSince1970: 1_000_000)
        let at = { (seconds: TimeInterval) in
            ThroVenueRota.showing(panels, since: start, now: start.addingTimeInterval(seconds))
        }
        XCTAssertEqual(at(0), panels[0])
        XCTAssertEqual(at(ThroVenueRota.dwell - 1), panels[0], "it holds for the whole dwell")
        XCTAssertEqual(at(ThroVenueRota.dwell), panels[1])
        XCTAssertEqual(at(ThroVenueRota.dwell * 3), panels[0], "and comes round again")
    }

    func testNothingAtAllIsAScreenOfItsOwnRatherThanABlankOne() {
        XCTAssertNil(ThroVenueRota.showing([], since: Date(), now: Date()))
        XCTAssertTrue(ThroVenueRota.panels(standings: nil, fixtures: nil).isEmpty)
    }

    func testAClockThatWentBackwardsDoesNotCrashTheWall() {
        // A TV's clock is set by the network and can jump. `showing` must never index out of range.
        let panels = ThroVenueRota.panels(standings: try? standings(divisions: [("Premier", 2)]), fixtures: nil)
        let start = Date(timeIntervalSince1970: 1_000_000)
        XCTAssertEqual(ThroVenueRota.showing(panels, since: start, now: start.addingTimeInterval(-9_999)),
                       panels.first)
    }

    func testResultsAreCappedBecauseAWallIsANoticeBoardAndNotAnArchive() throws {
        let panels = ThroVenueRota.panels(standings: nil, fixtures: try fixtures(toPlay: 0, decided: 40))
        let shown = panels.reduce(0) { total, panel in
            if case let .results(_, _, list) = panel { return total + list.count }
            return total
        }
        XCTAssertEqual(shown, ThroVenueRota.recentResults)
    }

    // MARK: the words

    func testAPrivateSideIsStillAFixtureAndIsNamedHonestly() throws {
        // The server does not name a private team. Hiding the row would leave a hole in a league's own
        // calendar on the one screen everybody in the room is looking at.
        let hidden = try fixtures(toPlay: 1, decided: 0, home: nil).toPlay[0]
        XCTAssertEqual(ThroVenueWords.sides(hidden), "Not named v Ship B")
    }

    func testADeclaredResultSaysSoBecauseNobodyThrewIt() throws {
        // Every other surface says where a figure came from. A wall is the one place a stranger reads a
        // scoreline with nobody to ask, so it is the one place the distinction cannot be left out.
        let json = { (kind: String) in """
        {"fixtures":[{"fixtureId":"\(UUID().uuidString.lowercased())","divisionId":null,"division":null,
         "scheduledAt":"2026-09-01T20:00:00Z","state":"scheduled","home":"Crown A","away":"Ship B",
         "venue":null,"locality":null,
         "decided":{"outcomeId":"\(UUID().uuidString.lowercased())","kind":"\(kind)","legsHome":6,
                    "legsAway":3,"awardedToHome":null},"annulled":null}]}
        """ }
        let played = try Wire.decoder.decode(LeagueFixtures.self, from: Data(json("played").utf8)).decided[0]
        let declared = try Wire.decoder.decode(LeagueFixtures.self, from: Data(json("declared").utf8)).decided[0]
        XCTAssertEqual(ThroVenueWords.outcome(played), "6–3")
        XCTAssertEqual(ThroVenueWords.outcome(declared), "6–3 · declared")
    }

    func testAnAwardIsNotAScoreline() throws {
        let json = """
        {"fixtures":[{"fixtureId":"\(UUID().uuidString.lowercased())","divisionId":null,"division":null,
         "scheduledAt":"2026-09-01T20:00:00Z","state":"scheduled","home":"Crown A","away":"Ship B",
         "venue":null,"locality":null,
         "decided":{"outcomeId":"\(UUID().uuidString.lowercased())","kind":"awarded","legsHome":null,
                    "legsAway":null,"awardedToHome":true},"annulled":null}]}
        """
        let awarded = try Wire.decoder.decode(LeagueFixtures.self, from: Data(json.utf8)).decided[0]
        XCTAssertEqual(ThroVenueWords.outcome(awarded), "Awarded — Crown A",
                       "a match nobody played does not get a scoreline on a wall")
    }

    func testANightGoneWithNothingEnteredSaysSoAndAPostponedOneDoesNot() throws {
        let json = { (state: String) in """
        {"fixtures":[{"fixtureId":"\(UUID().uuidString.lowercased())","divisionId":null,"division":null,
         "scheduledAt":"2026-09-01T20:00:00Z","state":"\(state)","home":"Crown A","away":"Ship B",
         "venue":null,"locality":null,"decided":null,"annulled":null}]}
        """ }
        let later = Date(timeIntervalSince1970: 1_800_000_000)
        let scheduled = try Wire.decoder.decode(LeagueFixtures.self, from: Data(json("scheduled").utf8)).fixtures[0]
        let postponed = try Wire.decoder.decode(LeagueFixtures.self, from: Data(json("postponed").utf8)).fixtures[0]
        XCTAssertTrue(ThroVenueWords.awaiting(scheduled, now: later))
        XCTAssertFalse(ThroVenueWords.awaiting(postponed, now: later),
                       "a postponed fixture is not a missing result; nobody was going to play it")
    }

    func testTheWallSaysWhenItLastHeard() {
        let heard = Date(timeIntervalSince1970: 1_000_000)
        XCTAssertEqual(ThroVenueWords.heard(at: nil), "Reading…")
        XCTAssertEqual(ThroVenueWords.heard(at: heard, now: heard.addingTimeInterval(30)), "Just now")
        XCTAssertEqual(ThroVenueWords.heard(at: heard, now: heard.addingTimeInterval(60)), "1 minute ago")
        XCTAssertEqual(ThroVenueWords.heard(at: heard, now: heard.addingTimeInterval(300)), "5 minutes ago")
        XCTAssertEqual(ThroVenueWords.heard(at: heard, now: heard.addingTimeInterval(3_600)),
                       "Out of date — check the connection")
    }

    func testTheRefreshIsWellInsideTheWindowAfterWhichTheWallDoubtsItself() {
        // The same shape as the live stream's ping against the proxy timeout: if the two ever crossed, a
        // working wall would spend its evening accusing itself of being out of date.
        XCTAssertLessThan(ThroVenueWall.refresh * 3, 15 * 60)
    }

    func testTroubleIsSaidInWordsAPersonInAPubCanActOn() {
        XCTAssertEqual(ThroVenueWords.trouble(APIError.unreachable("nope")), "Cannot reach THRØ")
        XCTAssertEqual(ThroVenueWords.trouble(APIError.status(404, "{}")), "THRØ answered, but not with this season")
    }
}
