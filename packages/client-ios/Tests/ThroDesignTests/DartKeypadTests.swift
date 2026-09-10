import XCTest
import SwiftUI
import ThroTokens
@testable import ThroDesign

/// The per-dart keypad's arithmetic and labelling.
///
/// A keypad's layout is not a matter of taste when the tray has a fixed height: six rows is what
/// `ThroStage` measured out, and a seventh row would come out of the board. These tests hold the
/// row count, hold every sector to exactly one key, and hold the two orderings the design argues
/// for — the board's sector order, and MISS rather than BULL next to Enter.
final class DartKeypadTests: XCTestCase {

    // MARK: - the six rows

    func testTheKeypadIsSixRows() {
        // 1 ring row + 4 sector rows + 1 bottom row. The tray was measured for six.
        let rows = 1 + DartKeypad.rows.count + 1
        XCTAssertEqual(rows, Int(ThroStage.trayRows),
                       "the dart tray must be exactly as tall as the tray ThroStage measured")
    }

    func testTheSixRowsFitTheSmallestPhoneTheAppRunsOn() {
        let se = StageTests.devices[0]
        XCTAssertEqual(se.name, "iPhone SE (3rd gen)", "the tightest device moved; re-read the arithmetic")
        let safe = se.height - se.portraitInsets.top - se.portraitInsets.bottom
        let stage = ThroStage.choose(width: se.width, height: safe)
        XCTAssertTrue(stage.keysFit(in: safe),
                      "six rows of scoring-height keys and the board must both fit the SE upright")
        XCTAssertEqual(stage.keyHeight, ThroSpacing.touchTargetScoring,
                       "and the keys are the scoring target, not the accessibility floor")
    }

    func testANinthRowWouldCostTheBoardItsNumberAltogether() {
        // Why the dart keypad is not nine rows — a ring row, five rows of sectors, a bull row and
        // Enter — kept as arithmetic so it cannot be re-litigated from memory. On the SE upright
        // there are 647 points of safe area; the six-row tray leaves 161 for the board, which is
        // 68 more than the head of the board needs at the smallest rung. Three more rows take 210
        // points, and what is left is negative.
        let se = StageTests.devices[0]
        let safe = se.height - se.portraitInsets.top - se.portraitInsets.bottom
        let nine = 9 * ThroSpacing.touchTargetScoring + 8 * ThroStage.trayGap + ThroStage.trayPadding
        let headAtTheSmallestRung = ThroStage.headFurniture
            + ThroStage.capBox(ThroTypography.ladder.last ?? 40, textScale: 1)

        XCTAssertGreaterThanOrEqual(safe - ThroStage.rail - ThroStage.trayIdeal, headAtTheSmallestRung,
                                    "six rows must leave the board at least its head")
        XCTAssertLessThan(safe - ThroStage.rail - nine, headAtTheSmallestRung,
                          "a nine-row tray leaves the smallest phone less than the head of the board needs")
    }

    // MARK: - the sectors

    func testEverySectorAppearsExactlyOnce() {
        let flat = DartKeypad.rows.flatMap { $0 }
        XCTAssertEqual(flat.count, 20)
        XCTAssertEqual(Set(flat), Set(1...20))
    }

    func testTheSectorRowsAreFiveWide() {
        XCTAssertEqual(DartKeypad.rows.count, 4)
        for row in DartKeypad.rows { XCTAssertEqual(row.count, 5) }
    }

    func testTheSectorsCountUpAndNotInTheBoardsOrder() {
        // PD-034: zero learning. The first version was the board's clockwise order, which put 20
        // in the top corner. If this fails, somebody has put the board back on the keypad.
        XCTAssertEqual(DartKeypad.rows.flatMap { $0 }, Array(1...20))
        XCTAssertNotEqual(DartKeypad.rows.flatMap { $0 }, ThroDart.sectors)
    }

    func testTheBigFiveAreOnTheBottomSectorRowNearestTheThumb() {
        // 16 to 20 are what most visits are made of; they sit on the last sector row, directly
        // above 25 · BULL · MISS · ENTER, so a scoring thumb rarely leaves the bottom of the tray.
        XCTAssertEqual(DartKeypad.rows.last, [16, 17, 18, 19, 20])
        XCTAssertEqual(DartKeypad.rows.first, [1, 2, 3, 4, 5])
    }

    // MARK: - the bottom row

    func testMissSitsBetweenBullAndEnter() {
        // Enter commits evidence. The key beside it must be the one that costs nothing when a fat
        // thumb catches it: MISS adds zero, BULL would add fifty.
        XCTAssertEqual(DartKeypad.centres.last, ThroDart.miss)
        XCTAssertEqual(DartKeypad.centres, [.outerBull, .bull, .miss])
    }

    func testTheCentresAreTheThreeDartsWithNoSector() {
        for dart in DartKeypad.centres {
            XCTAssertFalse(dart.ring.takesSector, "\(dart.written) has a sector and belongs on the grid")
        }
        // And no sectored dart is duplicated down there.
        XCTAssertTrue(Set(DartKeypad.centres).isDisjoint(with: Set(ThroDart.sectors.map { ThroDart.single($0)! })))
    }

    func testAMissKeySaysWhatPressingItDoes() {
        // `written` renders a miss as an em dash — right on a scoresheet, useless on a key.
        XCTAssertEqual(ThroDart.miss.written, "—")
        XCTAssertEqual(DartKeypad.centreLabel(.miss), "MISS")
        XCTAssertEqual(DartKeypad.centreLabel(.bull), "BULL")
        XCTAssertEqual(DartKeypad.centreLabel(.outerBull), "25")
    }

    // MARK: - the held ring

    func testASectorKeyShowsTheDartItWouldEnter() {
        XCTAssertEqual(DartKeypad.sectorLabel(20, ring: .single), "20")
        XCTAssertEqual(DartKeypad.sectorLabel(20, ring: .double), "D20")
        XCTAssertEqual(DartKeypad.sectorLabel(20, ring: .treble), "T20")
    }

    func testASectorKeyUnderARinglessRingFallsBackToTheBareNumber() {
        // `.bull` takes no sector, so `ThroDart(ring:sector:)` refuses it. The key must still say
        // something rather than render an empty face.
        XCTAssertEqual(DartKeypad.sectorLabel(20, ring: .bull), "20")
    }

    func testOnlyTheHeldRingIsLit() {
        for option in DartKeypad.rings {
            let lighting = DartKeypad.ringLighting(option, held: .double, disabled: false)
            XCTAssertEqual(lighting, option == .double ? .lit : .field)
        }
    }

    func testADisabledRingRowIsSunkenAndNeverDimmed() {
        for option in DartKeypad.rings {
            XCTAssertEqual(DartKeypad.ringLighting(option, held: option, disabled: true), .sunken,
                           "unavailability is a place in the light, never an opacity")
        }
    }

    func testTheRingRowIsTheThreeRingsAPlayerNames() {
        XCTAssertEqual(DartKeypad.rings, [.single, .double, .treble])
        for ring in DartKeypad.rings {
            XCTAssertTrue(ring.takesSector, "a ring on this row must qualify a sector key")
        }
    }

    func testEveryRingHasALabel() {
        for ring in ThroDart.Ring.allCases {
            XCTAssertFalse(DartKeypad.ringLabel(ring).isEmpty)
        }
    }

    // MARK: - Enter

    func testEnterCarriesTheRunningTotal() {
        var entry = ThroDartEntry()
        XCTAssertEqual(DartKeypad.enterLabel(entry, ready: false), "Enter score")
        entry.add(.treble(20)!)
        XCTAssertEqual(DartKeypad.enterLabel(entry, ready: true), "Enter 60")
        entry.add(.treble(20)!)
        entry.add(.treble(20)!)
        XCTAssertEqual(DartKeypad.enterLabel(entry, ready: true), "Enter 180")
    }

    func testAnEnterKeyThatIsNotReadySaysWhatIsMissing() {
        // A key out of the light with nothing to say is a key a player taps twice and then stops
        // trusting. It counts down in darts, which is the unit the player is thinking in.
        var entry = ThroDartEntry()
        entry.add(.treble(20)!)
        XCTAssertEqual(DartKeypad.enterLabel(entry, ready: false), "2 more darts")
        entry.add(.treble(20)!)
        XCTAssertEqual(DartKeypad.enterLabel(entry, ready: false), "One more dart")
    }

    // MARK: - the line of darts on the board

    func testTheDartLineAlwaysHasThreeSlots() {
        var entry = ThroDartEntry()
        XCTAssertEqual(ThroDartLine.slots(entry).count, 3)
        entry.add(.single(5)!)
        XCTAssertEqual(ThroDartLine.slots(entry).count, 3)
        XCTAssertEqual(ThroDartLine.slots(entry).compactMap { $0 }.count, 1)
        entry.add(.single(5)!)
        entry.add(.single(5)!)
        XCTAssertEqual(ThroDartLine.slots(entry).count, 3)
        XCTAssertNil(ThroDartLine.slots(entry).firstIndex(where: { $0 == nil }))
    }

    func testTheFilledSlotsComeFirstAndInTheOrderTheyWereThrown() {
        var entry = ThroDartEntry()
        entry.add(.treble(20)!)
        entry.add(.single(1)!)
        let slots = ThroDartLine.slots(entry)
        XCTAssertEqual(slots[0]?.written, "T20")
        XCTAssertEqual(slots[1]?.written, "1")
        XCTAssertNil(slots[2])
    }
}
