import XCTest
@testable import ThroApp

/// The opening waits for the account, and never traps anybody (the founder, 2026-09-11: *"shouldn't
/// load past the checking screen until checked in"*). And the slate Settings opens on.
final class OpeningHoldTests: XCTestCase {

    func testTheOpeningHandsOverOnlyOnceTheAccountHasAnswered() {
        XCTAssertEqual(OpeningHold.next(holding: false), .handOver)
        XCTAssertEqual(OpeningHold.next(holding: true), .hold)
    }

    func testATapSkipsTheThrowButNeverTheCheck() {
        XCTAssertEqual(OpeningHold.tap(holding: false), .finish)
        XCTAssertEqual(OpeningHold.tap(holding: true), .skipToRest,
                       "a tap brings the board to rest and waits with it")
    }

    func testTheWayPastTheCheckComesBeforeTheExplanation() {
        // A way out first — PD-012: nobody is kept from scoring by a server — then, if the wait goes
        // on, the reason it is slow.
        XCTAssertLessThan(OpeningHold.escapeAfter, OpeningHold.explainAfter)
        XCTAssertLessThanOrEqual(OpeningHold.escapeAfter, 5, "nobody waits long for the door")
        XCTAssertEqual(OpeningHold.escape, "Just score")
        XCTAssertTrue(OpeningHold.slow.contains("minute"), OpeningHold.slow)
    }

    func testTheAccountSlateSaysWhoIsSignedInInAFewWords() {
        XCTAssertEqual(AccountSlate.words(.signedIn(name: "Jenson R.", ageBand: "adult", friends: 1)).title, "Jenson R.")
        XCTAssertEqual(AccountSlate.words(.signedIn(name: nil, ageBand: "unknown", friends: nil)).title, "No name yet")
        XCTAssertTrue(AccountSlate.words(.signedIn(name: nil, ageBand: "unknown", friends: nil)).detail.hasPrefix("Age not said yet"))
        XCTAssertEqual(AccountSlate.words(.signedOut).title, "Sign in")
        XCTAssertEqual(AccountSlate.words(.unverified).title, "Signed in on this phone")
        XCTAssertEqual(AccountSlate.initials("Jenson Raper"), "JR")
        XCTAssertEqual(AccountSlate.initials(nil), "?")
    }
}
