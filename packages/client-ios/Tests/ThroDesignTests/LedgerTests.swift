import XCTest
import SwiftUI
@testable import ThroDesign

/// The ledger is a chalkboard, and a chalkboard strikes. When a visit goes on, the remainder it
/// replaces gets one line through it and stays legible under it; the newest remainder — the one on
/// the board — is the one figure in the column with no line through it. Retractions are still
/// scraped, in the board's own colour; they are a different thing and look it.
final class LedgerTests: XCTestCase {

    private func row(_ id: String, seat: Int, total: Int, left: Int?, struck: Bool = false) -> ThroLedgerRow {
        ThroLedgerRow(id: id, seat: seat, legOrdinal: 1, visitTotal: total, remainingAfter: left, struck: struck)
    }

    func testTheLastRemainderStandsAndEveryEarlierOneIsStruck() {
        let rows = [row("1", seat: 0, total: 60, left: 441), row("2", seat: 1, total: 45, left: 456),
                    row("3", seat: 0, total: 100, left: 341), row("4", seat: 1, total: 26, left: 430)]
        XCTAssertEqual(ThroLedger.standing(rows, seat: 0), "3")
        XCTAssertEqual(ThroLedger.standing(rows, seat: 1), "4")
        XCTAssertTrue(ThroLedger.isSuperseded(rows[0], in: rows), "441 was written over by 341")
        XCTAssertFalse(ThroLedger.isSuperseded(rows[2], in: rows), "341 is what is on the board")
        XCTAssertTrue(ThroLedger.isSuperseded(rows[1], in: rows))
        XCTAssertFalse(ThroLedger.isSuperseded(rows[3], in: rows))
    }

    func testARetractedRowNeverStandsAndTheRowBeforeItStandsAgain() {
        // 60 → 441, then 100 → 341, then the 100 is retracted: 441 is back on the board, so it is
        // not struck; the retracted row is scraped and is not "superseded" either — it is a
        // different mark, not two marks at once.
        let rows = [row("1", seat: 0, total: 60, left: 441), row("2", seat: 0, total: 100, left: 341, struck: true)]
        XCTAssertEqual(ThroLedger.standing(rows, seat: 0), "1")
        XCTAssertFalse(ThroLedger.isSuperseded(rows[0], in: rows))
        XCTAssertFalse(ThroLedger.isSuperseded(rows[1], in: rows))
    }

    func testASeatWithNoVisitsHasNothingStanding() {
        XCTAssertNil(ThroLedger.standing([], seat: 0))
        XCTAssertNil(ThroLedger.standing([row("1", seat: 1, total: 60, left: 441)], seat: 0))
    }

    func testTheLedgersStrikeIsAHandsStrokeThroughAFigureAndNotTheMarksSlash() {
        // A chalker strikes a remainder with a quick, nearly level stroke that rises a little to the
        // right. The Ø's 45° slash is for the mark and for a bust figure; laid through every old
        // remainder in a 24 pt column it would climb into the rows above and below.
        XCTAssertTrue((5.0...15.0).contains(ChalkStrike.boardAngle), "the ledger strike is \(ChalkStrike.boardAngle)°")
        let rect = CGRect(x: 0, y: 0, width: 40, height: 24)
        let box = ChalkStrike(capHeight: 16, angle: ChalkStrike.boardAngle).path(in: rect).boundingRect
        XCTAssertLessThan(box.height, ThroStage.ledgerRow, "the stroke stays inside its own row")
        XCTAssertGreaterThan(box.width, rect.width, "and runs past both ends of the figure")
        XCTAssertEqual(box.midX, rect.midX, accuracy: 0.5)
        XCTAssertEqual(box.midY, rect.midY, accuracy: 0.5)
    }

    func testTheStrokeRisesToTheRightLikeAHandsDoes() {
        let rect = CGRect(x: 0, y: 0, width: 40, height: 24)
        let path = ChalkStrike(capHeight: 16, angle: ChalkStrike.boardAngle).path(in: rect)
        var points: [CGPoint] = []
        path.forEach { element in
            switch element {
            case let .move(to: p), let .line(to: p): points.append(p)
            default: break
            }
        }
        let leftTip = points.min { $0.x < $1.x }!, rightTip = points.max { $0.x < $1.x }!
        XCTAssertLessThan(rightTip.y, leftTip.y, "the right end is higher on the screen")
    }

    func testTheDefaultStrikeIsStillTheMarksOwnSlash() {
        let rect = CGRect(x: 0, y: 0, width: 60, height: 40)
        XCTAssertEqual(ChalkStrike(capHeight: 20).angle, 45)
        let a = ChalkStrike(capHeight: 20).path(in: rect).boundingRect
        let b = ChalkStrike(capHeight: 20, angle: 45).path(in: rect).boundingRect
        XCTAssertEqual(a.width, b.width, accuracy: 0.01)
        XCTAssertEqual(a.height, b.height, accuracy: 0.01)
        XCTAssertEqual(a.width, a.height, accuracy: 0.01, "a 45° bar is as tall as it is wide")
    }

    // MARK: - The fixture slate

    func testBothNamesOnTheFixtureSlateTakeOneSizeSetByTheLonger() {
        XCTAssertEqual(ThroFixtureSlate.nameScale(longest: 5, expanded: true), 1)
        XCTAssertEqual(ThroFixtureSlate.nameScale(longest: 8, expanded: true), 1)
        XCTAssertEqual(ThroFixtureSlate.nameScale(longest: 10, expanded: true), 0.8, accuracy: 1e-9)
        XCTAssertEqual(ThroFixtureSlate.nameScale(longest: 10, expanded: false), 1)
        XCTAssertEqual(ThroFixtureSlate.nameScale(longest: 40, expanded: true), 0.6, "never smaller than this; the scale factor takes over")
        // The mark and the row are sized from the same role, so they scale with the names.
        let role = ThroTypography.display.family(.sport).weight(.bold).sized(30)
        XCTAssertEqual(ThroFixtureSlate.nameRowHeight(role), ThroTypography.capBox(role))
        XCTAssertEqual(ThroFixtureSlate.markSide(role), (1.4 * role.capHeight).rounded())
    }
}
