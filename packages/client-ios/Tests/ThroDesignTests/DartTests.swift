import XCTest
import SwiftUI
import ThroTokens
@testable import ThroDesign

/// The dart vocabulary: what a dart is, and what three of them add up to.
///
/// No darts *rules* here — checkability, out rules, busts belong to the engine and this package must
/// not depend on it. What this holds is the alphabet, and the arithmetic that alphabet forces.
final class DartTests: XCTestCase {

    // MARK: - What a dart can be

    func testThereAreSixtyThreeThingsOneDartCanDo() {
        // A miss, twenty singles, twenty doubles, twenty trebles, the 25 and the 50.
        XCTAssertEqual(ThroDart.all.count, 63)
        XCTAssertEqual(Set(ThroDart.all).count, 63, "two entries describe the same dart")
    }

    func testEveryDartScoresWhatTheBoardSaysItScores() {
        XCTAssertEqual(ThroDart.miss.value, 0)
        XCTAssertEqual(ThroDart.single(20)?.value, 20)
        XCTAssertEqual(ThroDart.double(20)?.value, 40)
        XCTAssertEqual(ThroDart.treble(20)?.value, 60)
        XCTAssertEqual(ThroDart.outerBull.value, 25)
        XCTAssertEqual(ThroDart.bull.value, 50)
        XCTAssertEqual(ThroDart.all.map(\.value).max(), ThroDart.maximum)
    }

    func testTheBullIsADoubleAndTheTwentyFiveIsNot() {
        // The 50 is the double of 25, which is why it finishes a leg under double-out and why a
        // dart that lands in it is a dart that landed in a double. Getting this wrong would call a
        // legitimate bull finish a bust.
        XCTAssertTrue(ThroDart.bull.isDouble)
        XCTAssertFalse(ThroDart.outerBull.isDouble)
        XCTAssertTrue(ThroDart.double(16)!.isDouble)
        XCTAssertFalse(ThroDart.treble(20)!.isDouble)
        XCTAssertFalse(ThroDart.single(20)!.isDouble)
        XCTAssertFalse(ThroDart.miss.isDouble)
    }

    func testADartOutsideTheTwentyBedsCannotBeMade() {
        // The type refuses it, so nothing downstream has to.
        XCTAssertNil(ThroDart.single(0))
        XCTAssertNil(ThroDart.single(21))
        XCTAssertNil(ThroDart.double(-1))
        XCTAssertNil(ThroDart.treble(25), "there is no treble 25")
        XCTAssertNil(ThroDart(ring: .bull, sector: 25), "a bull has no sector")
        XCTAssertNil(ThroDart(ring: .miss, sector: 1))
    }

    func testTheKeypadsSectorsAreTheBoardsOrderAndNotOneToTwenty() {
        // A keypad laid out 1-to-20 is a keypad nobody can find a number on: a player looks for 20
        // where it is, between 1 and 5.
        XCTAssertEqual(ThroDart.sectors.count, 20)
        XCTAssertEqual(Set(ThroDart.sectors), Set(1...20))
        XCTAssertEqual(ThroDart.sectors.first, 20)
        let twenty = ThroDart.sectors.firstIndex(of: 20)!
        let neighbours = Set([ThroDart.sectors[(twenty + 1) % 20], ThroDart.sectors[(twenty + 19) % 20]])
        XCTAssertEqual(neighbours, [1, 5], "20 does not sit between 1 and 5")
        XCTAssertNotEqual(ThroDart.sectors, Array(1...20))
    }

    func testEveryDartIsWrittenAndSaidDistinctly() {
        // A scoresheet and a screen reader both have to tell any two darts apart.
        XCTAssertEqual(Set(ThroDart.all.map(\.written)).count, ThroDart.all.count)
        XCTAssertEqual(Set(ThroDart.all.map(\.spoken)).count, ThroDart.all.count)
        XCTAssertEqual(ThroDart.treble(20)!.written, "T20")
        // "T20" read aloud is "tee twenty", which is not a number.
        XCTAssertEqual(ThroDart.treble(20)!.spoken, "treble 20")
        XCTAssertEqual(ThroDart.bull.written, "BULL")
        XCTAssertEqual(ThroDart.miss.spoken, "missed")
    }

    // MARK: - Three darts

    func testAVisitIsThreeDartsAndAFourthIsRefused() {
        var entry = ThroDartEntry()
        for _ in 0..<5 { entry.add(ThroDart.treble(20)!) }
        XCTAssertEqual(entry.darts.count, 3)
        XCTAssertEqual(entry.total, 180)
        XCTAssertTrue(entry.handIsSpent)
    }

    func testTakingOneDartBackTakesBackOneDartAndNotTheVisit() {
        // The undo a player reaches for when they tap D16 for D18.
        var entry = ThroDartEntry([ThroDart.treble(20)!, ThroDart.treble(20)!, ThroDart.double(16)!])
        entry.removeLast()
        XCTAssertEqual(entry.darts.count, 2)
        XCTAssertEqual(entry.total, 120)
        entry.add(ThroDart.double(18)!)
        XCTAssertEqual(entry.written, "T20 T20 D18")
    }

    func testAnEmptyEntryTakesNothingBackRatherThanCrashing() {
        var entry = ThroDartEntry()
        entry.removeLast()
        XCTAssertTrue(entry.isEmpty)
        XCTAssertEqual(entry.total, 0)
        XCTAssertNil(entry.dartsUsed, "a visit of no darts is not a visit")
    }

    func testTheEntryCountsTheDartsPDZeroZeroOneHasBeenAskingPlayersFor() {
        // PD-001 asks "Darts used to check out?" after the fact, because the app has no way to know.
        // A player who entered their darts has already answered, with what they did.
        XCTAssertEqual(ThroDartEntry([ThroDart.double(20)!]).dartsUsed, 1)
        XCTAssertEqual(ThroDartEntry([ThroDart.treble(20)!, ThroDart.double(20)!]).dartsUsed, 2)
        XCTAssertEqual(ThroDartEntry([.miss, .miss, ThroDart.double(1)!]).dartsUsed, 3)
    }

    func testAnEntryIsCappedAtThreeEvenWhenItIsHandedMore() {
        XCTAssertEqual(ThroDartEntry(Array(repeating: ThroDart.bull, count: 9)).darts.count, 3)
        XCTAssertEqual(ThroDartEntry(Array(repeating: ThroDart.bull, count: 9)).total, 150)
    }

    func testTheEntryIsSpokenAsDartsAndThenTheTotal() {
        XCTAssertEqual(ThroDartEntry().spoken, "no darts entered")
        XCTAssertEqual(ThroDartEntry([ThroDart.treble(20)!, ThroDart.single(5)!]).spoken,
                       "treble 20, single 5, 65")
    }

    // MARK: - What three darts can and cannot make

    func testTheReachableTotalsAreDerivedFromTheDartsRatherThanTranscribed() {
        // 172 of the 181 totals in 0...180 are reachable; the nine that are not are the ones every
        // X01 implementation is expected to refuse.
        let inRange = ThroDartEntry.reachableTotals.filter { (0...180).contains($0) }
        XCTAssertEqual(inRange.count, 172)
        XCTAssertEqual(ThroDartEntry.reachableTotals.max(), 180)
        for impossible in [163, 166, 169, 172, 173, 175, 176, 178, 179] {
            XCTAssertFalse(ThroDartEntry.reachableTotals.contains(impossible),
                           "\(impossible) is not a total three darts can make")
        }
    }

    func testOneHundredAndEightyIsThreeTrebleTwentiesAndNothingElse() {
        let ways = ThroDart.all.flatMap { a in
            ThroDart.all.flatMap { b in ThroDart.all.filter { a.value + b.value + $0.value == 180 } .map { (a, b, $0) } }
        }
        XCTAssertEqual(ways.count, 1)
        XCTAssertEqual(ways.first?.0, ThroDart.treble(20)!)
    }

    func testAnEntryCanNeverProduceATotalTheEngineWouldRefuse() {
        // This is the mis-key that per-dart entry removes: every entry's total is, by construction,
        // a total three darts can make.
        for a in ThroDart.all {
            for b in [ThroDart.miss, ThroDart.treble(20)!, ThroDart.bull, ThroDart.double(19)!] {
                let entry = ThroDartEntry([a, b, ThroDart.treble(17)!])
                XCTAssertTrue(ThroDartEntry.reachableTotals.contains(entry.total), entry.written)
            }
        }
    }
}
