import XCTest
import ThroEngine
@testable import ThroJournal

/// `Journal.ledger` — the leg as a scorer would have written it, struck rows included (PD-004).
///
/// The reason this read exists at all: a retraction is an `INSERT` carrying `corrects_seq`, so the
/// record keeps what was written — and the screen did not. An undo was a disappearance, which is
/// the one thing PD-004 says it is not.
///
/// The reason it is a **new** read rather than a change to `replayVisits`: every figure in this app
/// stands on the replayed visits, and a struck visit must never reach one. The first test below is
/// the one that makes the whole thing safe.
final class LedgerTests: XCTestCase {

    private var path: String!
    private let device = DeviceId("ledger-device")

    override func setUp() {
        super.setUp()
        path = NSTemporaryDirectory() + "thro-ledger-\(UUID().uuidString).sqlite"
    }

    override func tearDown() {
        for suffix in ["", "-wal", "-shm", "-journal"] {
            try? FileManager.default.removeItem(atPath: path + suffix)
        }
        super.tearDown()
    }

    private func open() throws -> Journal { try Journal(path: path, deviceId: device) }

    @discardableResult
    private func aLeg(_ j: Journal) throws -> MatchRecord {
        let m = try j.createMatch(NewMatch(homeName: "Ann", awayName: "Sam"))
        try j.append(.visit(Seat.home.playerId, 60), to: m.id)
        try j.append(.visit(Seat.away.playerId, 85), to: m.id)
        try j.append(.visit(Seat.home.playerId, 45), to: m.id)
        try j.append(.visit(Seat.away.playerId, 26), to: m.id)
        return m
    }

    // MARK: - The invariant that makes it safe

    func testTheLedgersStandingRowsAreExactlyTheReplayedVisits() throws {
        // Remainder for remainder, in order. If this ever parts company, a figure and the board are
        // reading two different matches — and the figure is the one people are judged on.
        let j = try open()
        let m = try aLeg(j)
        try j.retractLastVisit(in: m.id)
        try j.append(.visit(Seat.away.playerId, 41), to: m.id)

        let replayed = try j.replayVisits(m.id).visits
        let standing = try j.ledger(m.id).filter { !$0.struck }
        XCTAssertEqual(standing.count, replayed.count)
        for (row, visit) in zip(standing, replayed) {
            XCTAssertEqual(row.seat, visit.seat)
            XCTAssertEqual(row.legOrdinal, visit.legOrdinal)
            XCTAssertEqual(row.visitOrdinal, visit.visitOrdinal)
            XCTAssertEqual(row.visitTotal, visit.visitTotal)
            XCTAssertEqual(row.remainingAfter, visit.remainingAfter)
        }
    }

    func testAStruckVisitIsInTheLedgerAndNotInTheReplay() throws {
        let j = try open()
        let m = try aLeg(j)
        try j.retractLastVisit(in: m.id)

        let rows = try j.ledger(m.id)
        XCTAssertEqual(rows.count, 4, "the struck row keeps its place")
        XCTAssertEqual(rows.map(\.visitTotal), [60, 85, 45, 26])
        XCTAssertEqual(rows.map(\.struck), [false, false, false, true])
        XCTAssertEqual(try j.replayVisits(m.id).visits.count, 3, "and the replay does not see it")
    }

    // MARK: - What a struck row says

    func testAStruckRowShowsWhatStoodOnTheBoardWhenItWasWritten() throws {
        // Not what stands now — what was written. That is the whole point of keeping it.
        let j = try open()
        let m = try aLeg(j)
        try j.retractLastVisit(in: m.id)
        let struck = try XCTUnwrap(try j.ledger(m.id).last)
        XCTAssertTrue(struck.struck)
        XCTAssertEqual(struck.visitTotal, 26)
        XCTAssertEqual(struck.remainingAfter, 501 - 85 - 26, "Sam was on 390 when that 26 went up")
    }

    func testAStruckVisitDoesNotAdvanceTheMatchSoWhatCameNextIsUnaffected() throws {
        // It was taken back, so the next visit was thrown against the state before it. The ledger
        // has to reproduce that or every remainder after a retraction is wrong.
        let j = try open()
        let m = try aLeg(j)
        try j.retractLastVisit(in: m.id)      // takes back Sam's 26
        try j.append(.visit(Seat.away.playerId, 41), to: m.id)

        let rows = try j.ledger(m.id)
        XCTAssertEqual(rows.map(\.visitTotal), [60, 85, 45, 26, 41])
        XCTAssertEqual(rows.map(\.struck), [false, false, false, true, false])
        XCTAssertEqual(rows.last?.remainingAfter, 501 - 85 - 41,
                       "the 41 was thrown against 416, not against the 390 the struck 26 left")
    }

    func testAStruckRowAndTheVisitThatReplacedItShareTheirPlaceInTheOrder() throws {
        // They are the same turn. Numbering the replacement as a fresh visit would make the leg
        // look one visit longer than it was thrown.
        let j = try open()
        let m = try aLeg(j)
        try j.retractLastVisit(in: m.id)
        try j.append(.visit(Seat.away.playerId, 41), to: m.id)

        let away = try j.ledger(m.id).filter { $0.seat == .away }
        XCTAssertEqual(away.map(\.visitTotal), [85, 26, 41])
        XCTAssertEqual(away.map(\.visitOrdinal), [1, 2, 2], "the struck 26 and the 41 are both visit 2")
    }

    // MARK: - Nothing else moved

    func testTheLedgerChangesNoFigureAndReadsNoNewColumn() throws {
        // A new read beside the old ones, not a change to them. Same rows, same stored shape.
        let j = try open()
        let m = try aLeg(j)
        try j.retractLastVisit(in: m.id)

        let all = try j.entries(for: m.id)
        XCTAssertEqual(all.count, 5, "four visits and the retraction; nothing was deleted")
        XCTAssertEqual(Journal.standingVisits(all).count, 3)
        // Every ledger row corresponds to a scoring row that is really in the journal.
        let seqs = Set(all.filter { $0.kind.isScoring }.map(\.deviceSeq))
        for row in try j.ledger(m.id) {
            XCTAssertTrue(seqs.contains(row.deviceSeq), "a ledger row with no journal row behind it")
        }
    }

    func testEveryLedgerRowHasItsOwnIdentity() throws {
        // The board keys its rows on this. Two rows sharing one would make SwiftUI animate a
        // retraction as if a number had changed, which is exactly the disappearance being fixed.
        let j = try open()
        let m = try aLeg(j)
        try j.retractLastVisit(in: m.id)
        try j.append(.visit(Seat.away.playerId, 41), to: m.id)
        let ids = try j.ledger(m.id).map(\.deviceSeq)
        XCTAssertEqual(Set(ids).count, ids.count)
    }

    func testAnEmptyMatchHasAnEmptyLedgerRatherThanAnError() throws {
        let j = try open()
        let m = try j.createMatch(NewMatch(homeName: "Ann", awayName: "Sam"))
        XCTAssertEqual(try j.ledger(m.id), [])
    }

    func testALegWonReadsAsZeroLeftAndTheLedgerSaysSo() throws {
        let j = try open()
        let m = try j.createMatch(NewMatch(homeName: "Ann", awayName: "Sam"))
        try j.append(.visit(Seat.home.playerId, 180), to: m.id)
        try j.append(.visit(Seat.away.playerId, 60), to: m.id)
        try j.append(.visit(Seat.home.playerId, 180), to: m.id)
        try j.append(.visit(Seat.away.playerId, 60), to: m.id)
        try j.append(.visit(Seat.home.playerId, 141), to: m.id)   // 501 − 180 − 180 = 141
        let rows = try j.ledger(m.id)
        XCTAssertEqual(rows.last?.remainingAfter, 0)
        XCTAssertEqual(rows.last?.struck, false)
    }
}
