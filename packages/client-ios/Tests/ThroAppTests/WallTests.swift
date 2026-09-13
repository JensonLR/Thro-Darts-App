import XCTest
@testable import ThroApp
import ThroLiveKit
import ThroNet
import ThroVenueKit

/// A league on a pub television, driven from a phone (PD-089).
///
/// The Apple TV app is the better answer for a room that keeps a screen on all season. It is also £150 of
/// hardware registered to a developer team, and a landlord with an iPhone and an HDMI adapter has neither
/// of those problems tonight. These hold the two properties that make the phone version safe to ship.
final class WallTests: XCTestCase {

    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: "wall-tests-\(UUID().uuidString)")
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: defaults.dictionaryRepresentation().description)
        defaults = nil
        super.tearDown()
    }

    private var configuration: ServerConfiguration {
        ServerConfiguration(baseURL: URL(string: "https://thro.invalid")!, googleClientID: nil)
    }

    // MARK: what the wall reads with

    func testTheWallsClientHoldsNoSession() async {
        // The property the Apple TV app has structurally, arranged deliberately here. The phone has a
        // signed-in client a few lines away and passing it would work today, because every route the
        // wall reads is public. If one ever starts returning more to an authenticated caller, the pub
        // television must not be the surface that finds out.
        let signedIn = await ThroWall.api(for: configuration).isSignedIn
        XCTAssertFalse(signedIn)
    }

    func testTheWallsClientIsNotTheSameDeviceTwice() async {
        // Nothing the wall asks for is about a device, so there is nothing for its device id to be. One
        // that persisted would be a correlatable identifier attached to reads made on behalf of a room.
        let a = await ThroWall.api(for: configuration).deviceId
        let b = await ThroWall.api(for: configuration).deviceId
        XCTAssertNotEqual(a, b)
    }

    // MARK: what the wall shows

    func testASeasonChosenOnThePhoneIsRememberedAcrossAPowerCut() {
        // A pub's telly is unplugged at closing and switched on by somebody who is not going to set it
        // up again. The choice is the same one the Apple TV app holds, under the same key, so a venue
        // that later buys the box does not start over.
        let choice = ThroVenueChoice(defaults: defaults)
        XCTAssertNil(choice.season)

        let season = UUID()
        choice.season = season
        XCTAssertEqual(ThroVenueChoice(defaults: defaults).season, season)

        choice.season = nil
        XCTAssertNil(ThroVenueChoice(defaults: defaults).season, "and taking it off the telly takes it off")
    }

    @MainActor func testTheMatchTakesTheScreenFromTheLeague() {
        // Two things can want the wall. If a match is being scored on this phone the room is watching
        // that match, and a league table would be the app deciding the game ten feet away matters less.
        let venue = ThroVenue.shared
        venue.clear()
        XCTAssertNil(venue.state, "nothing on this phone: the league gets the screen")

        venue.show(ThroLiveState(homeName: "Ann", awayName: "Bob",
                                 homeRemaining: 81, awayRemaining: 230,
                                 homeLegs: 2, awayLegs: 1, thrower: .home),
                   format: "501, best of 5")
        XCTAssertNotNil(venue.state, "a match on this phone takes it")

        venue.clear()
        XCTAssertNil(venue.state, "and gives it back when the match ends")
    }

    // MARK: the words

    func testAWallWithNothingOnItSaysWhereToChange() {
        // A black television with an app's name on it teaches somebody the feature does not work. It has
        // to name the screen the setting is on, because whoever reads it is holding the thing to change.
        XCTAssertTrue(ThroWall.nothingHint.contains("Live"))
        XCTAssertTrue(ThroWall.nothingHint.lowercased().contains("league"))
        // And it says what happens when a match starts, because that is the other state and somebody
        // who has just set a league up will otherwise think it broke when the board changed.
        XCTAssertTrue(ThroWall.nothingHint.lowercased().contains("match"))
    }
}
