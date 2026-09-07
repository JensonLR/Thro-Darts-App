import Foundation
import XCTest
import ThroEngine
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

        // Take the table out of reach behind the store's back: listing must now fail, and be
        // reported. Renaming rather than dropping leaves the journal's foreign key intact, so this
        // tests the read path and not SQLite's own reaction to a missing parent table.
        try j.exec("ALTER TABLE local_match RENAME TO local_match_moved;")
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

    /// The journal refusing a second identity is only half the guarantee. If the caller's own copy
    /// is left holding the identity the journal just rejected, the next thing to ask for one — a
    /// sync client naming this device to a server — names the device the journal's rows do not, and
    /// one device arrives as two after all. So the journal's answer is written back.
    func testTheJournalsIdentityCorrectsTheCallersRatherThanJustDisagreeingWithIt() throws {
        let suite = "thro.tests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { UserDefaults.standard.removePersistentDomain(forName: suite) }

        // A first open settles the journal on the identity it was created with.
        let first = try Journal(path: path, deviceId: DeviceId("the-original"))
        defaults.set("the-original", forKey: AppStore.deviceIdKey)
        XCTAssertFalse(AppStore.reconcileDeviceId(first, in: defaults),
                       "nothing to correct while the two agree")
        XCTAssertEqual(defaults.string(forKey: AppStore.deviceIdKey), "the-original")

        // UserDefaults is then lost, so the caller asks with a fresh identity. The journal keeps its
        // own — and the caller's copy is corrected to match it.
        defaults.removeObject(forKey: AppStore.deviceIdKey)
        let asked = AppStore.deviceId(in: defaults)
        XCTAssertNotEqual(asked, "the-original", "a lost identity is regenerated, not remembered")

        let second = try Journal(path: path, deviceId: DeviceId(asked))
        XCTAssertEqual(second.deviceId, DeviceId("the-original"), "the journal keeps its own")
        XCTAssertEqual(second.deviceIdSupersededCallers, DeviceId(asked), "and says what it refused")

        XCTAssertTrue(AppStore.reconcileDeviceId(second, in: defaults), "the caller is corrected")
        XCTAssertEqual(defaults.string(forKey: AppStore.deviceIdKey), "the-original",
                       "and asking again now gives the journal's identity, not a third one")
        XCTAssertEqual(AppStore.deviceId(in: defaults), "the-original")
    }

    // MARK: - ending a match short (PD-016)

    /// Home has three states, not two. An abandoned match is finished AND is not a result, so a row
    /// that showed it as "In progress" would offer to resume a match nothing can be added to, and a
    /// row that showed a verification badge would attest to a result nobody claimed.
    func testHomeTellsTheThreeEndingsApart() throws {
        let j = try Journal(path: path, deviceId: DeviceId("home-tests"))
        let live = try j.createMatch(NewMatch(homeName: "A", awayName: "B"))
        try j.append(.visit(Seat.home.playerId, 60), to: live.id)

        let retired = try j.createMatch(NewMatch(homeName: "C", awayName: "D"))
        try j.append(.visit(Seat.home.playerId, 60), to: retired.id)
        try j.end(retired.id, as: .retired(by: .home))

        let abandoned = try j.createMatch(NewMatch(homeName: "E", awayName: "F"))
        try j.append(.visit(Seat.home.playerId, 60), to: abandoned.id)
        try j.end(abandoned.id, as: .abandoned)

        let store = AppStore(journal: j)
        func row(_ id: MatchId) -> AppStore.HomeMatch { store.matches.first { $0.id == id }! }

        XCTAssertEqual(row(live.id).status, "In progress")
        XCTAssertFalse(row(live.id).complete)

        XCTAssertEqual(row(retired.id).status, "Retired")
        XCTAssertTrue(row(retired.id).complete, "the keypad is closed, so the row must not offer to resume")

        XCTAssertEqual(row(abandoned.id).status, "No result")
        XCTAssertTrue(row(abandoned.id).complete)
        XCTAssertEqual(row(abandoned.id).ending, .abandoned)
    }
}
