import Foundation
import XCTest
@testable import ThroApp
@testable import ThroNet
@testable import ThroJournal
import ThroEngine

/// Following a match live (PD-044) — the wire's lines, the replay into a board, and the words on it —
/// and the sending side: its format, which every phone send had wrong, its seat, and the share switch.
@MainActor
final class MatchWatchTests: XCTestCase {

    // MARK: - the wire

    func testTheSplitterKeepsTheEmptyLinesThatEndEvents() {
        var lines = SSELineSplitter()
        var parser = SSEParser()
        var all: [String] = []
        var events: [StreamEvent] = []
        for byte in Array("id: a\r\nevent: VisitRecorded\ndata: {}\n\n: ping\n\nid: b\ndata: x\n\n".utf8) {
            guard let line = lines.feed(byte) else { continue }
            all.append(line)
            if let event = parser.feed(line) { events.append(event) }
        }
        XCTAssertEqual(all.filter(\.isEmpty).count, 3, "an empty line is a line: it is the one that ends an event")
        XCTAssertEqual(events.map(\.id), ["a", "b"])
        XCTAssertEqual(events.first?.type, "VisitRecorded", "a carriage return before the newline is not part of the line")
        XCTAssertEqual(parser.lastEventId, "b")
    }

    // MARK: - the replay

    /// One leg of 101, straight in, double out, home to throw: three visits make a match.
    private let first101 = MatchOnRecord.Format(startingScore: 101, inRule: "straight", outRule: "double",
                                                legsMode: "first_to", legsTarget: 1, throwFirst: "home")

    /// An event as the stream's data carries it.
    private func event(_ type: String, id: UUID = UUID(), corrects: UUID? = nil, player: String? = nil, total: Int? = nil,
                       ending: String? = nil, seat: String? = nil,
                       at: String? = "2026-09-11T19:31:05.123456+00:00") -> StreamEvent {
        var payload: [String: Any] = [:]
        if let player { payload["player"] = player }
        if let total { payload["visitTotal"] = total }
        if let ending { payload["ending"] = ending }
        if let seat { payload["seat"] = seat }
        var object: [String: Any] = ["eventId": id.uuidString.lowercased(), "deviceId": UUID().uuidString.lowercased(),
                                     "deviceSeq": 1, "type": type, "actorRole": "participant", "payload": payload]
        object["correctsEventId"] = corrects.map { $0.uuidString.lowercased() } ?? NSNull()
        if let at { object["occurredAt"] = at }
        let data = String(decoding: try! JSONSerialization.data(withJSONObject: object), as: UTF8.self)
        return StreamEvent(id: "match:m:1-\(Int.random(in: 1...99_999))", type: type, data: data)
    }

    private func board(_ events: [StreamEvent], yours: String = "home", format: MatchOnRecord.Format? = nil) -> WatchBoard? {
        MatchReplay.board(format: format ?? first101, yours: yours, events: events.compactMap(WatchedEvent.read))
    }

    func testVisitsReplayIntoTheBoardFromTheReadersSide() throws {
        let events = [event("VisitRecorded", player: "home", total: 60), event("VisitRecorded", player: "away", total: 45)]
        let mine = try XCTUnwrap(board(events))
        XCTAssertEqual(mine.yours.needs, 41)
        XCTAssertEqual(mine.theirs.needs, 56)
        XCTAssertTrue(mine.yours.throwing, "home threw first and away has answered: home is on")
        XCTAssertEqual(mine.last?.seat, "away")
        XCTAssertEqual(mine.last?.total, 45)
        let theirs = try XCTUnwrap(board(events, yours: "away"))
        XCTAssertEqual(theirs.yours.needs, 56, "the same log, read from the other seat")
        XCTAssertFalse(theirs.yours.throwing)
    }

    func testARetractionStrikesTheVisitItNamesAndOnlyThat() throws {
        let bust = UUID()
        let b = try XCTUnwrap(board([event("VisitRecorded", player: "home", total: 60),
                                     event("VisitRecorded", player: "away", total: 45),
                                     event("VisitRecorded", id: bust, player: "home", total: 100),
                                     event("VisitRetracted", corrects: bust, player: "home")]))
        XCTAssertEqual(b.visits, 2, "the struck visit is evidence, and counts for nothing")
        XCTAssertEqual(b.yours.needs, 41)
        XCTAssertTrue(b.yours.throwing, "with the bust struck, home throws again")
    }

    func testTheCheckoutWinsTheMatchAndTheBoardSaysSo() throws {
        let b = try XCTUnwrap(board([event("VisitRecorded", player: "home", total: 60),
                                     event("VisitRecorded", player: "away", total: 45),
                                     event("VisitRecorded", player: "home", total: 41)]))
        XCTAssertEqual(b.winner, "home")
        XCTAssertEqual(b.yours.legs, 1)
        XCTAssertFalse(b.yours.throwing || b.theirs.throwing, "nobody throws in a finished match")
        XCTAssertEqual(LiveBoardWords.lastLine(b, them: "Ethan T."), "Your win.")
        XCTAssertEqual(LiveBoardWords.health(.live, board: b), "Finished", "a finished match is not called live, whatever the socket says")
        XCTAssertTrue(LiveBoardWords.finished(b))
    }

    func testARetirementIsWonByTheSeatThatStayed() throws {
        let b = try XCTUnwrap(board([event("VisitRecorded", player: "home", total: 60),
                                     event("MatchEndedShort", ending: "retired", seat: "away")]))
        XCTAssertEqual(b.winner, "home")
        XCTAssertFalse(b.yours.throwing || b.theirs.throwing)
        XCTAssertEqual(LiveBoardWords.lastLine(b, them: "Ethan T."), "They retired, so it is your win.")
    }

    func testAnAbandonmentHasNoWinner() throws {
        let b = try XCTUnwrap(board([event("VisitRecorded", player: "home", total: 60),
                                     event("MatchEndedShort", ending: "abandoned")]))
        XCTAssertNil(b.winner)
        XCTAssertEqual(LiveBoardWords.lastLine(b, them: "Ethan T."), "Abandoned. There is no result.")
    }

    func testWithoutWhoThrewFirstThereIsNoBoardRatherThanAGuess() {
        let unknown = MatchOnRecord.Format(startingScore: 501, inRule: "straight", outRule: "double", legsMode: "first_to", legsTarget: 3)
        XCTAssertNil(board([event("VisitRecorded", player: "home", total: 60)], format: unknown))
        let strange = MatchOnRecord.Format(startingScore: 501, inRule: "straight", outRule: "treble", legsMode: "first_to",
                                           legsTarget: 3, throwFirst: "home")
        XCTAssertNil(board([], format: strange), "an out-rule this build does not know is not replayed as another one")
    }

    func testAnEventThisBuildCannotReadIsSkippedAndAResendLandsOnce() {
        XCTAssertNil(WatchedEvent.read(StreamEvent(id: "x", type: "VisitRecorded", data: "not json")))
        let model = MatchWatchModel()
        let visit = event("VisitRecorded", player: "home", total: 60)
        model.take(visit, format: first101, yours: "home")
        model.take(visit, format: first101, yours: "home")
        XCTAssertEqual(model.board?.visits, 1, "a reconnect that hands an event over twice does not count it twice")
    }

    func testTheLastLineSaysWhoThrewWhat() throws {
        let b = try XCTUnwrap(board([event("VisitRecorded", player: "home", total: 60),
                                     event("VisitRecorded", player: "away", total: 45)]))
        let line = LiveBoardWords.lastLine(b, them: "Ethan T.")
        XCTAssertTrue(line.hasPrefix("Last visit: Ethan T., 45 at "), line)
        XCTAssertEqual(LiveBoardWords.lastLine(try XCTUnwrap(board([])), them: "Ethan T."), "Nothing thrown yet.")
    }

    func testTheHealthWordNeverCallsAFrozenFeedLive() {
        XCTAssertEqual(LiveBoardWords.health(.connecting, board: nil), "Connecting")
        XCTAssertEqual(LiveBoardWords.health(.live, board: nil), "Live")
        XCTAssertEqual(LiveBoardWords.health(.stale, board: nil), "Reconnecting")
        XCTAssertEqual(LiveBoardWords.health(.ended("gone"), board: nil), "Not following")
    }

    // MARK: - the sending side

    private func record(_ mode: StructureMode) -> MatchRecord {
        MatchRecord(id: MatchId(UUID().uuidString), homeName: "Jenson R.", awayName: "Ethan T.", startingScore: 501,
                    inRule: .double, outRule: .master, legsMode: mode, legsTarget: 5, throwFirst: .away,
                    startedAt: Date(), homePlayerId: nil, awayPlayerId: nil, archivedAt: nil)
    }

    func testTheFormatGoesInTheServersWords() {
        let bestOf = MatchUpload.format(for: record(.bestOf))
        XCTAssertEqual(bestOf.legsMode, "best_of", "described, this was `bestof`, and the server took no match a phone sent")
        XCTAssertEqual(MatchUpload.format(for: record(.firstTo)).legsMode, "first_to")
        XCTAssertEqual(bestOf.inRule, "double")
        XCTAssertEqual(bestOf.outRule, "master")
        XCTAssertEqual(bestOf.throwFirst, "away")
        XCTAssertEqual(bestOf.legsTarget, 5)
        XCTAssertEqual(bestOf.startingScore, 501)
    }

    func testTheSeatIsTheOneWhoseNameIsYours() {
        XCTAssertEqual(MatchUpload.seat(of: "Jenson R.", home: "  jenson r. ", away: "Ethan T."), "home")
        XCTAssertEqual(MatchUpload.seat(of: "Ethan T.", home: "Jenson R.", away: "ETHAN T."), "away")
        XCTAssertNil(MatchUpload.seat(of: "Sam", home: "Jenson R.", away: "Ethan T."), "neither is yours, so nothing is filed")
    }

    func testASharedMatchIsRememberedAndOnlyNewRowsAreDue() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "thro-live-share-\(UUID())"))
        let id = MatchId(UUID().uuidString)
        LiveShare(defaults: defaults).set(id, sharing: true)
        XCTAssertTrue(LiveShare(defaults: defaults).isSharing(id), "shared before the phone slept, shared when it wakes")
        LiveShare(defaults: defaults).set(id, sharing: false)
        XCTAssertFalse(LiveShare(defaults: defaults).isSharing(id))
        XCTAssertTrue(LiveShare.due(rows: 3, taken: nil))
        XCTAssertFalse(LiveShare.due(rows: 3, taken: 3))
        XCTAssertTrue(LiveShare.due(rows: 4, taken: 3))
    }
}
