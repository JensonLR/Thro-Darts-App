import SwiftUI
import XCTest
@testable import ThroPlay
import ThroDesign
import ThroTokens

/// The set-up screen is one screen: at the default text size it fits the smallest phone upright
/// with its Continue pinned, so nothing has to be scrolled to before a match can start.
final class MatchSetupLayoutTests: XCTestCase {
    func testTheSetupFitsTheSmallestPhoneWithoutScrolling() {
        XCTAssertLessThanOrEqual(MatchSetupLayout.height(knownPeople: true), MatchSetupLayout.smallestUsableHeight,
                                 "with a row of known names it must still fit an iPhone SE")
        XCTAssertLessThanOrEqual(MatchSetupLayout.height(knownPeople: false), MatchSetupLayout.smallestUsableHeight)
    }

    func testTheChoiceRowsShareOneLabelColumnSoTheControlsLineUp() {
        XCTAssertGreaterThanOrEqual(ThroChoiceRow<EmptyView>.labelWidth, 88, "wide enough for “First throw”")
        XCTAssertLessThan(ThroChoiceRow<EmptyView>.labelWidth, 120, "and not so wide the control loses a segment")
    }
}
