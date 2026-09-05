import XCTest
@testable import ThroStatistics

/// The point of these tests is not that the arithmetic is right — it is that a statistic which
/// cannot be honestly computed **says so**, and that one which is only approximate never presents
/// itself as a fact.
///
/// Ported case for case from packages/statistics/src/test (Kotlin), so both implementations are held
/// to the same twenty assertions.
final class StatisticsTests: XCTestCase {

    private func v(
        _ leg: Int, _ ord: Int, _ total: Int, _ darts: Int? = 3,
        _ before: Int, _ after: Int, won: Bool = false, bust: Bool = false,
        atDouble: Int? = nil
    ) -> VisitRecord {
        VisitRecord(legOrdinal: leg, visitOrdinal: ord, visitTotal: total, dartsUsed: darts, bust: bust,
                    remainingBefore: before, remainingAfter: after, wonLeg: won, dartsAtDouble: atDouble)
    }

    /// Double-out checkout numbers: everything to 170 except the seven bogeys.
    private let checkable: Set<Int> = Set(2...170).subtracting([159, 162, 163, 165, 166, 168, 169])

    /// A 501 leg won in 15 darts: 180, 180, 141 with the last visit using all three darts.
    private func nineDartLeg(darts: Int? = 3) -> [VisitRecord] {
        [
            v(1, 1, 180, 3, 501, 321),
            v(1, 2, 180, 3, 321, 141),
            v(1, 3, 141, darts, 141, 0, won: true),
        ]
    }

    func testNeverStandingOnAFinishIsReportedDifferentlyFromNotHavingSaid() {
        // A player who was never on a finish threw no darts at a double. Telling them their
        // attempts "were not recorded" describes missing evidence that does not exist.
        let neverOnAFinish = [v(1, 1, 60, 3, 501, 441), v(1, 2, 60, 3, 441, 381)]
        let a = Statistics.doublesAttempted(neverOnAFinish, checkable: checkable)
        XCTAssertEqual(a.basis, .unavailable)
        XCTAssertTrue(a.note!.contains("finishable"), "wrong reason given: \(a.note!)")

        let onAFinishButSilent = [v(1, 1, 20, 3, 40, 20)]
        let b = Statistics.doublesAttempted(onAFinishButSilent, checkable: checkable)
        XCTAssertEqual(b.basis, .unavailable)
        XCTAssertTrue(b.note!.contains("recorded"), "wrong reason given: \(b.note!)")
    }

    func testDoublesAttemptedDoesNotReportAPartialCountAsAMatchTotal() {
        // Two visits stood on a finish; only one said how many darts it threw at a double. The
        // recorded sum is 2, but the match total is not 2 — reporting it as exact would state a
        // partial count as a fact.
        let visits = [
            v(1, 1, 20, 3, 40, 20, atDouble: 2),                 // recorded
            v(1, 2, 20, 2, 20, 0, won: true, atDouble: nil),     // on a finish, did not say
        ]
        let s = Statistics.doublesAttempted(visits, checkable: checkable)
        XCTAssertEqual(s.basis, .bounded)
        XCTAssertEqual(s.lower, 3.0)   // the winning visit threw at least one
        XCTAssertEqual(s.upper, 5.0)   // and at most three
        XCTAssertNil(s.value, "a bounded figure must not also carry a point value")
    }

    func testABoundedCheckoutPercentageCanNeverExceed100Percent() {
        // A leg-winning visit whose attempts went unrecorded still counts as a hit. If the bound
        // ignores that it also threw at least one dart at a double, the numerator grows while the
        // denominator does not, and the upper bound climbs past 100% — a figure the quantity
        // cannot take. Under double-out the winning dart IS a double, so that attempt is known to
        // have happened even when its count was not recorded.
        let visits = [
            v(1, 1, 20, 3, 40, 20, atDouble: 1),                 // recorded miss
            v(1, 2, 20, 2, 20, 0, won: true, atDouble: nil),     // won, attempts unrecorded
            v(2, 1, 40, 2, 40, 0, won: true, atDouble: nil),     // won, attempts unrecorded
        ]
        let s = Statistics.checkoutPercentage(visits, checkable: checkable)
        XCTAssertEqual(s.basis, .bounded)
        XCTAssertNotNil(s.upper)
        XCTAssertLessThanOrEqual(s.upper!, 100.0, "upper bound was \(s.upper!)%")
        XCTAssertLessThanOrEqual(s.lower!, s.upper!, "bounds inverted")
    }

    func testBoundsHoldAcrossEveryMixtureOfRecordedAndUnrecordedAttempts() {
        // Exhaustive over small shapes: whatever the unrecorded visits actually threw, the true
        // percentage must lie inside the reported interval, and the interval must stay in range.
        var checked = 0
        for wins in 0...3 {
            for misses in 0...3 {
                for unrecordedWins in 0...wins {
                    let recordedWins = wins - unrecordedWins
                    var visits: [VisitRecord] = []
                    for i in 0..<recordedWins { visits.append(v(i + 1, 1, 40, 2, 40, 0, won: true, atDouble: 1)) }
                    for i in 0..<unrecordedWins { visits.append(v(100 + i, 1, 40, 2, 40, 0, won: true)) }
                    for i in 0..<misses { visits.append(v(200 + i, 1, 20, 3, 40, 20, atDouble: 1)) }

                    let s = Statistics.checkoutPercentage(visits, checkable: checkable)
                    if s.basis == .unavailable { continue }
                    checked += 1
                    let lo = s.lower ?? s.value!
                    let hi = s.upper ?? s.value!
                    XCTAssertLessThanOrEqual(hi, 100.0 + 1e-9, "upper \(hi)% out of range for w=\(wins) m=\(misses) u=\(unrecordedWins)")
                    XCTAssertGreaterThanOrEqual(lo, 0.0, "lower \(lo)% out of range")
                    XCTAssertLessThanOrEqual(lo, hi + 1e-9, "bounds inverted for w=\(wins) m=\(misses) u=\(unrecordedWins)")
                    // the truth, for every attempt count the unrecorded visits could have had
                    let known = recordedWins + misses
                    if unrecordedWins * 3 >= unrecordedWins {
                        for extra in unrecordedWins...(unrecordedWins * 3) {
                            let truth = Double(wins) * 100 / Double(known + extra)
                            XCTAssertTrue(
                                truth >= lo - 1e-9 && truth <= hi + 1e-9,
                                "true \(truth)% escapes [\(lo), \(hi)] for w=\(wins) m=\(misses) u=\(unrecordedWins) extra=\(extra)"
                            )
                        }
                    }
                }
            }
        }
        XCTAssertGreaterThan(checked, 20, "only \(checked) shapes exercised")
    }

    func testCheckoutPercentageCountsAttemptsFromVisitsThatDidNotFinish() {
        // This is the correction that makes the figure computable at all. A player on 40 who throws
        // a single 20 and misses has attempted a double; asking only on a successful checkout would
        // never record it, and the percentage would be silently inflated.
        let visits = [
            v(1, 1, 180, 3, 501, 321),
            v(1, 2, 180, 3, 321, 141),
            v(1, 3, 101, 3, 141, 40, atDouble: 0),               // 141 is itself a finish; set up instead
            v(1, 4, 20, 3, 40, 20, atDouble: 1),                  // on a finish, missed
            v(1, 5, 20, 2, 20, 0, won: true, atDouble: 2),        // on a finish, hit on the second
        ]
        let s = Statistics.checkoutPercentage(visits, checkable: checkable)
        XCTAssertEqual(s.basis, .exact)
        XCTAssertEqual(s.evidenceLevel, .dartLevel)
        // one leg won from three darts thrown at a double
        XCTAssertEqual(s.value!, 100.0 / 3, accuracy: 0.001)
        XCTAssertEqual(s.sampleSize, 3)
    }

    func testAskingOnlyOnASuccessfulCheckoutWouldOverstateThePercentage() {
        let full = [
            v(1, 1, 180, 3, 501, 321), v(1, 2, 180, 3, 321, 141),
            v(1, 3, 101, 3, 141, 40, atDouble: 0),
            v(1, 4, 20, 3, 40, 20, atDouble: 1),
            v(1, 5, 20, 2, 20, 0, won: true, atDouble: 1),
        ]
        // the same match, if the missed attempt had never been asked about
        let winnerOnly = full.map { $0.wonLeg ? $0 : $0.with(dartsAtDouble: nil) }
        let honest = Statistics.checkoutPercentage(full, checkable: checkable).value!
        let inflated = Statistics.checkoutPercentage(winnerOnly, checkable: checkable)
        // the incomplete version cannot report a point value at all — it is bounded
        XCTAssertEqual(inflated.basis, .bounded)
        XCTAssertNil(inflated.value)
        // and its upper bound is exactly the overstatement the old rule would have published
        XCTAssertGreaterThan(inflated.upper!, honest, "\(inflated.upper!) should exceed \(honest)")
        XCTAssertTrue(honest >= inflated.lower! && honest <= inflated.upper!)
    }

    func testAMatchThatRecordedNoDoubleAttemptsSaysSoRatherThanGuessing() {
        let visits = [
            v(1, 1, 180, 3, 501, 321),
            v(1, 2, 101, 3, 321, 220),
            v(1, 3, 180, 3, 220, 40),
            v(1, 4, 40, 1, 40, 0, won: true),   // finished, but attempts never recorded
        ]
        let s = Statistics.checkoutPercentage(visits, checkable: checkable)
        XCTAssertEqual(s.basis, .unavailable)
        XCTAssertNil(s.value)
        XCTAssertTrue(s.note!.contains("darts were thrown at a double"))
    }

    func testDoublesAttemptedIsExactOverTheVisitsThatRecordedIt() {
        let visits = [
            v(1, 1, 20, 3, 40, 20, atDouble: 1),
            v(1, 2, 20, 2, 20, 0, won: true, atDouble: 2),
        ]
        XCTAssertEqual(Statistics.doublesAttempted(visits, checkable: checkable).value, 3.0)
        XCTAssertEqual(Statistics.doublesAttempted(visits, checkable: checkable).basis, .exact)
    }

    func testThreeDartAverageIsExactWhenTheWinningVisitRecordedItsDarts() {
        let s = Statistics.threeDartAverage(nineDartLeg(darts: 3))
        XCTAssertEqual(s.basis, .exact)
        // 501 scored across 9 darts = 167.0
        XCTAssertEqual(s.value!, 167.0, accuracy: 0.001)
    }

    func testThreeDartAverageIsBoundedNotAPointValueWhenDartsUsedIsUnknown() {
        let s = Statistics.threeDartAverage(nineDartLeg(darts: nil))
        XCTAssertEqual(s.basis, .bounded)
        XCTAssertNil(s.value)          // must NOT present a single number
        XCTAssertNotNil(s.lower)
        XCTAssertNotNil(s.upper)
        // 501 over 9 darts (all three used) up to 501 over 7 darts (one used)
        XCTAssertEqual(s.lower!, 167.0, accuracy: 0.001)
        XCTAssertEqual(s.upper!, 501.0 * 3 / 7, accuracy: 0.001)
        XCTAssertGreaterThan(s.upper!, s.lower!)
        XCTAssertTrue(s.note!.contains("did not record"))
    }

    func testTheUnknownDartsIntervalBracketsTheTruth() {
        // the same leg, computed exactly, must fall inside the bounded version's range
        let exact = Statistics.threeDartAverage(nineDartLeg(darts: 3)).value!
        let bounded = Statistics.threeDartAverage(nineDartLeg(darts: nil))
        XCTAssertTrue(exact >= bounded.lower! && exact <= bounded.upper!,
                      "\(exact) outside [\(bounded.lower!), \(bounded.upper!)]")
    }

    func testAssumingThreeDartsUnderstatesTheAverageWhichIsWhyTheFieldIsCaptured() {
        // a 501 leg won in 13 darts: 180, 180, 141 with the last visit using one dart
        let visits = [
            v(1, 1, 180, 3, 501, 321),
            v(1, 2, 180, 3, 321, 141),
            v(1, 3, 141, 1, 141, 0, won: true),
        ]
        let truth = Statistics.threeDartAverage(visits).value!               // 501 over 7 darts
        let assumed = Statistics.threeDartAverage(nineDartLeg(darts: 3)).value!  // 501 over 9 darts
        XCTAssertGreaterThan(truth, assumed)
        let understatementPct = (truth - assumed) / truth * 100
        XCTAssertGreaterThan(understatementPct, 20, "understated by only \(understatementPct)%")
    }

    func testABustVisitCountsItsDartsButContributesNothing() {
        let visits = [
            v(1, 1, 180, 3, 501, 321),
            v(1, 2, 100, 3, 321, 321, bust: true),   // busted: remaining unchanged
            v(1, 3, 180, 3, 321, 141),
            v(1, 4, 141, 3, 141, 0, won: true),
        ]
        let s = Statistics.threeDartAverage(visits)
        XCTAssertEqual(s.basis, .exact)
        // 501 scored over 12 darts — the bust drags the average down, correctly
        XCTAssertEqual(s.value!, 501.0 * 3 / 12, accuracy: 0.001)
        XCTAssertLessThan(s.value!, 167.0, "a bust must lower the average, not be discarded")
    }

    func testMaximumsAndScoreBandsAreExact() {
        let visits = nineDartLeg()
        XCTAssertEqual(Statistics.maximums(visits).value, 2.0)
        XCTAssertEqual(Statistics.maximums(visits).basis, .exact)
        XCTAssertEqual(Statistics.scoresAtLeast(visits, threshold: 100).value, 3.0)
        XCTAssertEqual(Statistics.scoresAtLeast(visits, threshold: 180).value, 2.0)
    }

    func testHighestCheckoutIsTheRemainingFinishedFrom() {
        let s = Statistics.highestCheckout(nineDartLeg())
        XCTAssertEqual(s.basis, .exact)
        XCTAssertEqual(s.value, 141.0)
    }

    func testFirstNineDisclosesTheLegsItExcluded() {
        let visits = nineDartLeg() + [
            // a second leg decided in two visits: no first nine
            v(2, 1, 180, 3, 501, 321),
            v(2, 2, 321, 3, 321, 0, won: true),
        ]
        let s = Statistics.firstNineAverage(visits)
        XCTAssertEqual(s.basis, .exact)
        XCTAssertEqual(s.sampleSize, 1)
        XCTAssertNotNil(s.note)
        XCTAssertTrue(s.note!.contains("excluded"), s.note!)
    }

    func testFinishRateFromACheckablePositionIsExactAndIsNotCheckoutPercentage() {
        let visits = [
            v(1, 1, 180, 3, 501, 321),
            v(1, 2, 180, 3, 321, 141),
            v(1, 3, 141, 3, 141, 0, won: true),   // opened checkable, took it
            v(2, 1, 180, 3, 501, 321),
            v(2, 2, 200, 3, 321, 121),
            v(2, 3, 60, 3, 121, 61),              // opened checkable, missed it
        ]
        let s = Statistics.finishRateFromCheckablePosition(visits, checkable: checkable)
        XCTAssertEqual(s.basis, .exact)
        XCTAssertEqual(s.sampleSize, 2)
        XCTAssertEqual(s.value, 50.0)
        // it remains a DIFFERENT quantity from checkout percentage: this counts visits that opened
        // on a finish, that counts darts thrown at a double. Both are real; they are not the same.
        let withAttempts = visits.map { checkable.contains($0.remainingBefore) ? $0.with(dartsAtDouble: 3) : $0 }
        let co = Statistics.checkoutPercentage(withAttempts, checkable: checkable)
        XCTAssertEqual(co.basis, .exact)
        XCTAssertGreaterThan(abs(co.value! - s.value!), 1.0, "the two measures should not coincide here")
    }

    func testBestLegIsMeasuredInVisitsBecauseDartsAreNotAlwaysKnown() {
        let s = Statistics.bestLegInVisits(nineDartLeg())
        XCTAssertEqual(s.basis, .exact)
        XCTAssertEqual(s.value, 3.0)
    }

    func testAnEmptyHistoryReportsUnavailableRatherThanZero() {
        for s in [
            Statistics.threeDartAverage([]),
            Statistics.firstNineAverage([]),
            Statistics.highestCheckout([]),
            Statistics.bestLegInVisits([]),
        ] {
            XCTAssertEqual(s.basis, .unavailable)
            XCTAssertNil(s.value)
            XCTAssertNotNil(s.note)
        }
    }

    func testEveryUnavailableStatisticExplainsItselfInWordsAPlayerCanActOn() {
        let unavailable = [
            Statistics.checkoutPercentage([], checkable: checkable),
            Statistics.doublesAttempted([], checkable: checkable),
            Statistics.threeDartAverage([]),
        ]
        for s in unavailable {
            XCTAssertNotNil(s.note, "an unavailable statistic with no explanation is a dead end")
            let note = s.note!
            // a proxy for "this is a sentence a player can act on", not an arbitrary bar:
            // a three-word fragment tells someone nothing about what to do next
            XCTAssertGreaterThanOrEqual(note.split(separator: " ").count, 6, "explanation too terse: \(note)")
            XCTAssertTrue(note.first!.isUppercase && note.hasSuffix("."),
                          "explanations are sentences, not codes: \(note)")
        }
    }
}
