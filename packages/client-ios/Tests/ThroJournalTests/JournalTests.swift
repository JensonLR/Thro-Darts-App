import XCTest
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
}
