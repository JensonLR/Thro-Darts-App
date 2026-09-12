import XCTest
@testable import ThroWatchKit
import ThroLiveKit

/// The link to the wrist, and what the wrist believes (PD-078).
///
/// None of this needs two devices, which is the point of keeping the payload and the holder apart from
/// `WCSession`: the failures worth catching are a dictionary the system refuses to carry, a message that
/// blanks a watch because it was not understood, and a score that goes on claiming to be now.
final class WristTests: XCTestCase {

    private func leg(remaining: Int = 81, winner: LiveSeat? = nil) -> ThroLiveState {
        ThroLiveState(homeName: "Jenson R.", awayName: "Ethan T.",
                      homeRemaining: remaining, awayRemaining: 230,
                      homeLegs: 2, awayLegs: 1,
                      thrower: .home, checkout: ["T19", "D12"], winner: winner)
    }

    // MARK: what crosses

    func testTheLegCrossesIntact() {
        let sent = leg()
        let read = ThroWristPayload.read(ThroWristPayload.context(sent, format: "501, best of 5"))
        XCTAssertEqual(read?.state, sent)
        XCTAssertEqual(read?.format, "501, best of 5")
    }

    func testEverythingSentIsSomethingTheSystemWillCarry() {
        // `updateApplicationContext` throws on a value that is not a property-list type, and it throws
        // on a device rather than here — so the shape is held here instead. This is why the state
        // travels as the JSON it already knows how to be.
        let context = ThroWristPayload.context(leg(), format: "501")
        XCTAssertTrue(PropertyListSerialization.propertyList(context, isValidFor: .binary),
                      "a context the system refuses is a wrist that silently never updates")
    }

    func testNothingOnIsAFactAndNotAnAbsenceOfOne() {
        let read = ThroWristPayload.read(ThroWristPayload.context(nil, format: "501"))
        XCTAssertNotNil(read, "the phone said something: that there is nothing on")
        XCTAssertNil(read?.state)
    }

    func testAContextThatIsNotOursIsIgnoredRatherThanReadAsIdle() {
        // The one that matters. A wrist that blanked itself on an unrecognised message would be
        // reporting a link failure as "no match on" — and the player would believe it.
        XCTAssertNil(ThroWristPayload.read(["something": "else"]))
        XCTAssertNil(ThroWristPayload.read([:]))
    }

    func testOursButUnreadableSaysNothingIsOnRatherThanGuessing() {
        // A phone on a newer shape than the watch. Half a leg drawn from a half-decoded state would be
        // the worst of the three outcomes.
        var context = ThroWristPayload.context(leg(), format: "501")
        context[ThroWristPayload.legKey] = Data("not a leg".utf8)
        let read = ThroWristPayload.read(context)
        XCTAssertNotNil(read)
        XCTAssertNil(read?.state)
    }

    // MARK: what the wrist does with it

    func testAnArrivingLegIsShownAndAClearedOneIsCleared() {
        let wrist = ThroWrist()
        let link = ThroWristLink(wrist: wrist)
        link.receive(ThroWristPayload.context(leg(), format: "501"))
        XCTAssertEqual(wrist.state?.homeRemaining, 81)
        XCTAssertEqual(wrist.format, "501")
        link.receive(ThroWristPayload.context(nil, format: "501"))
        XCTAssertNil(wrist.state)
        XCTAssertNil(wrist.heardAt, "and it stops claiming to have heard anything")
    }

    func testAnUnrecognisedContextLeavesTheLegWhereItIs() {
        let wrist = ThroWrist()
        let link = ThroWristLink(wrist: wrist)
        link.receive(ThroWristPayload.context(leg(), format: "501"))
        link.receive(["not": "ours"])
        XCTAssertEqual(wrist.state?.homeRemaining, 81)
    }

    // MARK: whether it still claims to be now

    func testASilentLinkGoesStale() {
        let wrist = ThroWrist()
        wrist.show(leg(), format: "501")
        let heard = try? XCTUnwrap(wrist.heardAt)
        XCTAssertFalse(wrist.isStale(now: heard ?? Date()))
        XCTAssertTrue(wrist.isStale(now: (heard ?? Date()).addingTimeInterval(ThroWrist.freshness + 1)))
    }

    func testADecidedLegNeverGoesStale() {
        // "Ann wins" does not go out of date. The Lock Screen and the widgets already say so; this is
        // the same rule on a third surface rather than a third opinion.
        let wrist = ThroWrist()
        wrist.show(leg(winner: .home), format: "501")
        let heard = wrist.heardAt ?? Date()
        XCTAssertFalse(wrist.isStale(now: heard.addingTimeInterval(ThroWrist.freshness * 100)))
    }

    func testAWristThatHasHeardNothingIsEmptyAndNotStale() {
        // Two different things to say, and only one of them is alarming. An empty wrist shows the
        // waiting screen; a stale one shows a score with a warning on it.
        let wrist = ThroWrist()
        XCTAssertFalse(wrist.isStale(now: Date().addingTimeInterval(10_000)))
        XCTAssertNil(wrist.state)
    }

    func testTheWristAndTheWallAgreeOnHowLongIsTooLong() {
        // One number, in one place. Two surfaces disagreeing about when a score stopped being true
        // would mean the wall and the wrist contradicting each other in the same room.
        XCTAssertEqual(ThroWrist.freshness, ThroVenue.freshness)
    }

    func testTheDemoLegOnlyAppearsWhenItIsAskedFor() {
        // A wrist that seeded itself would be showing a fictional score to somebody who would believe
        // it. It is DEBUG-only as well, so this holds the argument and the build guard holds the rest.
        let wrist = ThroWrist()
        wrist.seedFromLaunchArguments(["ThroWatch"])
        XCTAssertNil(wrist.state)
        wrist.seedFromLaunchArguments(["ThroWatch", "-ThroWristDemo"])
        XCTAssertNotNil(wrist.state)
    }

    // MARK: the words when there is nothing

    func testTheWaitingScreenSaysWhereAMatchComesFrom() {
        // An empty screen that only says "nothing" leaves a player wondering whether the watch is
        // broken. It says which device to start on.
        XCTAssertTrue(ThroWatchWords.nothingOnHint.lowercased().contains("phone"))
        XCTAssertFalse(ThroWatchWords.nothingOn.isEmpty)
    }
}
