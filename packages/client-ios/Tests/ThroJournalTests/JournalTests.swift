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
}
