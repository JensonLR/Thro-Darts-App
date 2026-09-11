import XCTest
@testable import ThroApp

/// The welcome after the opening: asked once, never a gate, and never claiming more than THRØ does.
final class WelcomeTests: XCTestCase {

    func testItIsAskedOnceAndOnlyWhenThereIsSomethingToAsk() {
        XCTAssertTrue(Welcome.shows(configured: true, signedIn: false, seen: false))
        // Answered by signing in.
        XCTAssertFalse(Welcome.shows(configured: true, signedIn: true, seen: false))
        // Answered by "not now" — the same answer as far as being asked again goes.
        XCTAssertFalse(Welcome.shows(configured: true, signedIn: false, seen: true))
        // A build with no server has nothing to sign in to, so it does not ask.
        XCTAssertFalse(Welcome.shows(configured: false, signedIn: false, seen: false))
        XCTAssertFalse(Welcome.shows(configured: false, signedIn: true, seen: true))
    }

    func testTheDoorOutIsPlainAndSaysWhatItCosts() {
        // PD-012 is local-first: two people score a match on one phone with no account. A welcome
        // that hid the way past it would be a lie about what the product is, so the skip is worded
        // as an action a person can want, not as a refusal.
        XCTAssertEqual(Welcome.skip, "Not now, just score")
        XCTAssertFalse(Welcome.skip.lowercased().contains("skip"), "not a dismissal, a choice")
    }

    func testThePromiseIsTheOneThisBuildCanKeep() {
        // This sentence is on the screen because it is TRUE of this build: nothing scored here is
        // uploaded, signed in or not. The day match upload ships, this assertion fails and the
        // sentence has to change with the behaviour — which is the point of testing copy at all.
        XCTAssertEqual(Welcome.promise,
                       "Matches scored on this phone stay on this phone, signed in or not.")
    }

    func testTheCopySellsWhatAnAccountActuallyDoes() {
        // Every claim maps to something shipped: a lineup (V029 team membership), a league
        // registration (V014), a friend by code (PD-035). No rating is promised, because OD-001
        // says there is none.
        for claim in ["lineup", "league", "friend"] {
            XCTAssertTrue(Welcome.body.lowercased().contains(claim), "the body drops \(claim)")
        }
        XCTAssertFalse(Welcome.body.lowercased().contains("rating"), "OD-001: THRØ has no rating")
        XCTAssertFalse(Welcome.headline.isEmpty)
        XCTAssertLessThan(Welcome.headline.count, 30, "a headline, not a paragraph")
    }
}
