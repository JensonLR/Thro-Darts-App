import Foundation
import XCTest
import ThroEngine
import ThroPlay
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

    // MARK: - checking an export file (PD-017)

    /// The picker's own two failures are not the file's fault and must not be reported as if they
    /// were. Driven through the importer's `Result` rather than a file picker, so both are testable.
    // MARK: the shelf and the delete (PD-026)

    /// Archiving moves a match between two lists Home already holds, and takes it out of neither
    /// the journal nor anybody's figures.
    func testAnArchivedMatchIsOffHomeAndOnTheShelf() throws {
        let j = try journal()
        let kept = try j.createMatch(NewMatch(homeName: "Ann", awayName: "Ben"))
        let shelved = try j.createMatch(NewMatch(homeName: "Cara", awayName: "Dai"))
        let store = AppStore(journal: j)
        XCTAssertEqual(store.matches.count, 2)
        XCTAssertTrue(store.archived.isEmpty)

        store.setArchived(shelved.id, true)
        XCTAssertEqual(store.matches.map(\.id), [kept.id])
        XCTAssertEqual(store.archived.map(\.id), [shelved.id])
        XCTAssertNil(store.actionProblem)

        store.setArchived(shelved.id, false)
        XCTAssertEqual(store.matches.count, 2)
        XCTAssertTrue(store.archived.isEmpty)
    }

    /// A match a league has taken a result from may not be deleted, and the refusal says why and
    /// names the thing that can be done instead.
    ///
    /// This is the one rule in PD-026 that is about somebody other than the person holding the
    /// phone: a `scored` result cites the match by id, and that citation is the whole of its
    /// provenance. Deleting the match would leave a table resting on evidence nobody can produce.
    func testDeleteIsRefusedWhileAFixtureRestsOnTheMatch() throws {
        let j = try journal()
        let m = try j.createMatch(NewMatch(homeName: "Ann", awayName: "Ben"))
        try j.append(.visit(Seat.home.playerId, 60), to: m.id)
        let store = AppStore(journal: j)
        store.fixturesCiting = { $0 == m.id ? ["fixture-1"] : [] }

        XCTAssertNotNil(store.deletionRefusal(m.id))
        XCTAssertNil(store.delete(m.id), "it did not happen")
        XCTAssertEqual(store.actionProblem, store.deletionRefusal(m.id))
        XCTAssertEqual(store.matches.count, 1, "and the match is still there")
        XCTAssertEqual(try j.entries(for: m.id).count, 1)

        // Archiving is what the refusal offers, and it works.
        store.setArchived(m.id, true)
        XCTAssertEqual(store.archived.map(\.id), [m.id])
    }

    /// A delete nobody is relying on goes through, takes its visits, and says how many.
    func testDeleteTakesTheMatchAndSaysWhatWentWithIt() throws {
        let j = try journal()
        let doomed = try j.createMatch(NewMatch(homeName: "Ann", awayName: "Ben"))
        let kept = try j.createMatch(NewMatch(homeName: "Cara", awayName: "Dai"))
        try j.append(.visit(Seat.home.playerId, 180), to: doomed.id)
        try j.append(.visit(Seat.away.playerId, 60), to: doomed.id)
        let store = AppStore(journal: j)

        XCTAssertEqual(store.delete(doomed.id), 2)
        XCTAssertNil(store.actionProblem)
        XCTAssertEqual(store.matches.map(\.id), [kept.id])
        XCTAssertThrowsError(try j.match(doomed.id))
    }

    /// The warning names the match, the date and what a delete cannot reach. Not "this cannot be
    /// undone", which every app says and nobody reads.
    func testTheDeleteWarningSaysWhatIsActuallyLost() throws {
        let j = try journal()
        let m = try j.createMatch(NewMatch(homeName: "Ann", awayName: "Ben"))
        let store = AppStore(journal: j)
        let match = try XCTUnwrap(store.matches.first)
        let warning = HomeScreen.deleteWarning(match)
        XCTAssertTrue(warning.contains("Ann v Ben"), warning)
        XCTAssertTrue(warning.contains("export"), "it must say an export already written still has it")
        XCTAssertTrue(warning.contains("Archiving"), "and offer the thing that keeps it")
        _ = m
    }

    /// Home offers to continue the newest match that is still open, and offers nothing when every
    /// match is done. A match that ended short is done (PD-016), so the card must not offer it.
    func testHomeOffersTheMatchThatIsStillGoing() throws {
        let j = try journal()
        let finished = try j.createMatch(NewMatch(homeName: "Ann", awayName: "Ben", legsTarget: 1),
                                         startedAt: Date(timeIntervalSince1970: 1_000))
        try j.append(.visit(Seat.home.playerId, 441), to: finished.id)
        try j.append(.visit(Seat.home.playerId, 60, dartsUsed: 3, dartsAtDouble: 1), to: finished.id)
        let open = try j.createMatch(NewMatch(homeName: "Cara", awayName: "Dai"),
                                     startedAt: Date(timeIntervalSince1970: 2_000))
        try j.append(.visit(Seat.home.playerId, 60), to: open.id)

        let store = AppStore(journal: j)
        XCTAssertEqual(store.matches.filter { !$0.complete && $0.unreadable == nil }.map(\.id), [open.id])
    }

    /// The last seven days, and only those. A match older than the window is in the record and out
    /// of the strip, and the strip says which of "nothing yet" and "nothing lately" it is.
    func testTheWeekCountsTheLastSevenDaysAndSaysWhenItIsQuiet() throws {
        let j = try journal()
        let now = Date(timeIntervalSince1970: 1_000_000)
        let old = try j.createMatch(NewMatch(homeName: "Ann", awayName: "Ben"),
                                    startedAt: now.addingTimeInterval(-30 * 86_400))
        try j.append(.visit(Seat.home.playerId, 180), to: old.id)

        var week = try DeviceSummary.week(in: j, now: now)
        XCTAssertEqual(week.matches, 0)
        XCTAssertTrue(week.quietWeek, "a phone with history and a quiet week is not an empty phone")

        let recent = try j.createMatch(NewMatch(homeName: "Cara", awayName: "Dai"),
                                       startedAt: now.addingTimeInterval(-2 * 86_400))
        try j.append(.visit(Seat.home.playerId, 140), to: recent.id)
        week = try DeviceSummary.week(in: j, now: now)
        XCTAssertEqual(week.matches, 1)
        XCTAssertFalse(week.quietWeek)
        XCTAssertEqual(week.figures.count, 3)
        XCTAssertEqual(week.unreadable, 0)
    }

    /// The best leg on Home counts one player's visits, not both of theirs added together.
    ///
    /// **This is a defect that was written and caught before it shipped.** Pooling a whole device's
    /// visits under one leg ordinal per match would have handed `bestLegInVisits` a leg containing
    /// both players' darts, and the first screen of the app would have reported every 15-visit leg
    /// as a 30-visit one. Each seat of each match gets its own block of ordinals instead.
    func testTheWeeksBestLegIsOnePlayersLegNotTwo() throws {
        let j = try journal()
        let now = Date(timeIntervalSince1970: 1_000_000)
        let m = try j.createMatch(NewMatch(homeName: "Ann", awayName: "Ben", legsTarget: 1),
                                  startedAt: now.addingTimeInterval(-86_400))
        // Ann takes the leg in three visits; Ben throws two in the same leg.
        try j.append(.visit(Seat.home.playerId, 180), to: m.id)
        try j.append(.visit(Seat.away.playerId, 100), to: m.id)
        try j.append(.visit(Seat.home.playerId, 180), to: m.id)
        try j.append(.visit(Seat.away.playerId, 100), to: m.id)
        try j.append(.visit(Seat.home.playerId, 141, dartsUsed: 3, dartsAtDouble: 1), to: m.id)

        let week = try DeviceSummary.week(in: j, now: now)
        let best = try XCTUnwrap(week.figures.first { $0.label == "Best leg" })
        XCTAssertEqual(best.value, "3", "Ann's three visits, not Ann's three plus Ben's two")
    }

    /// A match this week whose rows will not replay is **counted and named**, not skipped.
    ///
    /// Home's strip would otherwise show an average over the readable half of the week and call it
    /// the week — which is a different number, not a smaller sample. This is the same rule
    /// `PersonHistory.unreadable` holds for a person, applied to the first screen of the app.
    func testTheWeekCountsAMatchItCouldNotReadRatherThanSkippingIt() throws {
        let j = try journal()
        let now = Date(timeIntervalSince1970: 1_000_000)
        let good = try j.createMatch(NewMatch(homeName: "Ann", awayName: "Ben"),
                                     startedAt: now.addingTimeInterval(-86_400))
        try j.append(.visit(Seat.home.playerId, 180), to: good.id)
        let bad = try j.createMatch(NewMatch(homeName: "Cara", awayName: "Dai"),
                                    startedAt: now.addingTimeInterval(-86_400))
        // 179 is not a total three darts can make: the engine refuses it, so replay throws.
        try j.exec("""
            INSERT INTO journal (match_id, device_id, device_seq, command_id, seat, visit_total, occurred_at)
            VALUES ('\(bad.id.value)', 'test-device', 1, 'corrupt-week', 'home', 179, '2026-09-05T00:00:00.000Z');
            """)

        let week = try DeviceSummary.week(in: j, now: now)
        XCTAssertEqual(week.matches, 2, "both were started this week")
        XCTAssertEqual(week.unreadable, 1, "and one of them is not in any figure above")
    }

    func testAFileThatCannotBeOpenedIsNotReportedAsABadExport() throws {
        struct Denied: LocalizedError { var errorDescription: String? { "permission denied" } }

        guard case let .refused(why) = SettingsScreen.inspect(.failure(Denied())) else {
            return XCTFail("a picker failure is still an answer")
        }
        XCTAssertTrue(why.contains("could not be opened"), why)
        XCTAssertTrue(why.contains("permission denied"), "and it carries the reason: \(why)")
        XCTAssertFalse(why.contains("changed since"), "which is NOT the same as a forged file")

        // A path that is not there is the same class of problem, and reads the same way.
        let missing = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("no-such-\(UUID()).json")
        guard case let .refused(gone) = SettingsScreen.inspect(.success(missing)) else {
            return XCTFail("a missing file is refused")
        }
        XCTAssertTrue(gone.contains("could not be opened"), gone)
    }

    /// And a real file on disk, chosen and read, describes itself.
    func testAFileOnDiskIsReadAndDescribed() throws {
        let j = try Journal(path: path, deviceId: DeviceId("home-tests"))
        let m = try j.createMatch(NewMatch(homeName: "A", awayName: "B"))
        try j.append(.visit(Seat.home.playerId, 60), to: m.id)

        let url = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("thro-\(UUID()).json")
        try Export.data(try Export.make(j)).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        guard case let .readable(file) = SettingsScreen.inspect(.success(url), thisDevice: DeviceId("home-tests"))
        else { return XCTFail("a file this device wrote must read back") }
        XCTAssertEqual(file.matches, 1)
        XCTAssertEqual(file.visits, 1)
        XCTAssertTrue(file.fromThisDevice)
    }
}
