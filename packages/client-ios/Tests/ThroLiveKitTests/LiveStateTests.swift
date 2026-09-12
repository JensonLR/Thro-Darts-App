import XCTest
@testable import ThroLiveKit

/// What the Lock Screen says, and the one rule that makes it honest.
///
/// A Live Activity keeps drawing after the app stops running, and nothing updates it while the app
/// is in the background. A score there can be minutes old and look exactly as authoritative as one
/// from a second ago. Every other figure in THRØ says what it is; this is the same rule on a new
/// surface, and it is the thing these tests exist for.
final class LiveStateTests: XCTestCase {

    private func leg(thrower: LiveSeat? = .home, checkout: [String] = [],
                     winner: LiveSeat? = nil) -> ThroLiveState {
        ThroLiveState(homeName: "Ann", awayName: "Bea",
                      homeRemaining: 141, awayRemaining: 220,
                      homeLegs: 1, awayLegs: 2,
                      thrower: thrower, checkout: checkout, winner: winner)
    }

    /// **A stale score says so.** Not a subtitle tweak — the alternative is a Lock Screen showing a
    /// number it cannot vouch for, which is the exact failure the statistics layer exists to prevent
    /// one screen further in.
    func testAStaleScoreSaysSoInsteadOfLookingCurrent() {
        let fresh = ThroLiveCopy.caption(leg(), stale: false)
        let stale = ThroLiveCopy.caption(leg(), stale: true)
        XCTAssertNotEqual(fresh, stale)
        XCTAssertTrue(stale.lowercased().contains("out of date"), stale)
        XCTAssertFalse(fresh.lowercased().contains("out of date"), fresh)
    }

    /// A decided match outranks staleness. "Ann wins" does not go out of date.
    func testAFinishedMatchIsNeverDescribedAsStale() {
        let caption = ThroLiveCopy.caption(leg(thrower: nil, winner: .home), stale: true)
        XCTAssertEqual(caption, "Ann wins")
    }

    /// Nobody is shown on the oche once the match is over.
    func testNobodyIsThrowingAfterTheMatchIsDecided() {
        let over = leg(thrower: .home, winner: .away)
        XCTAssertFalse(ThroLiveCopy.isThrowing(over, .home))
        XCTAssertFalse(ThroLiveCopy.isThrowing(over, .away))
        XCTAssertTrue(ThroLiveCopy.isThrowing(leg(thrower: .home), .home))
        XCTAssertFalse(ThroLiveCopy.isThrowing(leg(thrower: .home), .away))
    }

    /// A checkout is named with the player who is on it, never floating free.
    func testACheckoutBelongsToWhoeverIsThrowing() {
        let caption = ThroLiveCopy.caption(leg(thrower: .away, checkout: ["T20", "D16"]), stale: false)
        XCTAssertTrue(caption.hasPrefix("Bea to throw"), caption)
        XCTAssertTrue(caption.contains("T20 D16"), caption)
    }

    /// Between legs there is no thrower and no invention.
    func testBetweenLegsSaysSo() {
        XCTAssertEqual(ThroLiveCopy.caption(leg(thrower: nil), stale: false), "Between legs")
    }

    /// **No statistic reaches this surface.** It can carry neither a basis nor a sample, so it
    /// carries legs and remainders and nothing else.
    func testTheSurfaceCarriesNoFigureItCannotQualify() {
        let texts = [ThroLiveCopy.caption(leg(checkout: ["T20", "D16"]), stale: false),
                     ThroLiveCopy.caption(leg(), stale: true),
                     ThroLiveCopy.legs(leg()),
                     ThroLiveCopy.compact(leg())]
        for text in texts {
            for banned in ["average", "avg", "%", "form", "rating", "rank"] {
                XCTAssertFalse(text.lowercased().contains(banned), "\(banned) in: \(text)")
            }
        }
    }

    /// The two sides are never crossed. A remainder under the wrong name is the one error on this
    /// surface a player would act on without checking.
    func testEachSideKeepsItsOwnNumbers() {
        let state = leg()
        XCTAssertEqual(state.name(.home), "Ann")
        XCTAssertEqual(state.name(.away), "Bea")
        XCTAssertEqual(state.remaining(.home), 141)
        XCTAssertEqual(state.remaining(.away), 220)
        XCTAssertEqual(state.legs(.home), 1)
        XCTAssertEqual(state.legs(.away), 2)
        XCTAssertEqual(ThroLiveCopy.legs(state), "1–2")
        XCTAssertEqual(ThroLiveCopy.compact(state), "141 · 220")
    }

    /// The whole state stays far inside ActivityKit's budget, which caps the attributes and the
    /// state **together** at 4 KB — for a pushed update as well as a local one.
    func testTheStateIsSmallEnoughForTheSurfaceItIsFor() throws {
        let big = ThroLiveState(homeName: String(repeating: "N", count: 60),
                                awayName: String(repeating: "M", count: 60),
                                homeRemaining: 501, awayRemaining: 501,
                                homeLegs: 9, awayLegs: 9, thrower: .home,
                                checkout: ["T20", "T20", "D20"])
        let encoded = try JSONEncoder().encode(big)
        XCTAssertLessThan(encoded.count, 1024,
                          "the state alone should leave most of the 4 KB budget for the attributes")
    }
}
