import XCTest
import ThroDesign
import ThroEngine
import ThroJournal
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

    func testTheOneDartFinishesAreDerivedAndMatchTheLiteralTheEngineCarries() {
        // The derived set and the engine's hand-written one hold each other up. If a route ever
        // changes so that some number stops being finishable in one dart, exactly one of these two
        // moves and this fails — which is the only reason to keep a literal at all.
        XCTAssertEqual(DartVisit.oneDartFinishes[.double], RuleTables.oneDartFinishesDouble)
        XCTAssertEqual(DartVisit.oneDartFinishes[.double]?.count, 21, "twenty doubles and the bull")
        XCTAssertTrue(DartVisit.oneDartFinishes[.double]?.allSatisfy { $0 == 50 || ($0 % 2 == 0 && $0 <= 40) } ?? false)
    }

    func testADartIsAtADoubleWhenOneDartCouldFinishFromWhereItStands() {
        // The definition a scorer uses, and the only one observable from an entry: the ring a dart
        // lands in does not say what it was aimed at.
        let entry = ThroDartEntry([ThroDart.single(16)!, ThroDart.double(8)!])
        // 32 is D16; after the single 16, 16 is D8. Two darts at a double, one of them in.
        XCTAssertEqual(DartVisit.dartsAtDouble(entry, from: 32, outRule: .double), 2)
    }

    func testDartsThrownFromAThreeDartCheckoutAreNotDartsAtADouble() {
        // **The correction.** 141 is a checkout — `T20, T19, D12` — and the first version of this
        // counted all three of its darts, because it asked whether the remaining was checkable
        // rather than whether one dart could finish it. A player asked "darts at a double?" after
        // that visit answers one, and `Statistics.checkoutPercentage` divides leg wins by the sum
        // of this column, so counting three would have made every checkout look a third as good.
        let entry = ThroDartEntry([ThroDart.treble(20)!, ThroDart.treble(19)!, ThroDart.double(12)!])
        XCTAssertEqual(DartVisit.dartsAtDouble(entry, from: 141, outRule: .double), 1)
        XCTAssertTrue(RuleTables.checkouts(.double).contains(141),
                      "141 must still be a checkout, or this test is measuring nothing")
        XCTAssertTrue(RuleTables.checkouts(.double).contains(81))
    }

    func testDartsThrownBeforeThePlayerIsAnywhereNearADoubleDoNotCount() {
        // 231 → 171 → 111 → 51. Not one of those is a number a single dart can finish.
        let entry = ThroDartEntry([ThroDart.treble(20)!, ThroDart.treble(20)!, ThroDart.treble(20)!])
        XCTAssertEqual(DartVisit.dartsAtDouble(entry, from: 231, outRule: .double), 0)
    }

    func testAVisitSpentEntirelyOnDoublesCountsEveryDart() {
        // 32 → 16 → 8, missing into the single each time. Three attempts, none in — the case that
        // makes checkout percentage mean anything, and the case a leg-won count alone cannot see.
        let entry = ThroDartEntry([ThroDart.single(16)!, ThroDart.single(8)!, ThroDart.single(4)!])
        XCTAssertEqual(DartVisit.dartsAtDouble(entry, from: 32, outRule: .double), 3)
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

    func testTheOutRuleDecidesWhatOneDartCanFinish() {
        // Under master-out a treble finishes, so 60 is a one-dart finish (`T20`) where under
        // double-out it is two (`20, D20`). That is why this walk reads the match's own rule
        // instead of assuming double-out.
        let entry = ThroDartEntry([ThroDart.treble(20)!])
        XCTAssertEqual(DartVisit.dartsAtDouble(entry, from: 60, outRule: .double), 0)
        XCTAssertEqual(DartVisit.dartsAtDouble(entry, from: 60, outRule: .master), 1)
        XCTAssertEqual(RuleTables.route(60, .master)?.count, 1,
                       "60 must still be a one-dart master finish or this test is measuring nothing")
        XCTAssertEqual(RuleTables.route(60, .double)?.count, 2)
        // Straight-out finishes on anything, so every single is one dart.
        XCTAssertEqual(DartVisit.dartsAtDouble(entry, from: 17, outRule: .straight), 1)
        XCTAssertEqual(DartVisit.dartsAtDouble(entry, from: 17, outRule: .double), 0)
    }

    // MARK: - The engine's own rules, held from this side

    func testAOneDartFinishIsUnreachableFromAnythingThreeDartsCannotFinish() {
        // `evidence` floors dartsAtDouble at zero from a non-checkout, because the engine calls
        // attempts claimed from there "evidence that cannot have happened". This proves the floor is
        // never load-bearing: from every start no three darts can finish, no run of one or two darts
        // can put the player on a number one dart could finish. If that ever stops being true, the
        // walk and the floor disagree — and the floor would be hiding it.
        let values = Set(ThroDart.all.map(\.value))
        for outRule in [OutRule.double, .master, .straight] {
            let checkouts = RuleTables.checkouts(outRule)
            let oneDart = DartVisit.oneDartFinishes[outRule] ?? []
            // Why 180 is far enough to walk: the largest one-dart finish is 60, and two darts take
            // at most 120 off, so nothing above 180 can reach one inside a visit.
            XCTAssertLessThanOrEqual(oneDart.max() ?? 0, 60, "\(outRule)")
            for start in 2...RuleTables.maxVisitTotal where !checkouts.contains(start) {
                XCTAssertFalse(oneDart.contains(start), "\(outRule) \(start)")
                for a in values where start - a > 1 {
                    XCTAssertFalse(oneDart.contains(start - a), "\(outRule) \(start) after \(a)")
                    for b in values where start - a - b > 1 {
                        XCTAssertFalse(oneDart.contains(start - a - b),
                                       "\(outRule) \(start) after \(a) and \(b)")
                    }
                }
            }
        }
    }

    func testOnlyALegWinningVisitCarriesFewerThanThreeDarts() {
        // `Engine.recordVisit` rejects DARTS_USED_INVALID for any visit that did not win the leg and
        // claims fewer than three darts — including a bust, whose convention is that it consumed the
        // whole hand. So a two-dart entry that neither finishes nor busts carries nil, not two.
        let two = ThroDartEntry([ThroDart.treble(20)!, ThroDart.treble(20)!])
        XCTAssertEqual(two.dartsUsed, 2, "the entry knows what it holds")
        XCTAssertNil(DartVisit.evidence(two, from: 501, outRule: .double).dartsUsed,
                     "…and the record does not claim it, because the engine would refuse it")

        // A finish may. 40 → D20 is one dart and one leg.
        let one = ThroDartEntry([ThroDart.double(20)!])
        XCTAssertEqual(DartVisit.evidence(one, from: 40, outRule: .double).dartsUsed, 1)
        XCTAssertEqual(DartVisit.evidence(one, from: 40, outRule: .double).dartsAtDouble, 1)

        // A bust after one dart records nil: one is the observed count, three is the engine's
        // convention, and nil is the only one of the three the record can stand behind.
        let bust = ThroDartEntry([ThroDart.double(20)!])
        XCTAssertTrue(DartVisit.settles(bust, from: 20, outRule: .double))
        XCTAssertNil(DartVisit.evidence(bust, from: 20, outRule: .double).dartsUsed)
    }

    func testEveryEvidencePairThisProducesIsOneTheEngineAccepts() {
        // The claim that matters, walked rather than argued: take a real match state, apply the
        // command an entry produces, and assert it is never refused for its evidence.
        let home = Seat.home.playerId
        let format = MatchFormat(startingScore: 501, inRule: .straight, outRule: .double,
                                 legs: Structure(mode: .bestOf, target: 3), throwFirst: home)
        let base = MatchState.start(format: format, home: home, away: Seat.away.playerId)
        XCTAssertEqual(base.thrower, home, "the walk below assumes home is throwing")
        for start in [2, 3, 8, 20, 32, 40, 50, 60, 81, 100, 141, 158, 170, 171, 301, 501] {
            for a in ThroDart.all {
                for entry in [ThroDartEntry([a]),
                              ThroDartEntry([a, ThroDart.treble(20)!]),
                              ThroDartEntry([a, ThroDart.treble(20)!, ThroDart.double(16)!])] {
                    var state = base
                    state.remaining[home] = start
                    // An entry that reaches zero on a dart that cannot end the leg never gets this
                    // far: `MatchSession` refuses it and names the dart. Everything else must
                    // produce evidence the engine accepts.
                    if DartVisit.illegalFinish(entry, from: start, outRule: .double) != nil { continue }
                    let command = DartVisit.command(entry, player: home, from: start, outRule: .double)
                    if case let .rejected(reason) = Engine.apply(state, command) {
                        XCTAssertNotEqual(reason, .DARTS_USED_INVALID, "\(start) \(entry.written)")
                        XCTAssertNotEqual(reason, .DARTS_AT_DOUBLE_INVALID, "\(start) \(entry.written)")
                    }
                }
            }
        }
    }

    func testADartThatCannotEndTheLegIsCaughtBeforeTheEngineSeesIt() {
        // **What per-dart entry can see and a visit total cannot.** On 60 a `T20` reaches zero on a
        // treble, which under double-out is a bust and not a checkout. The engine scores a visit,
        // so all it can ask is whether 60 was finishable — it is — and left to itself it answers
        // two ways for one situation: it rejects this one (dartsAtDouble comes out 0) and accepts
        // `20` from 20 as a leg won, because 20 is D10 and the dart was thrown from a one-dart
        // finish. Both are refused here, before either reaches it.
        XCTAssertEqual(DartVisit.illegalFinish(ThroDartEntry([ThroDart.treble(20)!]),
                                               from: 60, outRule: .double)?.written, "T20")
        XCTAssertEqual(DartVisit.illegalFinish(ThroDartEntry([ThroDart.single(20)!]),
                                               from: 20, outRule: .double)?.written, "20")
        // A real finish is not touched.
        XCTAssertNil(DartVisit.illegalFinish(ThroDartEntry([ThroDart.double(10)!]),
                                             from: 20, outRule: .double))
        // Nor is a visit that does not reach zero, however it ends.
        XCTAssertNil(DartVisit.illegalFinish(ThroDartEntry([ThroDart.treble(20)!]),
                                             from: 100, outRule: .double))
        // Nor a bust below zero, which the engine can see for itself.
        XCTAssertNil(DartVisit.illegalFinish(ThroDartEntry([ThroDart.treble(20)!]),
                                             from: 40, outRule: .double))
    }

    func testAZeroReachedFromABogeyIsLeftToTheEngineToBust() {
        // 159 is a double-out bogey, so reaching zero from it is `NOT_CHECKOUT_POSSIBLE` — a bust
        // the app records correctly today. Refusing it here would take that away, so this only
        // speaks where the engine would otherwise call it a leg won.
        let entry = ThroDartEntry([ThroDart.treble(20)!, ThroDart.treble(13)!, ThroDart.treble(20)!])
        XCTAssertEqual(entry.total, 159)
        XCTAssertFalse(RuleTables.checkouts(.double).contains(159),
                       "159 must still be a bogey or this test is measuring nothing")
        XCTAssertNil(DartVisit.illegalFinish(entry, from: 159, outRule: .double))
        // The same darts under master-out, where 159 IS a checkout and a treble MAY end it.
        XCTAssertTrue(RuleTables.checkouts(.master).contains(159))
        XCTAssertNil(DartVisit.illegalFinish(entry, from: 159, outRule: .master))
        // And a master-out finish on a single, which is not allowed: 60 is `T20` under master.
        let singles = ThroDartEntry([ThroDart.single(20)!, ThroDart.single(20)!, ThroDart.single(20)!])
        XCTAssertTrue(RuleTables.checkouts(.master).contains(60))
        XCTAssertEqual(DartVisit.illegalFinish(singles, from: 60, outRule: .master)?.written, "20")
        XCTAssertNil(DartVisit.illegalFinish(singles, from: 60, outRule: .straight),
                     "straight-out ends on anything that scores")
    }

    func testTheOutRuleDecidesWhichDartsMayEndALeg() {
        XCTAssertTrue(DartVisit.mayFinish(.double(20)!, outRule: .double))
        XCTAssertTrue(DartVisit.mayFinish(.bull, outRule: .double), "the bull is a double")
        XCTAssertFalse(DartVisit.mayFinish(.outerBull, outRule: .double), "the 25 is not")
        XCTAssertFalse(DartVisit.mayFinish(.treble(20)!, outRule: .double))
        XCTAssertTrue(DartVisit.mayFinish(.treble(20)!, outRule: .master))
        XCTAssertFalse(DartVisit.mayFinish(.single(20)!, outRule: .master))
        XCTAssertTrue(DartVisit.mayFinish(.single(20)!, outRule: .straight))
        XCTAssertFalse(DartVisit.mayFinish(.miss, outRule: .straight), "a miss reaches nothing")
    }

    func testEveryEntryThatReachesZeroIsEitherALegalFinishOrNamedAsNotOne() {
        // No third case: an entry that finishes is one the engine may have, or one the player is
        // told about. Walked over every dart from every one-dart finish under double-out.
        for start in RuleTables.oneDartFinishesDouble {
            for dart in ThroDart.all where dart.value == start {
                let entry = ThroDartEntry([dart])
                let illegal = DartVisit.illegalFinish(entry, from: start, outRule: .double)
                XCTAssertEqual(illegal == nil, dart.isDouble,
                               "\(dart.written) from \(start)")
            }
        }
    }

    func testEnteringDartsAnswersBothOfPDZeroZeroOnesQuestionsOrNeither() {
        // A half-answered prompt is still a prompt, so this is one decision and not two.
        XCTAssertTrue(DartVisit.answersThePrompts(ThroDartEntry([ThroDart.double(20)!])))
        XCTAssertFalse(DartVisit.answersThePrompts(ThroDartEntry()))
    }
}
