import XCTest
@testable import ThroApp
import ThroNet

/// The local leagues screen (PD-033): what the wire says decodes, one pin per venue, the season
/// shown is the running one, and every line a player reads says where it came from.
final class LeaguesScreenTests: XCTestCase {

    static let wire = """
    {"leagues":[{"leagueId":"11111111-1111-1111-1111-111111111111","name":"Stockton and District Thursday Night Darts League","shortName":"Stockton Thursday Night Darts","playsOn":"Thursday","locality":"Stockton-on-Tees",
      "sources":[{"source":"LeagueRepublic","url":"https://stocktonthursdaydarts.leaguerepublic.com/","retrievedOn":"2026-09-10"}],
      "seasons":[
        {"leagueSeasonId":"22222222-2222-2222-2222-222222222221","label":"2025-2026","startsOn":"2025-09-01","endsOn":"2026-05-31","current":true,"divisions":[
          {"divisionId":"33333333-3333-3333-3333-333333333331","name":"Thursday Night Darts League","ordinal":1,"teams":[
            {"teamId":"44444444-4444-4444-4444-444444444441","name":"Blue Bell","venue":{"venueId":"55555555-5555-5555-5555-555555555551","name":"The Blue Bell","locality":"Egglescliffe","postcode":"TS16 0JF","latitude":54.5122671,"longitude":-1.3547167,"basis":"inferred from the team's name"}},
            {"teamId":"44444444-4444-4444-4444-444444444442","name":"Sheraton A","venue":{"venueId":"55555555-5555-5555-5555-555555555552","name":"The Thomas Sheraton","locality":"Stockton-on-Tees","postcode":"TS18 1BH","latitude":54.5613574,"longitude":-1.3131986,"basis":"inferred from the team's name"}},
            {"teamId":"44444444-4444-4444-4444-444444444443","name":"Sheraton B","venue":{"venueId":"55555555-5555-5555-5555-555555555552","name":"The Thomas Sheraton","locality":"Stockton-on-Tees","postcode":"TS18 1BH","latitude":54.5613574,"longitude":-1.3131986,"basis":"inferred from the team's name"}},
            {"teamId":"44444444-4444-4444-4444-444444444444","name":"Buffs","venue":null}
          ]}]},
        {"leagueSeasonId":"22222222-2222-2222-2222-222222222222","label":"2024-2025","startsOn":"2024-09-01","endsOn":"2025-05-31","current":false,"divisions":[]}
      ]}]}
    """

    private func leagues() throws -> [PublicLeague] {
        struct Envelope: Decodable { let leagues: [PublicLeague] }
        return try Wire.decoder.decode(Envelope.self, from: Data(Self.wire.utf8)).leagues
    }

    func testTheWireDecodesAndTheRunningSeasonIsTheOneShown() throws {
        let l = try leagues()
        XCTAssertEqual(l.count, 1)
        XCTAssertEqual(l[0].shownSeason?.label, "2025-2026")
        XCTAssertEqual(l[0].shownSeason?.divisions[0].teams.count, 4)
        XCTAssertEqual(l[0].sources[0].source, "LeagueRepublic")
    }

    func testOnePinPerVenueSoTwoSidesOfOnePubAreOneMarker() throws {
        let pins = LeaguesPlot.plotted(try leagues())
        XCTAssertEqual(pins.count, 2, "Blue Bell and the Thomas Sheraton; Buffs has no venue and no pin")
        XCTAssertEqual(pins[1].teams, ["Sheraton A", "Sheraton B"])
        XCTAssertTrue(pins[0].inferred)
        let region = LeaguesPlot.region(pins)
        XCTAssertEqual(region.center.latitude, (54.5122671 + 54.5613574) / 2, accuracy: 1e-6)
        XCTAssertGreaterThanOrEqual(region.span.latitudeDelta, 0.02)
    }

    static let directoryWire = """
    {"leagueId":"66666666-6666-6666-6666-666666666661","name":"Salisbury Premier Darts League","shortName":null,"playsOn":null,"locality":null,
     "latitude":51.0768,"longitude":-1.8014,"website":"https://salisburypremdartsleague.leaguerepublic.com/",
     "sources":[{"source":"LeagueRepublic","url":"https://salisburypremdartsleague.leaguerepublic.com/","retrievedOn":"2026-09-11"}],"seasons":[]}
    """

    func testALeagueTheDirectoryPlacedIsALeaguePinAndALeagueWithPubsIsNot() throws {
        let salisbury = try Wire.decoder.decode(PublicLeague.self, from: Data(Self.directoryWire.utf8))
        let pins = LeaguesPlot.plotted(try leagues() + [salisbury])
        XCTAssertEqual(pins.count, 3, "two pubs and one league")
        XCTAssertEqual(pins.filter { $0.kind == .league }.map(\.name), ["Salisbury Premier Darts League"])
        XCTAssertEqual(pins.last?.link, "https://salisburypremdartsleague.leaguerepublic.com/")
        XCTAssertTrue(pins.last!.teams.isEmpty, "a league pin claims no team and no pub")
        XCTAssertFalse(pins.prefix(2).contains { $0.kind == .league }, "Stockton has pubs, so it is not also a point")

        // The list under the map is for leagues with teams; the note counts the rest.
        XCTAssertEqual(LeaguesPlot.sections(try leagues() + [salisbury], place: .unknown).map(\.name).count, 1)
        XCTAssertEqual(LeaguesPlot.unfilledLine(1), "1 more league is on the map with no teams listed yet. Tap its pin.")

        // The map opens round the player, not round the whole country.
        let region = LeaguesPlot.region(pins, place: .located(lat: 51.07, lon: -1.79))
        XCTAssertEqual(region.center.latitude, 51.07, accuracy: 1e-9)
        XCTAssertLessThan(region.span.latitudeDelta, 10, "Salisbury to Stockton is 3.5° of latitude; the frame is the nearest five, not the lot")
        XCTAssertEqual(LeaguesPlot.region(pins, place: .unknown).center.latitude, LeaguesPlot.region(pins).center.latitude, accuracy: 1e-9)
    }

    func testEveryLineSaysWhereItCameFrom() throws {
        let l = try leagues()[0]
        XCTAssertEqual(LeaguesPlot.meta(l), "Thursday nights · Stockton-on-Tees")
        XCTAssertEqual(LeaguesPlot.provenance(l),
                       "From LeagueRepublic (read 10 Sep 2026). Venues are matched from OpenStreetMap, most by the team's name; tell THRØ if one is wrong.")
        XCTAssertEqual(LeaguesPlot.venueLine(l.shownSeason?.divisions[0].teams[0].venue), "The Blue Bell · TS16 0JF (by name)")
        XCTAssertEqual(LeaguesPlot.venueLine(nil), "venue not known")
    }

    func testNoPersonIsOnTheWireOrTheScreen() throws {
        XCTAssertFalse(Self.wire.lowercased().contains("player"))
        let mirror = Mirror(reflecting: try leagues()[0].shownSeason!.divisions[0].teams[0])
        XCTAssertEqual(Set(mirror.children.compactMap(\.label)), ["teamId", "name", "venue"])
    }

    @MainActor
    func testAnUnreachableServerIsExplainedNotBlamedOnThePhone() async {
        let model = LeaguesModel()
        await model.load(nil)
        XCTAssertEqual(model.state, .failed("This build names no server."))
        XCTAssertTrue(LeaguesModel.explain(APIError.unreachable("offline")).contains("No connection"))
        XCTAssertTrue(LeaguesModel.explain(APIError.status(503, "")).contains("503"))
    }
}
