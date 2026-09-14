import SwiftUI
import XCTest
@testable import ThroDesign

/// What the masthead does when the screen is short (PD-061).
///
/// The number that decides it lives in one place and is tested against the devices THRØ runs on, in the
/// same shape `ThroStage`'s beside-or-stacked choice is. The last test is the important one: the view
/// reads iOS's vertical size class and the rule is written as a height, and two ways of saying one thing
/// is how a rule drifts apart.
final class MastheadShapeTests: XCTestCase {

    /// height in points, and whether iOS reports a compact vertical size class there.
    private let screens: [(name: String, height: CGFloat, compact: Bool)] = [
        ("iPhone SE, upright", 568, false),
        ("iPhone 13 mini, upright", 812, false),
        ("iPhone 17 Pro, upright", 874, false),
        ("iPhone 17 Pro Max, upright", 956, false),
        ("iPhone SE, on its side", 320, true),
        ("iPhone 13 mini, on its side", 375, true),
        ("iPhone 17 Pro, on its side", 402, true),
        ("iPhone 17 Pro Max, on its side", 440, true),
        ("iPad Pro 11, upright", 1194, false),
        ("iPad Pro 11, on its side", 834, false),
    ]

    func testEveryPortraitPhoneKeepsTheFullMasthead() {
        for s in screens where !s.compact {
            XCTAssertEqual(ThroMasthead.shape(forHeight: s.height), .stacked, s.name)
        }
    }

    func testAPhoneOnItsSideFoldsToOneLine() {
        for s in screens where s.compact {
            XCTAssertEqual(ThroMasthead.shape(forHeight: s.height), .oneLine, s.name)
        }
    }

    func testATabletKeepsTheFullMastheadEvenOnItsSide() {
        // 834 points is taller than an upright iPhone SE. There is nothing to buy by folding it.
        XCTAssertEqual(ThroMasthead.shape(forHeight: 834), .stacked)
    }

    func testTheThresholdHasRoomOnBothSides() {
        // The tallest phone on its side is 440 and the shortest upright is 568. A threshold that sat
        // against either edge would fold or unfold a device on the next hardware revision.
        XCTAssertGreaterThan(ThroMasthead.shortestTallScreen, 440 + 40)
        XCTAssertLessThan(ThroMasthead.shortestTallScreen, 568 - 40)
    }

    func testTheHeightRuleAndTheSizeClassAgreeOnEveryDevice() {
        // The view cannot measure the window, so it reads the vertical size class; the rule is written
        // as a height. This is the test that stops those two becoming different rules.
        for s in screens {
            XCTAssertEqual(ThroMasthead.shape(forHeight: s.height),
                           ThroMasthead.shape(verticalSizeClassIsCompact: s.compact),
                           "\(s.name): the height rule and the size class disagree")
        }
    }
}
