import XCTest
@testable import ThroApp
@testable import ThroJournal

/// Home reads the journal, and must say so when it cannot.
///
/// Both failures these tests cover were being swallowed. `matches()` throwing produced an empty
/// list, so an unreadable journal showed the same screen as an empty one — "No matches yet" over a
/// database full of them. And a record whose replay threw was dropped from the list entirely, which
/// is worse: the journal refuses to replay a corrupt row **on purpose** (`ThroJournalTests` asserts
/// that), and the app answered by hiding the match. Evidence that exists must never be shown as
/// evidence that does not.
final class AppStoreTests: XCTestCase {

    private var path = ""

    override func setUp() {
        super.setUp()
        path = NSTemporaryDirectory() + "thro-appstore-\(UUID().uuidString).sqlite"
    }

    override func tearDown() {
        for suffix in ["", "-wal", "-shm"] { try? FileManager.default.removeItem(atPath: path + suffix) }
        super.tearDown()
    }

    private func journal() throws -> Journal {
        try Journal(path: path, deviceId: DeviceId("test-device"))
    }

    func testAMatchWhoseRowsWillNotReplayStaysOnTheListAndSaysWhy() throws {
        let j = try journal()
        let good = try j.createMatch(NewMatch(homeName: "Ann", awayName: "Ben"))
        let bad = try j.createMatch(NewMatch(homeName: "Cara", awayName: "Dai"))
        // 179 is not a total three darts can make: the engine refuses it, so replay throws.
        try j.exec("""
            INSERT INTO journal (match_id, device_id, device_seq, command_id, seat, visit_total, occurred_at)
            VALUES ('\(bad.id.value)', 'test-device', 1, 'corrupt', 'home', 179, '2026-09-05T00:00:00.000Z');
            """)

        let store = AppStore(journal: j)
        XCTAssertEqual(store.matches.count, 2, "the unreadable match must not vanish from Home")
        XCTAssertNil(store.listProblem, "the list itself was readable")

        let unreadable = try XCTUnwrap(store.matches.first { $0.id == bad.id })
        XCTAssertNotNil(unreadable.unreadable, "it must say it cannot be read")
        XCTAssertTrue(unreadable.unreadable!.contains("IMPOSSIBLE_VISIT_TOTAL"),
                      "and say why: \(unreadable.unreadable!)")
        XCTAssertEqual(unreadable.legsHome, 0)
        XCTAssertEqual(unreadable.legsAway, 0)
        XCTAssertFalse(unreadable.complete, "a match that cannot be replayed is not a finished one")

        let readable = try XCTUnwrap(store.matches.first { $0.id == good.id })
        XCTAssertNil(readable.unreadable, "one bad match does not tarnish the others")
    }

    func testAJournalThatCannotBeListedIsReportedRatherThanShownAsEmpty() throws {
        let j = try journal()
        _ = try j.createMatch(NewMatch(homeName: "Ann", awayName: "Ben"))
        let store = AppStore(journal: j)
        XCTAssertEqual(store.matches.count, 1)
        XCTAssertNil(store.listProblem)

        // Take the table away behind the store's back: listing must now fail, and be reported.
        try j.exec("DROP TABLE match;")
        store.refresh()
        XCTAssertNotNil(store.listProblem, "an unreadable list is not an empty one")
        XCTAssertTrue(store.matches.isEmpty, "and nothing is invented to fill it")
    }

    func testAnEmptyJournalIsEmptyAndNotAProblem() throws {
        let store = AppStore(journal: try journal())
        XCTAssertTrue(store.matches.isEmpty)
        XCTAssertNil(store.listProblem, "nothing to read is not a failure to read")
        XCTAssertNil(store.openProblem)
    }
}
