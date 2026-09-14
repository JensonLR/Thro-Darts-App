import XCTest
import ThroEngine
import ThroJournal
@testable import ThroLiveKit
@testable import ThroPlay
@testable import ThroWatchKit

/// The join between a real match and the surfaces outside the app (PD-078).
///
/// `LiveBoard` is the one place a leg leaves `ThroPlay`, and it reaches three singletons — the wall, the
/// Lock Screen and now the wrist. Every piece under it is tested on its own: the payload round-trips, the
/// wrist shows what it is handed, the transport was watched carrying a real message between two processes.
/// **This is the concatenation**, which is the part a script cannot reach by tapping and the part a person
/// would notice: a phone that scores a leg and a watch that never hears about it.
final class LiveBoardBridgeTests: XCTestCase {

    private var path: String!
    private var journal: Journal!

    override func setUpWithError() throws {
        try super.setUpWithError()
        path = NSTemporaryDirectory() + "thro-bridge-\(UUID().uuidString).sqlite"
        journal = try Journal(path: path, deviceId: DeviceId("bridge-tests"))
    }

    override func tearDown() {
        journal = nil
        for suffix in ["", "-wal", "-shm"] { try? FileManager.default.removeItem(atPath: path + suffix) }
        super.tearDown()
    }

    private func session() throws -> MatchSession {
        try MatchSession.start(NewMatch(homeName: "Jenson", awayName: "Alex", legsTarget: 3), in: journal)
    }

    private func onTheWrist() throws -> (state: ThroLiveState?, format: String) {
        try XCTUnwrap(ThroWristPayload.read(try XCTUnwrap(ThroWristLink.shared.pending)))
    }

    func testStartingAMatchPutsThatLegOnTheWrist() throws {
        let match = try session()
        LiveBoard().start(match)
        let sent = try onTheWrist()
        XCTAssertEqual(sent.state, match.liveState)
        XCTAssertEqual(sent.format, match.liveFormat, "the format the wall was given, not a second one")
    }

    func testAVisitReachesTheWrist() throws {
        let match = try session()
        let board = LiveBoard()
        board.start(match)
        match.quick(180)
        board.update(match.liveState)
        XCTAssertEqual(try onTheWrist().state?.homeRemaining, 321)
    }

    func testTheWallIsClearedAtTheEndAndTheWristIsSentTheFinishedLeg() throws {
        // The one asymmetry, held here so it cannot be tidied away into consistency. A room reading a
        // decided scoreline as though it were live is the failure the wall exists to avoid; a watch is on
        // the arm of somebody who was there, and "Alex wins" is what they want for the walk back.
        let match = try session()
        let board = LiveBoard()
        board.start(match)
        board.finish(match)
        XCTAssertNil(ThroVenue.shared.state, "the wall goes dark")
        XCTAssertNotNil(try onTheWrist().state, "the wrist keeps the result")
    }

    func testALaunchTellsTheWristNothingIsOn() throws {
        // A phone killed mid-leg leaves its last context on the watch until something replaces it. This
        // is the something, and it runs before anything else at launch.
        LiveBoard().start(try session())
        XCTAssertNotNil(try onTheWrist().state)
        LiveBoard.clearStale()
        XCTAssertNil(try onTheWrist().state)
    }
}
