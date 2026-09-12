import CoreLocation
import XCTest
@testable import ThroApp
import ThroNet

/// "Around you" is measured, not assumed: distances from the phone to the venues, nearest first,
/// and honest words when the nearest league is a long way off.
final class NearbyTests: XCTestCase {

    private func league(_ name: String, short: String? = nil, night: String? = "Thursday", locality: String = "Stockton-on-Tees",
                        venues: [(String, Double, Double)]) -> PublicLeague {
        let teams = venues.enumerated().map { i, v -> String in
            """
            {"teamId":"\(UUID().uuidString)","name":"Team \(i)","venue":{"venueId":"\(UUID().uuidString)","name":"\(v.0)","locality":"\(locality)","postcode":null,"latitude":\(v.1),"longitude":\(v.2),"basis":"inferred from the team's name"}}
            """
        }.joined(separator: ",")
        let json = """
        {"leagueId":"\(UUID().uuidString)","name":"\(name)","shortName":\(short.map { "\"\($0)\"" } ?? "null"),"playsOn":\(night.map { "\"\($0)\"" } ?? "null"),"locality":"\(locality)",
         "sources":[{"source":"LeagueRepublic","url":null,"retrievedOn":"2026-09-10"}],
         "seasons":[{"leagueSeasonId":"\(UUID().uuidString)","label":"2025-2026","startsOn":"2025-09-01","endsOn":"2026-05-31","current":true,
           "divisions":[{"divisionId":"\(UUID().uuidString)","name":"Division 1","ordinal":1,"teams":[\(teams)]}]}]}
        """
        return try! Wire.decoder.decode(PublicLeague.self, from: Data(json.utf8))
    }

    func testDistanceIsGreatCircleInKilometres() {
        // Stockton High Street to Redcar seafront is about 22 km as the crow flies.
        let km = NearbyLogic.distanceKm(fromLat: 54.5645, lon: -1.3187, toLat: 54.6180, lon: -1.0630)
        XCTAssertEqual(km, 17.5, accuracy: 1.5)
        XCTAssertEqual(NearbyLogic.distanceKm(fromLat: 54.5, lon: -1.3, toLat: 54.5, lon: -1.3), 0, accuracy: 1e-9)
    }

    func testLeaguesAreSortedByTheirNearestVenueAndUnplacedOnesGoLast() {
        let stockton = league("Stockton Thursday", venues: [("The Sun Inn", 54.5656, -1.3119), ("Golden Jubilee", 54.4968, -1.3435)])
        let redcar = league("Redcar", locality: "Redcar", venues: [("The Lobster", 54.6174, -1.0764)])
        let unplaced = league("Nowhere", venues: [])
        // From Redcar seafront: Redcar first, then Stockton by its nearer pub, then the league with no pins.
        let ranked = NearbyLogic.sorted([unplaced, stockton, redcar], fromLat: 54.6180, lon: -1.0630)
        XCTAssertEqual(ranked.map { $0.league.name }, ["Redcar", "Stockton Thursday", "Nowhere"])
        XCTAssertNil(ranked[2].km)
        XCTAssertLessThan(ranked[0].km!, ranked[1].km!)
    }

    /// A league the directory placed: a point of its own and nothing else yet.
    private func placed(_ name: String, lat: Double, lon: Double) -> PublicLeague {
        let json = """
        {"leagueId":"\(UUID().uuidString)","name":"\(name)","shortName":null,"playsOn":null,"locality":null,
         "latitude":\(lat),"longitude":\(lon),"website":"https://example.leaguerepublic.com/",
         "sources":[{"source":"LeagueRepublic","url":"https://example.leaguerepublic.com/","retrievedOn":"2026-09-11"}],"seasons":[]}
        """
        return try! Wire.decoder.decode(PublicLeague.self, from: Data(json.utf8))
    }

    func testALeagueWithNoPubPlacedIsMeasuredFromItsOwnPoint() {
        // Salisbury Premier is a point on the directory and nothing more; Stockton has pubs. From
        // Salisbury market square the directory league is a mile off and Stockton is not.
        let salisbury = placed("Salisbury Premier Darts League", lat: 51.0768, lon: -1.8014)
        let stockton = league("Stockton Thursday", venues: [("The Sun Inn", 54.5656, -1.3119)])
        let ranked = NearbyLogic.sorted([stockton, salisbury], fromLat: 51.0700, lon: -1.7950)
        XCTAssertEqual(ranked.map { $0.league.name }, ["Salisbury Premier Darts League", "Stockton Thursday"])
        XCTAssertLessThan(ranked[0].km!, 2)

        // And the slate says the truth about it: near, teams not here yet.
        let slate = NearbyLogic.headline(place: .located(lat: 51.0700, lon: -1.7950), leagues: [stockton, salisbury])
        XCTAssertEqual(slate.title, "1 league near you")
        XCTAssertTrue(slate.detail.hasPrefix("Within 24 miles; their teams are not on THRØ yet."), slate.detail)
        XCTAssertEqual(NearbyLogic.filled([stockton, salisbury]), 1)
        let unknown = NearbyLogic.headline(place: .unknown, leagues: [stockton, salisbury])
        XCTAssertEqual(unknown.title, "2 leagues listed")
        XCTAssertTrue(unknown.detail.hasPrefix("One has its teams on THRØ so far"), unknown.detail)
    }

    func testDiscoverShortlistsSixAndOpensOnLeaguesWithTeamsWhenItCannotMeasure() {
        var many = (0..<9).map { placed("Directory \($0)", lat: 52 + Double($0) * 0.1, lon: -1) }
        let stockton = league("Stockton Thursday", venues: [("The Sun Inn", 54.5656, -1.3119)])
        many.append(stockton)
        let unlocated = DiscoverScreen.shortlist(many, place: .unknown)
        XCTAssertEqual(unlocated.count, DiscoverScreen.shortlistLength)
        XCTAssertEqual(unlocated.first?.league.name, "Stockton Thursday", "a league you can join comes first")
        XCTAssertEqual(DiscoverScreen.leagueMeta(many[0], km: nil), "teams not listed yet")
        let located = DiscoverScreen.shortlist(many, place: .located(lat: 52.85, lon: -1))
        XCTAssertEqual(located.count, DiscoverScreen.shortlistLength)
        XCTAssertEqual(located.first?.league.name, "Directory 8", "nearest first when the phone knows where it is")
    }

    func testMilesReadTheWayTheUKReadsThem() {
        XCTAssertEqual(NearbyLogic.miles(0.05), "here")
        XCTAssertEqual(NearbyLogic.miles(3.2), "2.0 mi")
        XCTAssertEqual(NearbyLogic.miles(300), "186 mi")
    }

    func testTheSlateTellsSomeoneInBrightonTheTruth() {
        let stockton = league("Stockton and District Thursday Night Darts League", short: "Stockton Thursday", venues: [("The Sun Inn", 54.5656, -1.3119)])
        let brighton = NearbyLogic.headline(place: .located(lat: 50.8225, lon: -0.1372), leagues: [stockton])
        XCTAssertEqual(brighton.title, "Nothing near you yet")
        XCTAssertTrue(brighton.detail.hasPrefix("The nearest league THRØ knows is Stockton Thursday, 2"), brighton.detail)
        XCTAssertTrue(brighton.detail.contains(" mi away"))

        let stocktonian = NearbyLogic.headline(place: .located(lat: 54.5645, lon: -1.3187), leagues: [stockton])
        XCTAssertEqual(stocktonian.title, "1 league near you")
        XCTAssertTrue(stocktonian.detail.contains("Nearest: Stockton Thursday"))

        let noLocation = NearbyLogic.headline(place: .unknown, leagues: [stockton])
        XCTAssertEqual(noLocation.title, "1 league listed")
        XCTAssertTrue(noLocation.detail.hasPrefix("One has its teams on THRØ so far (1 teams)."), noLocation.detail)
        XCTAssertTrue(noLocation.detail.contains("Use your location"))
        XCTAssertTrue(NearbyLogic.headline(place: .denied, leagues: [stockton]).detail.contains("Location is off"))
        XCTAssertEqual(NearbyLogic.headline(place: .unknown, leagues: nil).title, "Finding the leagues")
        XCTAssertEqual(NearbyLogic.headline(place: .unknown, leagues: []).title, "No leagues listed yet")
    }

    func testTheLocationButtonStaysUntilThePhoneHasSaidWhereItIs() {
        XCTAssertTrue(DiscoverScreen.offersLocation(.unknown))
        XCTAssertTrue(DiscoverScreen.offersLocation(.asking))
        XCTAssertTrue(DiscoverScreen.offersLocation(.denied), "disabled and saying so, not vanished")
        XCTAssertFalse(DiscoverScreen.offersLocation(.located(lat: 54.5, lon: -1.3)))
    }

    func testALeagueRowSaysNightTeamsAndTownAndItsDistanceGoesOnTheRight() {
        let l = league("Stockton and District Monday Night Mixed Darts League", short: "Stockton Monday Mixed", night: "Monday", venues: [("The Hoptimist", 54.5617, -1.3145)])
        XCTAssertEqual(DiscoverScreen.leagueMeta(l, km: 3), "Monday nights · 1 teams · Stockton-on-Tees".replacingOccurrences(of: "1 teams", with: "1 teams"))
        XCTAssertEqual(DiscoverScreen.initials(l), "SM")
        let far = LeaguesPlot.farAway(place: .located(lat: 50.8225, lon: -0.1372), pins: LeaguesPlot.plotted([l]))
        XCTAssertTrue(far?.hasPrefix("You are 2") == true && far!.contains("nearest league THRØ has listed"), far ?? "nil")
        XCTAssertNil(LeaguesPlot.farAway(place: .located(lat: 54.5645, lon: -1.3187), pins: LeaguesPlot.plotted([l])))
        XCTAssertNil(LeaguesPlot.farAway(place: .unknown, pins: LeaguesPlot.plotted([l])))
    }
}

extension NearbyTests {
    func testPinsATheThumbApartBecomeOneMarkerUntilYouZoomIn() {
        func pin(_ name: String, _ lat: Double, _ lon: Double) -> PlottedVenue {
            PlottedVenue(id: UUID(), name: name, postcode: nil, locality: nil, coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lon), teams: [name], inferred: false)
        }
        // Three Portrack pubs within 400 m, one in Yarm 7 km away.
        let pins = [pin("Hoptimist", 54.5617, -1.3145), pin("Thomas Sheraton", 54.5614, -1.3132), pin("Sun Inn", 54.5656, -1.3119), pin("Golden Jubilee", 54.4968, -1.3435)]
        // Zoomed out: the whole borough across the phone.
        let far = LeaguesPlot.clustered(pins, degreesPerPoint: 0.15 / 400)
        XCTAssertEqual(far.map(\.count), [3, 1], "the three neighbours are one marker; Yarm stands alone")
        XCTAssertEqual(far[0].pins.map(\.name), ["Hoptimist", "Thomas Sheraton", "Sun Inn"])
        // Zoomed in on Portrack: they come apart.
        let near = LeaguesPlot.clustered(pins, degreesPerPoint: 0.004 / 400)
        XCTAssertEqual(near.count, 4)
        // Order is stable, so markers do not shuffle between frames.
        XCTAssertEqual(LeaguesPlot.clustered(pins, degreesPerPoint: 0.15 / 400).map(\.id), far.map(\.id))
        XCTAssertEqual(LeaguesPlot.clustered(pins, degreesPerPoint: 0).count, 4, "no scale yet: every pin its own marker")
    }
}
