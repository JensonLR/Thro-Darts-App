import XCTest
import SQLite3
import ThroEngine
@testable import ThroJournal

final class JournalTests: XCTestCase {

    private var path: String!
    private let device = DeviceId("test-device")

    override func setUp() {
        super.setUp()
        path = NSTemporaryDirectory() + "thro-journal-\(UUID().uuidString).sqlite"
    }

    override func tearDown() {
        for suffix in ["", "-wal", "-shm", "-journal"] {
            try? FileManager.default.removeItem(atPath: path + suffix)
        }
        super.tearDown()
    }

    private func open() throws -> Journal { try Journal(path: path, deviceId: device) }

    // MARK: configuration

    /// The pragmas are read back, not assumed. This is the lesson the durability probe paid for.
    func testTheMeasuredConfigurationIsInForceAfterOpen() throws {
        let j = try open()
        let inForce = j.configurationInForce
        XCTAssertEqual(inForce["journal_mode"], "wal")
        XCTAssertEqual(inForce["synchronous"], "2", "FULL reads back as 2")
        XCTAssertEqual(inForce["fullfsync"], "1")
        XCTAssertEqual(inForce["checkpoint_fullfsync"], "1")
    }

    /// An in-memory database cannot enter WAL; it reports `memory`. Opening must throw rather than
    /// carry on under a configuration that is not the one measured.
    func testARefusedConfigurationIsAnErrorNotASilentSuccess() {
        XCTAssertThrowsError(try Journal(path: ":memory:", deviceId: device)) { error in
            guard case let JournalError.configurationNotInForce(pragma, wanted, got) = error as! JournalError else {
                return XCTFail("wrong error: \(error)")
            }
            XCTAssertEqual(pragma, "journal_mode")
            XCTAssertEqual(wanted, "wal")
            XCTAssertEqual(got, "memory")
        }
    }

    // MARK: sequence and durability

    func testDeviceSequenceIsGaplessAndStartsAtOne() throws {
        let j = try open()
        let m = try j.createMatch(NewMatch(homeName: "A", awayName: "B"))
        var seqs: [Int64] = []
        for total in [60, 45, 100, 26, 180] {
            let seat: Seat = seqs.count % 2 == 0 ? .home : .away
            seqs.append(try j.append(.visit(seat.playerId, total), to: m.id).deviceSeq)
        }
        XCTAssertEqual(seqs, [1, 2, 3, 4, 5])
    }

    func testAnAppendSurvivesCloseAndReopen() throws {
        let matchId: MatchId
        let written: [JournalEntry]
        do {
            let j = try open()
            let m = try j.createMatch(NewMatch(homeName: "Home", awayName: "Away"))
            matchId = m.id
            written = try [
                j.append(.visit(Seat.home.playerId, 140), to: m.id),
                j.append(.visit(Seat.away.playerId, 100), to: m.id),
            ]
            // j is released here; deinit closes the connection.
        }
        let reopened = try open()
        let read = try reopened.entries(for: matchId)
        XCTAssertEqual(read.count, 2)
        XCTAssertEqual(read.map(\.deviceSeq), written.map(\.deviceSeq))
        XCTAssertEqual(read.map(\.visitTotal), [140, 100])
        XCTAssertEqual(read.map(\.commandId), written.map(\.commandId))
        XCTAssertEqual(try reopened.match(matchId).homeName, "Home")
    }

    /// The database, not the caller, refuses to rewrite history.
    func testTheJournalIsAppendOnly() throws {
        let j = try open()
        let m = try j.createMatch(NewMatch(homeName: "A", awayName: "B"))
        try j.append(.visit(Seat.home.playerId, 60), to: m.id)

        XCTAssertThrowsError(try j.exec("UPDATE journal SET visit_total = 180;")) { error in
            XCTAssertTrue("\(error)".contains("append-only"), "got: \(error)")
        }
        XCTAssertThrowsError(try j.exec("DELETE FROM journal;")) { error in
            XCTAssertTrue("\(error)".contains("append-only"), "got: \(error)")
        }
        XCTAssertEqual(try j.entries(for: m.id).map(\.visitTotal), [60])
    }

    // MARK: the shelf, and taking a match off the phone (PD-026)

    /// Archiving is a fact about a list, not about the darts. Every reader that is not Home still
    /// sees the match, which is the whole reason it is offered as the answer to "get this off my
    /// screen".
    func testArchivingTakesAMatchOffHomeAndNowhereElse() throws {
        let j = try open()
        let kept = try j.createMatch(NewMatch(homeName: "A", awayName: "B"),
                                     startedAt: Date(timeIntervalSince1970: 2_000))
        let shelved = try j.createMatch(NewMatch(homeName: "C", awayName: "D"),
                                        startedAt: Date(timeIntervalSince1970: 1_000))
        try j.append(.visit(Seat.home.playerId, 60), to: shelved.id)

        try j.setArchived(shelved.id, true)
        XCTAssertEqual(try j.matches(archived: false).map(\.id), [kept.id])
        XCTAssertEqual(try j.matches(archived: true).map(\.id), [shelved.id])
        XCTAssertEqual(try j.matches().map(\.id), [kept.id, shelved.id], "everything, for the export")
        XCTAssertNotNil(try j.match(shelved.id).archivedAt)
        XCTAssertTrue(try j.match(shelved.id).isArchived)
        XCTAssertEqual(try j.entries(for: shelved.id).map(\.visitTotal), [60], "the visit is untouched")

        try j.setArchived(shelved.id, false)
        XCTAssertNil(try j.match(shelved.id).archivedAt)
        XCTAssertEqual(try j.matches(archived: false).map(\.id), [kept.id, shelved.id])
        XCTAssertThrowsError(try j.setArchived(MatchId("nope"), true))
    }

    /// The archive stamp survives a close and reopen, like every other column. It is stored, not a
    /// flag some view model is holding.
    func testTheShelfSurvivesReopening() throws {
        let m: MatchRecord
        do {
            let j = try open()
            m = try j.createMatch(NewMatch(homeName: "A", awayName: "B"))
            try j.setArchived(m.id, true)
        }
        let reopened = try open()
        XCTAssertTrue(try reopened.match(m.id).isArchived)
        XCTAssertTrue(try reopened.matches(archived: false).isEmpty)
    }

    /// A delete takes the match and every visit in it, and leaves everything else exactly as it was.
    func testDeletingAMatchTakesItsVisitsAndNothingElse() throws {
        let j = try open()
        let doomed = try j.createMatch(NewMatch(homeName: "A", awayName: "B"))
        let kept = try j.createMatch(NewMatch(homeName: "C", awayName: "D"))
        try j.append(.visit(Seat.home.playerId, 180), to: doomed.id)
        try j.append(.visit(Seat.away.playerId, 60), to: doomed.id)
        try j.append(.visit(Seat.home.playerId, 100), to: kept.id)

        XCTAssertEqual(try j.deleteMatch(doomed.id), 2, "it says how many darts went with it")
        XCTAssertEqual(try j.matches().map(\.id), [kept.id])
        XCTAssertThrowsError(try j.match(doomed.id))
        XCTAssertTrue(try j.entries(for: doomed.id).isEmpty)
        XCTAssertEqual(try j.entries(for: kept.id).map(\.visitTotal), [100])
        XCTAssertThrowsError(try j.deleteMatch(doomed.id), "and it is gone, so a second one fails")
    }

    /// The delete a person asks for is the ONLY delete. Everything else still aborts — including a
    /// bare `DELETE FROM journal`, which is what the trigger was written to stop and what a
    /// carelessly relaxed trigger would have let through.
    func testEveryDeleteThatIsNotAPurgeIsStillRefused() throws {
        let j = try open()
        let m = try j.createMatch(NewMatch(homeName: "A", awayName: "B"))
        try j.append(.visit(Seat.home.playerId, 60), to: m.id)

        XCTAssertThrowsError(try j.exec("DELETE FROM journal;")) { error in
            XCTAssertTrue("\(error)".contains("append-only"), "got: \(error)")
        }
        XCTAssertThrowsError(try j.exec("DELETE FROM journal WHERE match_id = '\(m.id.value)';")) { error in
            XCTAssertTrue("\(error)".contains("append-only"), "got: \(error)")
        }
        XCTAssertThrowsError(try j.exec("UPDATE journal SET visit_total = 180;")) { error in
            XCTAssertTrue("\(error)".contains("append-only"), "got: \(error)")
        }
        XCTAssertEqual(try j.entries(for: m.id).map(\.visitTotal), [60])
    }

    /// A purge opens the door for exactly one match. While one is named, another match's rows are
    /// as protected as they were before — which is the difference between narrowing the rule and
    /// removing it.
    func testAPurgeUnlocksOnlyTheMatchItNames() throws {
        let j = try open()
        let named = try j.createMatch(NewMatch(homeName: "A", awayName: "B"))
        let other = try j.createMatch(NewMatch(homeName: "C", awayName: "D"))
        try j.append(.visit(Seat.home.playerId, 60), to: named.id)
        try j.append(.visit(Seat.home.playerId, 41), to: other.id)

        try j.exec("INSERT OR REPLACE INTO meta (key, value) VALUES ('purging', '\(named.id.value)');")
        XCTAssertThrowsError(try j.exec("DELETE FROM journal WHERE match_id = '\(other.id.value)';")) { error in
            XCTAssertTrue("\(error)".contains("append-only"), "got: \(error)")
        }
        XCTAssertEqual(try j.entries(for: other.id).map(\.visitTotal), [41])
        try j.exec("DELETE FROM meta WHERE key = 'purging';")
        XCTAssertThrowsError(try j.exec("DELETE FROM journal WHERE match_id = '\(named.id.value)';"),
                             "and with no purge running, not even that one")
    }

    /// A journal written before the shelf existed opens with the column and the narrowed trigger,
    /// and every match in it reads back as what it was: on Home.
    func testAJournalFromBeforeTheShelfIsUpgradedOnOpen() throws {
        var handle: OpaquePointer?
        XCTAssertEqual(sqlite3_open(path, &handle), SQLITE_OK)
        let h = handle!
        // The schema as it stood, including the unconditional delete trigger.
        try Journal.exec(h, """
            CREATE TABLE local_match (
              match_id TEXT PRIMARY KEY, home_name TEXT NOT NULL, away_name TEXT NOT NULL,
              starting_score INTEGER NOT NULL, out_rule TEXT NOT NULL, legs_mode TEXT NOT NULL,
              legs_target INTEGER NOT NULL, throw_first TEXT NOT NULL, started_at TEXT NOT NULL,
              device_id TEXT NOT NULL);
            """)
        try Journal.exec(h, """
            CREATE TABLE journal (
              match_id TEXT NOT NULL REFERENCES local_match(match_id), device_id TEXT NOT NULL,
              device_seq INTEGER NOT NULL, command_id TEXT NOT NULL UNIQUE,
              kind TEXT NOT NULL DEFAULT 'visit', seat TEXT NOT NULL, visit_total INTEGER NOT NULL,
              darts_used INTEGER, darts_at_double INTEGER, occurred_at TEXT NOT NULL,
              PRIMARY KEY (match_id, device_id, device_seq));
            """)
        try Journal.exec(h, """
            CREATE TRIGGER journal_append_only_delete BEFORE DELETE ON journal
            BEGIN SELECT RAISE(ABORT, 'journal is append-only'); END;
            """)
        try Journal.exec(h, """
            INSERT INTO local_match (match_id, home_name, away_name, starting_score, out_rule,
                                     legs_mode, legs_target, throw_first, started_at, device_id)
            VALUES ('old', 'A', 'B', 501, 'double', 'bestOf', 3, 'home', '2024-01-01T00:00:00Z', 'd');
            """)
        sqlite3_close(h)

        let j = try open()
        XCTAssertFalse(try j.match(MatchId("old")).isArchived, "a match nobody archived is on Home")
        XCTAssertEqual(try j.matches(archived: false).count, 1)
        // The old trigger was replaced rather than left beside the new one, so a purge works.
        try j.append(.visit(Seat.home.playerId, 60), to: MatchId("old"))
        XCTAssertEqual(try j.deleteMatch(MatchId("old")), 1)
    }

    // MARK: replay

    /// A whole leg, played through the engine and journaled, is rebuilt exactly by replay — including
    /// whose turn it is and which leg the match is on, which per-visit outcomes alone would miss.
    func testReplayReproducesTheEngineState() throws {
        let j = try open()
        let m = try j.createMatch(NewMatch(homeName: "A", awayName: "B", legsMode: .bestOf, legsTarget: 3))
        var live = m.initialState

        // A: 180, 180, 141 (3 darts, 1 at a double) — a fifteen-dart leg; B: 100 in between.
        let script: [(Seat, Int, Int?, Int?)] = [
            (.home, 180, 3, nil), (.away, 100, 3, nil),
            (.home, 180, 3, nil), (.away, 100, 3, nil),
            (.home, 141, 3, 1),
        ]
        for (seat, total, darts, atDouble) in script {
            let cmd = Command.visit(seat.playerId, total, dartsUsed: darts, dartsAtDouble: atDouble)
            guard case let .accepted(next, _, _) = Engine.apply(live, cmd) else { return XCTFail("script rejected") }
            try j.append(cmd, to: m.id)   // flush before acknowledging …
            live = next                   // … then apply
        }

        let replayed = try j.replay(m.id)
        XCTAssertEqual(replayed.legsWonTotal[Seat.home.playerId], 1)
        XCTAssertEqual(replayed.legsWonTotal[Seat.away.playerId], 0)
        XCTAssertEqual(replayed.currentLeg, 2)
        XCTAssertEqual(replayed.thrower, live.thrower, "replay lost whose turn it is")
        XCTAssertEqual(replayed.remaining, live.remaining)
        XCTAssertEqual(replayed.legStarter, live.legStarter)
    }

    /// Visit ordinals are per (seat, leg). Shared ordinals would put the opponent's visits into a
    /// player's first nine.
    func testReplayedVisitsCarryPerSeatOrdinalsAndOutcomes() throws {
        let j = try open()
        let m = try j.createMatch(NewMatch(homeName: "A", awayName: "B", legsMode: .bestOf, legsTarget: 3))
        var live = m.initialState
        // Home: 180, 180, 101, then 40 with a single dart at D20. Away throws 60s in between.
        let script: [(Seat, Int, Int?, Int?)] = [
            (.home, 180, 3, nil), (.away, 60, 3, nil),
            (.home, 180, 3, nil), (.away, 60, 3, nil),
            (.home, 101, 3, nil), (.away, 60, 3, nil),
            (.home, 40, 1, 1),
        ]
        for (seat, total, darts, atDouble) in script {
            let cmd = Command.visit(seat.playerId, total, dartsUsed: darts, dartsAtDouble: atDouble)
            guard case let .accepted(next, _, _) = Engine.apply(live, cmd) else { return XCTFail("script rejected at \(total)") }
            try j.append(cmd, to: m.id)
            live = next
        }

        let (_, visits) = try j.replayVisits(m.id)
        let home = visits.filter { $0.seat == .home }
        let away = visits.filter { $0.seat == .away }
        XCTAssertEqual(home.map(\.visitOrdinal), [1, 2, 3, 4], "home ordinals must count only home visits")
        XCTAssertEqual(away.map(\.visitOrdinal), [1, 2, 3])
        XCTAssertEqual(home.map(\.remainingBefore), [501, 321, 141, 40])
        XCTAssertEqual(away.map(\.remainingAfter), [441, 381, 321])
        XCTAssertEqual(home.last?.remainingAfter, 0)
        XCTAssertEqual(home.last?.wonLeg, true)
        XCTAssertEqual(home.last?.dartsUsed, 1)
        XCTAssertEqual(home.last?.dartsAtDouble, 1)
        XCTAssertNil(home.first?.dartsAtDouble, "unknown stays unknown; it is never zero")
        XCTAssertTrue(visits.allSatisfy { $0.legOrdinal == 1 })
        XCTAssertFalse(visits.contains { $0.bust })
    }

    func testABustIsReplayedAsABustWithRemainingRestored() throws {
        let j = try open()
        let m = try j.createMatch(NewMatch(homeName: "A", awayName: "B"))
        var live = m.initialState
        for (seat, total) in [(Seat.home, 180), (.away, 60), (.home, 180), (.away, 60), (.home, 180)] as [(Seat, Int)] {
            // home: 501 → 321 → 141 → 180 would bust (141 - 180 < 0)
            let cmd = Command.visit(seat.playerId, total)
            guard case let .accepted(next, _, _) = Engine.apply(live, cmd) else { return XCTFail("rejected \(total)") }
            try j.append(cmd, to: m.id)
            live = next
        }
        let (_, visits) = try j.replayVisits(m.id)
        let last = visits.last!
        XCTAssertTrue(last.bust)
        XCTAssertEqual(last.remainingBefore, 141)
        XCTAssertEqual(last.remainingAfter, 141, "a bust restores the remaining")
        XCTAssertFalse(last.wonLeg)
    }

    /// A row the engine would refuse cannot be replayed into a match. Inserted behind the engine's
    /// back to simulate corruption; replay must throw, not skip.
    func testAReplayThatHitsARejectionThrowsRatherThanSkipping() throws {
        let j = try open()
        let m = try j.createMatch(NewMatch(homeName: "A", awayName: "B"))
        try j.exec("""
            INSERT INTO journal (match_id, device_id, device_seq, command_id, seat, visit_total, occurred_at)
            VALUES ('\(m.id.value)', 'test-device', 1, 'corrupt', 'home', 179, '2026-09-05T00:00:00.000Z');
            """)   // 179 is not a total three darts can make
        XCTAssertThrowsError(try j.replay(m.id)) { error in
            guard case let JournalError.replayRejected(seq, reason) = error as! JournalError else {
                return XCTFail("wrong error: \(error)")
            }
            XCTAssertEqual(seq, 1)
            XCTAssertEqual(reason, "IMPOSSIBLE_VISIT_TOTAL")
        }
    }

    // MARK: matches

    func testMatchesListsWhatIsOnThisDeviceNewestFirst() throws {
        let j = try open()
        let older = try j.createMatch(NewMatch(homeName: "A", awayName: "B"), startedAt: Date(timeIntervalSince1970: 1_000))
        let newer = try j.createMatch(NewMatch(homeName: "C", awayName: "D"), startedAt: Date(timeIntervalSince1970: 2_000))
        XCTAssertEqual(try j.matches().map(\.id), [newer.id, older.id])
        XCTAssertThrowsError(try j.match(MatchId("nope")))
    }

    func testAMatchRecordRebuildsItsFormat() throws {
        let j = try open()
        let m = try j.createMatch(NewMatch(homeName: "A", awayName: "B", startingScore: 301, outRule: .straight,
                                           legsMode: .firstTo, legsTarget: 2, throwFirst: .away))
        let f = m.format
        XCTAssertEqual(f.startingScore, 301)
        XCTAssertEqual(f.outRule, .straight)
        XCTAssertEqual(f.legs.mode, .firstTo)
        XCTAssertEqual(f.legs.target, 2)
        XCTAssertEqual(f.throwFirst, Seat.away.playerId)
        XCTAssertEqual(m.initialState.thrower, Seat.away.playerId)
    }

    // MARK: retractions (PD-004)

    private func threeVisits(_ j: Journal) throws -> MatchRecord {
        let m = try j.createMatch(NewMatch(homeName: "A", awayName: "B"))
        try j.append(.visit(Seat.home.playerId, 180), to: m.id)
        try j.append(.visit(Seat.away.playerId, 60), to: m.id)
        try j.append(.visit(Seat.home.playerId, 100), to: m.id)
        return m
    }

    /// A correction supersedes; it never deletes. The struck row stays for an investigator to read.
    func testARetractionStrikesTheLastVisitFromReplayButNotFromTheRecord() throws {
        let j = try open()
        let m = try threeVisits(j)
        let r = try j.retractLastVisit(in: m.id)
        XCTAssertEqual(r.kind, .retraction)
        XCTAssertEqual(r.correctsSeq, 3)
        XCTAssertEqual(r.deviceSeq, 4)
        let all = try j.entries(for: m.id)
        XCTAssertEqual(all.count, 4, "nothing is deleted")
        XCTAssertEqual(all.map(\.kind), [.visit, .visit, .visit, .retraction])
        let replayed = try j.replayVisits(m.id)
        XCTAssertEqual(replayed.visits.map(\.visitTotal), [180, 60])
        XCTAssertEqual(replayed.state.remaining[Seat.home.playerId], 321)
        XCTAssertEqual(replayed.state.thrower, Seat.home.playerId, "the struck visit's thrower is back on")
    }

    func testRetractingAgainWalksOneFurtherBack() throws {
        let j = try open()
        let m = try threeVisits(j)
        try j.retractLastVisit(in: m.id)
        let second = try j.retractLastVisit(in: m.id)
        XCTAssertEqual(second.correctsSeq, 2)
        XCTAssertEqual(try j.replayVisits(m.id).visits.map(\.visitTotal), [180])
        XCTAssertEqual(try j.replay(m.id).remaining[Seat.away.playerId], 501)
    }

    func testRetractingWithNothingStandingThrows() throws {
        let j = try open()
        let m = try j.createMatch(NewMatch(homeName: "A", awayName: "B"))
        XCTAssertThrowsError(try j.retractLastVisit(in: m.id)) { error in
            XCTAssertEqual(error as? JournalError, .nothingToRetract)
        }
        try j.append(.visit(Seat.home.playerId, 60), to: m.id)
        try j.retractLastVisit(in: m.id)
        XCTAssertThrowsError(try j.retractLastVisit(in: m.id))
        XCTAssertEqual(try j.entries(for: m.id).count, 2)
    }

    /// A journal written before corrections existed — the founder's phone has one — opens, gains the
    /// two columns, and keeps working, with every old row reading as a visit.
    func testAJournalFromBeforeCorrectionsIsUpgradedOnOpen() throws {
        var db: OpaquePointer?
        XCTAssertEqual(sqlite3_open(path, &db), SQLITE_OK)
        let old = """
            CREATE TABLE local_match (match_id TEXT PRIMARY KEY, home_name TEXT NOT NULL, away_name TEXT NOT NULL,
              starting_score INTEGER NOT NULL, out_rule TEXT NOT NULL, legs_mode TEXT NOT NULL, legs_target INTEGER NOT NULL,
              throw_first TEXT NOT NULL, started_at TEXT NOT NULL, device_id TEXT NOT NULL);
            CREATE TABLE journal (match_id TEXT NOT NULL REFERENCES local_match(match_id), device_id TEXT NOT NULL,
              device_seq INTEGER NOT NULL, command_id TEXT NOT NULL UNIQUE, seat TEXT NOT NULL, visit_total INTEGER NOT NULL,
              darts_used INTEGER, darts_at_double INTEGER, occurred_at TEXT NOT NULL,
              PRIMARY KEY (match_id, device_id, device_seq));
            INSERT INTO local_match VALUES ('old', 'A', 'B', 501, 'double', 'bestOf', 3, 'home', '2026-09-05T00:00:00.000Z', 'test-device');
            INSERT INTO journal (match_id, device_id, device_seq, command_id, seat, visit_total, occurred_at)
              VALUES ('old', 'test-device', 1, 'c1', 'home', 60, '2026-09-05T00:00:01.000Z');
            """
        XCTAssertEqual(sqlite3_exec(db, old, nil, nil, nil), SQLITE_OK)
        sqlite3_close(db)

        let j = try open()
        let entries = try j.entries(for: MatchId("old"))
        XCTAssertEqual(entries.map(\.kind), [.visit])
        XCTAssertNil(entries[0].correctsSeq)
        try j.append(.visit(Seat.away.playerId, 45), to: MatchId("old"))
        try j.retractLastVisit(in: MatchId("old"))
        XCTAssertEqual(try j.replayVisits(MatchId("old")).visits.map(\.visitTotal), [60])
        // That journal also predates double-in, so it has no in-rule. It reads back as straight —
        // which is not a guess: the engine refused every other value at the time it was written.
        XCTAssertEqual(try j.match(MatchId("old")).inRule, .straight)
        XCTAssertEqual(try j.match(MatchId("old")).outRule, .double, "and the columns did not shift")
        XCTAssertEqual(try j.match(MatchId("old")).legsTarget, 3)
        XCTAssertEqual(try j.match(MatchId("old")).homeName, "A")
    }

    /// A double-in match keeps its in-rule across a close and reopen, and the state it replays to
    /// knows nobody is in yet. Before PD-008 the journal stored no in-rule at all and every record
    /// claimed straight-in, so a double-in match would have replayed as a different match.
    func testADoubleInMatchIsStoredAndReplayedAsDoubleIn() throws {
        let j = try open()
        let m = try j.createMatch(NewMatch(homeName: "A", awayName: "B", inRule: .double, legsTarget: 3))
        XCTAssertEqual(m.inRule, .double)
        XCTAssertEqual(m.format.inRule, .double, "and the format it rebuilds carries it")
        XCTAssertEqual(m.initialState.opened[Seat.home.playerId], false, "nobody is in at the start")

        // 0 does not open; 40 does; and the replay agrees after a close and reopen.
        try j.append(.visit(Seat.home.playerId, 0), to: m.id)
        try j.append(.visit(Seat.away.playerId, 40), to: m.id)
        let reopened = try open()
        let record = try reopened.match(m.id)
        XCTAssertEqual(record.inRule, .double, "the in-rule survives the file")
        let replay = try reopened.replayVisits(m.id)
        XCTAssertEqual(replay.state.remaining[Seat.home.playerId], 501, "a visit that did not open scores nothing")
        XCTAssertEqual(replay.state.remaining[Seat.away.playerId], 461)
        XCTAssertEqual(replay.state.opened[Seat.home.playerId], false)
        XCTAssertEqual(replay.state.opened[Seat.away.playerId], true)
    }

    // MARK: device identity

    /// The journal's identity belongs to the journal, not to whatever the caller happens to have.
    ///
    /// It used to come from `UserDefaults` on every open. That file can be lost while the journal
    /// survives — a restore that brings back Application Support but not the preferences — and a new
    /// identity would restart `device_seq` at 1 for a match that already had rows. ADR-006's gapless
    /// per-device sequence is precisely what the server uses to notice a device is missing events, so
    /// one device would arrive as two, each with its own sequence and neither with a gap to report.
    func testTheJournalKeepsTheDeviceIdentityItWasCreatedWithEvenIfTheCallerForgetsIt() throws {
        let first = try Journal(path: path, deviceId: DeviceId("the-original"))
        XCTAssertEqual(first.deviceId, DeviceId("the-original"))
        XCTAssertNil(first.deviceIdSupersededCallers, "nothing was superseded on the first open")
        let m = try first.createMatch(NewMatch(homeName: "A", awayName: "B"))
        _ = try first.append(.visit(Seat.home.playerId, 60), to: m.id)

        // the caller has lost its copy and made a new one
        let second = try Journal(path: path, deviceId: DeviceId("a-fresh-one"))
        XCTAssertEqual(second.deviceId, DeviceId("the-original"), "the journal's identity wins")
        XCTAssertEqual(second.deviceIdSupersededCallers, DeviceId("a-fresh-one"),
                       "and the disagreement is a fact, not a thing to swallow")

        // so the sequence continues rather than restarting under a second identity
        let next = try second.append(.visit(Seat.away.playerId, 60), to: m.id)
        XCTAssertEqual(next.deviceSeq, 2)
        XCTAssertEqual(next.deviceId, DeviceId("the-original"))
        let entries = try second.entries(for: m.id)
        XCTAssertEqual(Set(entries.map(\.deviceId)), [DeviceId("the-original")],
                       "one device, one stream")
    }

    // MARK: - attestation (PD-011)

    /// An attestation is an append like any other: durable, unremovable, and invisible to replay.
    /// The last property is the one that matters — a confirmation must not change the score.
    func testAnAttestationIsAppendedAndChangesNothingAboutTheScore() throws {
        let j = try open()
        let m = try j.createMatch(NewMatch(homeName: "A", awayName: "B", startingScore: 101, legsTarget: 1))
        try j.append(.visit(Seat.home.playerId, 61), to: m.id)
        let before = try j.replay(m.id)

        try j.attest(m.id, seat: .away, agrees: true)
        let after = try j.replay(m.id)
        XCTAssertEqual(before.remaining, after.remaining, "an attestation is not a throw")
        XCTAssertEqual(try j.entries(for: m.id).count, 2, "and it is on the record")
        XCTAssertEqual(Journal.standingVisits(try j.entries(for: m.id)).count, 1)
    }

    func testBothConfirmingIsBothConfirmingAndOneContestOutranksIt() throws {
        let j = try open()
        let m = try j.createMatch(NewMatch(homeName: "A", awayName: "B", startingScore: 101, legsTarget: 1))
        try j.append(.visit(Seat.home.playerId, 61), to: m.id)

        XCTAssertEqual(try j.standing(for: m.id), Journal.Standing(confirmed: [], contested: [], stale: false))
        try j.attest(m.id, seat: .home, agrees: true)
        XCTAssertFalse(try j.standing(for: m.id).bothConfirmed, "one is not both")
        try j.attest(m.id, seat: .away, agrees: true)
        XCTAssertTrue(try j.standing(for: m.id).bothConfirmed)
        XCTAssertFalse(try j.standing(for: m.id).anyContest)

        // A player may change their mind, and the last word is the one that counts.
        try j.attest(m.id, seat: .away, agrees: false)
        let standing = try j.standing(for: m.id)
        XCTAssertTrue(standing.anyContest)
        XCTAssertFalse(standing.bothConfirmed)
        XCTAssertEqual(standing.confirmed, [.home])
        XCTAssertEqual(standing.contested, [.away])
        XCTAssertEqual(try j.entries(for: m.id).count, 4, "and all three answers are still on the record")
    }

    /// The property that stops an agreement being borrowed. What was confirmed has to be what is
    /// recorded, so a visit or a retraction written afterwards makes the agreement stale — without
    /// deleting it, because nothing here is ever deleted.
    func testAnAgreementDoesNotSurviveTheResultChangingUnderIt() throws {
        let j = try open()
        let m = try j.createMatch(NewMatch(homeName: "A", awayName: "B", startingScore: 501, legsTarget: 1))
        try j.append(.visit(Seat.home.playerId, 60), to: m.id)
        try j.attest(m.id, seat: .home, agrees: true)
        try j.attest(m.id, seat: .away, agrees: true)
        XCTAssertTrue(try j.standing(for: m.id).bothConfirmed)

        try j.append(.visit(Seat.away.playerId, 60), to: m.id)
        var standing = try j.standing(for: m.id)
        XCTAssertTrue(standing.stale, "a visit came after the agreement")
        XCTAssertFalse(standing.bothConfirmed)
        XCTAssertEqual(standing.confirmed, [.home, .away], "the answers are still there; they just no longer apply")

        // The same for a retraction, which is the case that actually happens: somebody undoes a
        // mis-key after the other player has already said yes.
        try j.attest(m.id, seat: .home, agrees: true)
        try j.attest(m.id, seat: .away, agrees: true)
        XCTAssertTrue(try j.standing(for: m.id).bothConfirmed)
        try j.retractLastVisit(in: m.id)
        standing = try j.standing(for: m.id)
        XCTAssertTrue(standing.stale)
        XCTAssertFalse(standing.bothConfirmed)
    }

    /// A row written by a LATER build must not be replayed as a visit.
    ///
    /// It used to be: `Kind(rawValue:) ?? .visit`, so an unrecognised kind became a nil-scoring
    /// visit and quietly entered the match — changing the score and every statistic derived from it,
    /// with nothing anywhere saying so. A journal containing rows this build cannot interpret cannot
    /// be replayed faithfully, so it says that instead.
    func testARowThisBuildCannotReadIsRefusedRatherThanScoredAsAVisit() throws {
        let j = try open()
        let m = try j.createMatch(NewMatch(homeName: "A", awayName: "B", startingScore: 501, legsTarget: 1))
        try j.append(.visit(Seat.home.playerId, 60), to: m.id)
        try j.exec("""
            INSERT INTO journal (match_id, device_id, device_seq, command_id, kind, seat, visit_total, occurred_at)
            VALUES ('\(m.id.value)', 'test-device', 99, 'from-the-future', 'wager', 'home', 0, '2030-01-01T00:00:00.000Z');
            """)

        XCTAssertEqual(try j.entries(for: m.id).last?.kind, .unknown, "not silently a visit")
        XCTAssertThrowsError(try j.replay(m.id)) { error in
            guard case JournalError.replayRejected(_, let reason) = error else {
                return XCTFail("wrong error: \(error)")
            }
            XCTAssertEqual(reason, "UNKNOWN_ROW_KIND")
        }
    }

    // MARK: - who played (ADR-016)

    /// A match remembers who its two names referred to, and a match written before the device kept
    /// a book of people still reads — with nulls, which is the honest answer rather than a guess.
    func testAMatchCarriesItsPlayersAndAnOlderOneReadsBackWithout() throws {
        let j = try open()
        let attributed = try j.createMatch(NewMatch(homeName: "Jenson", awayName: "Alex",
                                                    homePlayerId: "p-jenson", awayPlayerId: "p-alex"))
        let anonymous = try j.createMatch(NewMatch(homeName: "A", awayName: "B"))

        let reopened = try Journal(path: path, deviceId: device)
        let read = try reopened.match(attributed.id)
        XCTAssertEqual(read.homePlayerId, "p-jenson")
        XCTAssertEqual(read.awayPlayerId, "p-alex")
        XCTAssertEqual(read.playerId(.home), "p-jenson")
        XCTAssertEqual(read.playerId(.away), "p-alex")

        let old = try reopened.match(anonymous.id)
        XCTAssertNil(old.homePlayerId, "not knowing is a value, and it is not a guess")
        XCTAssertNil(old.awayPlayerId)
        XCTAssertEqual(old.homeName, "A", "and everything else about it is unchanged")
    }

    /// One person's visits pooled across their matches, with legs renumbered.
    ///
    /// The renumbering is the point. Leg 1 of one match and leg 1 of another are different legs, and
    /// pooling them under the same ordinal would merge two best legs into one and put six visits in a
    /// first-nine average — the same class of defect as sharing visit ordinals between competitors,
    /// which this repository has already made once.
    func testAPersonsVisitsArePooledAcrossMatchesWithLegsKeptApart() throws {
        let j = try open()
        for _ in 0..<2 {
            let m = try j.createMatch(NewMatch(homeName: "Jenson", awayName: "Alex", startingScore: 101,
                                               legsTarget: 1, homePlayerId: "p-jenson", awayPlayerId: "p-alex"))
            try j.append(.visit(Seat.home.playerId, 60), to: m.id)
            try j.append(.visit(Seat.away.playerId, 20), to: m.id)
            try j.append(.visit(Seat.home.playerId, 41, dartsUsed: 2, dartsAtDouble: 1), to: m.id)
        }
        // A match the person is not in, so it must not be counted.
        let other = try j.createMatch(NewMatch(homeName: "Sam", awayName: "Chris", startingScore: 101,
                                               legsTarget: 1, homePlayerId: "p-sam", awayPlayerId: "p-chris"))
        try j.append(.visit(Seat.home.playerId, 60), to: other.id)

        let history = try j.history(of: "p-jenson")
        XCTAssertEqual(history.matches, 2)
        XCTAssertEqual(history.legsWon, 2, "they won both")
        XCTAssertEqual(history.unreadable, 0)
        XCTAssertEqual(history.outRules, ["double"])
        XCTAssertEqual(history.visits.count, 4, "two visits each, and none of Sam's")
        XCTAssertEqual(Set(history.visits.map(\.legOrdinal)).count, 2,
                       "the two matches' legs stay apart rather than both being leg 1")
        XCTAssertEqual(history.visits.map(\.visitTotal), [60, 41, 60, 41])

        let alex = try j.history(of: "p-alex")
        XCTAssertEqual(alex.matches, 2)
        XCTAssertEqual(alex.legsWon, 0)
        XCTAssertEqual(alex.visits.map(\.visitTotal), [20, 20])
    }

    /// A match of theirs that will not replay is counted and reported, never quietly dropped: an
    /// average computed over the readable half is a different number, not a smaller sample.
    func testAnUnreadableMatchOfTheirsIsCountedRatherThanSkipped() throws {
        let j = try open()
        let good = try j.createMatch(NewMatch(homeName: "Jenson", awayName: "Alex", startingScore: 101,
                                              legsTarget: 1, homePlayerId: "p-jenson", awayPlayerId: "p-alex"))
        try j.append(.visit(Seat.home.playerId, 60), to: good.id)
        let bad = try j.createMatch(NewMatch(homeName: "Jenson", awayName: "Alex", startingScore: 101,
                                             legsTarget: 1, homePlayerId: "p-jenson", awayPlayerId: "p-alex"))
        try j.exec("""
            INSERT INTO journal (match_id, device_id, device_seq, command_id, kind, seat, visit_total, occurred_at)
            VALUES ('\(bad.id.value)', 'test-device', 1, 'not-a-kind', 'wager', 'home', 0, '2030-01-01T00:00:00.000Z');
            """)

        let history = try j.history(of: "p-jenson")
        XCTAssertEqual(history.matches, 2, "both are theirs")
        XCTAssertEqual(history.unreadable, 1, "and one of them says so")
        XCTAssertEqual(history.visits.count, 1)
    }

    // MARK: - ending a match short (PD-016)

    /// The whole reason there are two endings rather than one. Retiring hands the win to the other
    /// player; abandoning hands it to nobody, and `winner` being optional is what stops anything
    /// downstream inventing one.
    func testRetiringHasAWinnerAndAbandoningHasNone() throws {
        let j = try open()
        let retired = try j.createMatch(NewMatch(homeName: "A", awayName: "B"))
        try j.append(.visit(Seat.home.playerId, 60), to: retired.id)
        try j.end(retired.id, as: .retired(by: .home))
        XCTAssertEqual(try j.ending(for: retired.id), .retired(by: .home))
        XCTAssertEqual(try j.ending(for: retired.id)?.winner, .away, "the player who did not stop")
        XCTAssertEqual(try j.ending(for: retired.id)?.isResult, true)

        let abandoned = try j.createMatch(NewMatch(homeName: "C", awayName: "D"))
        try j.append(.visit(Seat.home.playerId, 60), to: abandoned.id)
        try j.end(abandoned.id, as: .abandoned)
        XCTAssertEqual(try j.ending(for: abandoned.id), .abandoned)
        XCTAssertNil(try j.ending(for: abandoned.id)?.winner, "nobody won, and nobody is given the win")
        XCTAssertEqual(try j.ending(for: abandoned.id)?.isResult, false)
    }

    /// An abandonment has no seat, and the column will not take a null, so `home` goes in as a
    /// placeholder. This proves the placeholder is inert: the row is rewritten with the OTHER seat
    /// and reads back as the same ending. A comment saying "never read" is not a guarantee; this is.
    func testAbandonmentIgnoresTheSeatItStores() throws {
        let j = try open()
        let m = try j.createMatch(NewMatch(homeName: "A", awayName: "B"))
        try j.append(.visit(Seat.home.playerId, 60), to: m.id)
        try j.end(m.id, as: .abandoned)

        let asWritten = try j.entries(for: m.id).first { $0.kind == .abandonment }
        XCTAssertEqual(asWritten?.seat, .home, "the placeholder this test is about")

        // Read the same rows back with the seat flipped. Nothing goes through the journal's writer,
        // because the journal is append-only and this is a test of the READER.
        let flipped = try j.entries(for: m.id).map { e -> JournalEntry in
            guard e.kind == .abandonment else { return e }
            return JournalEntry(matchId: e.matchId, deviceId: e.deviceId, deviceSeq: e.deviceSeq,
                                commandId: e.commandId, kind: e.kind, seat: .away, visitTotal: e.visitTotal,
                                dartsUsed: e.dartsUsed, dartsAtDouble: e.dartsAtDouble,
                                correctsSeq: e.correctsSeq, occurredAt: e.occurredAt)
        }
        XCTAssertEqual(Journal.ending(flipped), .abandoned, "the stored seat changes nothing")
        XCTAssertNil(Journal.ending(flipped)?.winner)
    }

    /// An ending is final. Not a preference — the alternative is a result that moves after somebody
    /// has agreed to it, which is exactly what PD-011's attestation exists to pin down.
    func testAnEndingIsFinalAndASecondOneIsRefused() throws {
        let j = try open()
        let m = try j.createMatch(NewMatch(homeName: "A", awayName: "B"))
        try j.append(.visit(Seat.home.playerId, 60), to: m.id)
        try j.end(m.id, as: .retired(by: .away))

        XCTAssertThrowsError(try j.end(m.id, as: .abandoned)) { error in
            XCTAssertEqual(error as? JournalError, .alreadyEnded(.retired(by: .away)))
        }
        XCTAssertEqual(try j.ending(for: m.id), .retired(by: .away), "and the first one still stands")
    }

    /// No more darts, and no corrections either. Undoing the last visit of a retired match would
    /// change the scoreline behind a result somebody has already been given.
    func testAnEndedMatchTakesNoVisitAndNoRetraction() throws {
        let j = try open()
        let m = try j.createMatch(NewMatch(homeName: "A", awayName: "B"))
        try j.append(.visit(Seat.home.playerId, 60), to: m.id)
        try j.end(m.id, as: .abandoned)

        XCTAssertThrowsError(try j.append(.visit(Seat.away.playerId, 60), to: m.id)) { error in
            XCTAssertEqual(error as? JournalError, .alreadyEnded(.abandoned))
        }
        XCTAssertThrowsError(try j.retractLastVisit(in: m.id)) { error in
            XCTAssertEqual(error as? JournalError, .alreadyEnded(.abandoned))
        }
        XCTAssertEqual(Journal.standingVisits(try j.entries(for: m.id)).count, 1, "nothing was added or struck")
    }

    /// Ending short changes what the result IS, so an agreement given before it no longer applies.
    /// Retiring after both players confirmed a scoreline hands the match to somebody neither of them
    /// agreed had won it.
    func testAnEndingMakesAnEarlierAgreementStale() throws {
        let j = try open()
        let m = try j.createMatch(NewMatch(homeName: "A", awayName: "B", startingScore: 501, legsTarget: 1))
        try j.append(.visit(Seat.home.playerId, 60), to: m.id)
        try j.attest(m.id, seat: .home, agrees: true)
        try j.attest(m.id, seat: .away, agrees: true)
        XCTAssertTrue(try j.standing(for: m.id).bothConfirmed)

        try j.end(m.id, as: .retired(by: .away))
        let standing = try j.standing(for: m.id)
        XCTAssertTrue(standing.stale, "a retirement came after the agreement")
        XCTAssertFalse(standing.bothConfirmed)
        XCTAssertEqual(standing.confirmed, [.home, .away], "the answers are still there; they no longer apply")
    }

    /// The darts are real either way. Only the RESULT differs, so an ended match still replays every
    /// visit that was thrown in it — an ending is a fact about the record, not a throw.
    func testAnEndedMatchStillReplaysEveryVisitThrownInIt() throws {
        let j = try open()
        let m = try j.createMatch(NewMatch(homeName: "A", awayName: "B", startingScore: 501, legsTarget: 1))
        try j.append(.visit(Seat.home.playerId, 100), to: m.id)
        try j.append(.visit(Seat.away.playerId, 60), to: m.id)
        let before = try j.replayVisits(m.id)

        try j.end(m.id, as: .abandoned)
        let after = try j.replayVisits(m.id)
        XCTAssertEqual(after.visits, before.visits, "an ending adds no visit and removes none")
        XCTAssertEqual(after.state.remaining, before.state.remaining)
        XCTAssertFalse(after.state.isComplete, "the ENGINE never said this was complete; the journal did")
    }

    /// A person's darts count from an abandoned match; the match does not. Counted apart rather than
    /// folded in, because "played 12" meaning "9 played out and 3 walked away from" is a different
    /// claim to the one it looks like.
    func testAPersonsHistoryCountsRetiredAndAbandonedApart() throws {
        let j = try open()
        let me = "person-1"
        let cases: [(String, Ending?)] = [("one", nil), ("two", .retired(by: .away)), ("three", .abandoned)]
        for (name, ending) in cases {
            let m = try j.createMatch(NewMatch(homeName: name, awayName: "B", homePlayerId: me))
            try j.append(.visit(Seat.home.playerId, 60), to: m.id)
            if let ending { try j.end(m.id, as: ending) }
        }
        let history = try j.history(of: me)
        XCTAssertEqual(history.matches, 3)
        XCTAssertEqual(history.retired, 1)
        XCTAssertEqual(history.abandoned, 1)
        XCTAssertEqual(history.visits.count, 3, "every dart thrown counts, including in the abandoned one")
    }

    /// Leg 1 is the first leg this person played on this device; the highest ordinal is the most
    /// recent. `matches()` returns newest first, so pooling has to reverse it.
    ///
    /// Nothing before PD-018 would have noticed this: every pooled figure — averages, first nine,
    /// best leg — is order-independent, so the numbering could run either way and every test still
    /// passed. The form figure takes the HIGHEST ordinals as the recent ones, so under the other
    /// direction it would have described a player's oldest darts as their current form. This is the
    /// only thing holding the direction.
    func testHistoryNumbersLegsOldestFirst() throws {
        let j = try open()
        let me = "person-1"
        // Two one-leg matches, the second played a day later. Different scores so they are telling
        // apart by their darts rather than by their ordinals.
        let first = try j.createMatch(NewMatch(homeName: "A", awayName: "B", startingScore: 101,
                                               legsTarget: 1, homePlayerId: me),
                                      startedAt: Date(timeIntervalSince1970: 1_000))
        try j.append(.visit(Seat.home.playerId, 101, dartsUsed: 3, dartsAtDouble: 1), to: first.id)

        let second = try j.createMatch(NewMatch(homeName: "A", awayName: "C", startingScore: 101,
                                                legsTarget: 1, homePlayerId: me),
                                       startedAt: Date(timeIntervalSince1970: 2_000))
        try j.append(.visit(Seat.home.playerId, 60), to: second.id)
        try j.append(.visit(Seat.away.playerId, 60), to: second.id)

        let history = try j.history(of: me)
        let byLeg = Dictionary(grouping: history.visits, by: { $0.legOrdinal })
        XCTAssertEqual(byLeg.keys.sorted(), [1, 2])
        XCTAssertEqual(byLeg[1]?.map(\.visitTotal), [101], "the OLDER match is leg 1")
        XCTAssertEqual(byLeg[2]?.map(\.visitTotal), [60], "and the newer one is above it")
    }

    // MARK: a replay returns what was stored

    /// The server has answered replays this way since the command path shipped — *"a replay returns
    /// the stored response, including a stored refusal"* — and the journal did not. A duplicate
    /// command id hit the UNIQUE constraint and reached the player as *"Not saved, so not
    /// recorded"* for a visit that **was** saved, which is the worst shape a durability error can
    /// have.
    func testAReplayedVisitReturnsTheStoredRowAndWritesNothing() throws {
        let j = try open()
        let m = try j.createMatch(NewMatch(homeName: "A", awayName: "B"))
        let first = try j.append(.visit(Seat.home.playerId, 60), to: m.id, commandId: "cmd-1")
        let again = try j.append(.visit(Seat.home.playerId, 60), to: m.id, commandId: "cmd-1")
        XCTAssertEqual(first, again, "the stored row, returned verbatim")
        XCTAssertEqual(try j.entries(for: m.id).count, 1, "and nothing was written a second time")
        XCTAssertEqual(try j.entries(for: m.id).first?.deviceSeq, 1, "so the sequence did not advance")
    }

    /// Two different commands claiming one id is corruption, not a retry, and is refused.
    func testACommandIdOfferedForADifferentCommandIsRefused() throws {
        let j = try open()
        let m = try j.createMatch(NewMatch(homeName: "A", awayName: "B"))
        try j.append(.visit(Seat.home.playerId, 60), to: m.id, commandId: "cmd-1")
        XCTAssertThrowsError(try j.append(.visit(Seat.away.playerId, 100), to: m.id, commandId: "cmd-1")) { error in
            guard case let .commandIdReused(id, _)? = error as? JournalError else {
                return XCTFail("expected commandIdReused, got \(error)")
            }
            XCTAssertEqual(id, "cmd-1")
        }
        XCTAssertEqual(try j.entries(for: m.id).count, 1, "and nothing was written")
    }

    /// A replay is answered **before** the ending is checked. A retry of a visit that landed must
    /// not be refused on the ground that the match has since been retired — the row is already
    /// there, and telling the caller otherwise is the same lie the UNIQUE constraint used to tell.
    func testAReplayIsAnsweredEvenAfterTheMatchHasEnded() throws {
        let j = try open()
        let m = try j.createMatch(NewMatch(homeName: "A", awayName: "B"))
        let landed = try j.append(.visit(Seat.home.playerId, 60), to: m.id, commandId: "cmd-1")
        try j.end(m.id, as: .retired(by: .away))
        XCTAssertEqual(landed, try j.append(.visit(Seat.home.playerId, 60), to: m.id, commandId: "cmd-1"))
        // A genuinely new visit is still refused, which is the rule the replay must not weaken.
        XCTAssertThrowsError(try j.append(.visit(Seat.away.playerId, 60), to: m.id)) { error in
            XCTAssertEqual(error as? JournalError, .alreadyEnded(.retired(by: .away)))
        }
    }

    /// The other three writes answer a replay too: a retraction, an attestation and an ending.
    func testEveryWriteAnswersAReplay() throws {
        let j = try open()
        let m = try threeVisits(j)
        let undo = try j.retractLastVisit(in: m.id, commandId: "undo-1")
        XCTAssertEqual(undo, try j.retractLastVisit(in: m.id, commandId: "undo-1"))

        let said = try j.attest(m.id, seat: .home, agrees: true, commandId: "att-1")
        XCTAssertEqual(said, try j.attest(m.id, seat: .home, agrees: true, commandId: "att-1"))

        let over = try j.end(m.id, as: .abandoned, commandId: "end-1")
        XCTAssertEqual(over, try j.end(m.id, as: .abandoned, commandId: "end-1"))
        // Not a licence to end twice: a SECOND ending, with its own id, is still refused.
        XCTAssertThrowsError(try j.end(m.id, as: .retired(by: .home))) { error in
            XCTAssertEqual(error as? JournalError, .alreadyEnded(.abandoned))
        }

        XCTAssertEqual(try j.entries(for: m.id).count, 6, "three visits, an undo, an attestation, an ending")
    }

    /// The instant a write returns is the instant the journal holds. It was not: the returned entry
    /// carried sub-millisecond precision the stored ISO-8601 string cannot express, so a replay
    /// returned a row that differed from the one the first call handed back — by a value nothing in
    /// the app could see and every comparison could.
    func testTheInstantReturnedIsTheInstantStored() throws {
        let j = try open()
        let m = try j.createMatch(NewMatch(homeName: "A", awayName: "B"))
        let precise = Date(timeIntervalSince1970: 1_700_000_000.123_456)
        let written = try j.append(.visit(Seat.home.playerId, 60), to: m.id, occurredAt: precise)
        XCTAssertEqual(written, try j.entries(for: m.id).first)
        XCTAssertEqual(written.occurredAt.timeIntervalSince1970, 1_700_000_000.123, accuracy: 0.0005)
    }
}
