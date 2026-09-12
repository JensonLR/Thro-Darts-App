import XCTest
@testable import ThroLiveKit

/// The board on a pub wall, and the one thing it must never do.
///
/// A Lock Screen is held by somebody who can see it has not moved. A wall screen is read across a
/// room by people who cannot, and it goes on drawing whatever it was last given for as long as the
/// cable is in. So the same staleness rule applies here and matters more — and when a match ends the
/// wall is cleared outright rather than left on the final leg, because a room reading a finished
/// scoreline as though it were live is exactly the failure this surface exists to avoid.
final class VenueTests: XCTestCase {

    private let leg = ThroLiveState(homeName: "Ann", awayName: "Bea",
                                    homeRemaining: 141, awayRemaining: 220,
                                    homeLegs: 1, awayLegs: 2, thrower: .home)

    override func tearDown() {
        ThroVenue.shared.clear()
        super.tearDown()
    }

    func testAnEmptyBoardIsNeverStale() {
        ThroVenue.shared.clear()
        XCTAssertNil(ThroVenue.shared.state)
        XCTAssertFalse(ThroVenue.shared.isStale(), "nothing on the wall cannot be out of date")
    }

    func testAScoreGoesStaleOnceNothingHasBeenHeard() {
        let venue = ThroVenue.shared
        venue.show(leg, format: "501 · first to 3 · double out")
        guard let heard = venue.heardAt else { return XCTFail("the board did not record when it heard") }

        XCTAssertFalse(venue.isStale(now: heard.addingTimeInterval(10)))
        XCTAssertFalse(venue.isStale(now: heard.addingTimeInterval(ThroVenue.freshness - 1)))
        XCTAssertTrue(venue.isStale(now: heard.addingTimeInterval(ThroVenue.freshness + 1)),
                      "a wall screen that stopped hearing must say so")
    }

    /// A new visit makes the board current again.
    func testHearingSomethingMakesItCurrentAgain() {
        let venue = ThroVenue.shared
        venue.show(leg, format: "501")
        let old = venue.heardAt!
        venue.show(leg, format: "501")
        XCTAssertGreaterThanOrEqual(venue.heardAt!, old)
        XCTAssertFalse(venue.isStale())
    }

    /// Clearing takes the match off the wall rather than freezing it there.
    func testClearingEmptiesTheWallRatherThanFreezingIt() {
        let venue = ThroVenue.shared
        venue.show(leg, format: "501")
        XCTAssertNotNil(venue.state)
        venue.clear()
        XCTAssertNil(venue.state)
        XCTAssertNil(venue.heardAt)
        XCTAssertFalse(venue.isStale())
    }

    /// The wall and the Lock Screen say the same thing about staleness, because they are the same
    /// claim about the same score.
    func testTheWallAndTheLockScreenAgreeOnWhatStaleMeans() {
        XCTAssertEqual(ThroVenue.freshness, 150, accuracy: 0.001)
        let stale = ThroLiveCopy.caption(leg, stale: true)
        XCTAssertTrue(stale.lowercased().contains("out of date"), stale)
    }
}
