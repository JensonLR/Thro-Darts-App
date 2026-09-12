import XCTest
import SwiftUI
import ThroTokens
@testable import ThroDesign

/// SLATE B.3 — how a surface ends, held to what it claims.
///
/// The claims worth a test are the ones that would fail silently on a phone: a boundary that is
/// clipped by the view it decorates, a rule that crawls between frames, a strike that is not the
/// founder's mark's bar, and a keypad that says a control is unavailable by making its label
/// unreadable. None of those throws; all of them just look wrong, on somebody else's device.
final class ChalkTests: XCTestCase {

    // MARK: - ChalkRule

    func testARuleSpansTheDistanceItIsGivenAndIsNoThickerThanItsWeightAllows() {
        let rule = ChalkRule(weight: 3)
        let rect = CGRect(x: 0, y: 0, width: 200, height: 12)
        let box = rule.path(in: rect).boundingRect
        XCTAssertEqual(box.minX, rect.minX, accuracy: 0.001, "a rule starts where it is put")
        XCTAssertEqual(box.maxX, rect.maxX, accuracy: 0.001, "and ends where it is told to")
        // The band wanders by `roughness` of the nominal width and no further. Anything more is a
        // wobble, and anything that scales with the rect's height is a rule reading its own frame.
        let widest = 3 * (1 + ChalkRule.roughness)
        XCTAssertLessThanOrEqual(box.height, widest + 0.001)
        XCTAssertGreaterThan(box.height, 3 * (1 - ChalkRule.roughness) - 0.001)
    }

    func testTheSameRuleIsTheSameEveryTimeSoItNeverCrawls() {
        let rect = CGRect(x: 0, y: 0, width: 140, height: 10)
        XCTAssertEqual(ChalkRule(seedAngle: 61).path(in: rect),
                       ChalkRule(seedAngle: 61).path(in: rect),
                       "a rule redrawn on the next frame must be the rule that was there")
    }

    func testTwoRulesOnOneScreenDifferBecauseTheyAreGivenDifferentAngles() {
        let rect = CGRect(x: 0, y: 0, width: 140, height: 10)
        XCTAssertNotEqual(ChalkRule(seedAngle: 0).path(in: rect),
                          ChalkRule(seedAngle: 61).path(in: rect))
    }

    func testTrimDrawsARuleInAndAtZeroThereIsNoRule() {
        let rect = CGRect(x: 0, y: 0, width: 200, height: 12)
        XCTAssertTrue(ChalkRule(trim: 0).path(in: rect).isEmpty)
        let half = ChalkRule(trim: 0.5).path(in: rect).boundingRect
        XCTAssertEqual(half.maxX, 100, accuracy: 0.5, "half a rule reaches half way")
        XCTAssertEqual(half.minX, 0, accuracy: 0.001, "and it grows from the left, not the middle")
    }

    func testTrimIsTheAnimatableThingSoARuleCanBeDrawnIn() {
        var rule = ChalkRule()
        rule.animatableData = 0.25
        XCTAssertEqual(rule.trim, 0.25)
        XCTAssertEqual(rule.animatableData, 0.25)
    }

    func testARuleWithNoWeightDrawsNothingRatherThanACrash() {
        XCTAssertTrue(ChalkRule(weight: 0).path(in: CGRect(x: 0, y: 0, width: 50, height: 4)).isEmpty)
        XCTAssertTrue(ChalkRule().path(in: .zero).isEmpty)
    }

    // MARK: - ChalkBox

    func testABoxNeverLeavesTheFrameItIsGivenSoNothingClipsItsCorners() {
        // The whole reason the box is inset by its own overrun. A box that overran its bounds would
        // be clipped by the view it decorates, on exactly the four corners the overrun exists for —
        // and it would look correct in a preview, where nothing clips.
        for size in [CGSize(width: 120, height: 64), CGSize(width: 44, height: 44),
                     CGSize(width: 320, height: 56)] {
            let rect = CGRect(origin: .zero, size: size)
            let box = ChalkBox().path(in: rect).boundingRect
            XCTAssertTrue(rect.insetBy(dx: -0.001, dy: -0.001).contains(box),
                          "a \(size.width)×\(size.height) box drew outside its own frame")
        }
    }

    func testABoxHasFourSidesAndSquareCorners() {
        let rect = CGRect(x: 0, y: 0, width: 120, height: 64)
        let box = ChalkBox().path(in: rect).boundingRect
        // Square corners: the drawn extent is the same distance in from every edge. A radius would
        // pull the horizontal extent in further than the vertical one, or the reverse.
        let left = box.minX - rect.minX, right = rect.maxX - box.maxX
        let top = box.minY - rect.minY, bottom = rect.maxY - box.maxY
        XCTAssertEqual(left, right, accuracy: 0.25)
        XCTAssertEqual(top, bottom, accuracy: 0.25)
        XCTAssertEqual(left, top, accuracy: 0.25, "the box is inset the same amount all round")
        XCTAssertGreaterThan(box.width, rect.width - 8, "and it is a box round the key, not a stripe")
        XCTAssertGreaterThan(box.height, rect.height - 8)
    }

    func testABoxClosesItsCornersInsteadOfRunningPastThem() {
        // The founder's call: thirty keys of corner ticks were clutter, not the brand. The corners
        // are filled squares — a point just inside each corner of the drawn extent is on the box —
        // and nothing runs past them, so the drawn extent's corner is where the two rules meet.
        XCTAssertEqual(ChalkBox.defaultOverrun, 0)
        let rect = CGRect(x: 0, y: 0, width: 120, height: 64)
        let box = ChalkBox()
        let path = box.path(in: rect)
        let extent = path.boundingRect
        let inside = box.weight * 0.35
        for corner in [CGPoint(x: extent.minX + inside, y: extent.minY + inside),
                       CGPoint(x: extent.maxX - inside, y: extent.minY + inside),
                       CGPoint(x: extent.minX + inside, y: extent.maxY - inside),
                       CGPoint(x: extent.maxX - inside, y: extent.maxY - inside)] {
            XCTAssertTrue(path.contains(corner, eoFill: false), "the corner at \(corner) is open")
        }
        // No tail: the box's drawn extent is exactly as far in from the frame on both axes, and a
        // tick would poke the horizontal extent out past the vertical rule's outer edge.
        let ticked = ChalkBox(overrun: 3).path(in: rect).boundingRect
        XCTAssertEqual(extent.width, rect.width - 2 * (extent.minX - rect.minX), accuracy: 0.25)
        XCTAssertLessThan(extent.minX - rect.minX, ticked.minX - rect.minX + 3.001,
                          "the closed box is inset only by its own reach, the ticked one by its tails too")
    }

    func testABoxThatIsSmallerThanItsOwnOverrunDrawsNothingRatherThanInsideOut() {
        XCTAssertTrue(ChalkBox().path(in: CGRect(x: 0, y: 0, width: 2, height: 2)).isEmpty)
    }

    func testWeightIsTheAnimatableThingSoAPressCanPressTheChalkIn() {
        var box = ChalkBox()
        box.animatableData = ChalkKeyStyle.pressedWeight
        XCTAssertEqual(box.weight, ChalkKeyStyle.pressedWeight)
        XCTAssertGreaterThan(ChalkKeyStyle.pressedWeight, ChalkKeyStyle.restingWeight,
                             "a pressed key is chalk pressed harder, so the boundary gains ink")
    }

    // MARK: - ChalkStrike

    func testTheStrikeIsTheMarksOwnBarAtTheSizeTheFigureAsks() {
        let geometry = ChalkStrike.geometry(figureWidth: 100, capHeight: 60)
        XCTAssertEqual(geometry.tipToTip, ChalkStrike.span * 100, accuracy: 0.001,
                       "it runs 1.35 times the figure's width, so it clears both ends")
        XCTAssertEqual(2 * geometry.halfWidth, ChalkStrike.thickness * 60, accuracy: 0.001,
                       "and its thickness is a fraction of the cap, so it reads at any size")
        XCTAssertEqual(geometry.ratios.tip, MarkGeometry.Ratios.mark.tip,
                       "it is the mark's bar, not a line at the same angle")
    }

    func testTheStrikeRunsLowerLeftToUpperRightAtFortyFiveDegrees() {
        let rect = CGRect(x: 0, y: 0, width: 200, height: 80)
        let path = ChalkStrike(figureWidth: 60, capHeight: 40).path(in: rect)
        let box = path.boundingRect
        // The mark's axis is 45° in a y-down frame, so the bar's bounding box is square.
        XCTAssertEqual(box.width, box.height, accuracy: 0.5)
        XCTAssertEqual(box.midX, rect.midX, accuracy: 0.5, "and it is struck through the figure")
        XCTAssertEqual(box.midY, rect.midY, accuracy: 0.5)
    }

    func testTheStrikeWeighsWhatTheWordmarksSlashWeighsAgainstTheSameCap() {
        // The Ø's dart is 0.065 of the cap either side of its axis (`Ratios.wordmark.halfWidth`,
        // measured off Archivo ExtraBold). A strike that claims to be the Ø's dart takes that
        // weight, not one chosen by eye.
        XCTAssertEqual(ChalkStrike.thickness, 0.13, accuracy: 0.0001)
        XCTAssertEqual(ChalkStrike.thickness, 2 * MarkGeometry.Ratios.wordmark.halfWidth, accuracy: 1e-9)
        let geometry = ChalkStrike.geometry(figureWidth: 60, capHeight: 20)
        XCTAssertEqual(2 * geometry.halfWidth, 2.6, accuracy: 0.001, "2.6 pt through a 20 pt cap")
    }

    func testAStrikeWithNoWidthOfItsOwnStrikesWhatItIsLaidOver() {
        // A ledger row's width is the row's, not a guess: the shape takes the rect it is given.
        let rect = CGRect(x: 10, y: 0, width: 80, height: 30)
        let laid = ChalkStrike(capHeight: 20).path(in: rect).boundingRect
        let told = ChalkStrike(figureWidth: 80, capHeight: 20).path(in: rect).boundingRect
        XCTAssertEqual(laid.width, told.width, accuracy: 0.001)
        XCTAssertEqual(laid.midX, rect.midX, accuracy: 0.5)
        XCTAssertTrue(ChalkStrike(capHeight: 20).path(in: CGRect(x: 0, y: 0, width: 0, height: 30)).isEmpty)
    }

    func testARoleKnowsItsOwnCapHeight() {
        // The strike under a ledger row sizes itself from the row's role, so the role must say what
        // its capitals measure, per family, at the user's text size.
        let role = ThroTypography.heading3.family(.sport)
        XCTAssertEqual(role.capHeight, ThroTypography.capRatio(.sport) * role.size, accuracy: 0.5)
        XCTAssertGreaterThan(role.capHeight, 0)
        XCTAssertLessThan(role.capHeight, role.size)
    }

    func testAStrikeWithNoFigureToStrikeDrawsNothing() {
        let rect = CGRect(x: 0, y: 0, width: 40, height: 40)
        XCTAssertTrue(ChalkStrike(figureWidth: 0, capHeight: 40).path(in: rect).isEmpty)
        XCTAssertTrue(ChalkStrike(figureWidth: 40, capHeight: 0).path(in: rect).isEmpty)
    }

    // MARK: - The board's three grounds

    func testEveryLightingHasItsOwnGroundAndAPressStaysOnTheBoard() {
        // The board law: three stops, and nothing outside them. A press moves a key down one stop,
        // and from the bottom it stays — inventing a fourth ground is what would make the contrast
        // matrix a description of something other than what renders.
        XCTAssertEqual(ChalkKeyStyle.Lighting.allCases.count, 3)
        XCTAssertEqual(ChalkKeyStyle.Lighting.lit.pressed, .field)
        XCTAssertEqual(ChalkKeyStyle.Lighting.field.pressed, .sunken)
        XCTAssertEqual(ChalkKeyStyle.Lighting.sunken.pressed, .sunken)
        for lighting in ChalkKeyStyle.Lighting.allCases {
            XCTAssertTrue(ChalkKeyStyle.Lighting.allCases.contains(lighting.pressed),
                          "\(lighting.rawValue) pressed leaves the board")
        }
    }

    func testEveryKeyIsBigEnoughToHitWithAThumbMidLeg() {
        // The six quick totals used to be `touchTargetMinimum` while the digits were
        // `touchTargetScoring`: the most-pressed keys on the screen were the smallest ones. They
        // are all one size now, and that size is the style's default, so a new key inherits it.
        XCTAssertEqual(ChalkKeyStyle.defaultHeight, ThroSpacing.touchTargetScoring,
                       "the default key is the scoring target, not the accessibility floor")
        XCTAssertGreaterThan(ChalkKeyStyle.defaultHeight, ThroSpacing.touchTargetMinimum)
    }

    // MARK: - What the keypad says about availability

    func testUnavailableIsAPlaceInTheLightAndNeverAFade() {
        // The resting Enter key was the whole control at 0.4 opacity, which composited its label to
        // 2.20:1 in light and 2.92:1 in dark — on the one control in this app that commits
        // evidence. Out of the light it is a named ground with its own ink: 7.60:1.
        XCTAssertEqual(ScoreKeypad.enterLighting(ready: true, disabled: false), .lit)
        XCTAssertEqual(ScoreKeypad.enterLighting(ready: false, disabled: false), .sunken)
        XCTAssertEqual(ScoreKeypad.enterLighting(ready: true, disabled: true), .sunken,
                       "a typed score on a keypad that is not accepting one is still not pressable")
        XCTAssertEqual(ScoreKeypad.enterLighting(ready: false, disabled: true), .sunken)
    }

    func testTheReadyEnterKeyIsTheBrightestThingOnTheBoard() {
        // Ready is `lit` and every other key is `field`, so the key a player is about to press is
        // the brightest ground there is rather than the only one that has not been faded.
        XCTAssertEqual(ScoreKeypad.enterLighting(ready: true, disabled: false), .lit)
        XCTAssertEqual(ScoreKeypad.keyLighting(disabled: false), .field)
        XCTAssertEqual(ScoreKeypad.keyLighting(disabled: true), .sunken)
    }

    func testInkCarriesAvailabilityTooBecauseTheGroundsAreOnlyOneStopApart() {
        // `board-field` to `board-sunken` is 1.27:1 — a difference, not a signal. The ink between
        // the two states is what a player actually reads, and both inks are on the contrast matrix
        // against all three grounds, so neither can quietly fall below its floor.
        XCTAssertEqual(ScoreKeypad.ink(ready: true, disabled: false), ThroColor.colorTextOnBoard)
        XCTAssertEqual(ScoreKeypad.ink(ready: false, disabled: false), ThroColor.colorTextOnBoardSecondary)
        XCTAssertEqual(ScoreKeypad.ink(ready: true, disabled: true), ThroColor.colorTextOnBoardSecondary)
        XCTAssertEqual(ScoreKeypad.keyInk(disabled: false), ThroColor.colorTextOnBoard)
        XCTAssertEqual(ScoreKeypad.keyInk(disabled: true), ThroColor.colorTextOnBoardSecondary)
    }
}

// MARK: - the mark, one solid thing

extension ChalkTests {
    func testTheMarkFillsSolidWhereTheDartCrossesTheRing() {
        // The founder saw two darker bites where the bar met the ring: ring and bar wound opposite
        // ways, so the non-zero fill left the crossing empty. One path, one winding, no bite.
        let geometry = MarkGeometry(unit: 100)
        let centre = CGPoint(x: 200, y: 200)
        let mark = geometry.mark(at: centre)
        for sign in [CGFloat(1), CGFloat(-1)] {
            let crossing = geometry.onAxis(centre, sign * geometry.ringCentreRadius)
            XCTAssertTrue(mark.contains(crossing, eoFill: false), "the crossing at \(crossing) is a hole")
        }
        // and still a mark: the ring's far side, the dart's tip, and the empty middle
        XCTAssertTrue(mark.contains(geometry.onRing(centre, degrees: 45), eoFill: false))
        XCTAssertTrue(mark.contains(geometry.onAxis(centre, geometry.tip * 0.98), eoFill: false))
        XCTAssertFalse(mark.contains(geometry.onRing(centre, degrees: 45, radiusScale: 0.5), eoFill: false))
        XCTAssertTrue(ThroMark().path(in: CGRect(x: 0, y: 0, width: 100, height: 100))
                        .contains(MarkGeometry(tipToTip: 100).onAxis(CGPoint(x: 50, y: 50), MarkGeometry(tipToTip: 100).ringCentreRadius), eoFill: false))
    }
}
