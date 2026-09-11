import XCTest
@testable import ThroApp
import ThroNet

/// The leagues as a player asks of them (PD-046): a chosen team says its league, division and night;
/// a pub lists who plays there, across leagues; a team's rivals come nearest first; and a name finds
/// a team or a pub whatever its case or accents.
final class LeagueAtlasTests: XCTestCase {

    /// Two leagues. Stockton runs two divisions and last season too; Redcar runs one. The Thomas
    /// Sheraton hosts a side from each.
    static let wire = """
    {"leagues":[
     {"leagueId":"11111111-1111-1111-1111-111111111111","name":"Stockton and District Thursday Night Darts League","shortName":"Stockton Thursday","playsOn":"Thursday","locality":"Stockton-on-Tees",
      "sources":[{"source":"LeagueRepublic","url":null,"retrievedOn":"2026-09-10"}],
      "seasons":[
       {"leagueSeasonId":"22222222-2222-2222-2222-222222222221","label":"2025-2026","startsOn":"2025-09-01","endsOn":"2026-05-31","current":true,"divisions":[
        {"divisionId":"33333333-3333-3333-3333-333333333331","name":"Premier","ordinal":1,"teams":[
         {"teamId":"44444444-4444-4444-4444-444444444441","name":"Blue Bell","venue":{"venueId":"55555555-5555-5555-5555-555555555551","name":"The Blue Bell","locality":"Egglescliffe","postcode":"TS16 0JF","latitude":54.5122671,"longitude":-1.3547167,"basis":"inferred from the team's name"}},
         {"teamId":"44444444-4444-4444-4444-444444444442","name":"Sheraton A","venue":{"venueId":"55555555-5555-5555-5555-555555555552","name":"The Thomas Sheraton","locality":"Stockton-on-Tees","postcode":"TS18 1BH","latitude":54.5613574,"longitude":-1.3131986,"basis":"inferred from the team's name"}}
        ]},
        {"divisionId":"33333333-3333-3333-3333-333333333332","name":"Division One","ordinal":2,"teams":[
         {"teamId":"44444444-4444-4444-4444-444444444443","name":"Sheraton B","venue":{"venueId":"55555555-5555-5555-5555-555555555552","name":"The Thomas Sheraton","locality":"Stockton-on-Tees","postcode":"TS18 1BH","latitude":54.5613574,"longitude":-1.3131986,"basis":"inferred from the team's name"}},
         {"teamId":"44444444-4444-4444-4444-444444444444","name":"Buffs","venue":null},
         {"teamId":"44444444-4444-4444-4444-444444444445","name":"Kings Head","venue":{"venueId":"55555555-5555-5555-5555-555555555553","name":"The Kings Head","locality":"Stockton-on-Tees","postcode":null,"latitude":54.5700,"longitude":-1.3200,"basis":"stated by the source"}}
        ]}]},
       {"leagueSeasonId":"22222222-2222-2222-2222-222222222222","label":"2024-2025","startsOn":"2024-09-01","endsOn":"2025-05-31","current":false,"divisions":[
        {"divisionId":"33333333-3333-3333-3333-333333333339","name":"Old","ordinal":1,"teams":[
         {"teamId":"44444444-4444-4444-4444-444444444449","name":"Gone Arms","venue":null}]}]}
      ]},
     {"leagueId":"11111111-1111-1111-1111-111111111112","name":"Redcar Monday Darts League","shortName":null,"playsOn":"Monday","locality":"Redcar",
      "sources":[{"source":"LeagueRepublic","url":null,"retrievedOn":"2026-09-10"}],
      "seasons":[
       {"leagueSeasonId":"22222222-2222-2222-2222-222222222223","label":"2025-2026","startsOn":"2025-09-01","endsOn":"2026-05-31","current":true,"divisions":[
        {"divisionId":"33333333-3333-3333-3333-333333333333","name":"Redcar Monday Darts League","ordinal":1,"teams":[
         {"teamId":"44444444-4444-4444-4444-444444444446","name":"Sheraton C","venue":{"venueId":"55555555-5555-5555-5555-555555555552","name":"The Thomas Sheraton","locality":"Stockton-on-Tees","postcode":"TS18 1BH","latitude":54.5613574,"longitude":-1.3131986,"basis":"inferred from the team's name"}},
         {"teamId":"44444444-4444-4444-4444-444444444447","name":"Coatham","venue":{"venueId":"55555555-5555-5555-5555-555555555554","name":"Coatham Road SC","locality":"Redcar","postcode":null,"latitude":54.6180,"longitude":-1.0700,"basis":"stated by the source"}},
         {"teamId":"44444444-4444-4444-4444-444444444448","name":"Café Royal","venue":null}
        ]}]}
      ]}
    ]}
    """

    private func leagues() throws -> [PublicLeague] {
        struct Envelope: Decodable { let leagues: [PublicLeague] }
        return try Wire.decoder.decode(Envelope.self, from: Data(Self.wire.utf8)).leagues
    }

    private func atlas() throws -> LeagueAtlas { LeagueAtlas(try leagues()) }

    private func id(_ n: Int) -> UUID { UUID(uuidString: "44444444-4444-4444-4444-44444444444\(n)")! }
    private let sheraton = UUID(uuidString: "55555555-5555-5555-5555-555555555552")!

    func testAChosenTeamSaysItsLeagueItsDivisionAndItsNight() throws {
        let a = try atlas()
        XCTAssertEqual(a.entries.count, 8, "the shown season only: last season's Gone Arms is not on today's map")
        XCTAssertNil(a.entry(id(9)))
        XCTAssertEqual(LeagueAtlas.line(try XCTUnwrap(a.entry(id(3)))), "Stockton Thursday · Division One · Thursday nights")
        XCTAssertEqual(LeagueAtlas.line(try XCTUnwrap(a.entry(id(7)))), "Redcar Monday Darts League · Monday nights",
                       "a league with one division does not name it twice")
        XCTAssertEqual(a.entry(id(3))?.season, "2025-2026")
    }

    func testAPubListsEveryTeamThatPlaysThereAcrossLeagues() throws {
        let here = try atlas().teams(at: sheraton)
        XCTAssertEqual(here.map(\.team.name), ["Sheraton A", "Sheraton B", "Sheraton C"], "by league, then division, then name")
        XCTAssertEqual(here.map(\.league), ["Stockton Thursday", "Stockton Thursday", "Redcar Monday Darts League"])
    }

    func testRivalsAreTheDivisionNearestPubFirstAndTheUnplacedLast() throws {
        let rivals = try atlas().rivals(of: id(3))
        XCTAssertEqual(rivals.map(\.entry.team.name), ["Kings Head", "Buffs"], "Division One only; Sheraton A is in the Premier")
        let km = try XCTUnwrap(rivals.first?.km)
        XCTAssertGreaterThan(km, 0.5)
        XCTAssertLessThan(km, 2, "the Kings Head is about a kilometre from the Sheraton")
        XCTAssertNil(rivals.last?.km, "Buffs has no pub on the map, and is still a rival")
        XCTAssertTrue(try atlas().rivals(of: UUID()).isEmpty)
    }

    func testANameFindsTeamsAndPubsWhateverItsCaseOrAccents() throws {
        let a = try atlas()
        let sher = a.search("sher")
        XCTAssertEqual(sher.prefix(3).map(\.name), ["Sheraton A", "Sheraton B", "Sheraton C"], "names that begin with it come first")
        guard case .venue(let pub, let teams)? = sher.last else { return XCTFail("the pub is found too: \(sher)") }
        XCTAssertEqual(pub.name, "The Thomas Sheraton")
        XCTAssertEqual(teams.count, 3)
        XCTAssertEqual(a.search("  BLUE ").map(\.name), ["Blue Bell", "The Blue Bell"])
        XCTAssertEqual(a.search("cafe").map(\.name), ["Café Royal"], "accents aside")
        XCTAssertTrue(a.search("b").isEmpty, "one letter would match half the map")
        XCTAssertEqual(a.search("s", limit: 2).count, 0)
        XCTAssertEqual(a.search("sheraton", limit: 2).count, 2)
    }

    func testEachLeagueHasItsOwnChalkAndItsCount() throws {
        let a = try atlas()
        XCTAssertEqual(a.leagues.map(\.name), ["Stockton Thursday", "Redcar Monday Darts League"])
        XCTAssertEqual(a.leagues.map(\.chalk), [0, 1])
        XCTAssertEqual(a.leagues.map(\.teams), [5, 3])
        XCTAssertEqual(a.entry(id(6))?.chalk, 1)
    }

    func testAPubIsChalkedInEveryLeagueThatPlaysThere() throws {
        let a = try atlas()
        XCTAssertEqual(a.chalks(at: sheraton), [0, 1], "Stockton's chalk and Redcar's: sides from two leagues play there")
        XCTAssertEqual(a.chalks(at: UUID(uuidString: "55555555-5555-5555-5555-555555555551")!), [0])
        XCTAssertTrue(a.chalks(at: UUID()).isEmpty)
    }

    func testALeagueListsItsDivisionsInOrderWithTheirTeamsByName() throws {
        let d = try atlas().divisions(of: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!)
        XCTAssertEqual(d.map(\.name), ["Premier", "Division One"])
        XCTAssertEqual(d.last?.teams.map(\.team.name), ["Buffs", "Kings Head", "Sheraton B"])
        XCTAssertTrue(try atlas().divisions(of: UUID()).isEmpty)
    }

    func testAPubsLineCountsItsTeamsAndNamesItsLeagues() throws {
        let a = try atlas()
        XCTAssertEqual(LeagueAtlas.pubLine(a.teams(at: sheraton)), "3 teams · Stockton Thursday, Redcar Monday Darts League")
        XCTAssertEqual(LeagueAtlas.pubLine(a.teams(at: UUID(uuidString: "55555555-5555-5555-5555-555555555553")!)), "1 team · Stockton Thursday")
    }

    func testALeagueIsFoundByNameEvenWithNoTeamsOnTHRO() throws {
        let bare = #"{"leagueId":"11111111-1111-1111-1111-111111111113","name":"Salisbury and District Darts League","shortName":null,"playsOn":"Tuesday","locality":"Salisbury","sources":[],"seasons":[]}"#
        let all = try leagues() + [try Wire.decoder.decode(PublicLeague.self, from: Data(bare.utf8))]
        XCTAssertEqual(LeagueAtlas.leaguesNamed("salis", in: all).map(\.name), ["Salisbury and District Darts League"],
                       "a league with no teams listed is still found by its name")
        XCTAssertEqual(LeagueAtlas.leaguesNamed("red", in: all).map(\.name), ["Redcar Monday Darts League"])
        XCTAssertEqual(LeagueAtlas.leaguesNamed("STOCKTON thurs", in: all).map(\.name), ["Stockton and District Thursday Night Darts League"],
                       "by its short name too, whatever the case")
        XCTAssertEqual(LeagueAtlas.leaguesNamed("darts", in: all, limit: 2).count, 2)
        XCTAssertTrue(LeagueAtlas.leaguesNamed("d", in: all).isEmpty)
    }

    func testNoPersonIsInTheAtlas() throws {
        let entry = try XCTUnwrap(try atlas().entry(id(1)))
        let labels = Set(Mirror(reflecting: entry.team).children.compactMap(\.label))
        XCTAssertEqual(labels, ["teamId", "name", "venue"], "a team and its pub; nobody on it")
    }
}
