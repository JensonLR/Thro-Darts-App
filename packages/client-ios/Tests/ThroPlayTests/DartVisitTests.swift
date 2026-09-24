import XCTest
import ThroDesign
import ThroEngine
import ThroJournal
@testable import ThroPlay

/// Three entered darts, handed to the engine as darts (OD-023).
///
/// The cases below are the ones this file has always held — 141 on `T20 T19 D12` is one dart at a
/// double, not three; 32 on `16 D8` is two — and they now ask the ENGINE. That is the point: the
/// definition the iOS client shipped with and the one the engine enforces must be the same
/// definition, and these are where a difference between them would show.
final class DartVisitTests: XCTestCase {

    // MARK: - The keypad's darts and the engine's

    func testEveryKeypadDartIsTheEnginesDartAndBack() {
        for dart in ThroDart.all {
            let engine = DartVisit.engineDart(dart)
            XCTAssertTrue(engine.isOnTheBoard, dart.written)
            XCTAssertEqual(engine.value, dart.value, dart.written)
            XCTAssertEqual(DartVisit.keypadDart(engine), dart, dart.written)
        }
        XCTAssertEqual(Set(ThroDart.all.map(DartVisit.engineDart)).count, 63)
    }

    func testTheDartsDeriveExactlyTheImpossibleTotalsTheEngineCarries() {
        let derived = Set(0...RuleTables.maxVisitTotal).subtracting(ThroDartEntry.reachableTotals)
        XCTAssertEqual(derived, RuleTables.impossibleVisitTotals)
    }

    func testAnEnteredVisitIsTheDartsThemselves() {
        let entry = ThroDartEntry([ThroDart.treble(20)!, ThroDart.treble(20)!, ThroDart.treble(20)!])
        guard case let .recordDarts(player, darts) = DartVisit.command(entry, player: Seat.home.playerId) else {
            return XCTFail("not a recordDarts")
        }
        XCTAssertEqual(player, Seat.home.playerId)
        XCTAssertEqual(darts, Array(repeating: Dart(20, .treble), count: 3))
    }

    // MARK: - Darts at a double, as the engine counts them

    func testADartIsAtADoubleWhenOneDartCouldFinishFromWhereItStands() {
        // 32 is D16; after the single 16, 16 is D8. Two darts at a double, one of them in.
        let entry = ThroDartEntry([ThroDart.single(16)!, ThroDart.double(8)!])
        XCTAssertEqual(DartVisit.dartsAtDouble(entry, from: 32, outRule: .double), 2)
    }

    func testDartsThrownFromAThreeDartCheckoutAreNotDartsAtADouble() {
        // 141 is a checkout, and the first version of this counted all three darts, because it asked
        // whether the remaining was checkable rather than whether one dart could finish it. Counting
        // three would have made every checkout percentage a third of what it is.
        let entry = ThroDartEntry([ThroDart.treble(20)!, ThroDart.treble(19)!, ThroDart.double(12)!])
        XCTAssertEqual(DartVisit.dartsAtDouble(entry, from: 141, outRule: .double), 1)
    }

    func testAVisitSpentEntirelyOnDoublesCountsEveryDart() {
        // 32 → 16 → 8, missing into the single each time. Three attempts, none in.
        let entry = ThroDartEntry([ThroDart.single(16)!, ThroDart.single(8)!, ThroDart.single(4)!])
        XCTAssertEqual(DartVisit.dartsAtDouble(entry, from: 32, outRule: .double), 3)
    }

    func testNoDartIsAtADoubleFromAScoreNoDartCanReachAFinishFrom() {
        let entry = ThroDartEntry([ThroDart.treble(20)!, ThroDart.treble(20)!, ThroDart.treble(20)!])
        XCTAssertEqual(DartVisit.dartsAtDouble(entry, from: 231, outRule: .double), 0)
        XCTAssertEqual(DartVisit.dartsAtDouble(entry, from: 501, outRule: .double), 0)
    }

    func testDartsEnteredAfterTheVisitWasDecidedAreNotCounted() {
        let entry = ThroDartEntry([ThroDart.double(20)!, ThroDart.double(20)!, ThroDart.double(20)!])
        XCTAssertEqual(DartVisit.dartsAtDouble(entry, from: 40, outRule: .double), 1)
    }

    func testAnEmptyEntryIsUnknownRatherThanZero() {
        XCTAssertNil(DartVisit.dartsAtDouble(ThroDartEntry(), from: 40, outRule: .double))
        XCTAssertFalse(DartVisit.answersThePrompts(ThroDartEntry()))
        XCTAssertTrue(DartVisit.answersThePrompts(ThroDartEntry([ThroDart.double(20)!])))
    }

    func testTheOutRuleDecidesWhatOneDartCanFinish() {
        let entry = ThroDartEntry([ThroDart.treble(20)!])
        XCTAssertEqual(DartVisit.dartsAtDouble(entry, from: 60, outRule: .double), 0)
        XCTAssertEqual(DartVisit.dartsAtDouble(entry, from: 60, outRule: .master), 1)
        XCTAssertEqual(DartVisit.dartsAtDouble(entry, from: 17, outRule: .straight), 1)
        XCTAssertEqual(DartVisit.dartsAtDouble(entry, from: 17, outRule: .double), 0)
    }

    // MARK: - What the engine makes of every entry

    /// Every entry a player can key, from a range of scores, is either accepted or refused as an
    /// unfinished hand — never refused for evidence it supplied, because it supplies none: the engine
    /// derives it. That is the refusal-a-player-cannot-act-on this file used to guard by hand.
    func testEveryEntryIsAcceptedOrIsAnUnfinishedHand() {
        let home = Seat.home.playerId
        let format = MatchFormat(startingScore: 501, inRule: .straight, outRule: .double,
                                 legs: Structure(mode: .bestOf, target: 3), throwFirst: home)
        let base = MatchState.start(format: format, home: home, away: Seat.away.playerId)
        for start in [2, 3, 8, 20, 32, 40, 50, 60, 81, 100, 141, 158, 159, 170, 171, 301, 501] {
            for a in ThroDart.all {
                for entry in [ThroDartEntry([a]),
                              ThroDartEntry([a, ThroDart.treble(20)!]),
                              ThroDartEntry([a, ThroDart.treble(20)!, ThroDart.double(16)!])] {
                    var state = base
                    state.remaining[home] = start
                    let reading = DartVisit.read(entry, from: start, format: format)
                    switch Engine.apply(state, DartVisit.command(entry, player: home)) {
                    case .accepted:
                        XCTAssertNotNil(reading.settled, "\(start) \(entry.written) accepted while open")
                    case let .rejected(reason):
                        XCTAssertEqual(reason, .DARTS_USED_INVALID, "\(start) \(entry.written)")
                        XCTAssertTrue(reading.settled == nil || reading.thrown < entry.darts.count,
                                      "\(start) \(entry.written) refused although it was a whole visit")
                    }
                }
            }
        }
    }

    /// Reaching zero: a legal finish, or the bust it is. No third case, and never a refusal.
    func testEveryEntryThatReachesZeroIsALegalFinishOrABust() {
        for start in RuleTables.oneDartFinishesDouble {
            for dart in ThroDart.all where dart.value == start {
                let r = DartVisit.read(ThroDartEntry([dart]), from: start,
                                       format: MatchFormat(startingScore: 501, inRule: .straight, outRule: .double,
                                                           legs: Structure(mode: .bestOf, target: 3),
                                                           throwFirst: Seat.home.playerId))
                XCTAssertEqual(r.settled, dart.isDouble ? .legWon : .bust, "\(dart.written) from \(start)")
                if !dart.isDouble { XCTAssertEqual(r.bustReason, .NOT_A_FINISHING_DART) }
            }
        }
    }
}
