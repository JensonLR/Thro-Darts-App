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

    func testAStaleScoreShowsNoRouteAtAll() {
        // Found by looking at it on a watch: the wrist warned that the score might be out of date and went
        // on showing the finish underneath, in green. A route is only as true as the remainder it was
        // computed from, and a wrist is the surface somebody actually throws at.
        XCTAssertEqual(ThroLiveCopy.route(leg(checkout: ["T19", "D12"]), stale: true), [])
        XCTAssertEqual(ThroLiveCopy.route(leg(checkout: ["T19", "D12"]), stale: false), ["T19", "D12"])
    }

    func testADecidedLegShowsNoRouteEither() {
        XCTAssertEqual(ThroLiveCopy.route(leg(checkout: ["D20"], winner: .home), stale: false), [])
    }

    func testNobodyOnTheOcheMeansNobodysRoute() {
        // Also found by looking: between legs the wrist showed a finish for a throw nobody was about to
        // take. The caption had always dropped it; the rule was inside the sentence rather than named.
        XCTAssertEqual(ThroLiveCopy.route(leg(thrower: nil, checkout: ["D20"]), stale: false), [])
    }

    // MARK: whose screen it is

    func testTheWinnerIsTheSubjectEvenThoughTheyAreNoLongerThrowing() {
        // Found by looking at a decided leg on a watch: both numerals were dim, because emphasis followed
        // "is throwing" and nobody throws once it is won — so the screen's answer to the only question
        // left was drawn in the quiet colour.
        let wonByTheOtherPlayer = leg(thrower: .home, winner: .away)
        let glance = ThroWatchGlance(state: wonByTheOtherPlayer)
        XCTAssertEqual(glance.leading, .away, "the winner is the big numeral, not whoever threw last")
        XCTAssertTrue(glance.emphasised(.away))
        XCTAssertFalse(glance.emphasised(.home))
    }

    func testTheThrowerIsTheSubjectWhileTheLegIsAlive() {
        let glance = ThroWatchGlance(state: leg(thrower: .away))
        XCTAssertEqual(glance.leading, .away)
        XCTAssertTrue(glance.emphasised(.away))
    }

    func testBetweenLegsNeitherPlayerIsClaimedToMatterMore() {
        let glance = ThroWatchGlance(state: leg(thrower: nil))
        XCTAssertFalse(glance.emphasised(.home))
        XCTAssertFalse(glance.emphasised(.away))
        XCTAssertEqual(glance.leading, .home, "a stable order, not a random one")
    }

    // MARK: the one line of words

    func testALiveLegSaysNothingBecauseTheDrawingHasAlreadySaidIt() {
        // The thrower's numeral is nearly twice the size of the other, and the route has its own line in
        // the finish colour. "Jenson R. to throw · checkout T19 D12" would be captioning a picture with
        // the picture, on the surface with the least room of any of them.
        XCTAssertNil(ThroWatchWords.note(leg(checkout: ["T19", "D12"]), stale: false))
    }

    func testTheWordsAreSpentOnWhatTheDrawingCannotSay() {
        XCTAssertEqual(ThroWatchWords.note(leg(thrower: nil), stale: false), "Between legs")
        XCTAssertEqual(ThroWatchWords.note(leg(), stale: true), "May be out of date")
        XCTAssertEqual(ThroWatchWords.note(leg(winner: .home), stale: false), "Jenson R. wins")
    }

    func testTheOrderIsTheOneEveryOtherSurfaceUses() {
        // Decided outranks stale, and stale outranks the rest. Not a second opinion about precedence —
        // the same one, on a surface whose bottom of the list is empty. Held against `ThroLiveCopy`, so
        // a change there that reordered them would fail here.
        let decided = leg(winner: .home)
        XCTAssertEqual(ThroWatchWords.note(decided, stale: true), "Jenson R. wins")
        XCTAssertEqual(ThroLiveCopy.caption(decided, stale: true), "Jenson R. wins")
        let staleAndBetweenLegs = leg(thrower: nil)
        XCTAssertEqual(ThroWatchWords.note(staleAndBetweenLegs, stale: true), "May be out of date")
        XCTAssertTrue(ThroLiveCopy.caption(staleAndBetweenLegs, stale: true).hasPrefix("Score may be out of date"))
    }

    func testTheLegsAreShownOnceAsAScoreline() {
        // Two small digits beside two big ones read as noise; "2–1" reads as a match. The scoreline is
        // ThroLiveKit's, so the wall, the Lock Screen and the wrist cannot disagree about the separator.
        XCTAssertEqual(ThroLiveCopy.legs(leg(homeLegs: 2, awayLegs: 1)), "2–1")
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
