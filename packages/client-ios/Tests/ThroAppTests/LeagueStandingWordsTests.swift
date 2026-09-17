import XCTest
@testable import ThroApp
import ThroNet

/// What THRØ holds for a league, said in the league's own row (PD-126). Three hundred leagues are on the map because a
/// directory placed them; a handful have their teams listed; fewer still are run here, with fixtures and a table. A
/// screen that words all three alike reads as three hundred leagues on THRØ, which is false — so each says which it is,
/// and nothing offers a table where no fixture exists to make one.
final class LeagueStandingWordsTests: XCTestCase {

    private func league(_ name: String, standing: String?, teams: Int, fixtures: Int?, results: Int? = nil,
                        locality: String? = "Yarm") -> PublicLeague {
        let rows = (0..<teams).map { """
            {"teamId":"\(UUID().uuidString)","name":"Team \($0)","venue":null}
            """ }.joined(separator: ",")
        let counts = fixtures.map { ",\"fixtures\":\($0),\"results\":\(results ?? 0)" } ?? ""
        let season = (teams > 0 || fixtures != nil) ? """
            {"leagueSeasonId":"\(UUID().uuidString)","label":"2026-27","startsOn":"2026-09-01","endsOn":"2027-05-31","current":true\(counts),
             "divisions":[{"divisionId":"\(UUID().uuidString)","name":"One","ordinal":1,"teams":[\(rows)]}]}
            """ : ""
        let json = """
        {"leagueId":"\(UUID().uuidString)","name":"\(name)","shortName":null,"playsOn":"Thursday","locality":\(locality.map { "\"\($0)\"" } ?? "null"),
         "latitude":54.5,"longitude":-1.3,"website":"https://example.org/"\(standing.map { ",\"standing\":\"\($0)\"" } ?? ""),
         "sources":[],"seasons":[\(season)]}
        """
        return try! Wire.decoder.decode(PublicLeague.self, from: Data(json.utf8))
    }

    func testALeagueIsRunHereOrHasItsTeamsListedOrIsOnlyOnTheMap() {
        XCTAssertEqual(league("A", standing: "run_here", teams: 3, fixtures: 12).held, .run)
        XCTAssertEqual(league("B", standing: "run_here", teams: 0, fixtures: 0).held, .run, "started this morning, nothing in it yet: still run here")
        XCTAssertEqual(league("C", standing: "listed", teams: 18, fixtures: 0).held, .teams)
        XCTAssertEqual(league("D", standing: "listed", teams: 0, fixtures: nil).held, .placed)
        // A server from before PD-126 says nothing about standing: what can be seen decides it, and nothing is claimed.
        XCTAssertEqual(league("E", standing: nil, teams: 18, fixtures: nil).held, .teams)
        XCTAssertEqual(league("F", standing: nil, teams: 0, fixtures: nil).held, .placed)
    }

    func testALeagueRowSaysWhatThroHoldsForIt() {
        XCTAssertEqual(DiscoverScreen.leagueMeta(league("A", standing: "run_here", teams: 3, fixtures: 12, results: 4), km: nil),
                       "Run on THRØ · 12 fixtures, 4 results · Thursday nights · Yarm")
        XCTAssertEqual(DiscoverScreen.leagueMeta(league("B", standing: "run_here", teams: 0, fixtures: 0), km: nil),
                       "Run on THRØ · no fixtures yet · Thursday nights · Yarm")
        XCTAssertEqual(DiscoverScreen.leagueMeta(league("C", standing: "listed", teams: 1, fixtures: 0), km: nil),
                       "1 team listed · Thursday nights · Yarm")
        XCTAssertEqual(DiscoverScreen.leagueMeta(league("D", standing: "listed", teams: 0, fixtures: nil, locality: nil), km: nil),
                       "On the map only · Thursday nights")
    }

    func testTheSlateCountsTheThreeKindsApart() {
        let all = [league("A", standing: "run_here", teams: 3, fixtures: 12), league("C", standing: "listed", teams: 18, fixtures: 0),
                   league("C2", standing: "listed", teams: 4, fixtures: 0), league("D", standing: "listed", teams: 0, fixtures: nil),
                   league("D2", standing: "listed", teams: 0, fixtures: nil), league("D3", standing: "listed", teams: 0, fixtures: nil)]
        XCTAssertEqual(NearbyLogic.heldLine(all), "1 is run on THRØ. 2 more have their teams listed. The other 3 are on the map from their own websites.")
        XCTAssertEqual(NearbyLogic.heldLine([all[3]]), "It is on the map from its own website; nothing of it is on THRØ yet.")
        XCTAssertEqual(NearbyLogic.heldLine([all[0]]), "1 is run on THRØ.")
        XCTAssertEqual(NearbyLogic.heldLine(Array(all[3...])), "All are on the map from their own websites; none is run on THRØ yet.")
        let slate = NearbyLogic.headline(place: .unknown, leagues: all)
        XCTAssertEqual(slate.title, "6 leagues on the map")
        XCTAssertTrue(slate.detail.hasPrefix("1 is run on THRØ."), slate.detail)
    }

    func testDiscoverOpensOnWhatIsRunHereThenOnWhatHasTeams() {
        let placed = (0..<9).map { league("Placed \($0)", standing: "listed", teams: 0, fixtures: nil) }
        let list = placed + [league("Listed", standing: "listed", teams: 18, fixtures: 0), league("Run", standing: "run_here", teams: 0, fixtures: 0)]
        XCTAssertEqual(DiscoverScreen.shortlist(list, place: .unknown).prefix(3).map(\.league.name), ["Run", "Listed", "Placed 0"])
    }

    func testATableIsOfferedOnlyWhereFixturesExistToMakeOne() {
        XCTAssertTrue(LeagueBoardWords.offersTable(league("A", standing: "run_here", teams: 3, fixtures: 12)))
        XCTAssertFalse(LeagueBoardWords.offersTable(league("C", standing: "listed", teams: 18, fixtures: 0)), "imported teams and no fixtures: a table would be an empty page")
        XCTAssertFalse(LeagueBoardWords.offersTable(league("D", standing: "listed", teams: 0, fixtures: nil)))
        XCTAssertTrue(LeagueBoardWords.offersTable(league("E", standing: nil, teams: 18, fixtures: nil)), "an older server does not count: offer it, as before")
    }

    func testALeagueCardSaysWhereItsFixturesAre() {
        XCTAssertEqual(LeagueBoardWords.held(league("A", standing: "run_here", teams: 3, fixtures: 12, results: 4)),
                       "Run on THRØ: 12 fixtures, 4 with a result. The table is worked out from them.")
        XCTAssertEqual(LeagueBoardWords.held(league("B", standing: "run_here", teams: 0, fixtures: 0)),
                       "Run on THRØ. Its organiser has not scheduled a fixture yet.")
        XCTAssertEqual(LeagueBoardWords.held(league("C", standing: "listed", teams: 18, fixtures: 0)),
                       "Its teams are listed here from its own website. Its fixtures and table are kept there, not on THRØ.")
        XCTAssertEqual(LeagueBoardWords.held(league("D", standing: "listed", teams: 0, fixtures: nil)),
                       "On the map where the league lists itself. Its teams, fixtures and table are on its own website, not on THRØ.")
    }

    /// Found by looking: a league started here has no source to name, and its card read "From . Venues are matched…".
    func testALeagueStartedHereSaysSoRatherThanNamingNoSource() {
        XCTAssertEqual(LeaguesPlot.provenance(league("A", standing: "run_here", teams: 3, fixtures: 12)),
                       "Started on THRØ by whoever runs it. Each team's pub is the one its own captain or admin set.")
        XCTAssertEqual(LeaguesPlot.provenance(league("C", standing: "listed", teams: 3, fixtures: 0)),
                       "Listed from elsewhere. Venues are matched from OpenStreetMap (© OpenStreetMap contributors), most by the team's name; whoever runs a team sets its pub on the team's page.")
    }

    func testAnEmptyFixtureListSaysThereAreNoneRatherThanThatAllArePlayed() {
        XCTAssertEqual(LeagueTableWords.nothingToPlay(decided: 0), "No fixtures on THRØ for this season yet. They appear when the league's organiser schedules them.")
        XCTAssertEqual(LeagueTableWords.nothingToPlay(decided: 7), "Every fixture in this season has a result.")
    }
}
