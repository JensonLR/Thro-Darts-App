import XCTest
@testable import ThroApp
@testable import ThroJournal
import ThroNet

/// Sending a match this phone scored (PD-040): the journal as it was written, or a reason it cannot go.
final class MatchUploadTests: XCTestCase {

    private let match = MatchId("11111111-1111-1111-1111-111111111111")
    private let device = DeviceId("22222222-2222-2222-2222-222222222222")
    private let at = Date(timeIntervalSince1970: 1_789_000_000)

    private func entry(_ seq: Int64, _ kind: JournalEntry.Kind, _ seat: Seat = .home,
                       total: Int = 0, corrects: Int64? = nil) -> JournalEntry {
        JournalEntry(matchId: match, deviceId: device, deviceSeq: seq, commandId: "c\(seq)",
                     kind: kind, seat: seat, visitTotal: total, dartsUsed: nil, dartsAtDouble: nil,
                     correctsSeq: corrects, occurredAt: at.addingTimeInterval(Double(seq) * 20))
    }

    private func rows(_ entries: [JournalEntry]) -> [ThroAPI.UploadRow] {
        guard case .ready(let r) = MatchUpload.rows(from: entries, zone: TimeZone(identifier: "Europe/London")!) else {
            XCTFail("expected it to be ready: \(MatchUpload.rows(from: entries))"); return []
        }
        return r
    }

    private func why(_ entries: [JournalEntry]) -> String {
        guard case .notYet(let reason) = MatchUpload.rows(from: entries) else {
            XCTFail("expected a reason it cannot go"); return ""
        }
        return reason
    }

    func testTheStruckVisitGoesToo() {
        // The whole argument of PD-040 in one assertion: a retracted visit is SENT, not filtered
        // out, because the board showed it and the record keeps what was written (PD-004).
        let sent = rows([entry(1, .visit, .home, total: 60),
                         entry(2, .visit, .away, total: 45),
                         entry(3, .visit, .home, total: 100),
                         entry(4, .retraction, .home, corrects: 3),
                         entry(5, .visit, .home, total: 45)])
        XCTAssertEqual(sent.map(\.deviceSeq), [1, 2, 3, 4, 5])
        XCTAssertEqual(sent.map(\.kind), ["visit", "visit", "visit", "retraction", "visit"])
        XCTAssertEqual(sent[3].correctsSeq, 3, "and it says which one it struck")
        XCTAssertNil(sent[3].visitTotal, "a retraction scores nothing")
        XCTAssertEqual(sent[0].visitTotal, 60)
        XCTAssertEqual(sent[1].seat, "away")
    }

    func testTheRowsGoInTheOrderTheDeviceWroteThem() {
        // The server refuses anything else, and it is right to: out of order, this is not a journal.
        let sent = rows([entry(3, .visit, .home, total: 100), entry(1, .visit, .home, total: 60),
                         entry(2, .visit, .away, total: 45)])
        XCTAssertEqual(sent.map(\.deviceSeq), [1, 2, 3])
    }

    // A match that ended short (PD-016). This used to be refused — sending the visits alone would
    // have left THRØ saying the match was still going — and V034 gave the server an ending to hold, so
    // the refusal became the thing to replace. What stays true: it never goes as unfinished.

    func testARetirementIsSentLastAndSaysWhoRetired() {
        let sent = rows([entry(1, .visit, .home, total: 60), entry(2, .visit, .away, total: 45),
                         entry(3, .retirement, .away)])
        XCTAssertEqual(sent.map(\.kind), ["visit", "visit", "retirement"], "the ending is the last row")
        XCTAssertEqual(sent.last?.seat, "away", "the seat that retired; the winner is worked out, not sent")
        XCTAssertNil(sent.last?.visitTotal, "an ending scores nothing")
        XCTAssertNil(sent.last?.correctsSeq)
    }

    func testAnAbandonmentIsSentAndScoresNothing() {
        let sent = rows([entry(1, .visit, .home, total: 60), entry(2, .abandonment)])
        XCTAssertEqual(sent.map(\.kind), ["visit", "abandonment"])
        XCTAssertNil(sent.last?.visitTotal)
    }

    func testWhatAPersonIsToldSaysHowTheMatchEnded() {
        func sent(_ v: Int, _ ending: String?) -> ThroAPI.Sent {
            ThroAPI.Sent(matchId: UUID(), opponentId: UUID(), visits: v, retractions: 0,
                         alreadyHeld: 0, opened: true, selfReported: true, ending: ending)
        }
        XCTAssertTrue(MatchUpload.done(sent(2, "retired")).hasPrefix("Sent 2 visits and the retirement."))
        XCTAssertTrue(MatchUpload.done(sent(0, "abandoned")).hasPrefix("Sent the abandonment."),
                      "a resend that only added the ending says so, and nothing else")
        XCTAssertEqual(MatchUpload.sentence(["12 visits", "1 undo", "the retirement"]), "12 visits, 1 undo and the retirement")
    }

    func testARowFromANewerBuildIsNeverGuessedAt() {
        // `unknown` is what a row written by a later version reads back as. Sending it as a visit
        // would put a score in THRØ that nobody threw.
        let reason = why([entry(1, .visit, .home, total: 60), entry(2, .unknown)])
        XCTAssertTrue(reason.contains("newer version"), reason)
    }

    func testAnEmptyMatchAndAMatchOfOnlyOpinionsHaveNothingToSend() {
        XCTAssertEqual(why([]), MatchUpload.nothingToSend)
        // A confirmation and a contest are somebody's opinion of the result, not the record of it.
        XCTAssertEqual(why([entry(1, .confirmation), entry(2, .contest)]), MatchUpload.nothingToSend)
    }

    func testAnUndoWithNoVisitIsCaughtHereRatherThanByTheServer() {
        // The server would refuse it, but its sentence would be about a row this phone chose not to
        // send — which reads as a fault in THRØ rather than in the record.
        let reason = why([entry(1, .confirmation), entry(2, .retraction, .home, corrects: 1)])
        XCTAssertTrue(reason.contains("will not send half of it"), reason)
    }

    func testWhatAPersonIsToldAfterwardsIsTrueOfWhatWasStored() {
        func sent(_ v: Int, _ r: Int) -> ThroAPI.Sent {
            ThroAPI.Sent(matchId: UUID(), opponentId: UUID(), visits: v, retractions: r,
                         alreadyHeld: 0, opened: true, selfReported: true)
        }
        XCTAssertTrue(MatchUpload.done(sent(1, 0)).hasPrefix("Sent 1 visit."))
        XCTAssertTrue(MatchUpload.done(sent(12, 1)).hasPrefix("Sent 12 visits and 1 undo."))
        // A resend that added nothing must not claim it sent anything.
        XCTAssertTrue(MatchUpload.done(sent(0, 0)).hasPrefix("THRØ already had all of it."))
        // And every one of them carries the thing that matters (PD-011).
        for s in [sent(1, 0), sent(12, 1), sent(0, 0)] {
            XCTAssertTrue(MatchUpload.done(s).contains("until the other player confirms"), MatchUpload.done(s))
        }
    }

    func testTheInstantIsTheOneTheServerParses() {
        let sent = rows([entry(1, .visit, .home, total: 60)])
        // The server does `Instant.parse`, which wants a Z-terminated ISO-8601 instant.
        XCTAssertTrue(sent[0].occurredAt.hasSuffix("Z"), sent[0].occurredAt)
        XCTAssertEqual(sent[0].occurredTz, "Europe/London", "and the zone travels beside it, never inside it")
    }
}
