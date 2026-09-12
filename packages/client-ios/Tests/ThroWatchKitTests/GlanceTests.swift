import XCTest
@testable import ThroWatchKit
import ThroLiveKit

/// What a wrist says (PD-077). The drawing is looked at; these are the rules underneath it, which are the
/// part that can be wrong while nothing fails.
final class GlanceTests: XCTestCase {

    private func leg(thrower: LiveSeat? = .home, checkout: [String] = [],
                     homeLegs: Int = 2, awayLegs: Int = 1, winner: LiveSeat? = nil) -> ThroLiveState {
        ThroLiveState(homeName: "Jenson R.", awayName: "Ethan T.",
                      homeRemaining: 81, awayRemaining: 230,
                      homeLegs: homeLegs, awayLegs: awayLegs,
                      thrower: thrower, checkout: checkout, winner: winner)
    }

    func testTheThrowerIsSaidToBeThrowingAndTheOtherIsNot() {
        let state = leg()
        XCTAssertTrue(ThroWatchWords.spoken(state, .home).hasSuffix(", throwing"))
        XCTAssertFalse(ThroWatchWords.spoken(state, .away).contains("throwing"))
    }

    func testALegIsALegAndTwoAreLegs() {
        // "Jenson R., 81 remaining, 2" would be heard as part of the score. The word is what separates
        // them, which is the same reason the league table speaks its figures rather than reading them off.
        XCTAssertTrue(ThroWatchWords.spoken(leg(awayLegs: 1), .away).contains("1 leg,")
                        || ThroWatchWords.spoken(leg(awayLegs: 1), .away).contains("1 leg"))
        XCTAssertTrue(ThroWatchWords.spoken(leg(homeLegs: 2), .home).contains("2 legs"))
    }

    func testBothScoresAreSpokenBecauseADartsScoreOnlyMeansSomethingAgainstTheOther() {
        let state = leg()
        XCTAssertTrue(ThroWatchWords.spoken(state, .home).contains("81"))
        XCTAssertTrue(ThroWatchWords.spoken(state, .away).contains("230"))
    }

    func testTheStateIsCarriedNotDerived() {
        // The checkout is `[String]` on the state on purpose: the rule tables live in the engine, and a
        // watch that computed a route would be linking a scoring engine to draw three words (PD-077).
        // This holds that the glance never has to — it can only show what it was handed.
        let onAFinish = leg(checkout: ["T19", "D12"])
        XCTAssertEqual(onAFinish.checkout, ["T19", "D12"])
        XCTAssertTrue(leg().checkout.isEmpty, "and nothing is invented when there is no finish")
    }

    func testAFinishedMatchIsNotStillOnAFinish() {
        // `winner` set means the leg is over; a route still on screen would be telling somebody to throw
        // at a double in a match that is decided.
        let done = leg(checkout: ["T19", "D12"], winner: .home)
        XCTAssertNotNil(done.winner)
        XCTAssertFalse(ThroLiveCopy.isThrowing(done, .home),
                       "nobody is throwing once it is won, so nothing is marked as throwing")
    }

    func testAWatchReusesTheStateTheOtherSurfacesDraw() {
        // The point of the module: no fifth shape for two numbers and a checkout. If this ever needs its
        // own model, that is a decision to take and record, not a convenience to slip in.
        let state = leg(checkout: ["D20"])
        let coded = try? JSONEncoder().encode(state)
        XCTAssertNotNil(coded, "the state a watch draws is the state that crosses to a widget")
        let back = try? JSONDecoder().decode(ThroLiveState.self, from: coded ?? Data())
        XCTAssertEqual(back, state)
    }
}
