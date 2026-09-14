import XCTest
import SwiftUI
import ThroTokens
@testable import ThroDesign

/// SLATE B.4 and B.5 — the numeral system and the honesty layer's furniture.
///
/// The claims here are the ones that are invisible when they break. A register that is not a fixed
/// width is a number that walks across the screen; a cap box computed from a line box is a screen
/// with 56 points of nothing under its hero; a basis that two states share is a distinction the
/// product exists to make and does not.
final class FigureTests: XCTestCase {

    // MARK: - The register

    func testTheRegisterIsRightAlignedAndItsLeadingCellsAreEmptyNotZero() {
        // A leading zero states a digit the player does not have. 041 is not 41.
        XCTAssertEqual(ThroFigure.register("41", cells: 3), [nil, "4", "1"])
        XCTAssertEqual(ThroFigure.register("501", cells: 3), ["5", "0", "1"])
        XCTAssertEqual(ThroFigure.register("7", cells: 3), [nil, nil, "7"])
        XCTAssertEqual(ThroFigure.register("", cells: 3), [nil, nil, nil])
    }

    func testAFigureTooLongForItsRegisterShowsItsTailRatherThanHidingTheBug() {
        // An overflowing score is a defect. Its last digits are the reading that makes the defect
        // visible; an ellipsis is the reading that hides it.
        XCTAssertEqual(ThroFigure.register("1234", cells: 3), ["2", "3", "4"])
    }

    func testEveryRegisterOfTheSameWidthIsTheSameWidth() {
        // The whole point. 501 and 41 occupy the same space, so the number a player glances at
        // between darts does not migrate sideways as it comes down.
        let role = ThroTypography.boardHero
        for text in ["501", "41", "7", "180"] {
            XCTAssertEqual(ThroFigure.register(text, cells: 3).count, 3, text)
        }
        XCTAssertEqual(ThroFigure.width(cells: 3, role: role),
                       3 * (ThroFigure.cellRatio * ThroFont.scaled(role.size, relativeTo: role.relativeTo)).rounded())
    }

    func testTwoThreeDigitRegistersFitSideBySideOnTheNarrowestPhone() {
        // The arithmetic that decided the size. An iPhone SE is 320 pt wide; two 20 pt gutters and
        // a 16 pt column gap leave 264 pt. This is why boardHero is not the 88 pt SLATE specified —
        // 88 would need 285 pt, and 88 is not on the approved type scale either.
        let usable: CGFloat = 320 - 2 * ThroSpacing.spaceScreenGutter - ThroSpacing.spacing4
        let rung = ThroTypography.ladder.first {
            2 * ThroFigure.width(cells: 3, role: ThroTypography.boardHero.sized($0)) <= usable
        }
        XCTAssertNotNil(rung, "no rung of the ladder fits two three-digit registers on an SE")
        XCTAssertTrue(ThroTypography.ladder.contains(rung ?? 0))
    }

    func testEveryRungOfTheLadderIsOnTheApprovedScale() {
        // A density ladder that may invent a size is not a ladder, it is a licence.
        let scale: Set<CGFloat> = [13, 14, 15, 17, 18, 21, 25, 32, 40, 56, 72, 96]
        for rung in ThroTypography.ladder {
            XCTAssertTrue(scale.contains(rung), "rung at \(rung)px is off the approved scale")
        }
        XCTAssertEqual(ThroTypography.ladder, ThroTypography.ladder.sorted(by: >),
                       "the ladder runs largest first, so `first(where:)` picks the biggest that fits")
    }

    func testResizingARoleKeepsItsProportionsAndItsOtherProperties() {
        let role = ThroTypography.boardHero.sized(72)
        XCTAssertEqual(role.size, 72)
        XCTAssertEqual(role.family, ThroTypography.boardHero.family)
        XCTAssertEqual(role.weight, ThroTypography.boardHero.weight)
        XCTAssertTrue(role.tabularNumerals)
        XCTAssertEqual(role.lineHeight / role.size,
                       ThroTypography.boardHero.lineHeight / ThroTypography.boardHero.size,
                       accuracy: 0.02)
    }

    func testTrackingIsZeroInsideARegister() {
        // scoreHero carries −0.03 em. At 96 pt that is −2.88 pt per glyph, which pulls every digit
        // off its own cell. boardHero is the role that has it at zero.
        XCTAssertEqual(ThroTypography.boardHero.trackingEm, 0)
        XCTAssertEqual(ThroTypography.scoreHero.trackingEm, -0.03, accuracy: 1e-9,
                       "if scoreHero's tracking ever reaches zero this distinction has gone quiet")
    }

    // MARK: - The cap box

    func testACapBoxIsShorterThanTheBoxAFigureWouldOtherwiseTakeUp() {
        // What funds the ledger. A row of digits uses its capitals and nothing else; the box a
        // `Text` occupies is at least its em box, and reserves ascent, descent and leading that no
        // digit reaches into.
        //
        // The first version of this test compared the cap box against the role's TOKEN line height
        // (88 for `boardHero`) and demanded more than 20 points back. It gets 19, and CI said so.
        // The comparison was the wrong one: 88 is a line-spacing instruction, not the height a
        // figure takes. Against the em box the saving is 27 points per figure — which is also the
        // correction to SLATE's claim of 55.8, a number that does not come out of these ratios.
        let role = ThroTypography.boardHero
        let box = ThroTypography.capBox(role)
        let em = ThroFont.scaled(role.size, relativeTo: role.relativeTo)
        XCTAssertLessThan(box, em, "the cap box saves nothing")
        XCTAssertGreaterThan(em - box, 20, "at boardHero this should return real screen, not a point or two")
        XCTAssertGreaterThan(box, 0.6 * em, "and it must still contain the capitals")
    }

    func testEveryFamilyHasItsOwnMeasuredCapRatioAndNoneOfThemFallsBack() {
        // A dictionary lookup with a default is how a new family silently takes somebody else's cap
        // height. There is no default; this walks every family to prove each is answered.
        for family in ThroFont.Family.allCases {
            let ratio = ThroTypography.capRatio(family)
            XCTAssertGreaterThan(ratio, 0.6, "\(family) has an implausible cap ratio")
            XCTAssertLessThan(ratio, 0.8, "\(family) has an implausible cap ratio")
        }
        XCTAssertNotEqual(ThroTypography.capRatio(.ui), ThroTypography.capRatio(.sport),
                          "two faces with the same cap height would make this measurement decorative")
    }

    func testTheCapBoxIsComputedFromTheResolvedSizeAndNotTheLiteral() {
        // Dynamic Type scales the face. A cap box measured off the token literal would clip every
        // figure on a phone whose text size is above default — on the largest number in the app.
        let small = ThroTypography.boardHero.sized(40)
        let large = ThroTypography.boardHero.sized(96)
        XCTAssertLessThan(ThroTypography.capBox(small), ThroTypography.capBox(large))
    }

    // MARK: - The basis

    func testNoTwoBasesSoundTheSame() {
        // The compiler makes sure every case is handled. What it cannot see is a new case handled
        // by speaking an old one's line, and two states a listener cannot tell apart are one state.
        let spoken = ThroBasis.allCases.map(\.spoken)
        XCTAssertEqual(Set(spoken).count, ThroBasis.allCases.count, "\(spoken)")
    }

    func testOnlyTheCommonCaseIsSilent() {
        // Labelling `exact` would make every number in the app look qualified, which is the
        // opposite of what the honesty layer is for.
        XCTAssertTrue(ThroBasis.exact.spoken.isEmpty)
        XCTAssertFalse(ThroBasis.exact.qualifies)
        for basis in ThroBasis.allCases where basis != .exact {
            XCTAssertFalse(basis.spoken.isEmpty, "\(basis.rawValue) says nothing")
            XCTAssertTrue(basis.qualifies)
        }
    }

    func testEveryBasisExceptAbsenceDrawsSomethingAndAbsenceDrawsNothing() {
        let rect = CGRect(x: 0, y: 0, width: 160, height: 20)
        for basis in ThroBasis.allCases {
            let path = BasisRule(basis, figureWidth: 150, capHeight: 60).path(in: rect)
            if basis == .absent {
                XCTAssertTrue(path.isEmpty, "absence drew something; there is no measurement to qualify")
                XCTAssertEqual(BasisRule.height(.absent), 0)
            } else {
                XCTAssertFalse(path.isEmpty, "\(basis.rawValue) drew nothing")
                XCTAssertGreaterThan(BasisRule.height(basis), 0)
            }
        }
    }

    func testTheCalledOutFormIsTheOnlyOneWithTwoRules() {
        // A finish is the one thing a player wants to know before they look up, and it is the only
        // figure that gets two of anything — the board's own double ring, reduced.
        let rect = CGRect(x: 0, y: 0, width: 160, height: 24)
        let called = BasisRule(.calledOut, figureWidth: 150, capHeight: 60).path(in: rect).boundingRect
        let exact = BasisRule(.exact, figureWidth: 150, capHeight: 60).path(in: rect).boundingRect
        XCTAssertGreaterThan(called.height, exact.height * 2)
        XCTAssertGreaterThan(BasisRule.height(.calledOut), BasisRule.height(.exact))
    }

    func testABasisRuleNeverDrawsWiderThanTheFigureItQualifies() {
        let rect = CGRect(x: 0, y: 0, width: 300, height: 24)
        for basis in ThroBasis.allCases where basis != .absent {
            let box = BasisRule(basis, figureWidth: 100, capHeight: 60).path(in: rect).boundingRect
            XCTAssertLessThanOrEqual(box.width, 101, "\(basis.rawValue) ran past its figure")
        }
    }

    // MARK: - The figure and the states it draws

    func testAFigureSpeaksItsBasisAndAnAbsentValueIsNotReadAsPunctuation() {
        XCTAssertEqual(ThroFigure.spoken("141", basis: .calledOut), "141, on a finish")
        XCTAssertEqual(ThroFigure.spoken("141", basis: .exact), "141")
        XCTAssertEqual(ThroFigure.spoken("—", basis: .reference), "not available, not available")
        XCTAssertEqual(ThroFigure.spoken("—", basis: .absent), "not available, no result recorded")
    }

    func testTheRemainderStatesMapToBasesAndNoTwoShareOne() {
        XCTAssertEqual(RemainingScore.basis(for: .normal), .exact)
        XCTAssertEqual(RemainingScore.basis(for: .checkout), .calledOut)
        XCTAssertEqual(RemainingScore.basis(for: .bust), .struck)
        let bases = RemainingScore.State.allCases.map(RemainingScore.basis(for:))
        XCTAssertEqual(Set(bases).count, RemainingScore.State.allCases.count)
    }

    func testABustNoLongerThrowsAwayWhoseScoreItIs() {
        // The defect: the eyebrow drew "Bust — score restored" with no player in it, so the screen
        // attributed the restored score to nobody while the pill below named the other player —
        // and spokenLabel kept the name all along, so the two did not agree.
        for state in RemainingScore.State.allCases {
            let drawn = RemainingScore.eyebrow(label: "Ann requires", state: state)
            XCTAssertTrue(drawn.contains("Ann requires"),
                          "the \(state) eyebrow drops the caller's label: \(drawn)")
        }
        let bust = RemainingScore.eyebrow(label: "Ann requires", state: .bust)
        XCTAssertTrue(bust.lowercased().contains("bust"), bust)
        XCTAssertTrue(bust.lowercased().contains("restored"), bust)
    }

    func testWhatIsDrawnAndWhatIsSpokenCarryTheSameFacts() {
        for state in RemainingScore.State.allCases {
            let drawn = RemainingScore.eyebrow(label: "Ann requires", state: state).lowercased()
            let spoken = RemainingScore.spokenLabel(label: "Ann requires", state: state).lowercased()
            switch state {
            case .normal:
                XCTAssertEqual(drawn, spoken)
            case .checkout:
                XCTAssertTrue(spoken.contains("finish"), spoken)
            case .bust:
                XCTAssertTrue(drawn.contains("bust") && spoken.contains("bust"))
                XCTAssertTrue(drawn.contains("restored") && spoken.contains("restored"))
            }
        }
    }

    func testTheConfidencesMapToBasesAndNoTwoShareOne() {
        XCTAssertEqual(StatGrid.basis(for: .exact), .exact)
        XCTAssertEqual(StatGrid.basis(for: .range), .bounded)
        XCTAssertEqual(StatGrid.basis(for: .unavailable), .reference)
        let bases = StatItem.Confidence.allCases.map(StatGrid.basis(for:))
        XCTAssertEqual(Set(bases).count, StatItem.Confidence.allCases.count)
    }

    func testWhenThereIsNoNumberTheReasonBecomesTheContent() {
        // The inversion. An em dash at full strength over a reason in the quiet grey said that the
        // missing figure was the point and the explanation was a footnote. It is the other way
        // round: when there is no number, the reason IS the figure.
        XCTAssertEqual(StatGrid.noteColour(.unavailable), ThroColor.colorTextPrimary)
        XCTAssertEqual(StatGrid.valueColour(.unavailable), ThroColor.colorTextSecondary)
        XCTAssertEqual(StatGrid.noteColour(.exact), ThroColor.colorTextSecondary)
        XCTAssertEqual(StatGrid.valueColour(.exact), ThroColor.colorTextPrimary)
        for confidence in StatItem.Confidence.allCases {
            XCTAssertNotEqual(StatGrid.noteColour(confidence), StatGrid.valueColour(confidence),
                              "\(confidence) draws its figure and its reason in one colour, so neither leads")
        }
    }

    func testABasisTagIsNotACapsule() {
        // A pill makes a qualification look like another category to skim past, and a qualification
        // is the opposite of a category.
        XCTAssertEqual(Tag.Shape.allCases.count, 2)
        XCTAssertNotEqual(Tag.Shape.capsule, Tag.Shape.basis)
    }
}
