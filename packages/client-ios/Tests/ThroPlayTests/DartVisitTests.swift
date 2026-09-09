import XCTest
import ThroDesign
import ThroEngine
@testable import ThroPlay

/// Three entered darts becoming the evidence a visit carries.
///
/// The founder asked for per-dart entry on behalf of a player in a local league. What it is worth,
/// beyond the asking, is here: `dartsUsed` and `dartsAtDouble` are **always nil today** unless
/// PD-001 stops the player mid-leg and asks them to remember. Both columns already exist in the
/// journal and are already validated by the engine; nothing was ever filling them from evidence.
final class DartVisitTests: XCTestCase {

    // MARK: - The engine does not move

    func testTheDartsDeriveExactlyTheImpossibleTotalsTheEngineCarriesAsALiteral() {
        // `RuleTables.impossibleVisitTotals` is a hand-written set, and it is the correct one. This
        // derives the same fact from the 63 things a dart can do, so the two hold each other up: a
        // table of impossible totals that nobody re-derives is a table that can rot silently, and
        // this is the single most-missed validation in X01 implementations.
        let derived = Set(0...RuleTables.maxVisitTotal).subtracting(ThroDartEntry.reachableTotals)
        XCTAssertEqual(derived, RuleTables.impossibleVisitTotals)
    }

    func testAnEnteredVisitProducesTheSameCommandATypedTotalDoesApartFromTheEvidence() {
        // The engine scores a visit, not a dart. That is not changing, so what reaches it must be
        // the same command with the same total.
        let entry = ThroDartEntry([ThroDart.treble(20)!, ThroDart.treble(20)!, ThroDart.treble(20)!])
        let command = DartVisit.command(entry, player: Seat.home.playerId, from: 501, outRule: .double)
        guard case let .recordVisit(player, total, used, atDouble) = command else {
            return XCTFail("not a recordVisit")
        }
        XCTAssertEqual(player, Seat.home.playerId)
        XCTAssertEqual(total, 180)
        XCTAssertEqual(used, 3)
        XCTAssertEqual(atDouble, 0, "nobody is on a finish at 501")
    }

    func testEveryEnteredVisitIsOneTheEngineAccepts() {
        // By construction an entry's total is a total three darts can make — so the entry route can
        // never produce the refusal a typed total can.
        for a in ThroDart.all {
            let entry = ThroDartEntry([a, ThroDart.treble(20)!, ThroDart.bull])
            XCTAssertFalse(RuleTables.impossibleVisitTotals.contains(entry.total), entry.written)
            XCTAssertLessThanOrEqual(entry.total, RuleTables.maxVisitTotal)
        }
    }

    // MARK: - Darts at a double

    func testADartIsAtADoubleWhenItIsThrownFromAFinish() {
        // The definition a scorer uses, and the only one observable from an entry: the ring a dart
        // lands in does not say what it was aimed at.
        let entry = ThroDartEntry([ThroDart.single(16)!, ThroDart.double(8)!])
        // 32 is checkable; after the single 16, 16 is checkable too. Two darts at a double, one in.
        XCTAssertEqual(DartVisit.dartsAtDouble(entry, from: 32, outRule: .double), 2)
    }

    func testDartsThrownBeforeThePlayerIsOnAFinishDoNotCount() {
        // 231 → 171 → 111. The double-out checkouts stop at 170, so the first two darts were thrown
        // from numbers no three darts can finish and the third was not.
        let entry = ThroDartEntry([ThroDart.treble(20)!, ThroDart.treble(20)!, ThroDart.treble(20)!])
        XCTAssertEqual(DartVisit.dartsAtDouble(entry, from: 231, outRule: .double), 1)
    }

    func testAWholeVisitThrownFromAFinishCountsAllThree() {
        // 141 → 81 → 24, and every one of those is checkable. 170 is the largest checkout there is,
        // so a 141 start is comfortably a finish and so is everything this visit passes through.
        let entry = ThroDartEntry([ThroDart.treble(20)!, ThroDart.treble(19)!, ThroDart.double(20)!])
        XCTAssertEqual(DartVisit.dartsAtDouble(entry, from: 141, outRule: .double), 3)
    }

    func testAVisitThatNeverReachesAFinishCountsNone() {
        let entry = ThroDartEntry([ThroDart.single(1)!, ThroDart.single(1)!, ThroDart.single(1)!])
        XCTAssertEqual(DartVisit.dartsAtDouble(entry, from: 501, outRule: .double), 0)
    }

    func testDartsEnteredAfterTheVisitWasSettledAreNotCounted() {
        // Once the remaining reaches zero the leg is over; a fourth thing in the entry was not
        // thrown at anything.
        let entry = ThroDartEntry([ThroDart.double(20)!, ThroDart.double(20)!, ThroDart.double(20)!])
        XCTAssertEqual(DartVisit.dartsAtDouble(entry, from: 40, outRule: .double), 1)
    }

    func testAnEmptyEntryCarriesNoEvidenceRatherThanZero() {
        // Zero darts at a double is a claim about a visit that happened. No visit happened.
        let carried = DartVisit.evidence(ThroDartEntry(), from: 40, outRule: .double)
        XCTAssertNil(carried.dartsUsed)
        XCTAssertNil(carried.dartsAtDouble)
        XCTAssertNil(DartVisit.dartsAtDouble(ThroDartEntry(), from: 40, outRule: .double))
        XCTAssertFalse(DartVisit.answersThePrompts(ThroDartEntry()))
    }

    func testTheEvidenceNeverExceedsWhatTheEngineAccepts() {
        // The engine refuses a visit whose dartsAtDouble exceeds its dartsUsed, and a refusal a
        // player cannot act on is a dead end. Walked across every dart and several starting scores.
        for start in [2, 32, 40, 50, 60, 81, 141, 170, 501] {
            for a in ThroDart.all {
                let entry = ThroDartEntry([a, ThroDart.double(1)!, ThroDart.bull])
                let carried = DartVisit.evidence(entry, from: start, outRule: .double)
                XCTAssertEqual(carried.dartsUsed, 3)
                XCTAssertLessThanOrEqual(carried.dartsAtDouble ?? 0, 3, "\(start) \(entry.written)")
                XCTAssertGreaterThanOrEqual(carried.dartsAtDouble ?? 0, 0)
            }
        }
    }

    func testTheOutRuleDecidesWhatCountsAsAFinish() {
        // Under master-out a treble finishes, so numbers the double-out table calls bogeys become
        // checkouts. 159 is one of them — `T20, T13, T20` under master, nothing under double — and
        // it is the reason this walk reads the match's rule rather than assuming double-out.
        let entry = ThroDartEntry([ThroDart.treble(20)!])
        XCTAssertEqual(DartVisit.dartsAtDouble(entry, from: 159, outRule: .double), 0)
        XCTAssertEqual(DartVisit.dartsAtDouble(entry, from: 159, outRule: .master), 1)
        XCTAssertTrue(RuleTables.checkouts(.master).contains(159))
        XCTAssertFalse(RuleTables.checkouts(.double).contains(159),
                       "159 is a double-out bogey; if it stops being one this test is measuring nothing")
    }

    func testEnteringDartsAnswersBothOfPDZeroZeroOnesQuestionsOrNeither() {
        // A half-answered prompt is still a prompt, so this is one decision and not two.
        XCTAssertTrue(DartVisit.answersThePrompts(ThroDartEntry([ThroDart.double(20)!])))
        XCTAssertFalse(DartVisit.answersThePrompts(ThroDartEntry()))
    }
}
