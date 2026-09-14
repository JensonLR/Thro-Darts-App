import XCTest
@testable import ThroDesign

/// When a screen is two things and when it is one (PD-062).
final class SpreadTests: XCTestCase {

    private let screens: [(name: String, width: CGFloat)] = [
        ("iPhone SE, upright", 320),
        ("iPhone 13 mini, upright", 375),
        ("iPhone 17 Pro, upright", 402),
        ("iPhone 17 Pro Max, upright", 440),
        ("iPhone SE, on its side", 568),
        ("iPhone 13 mini, on its side", 812),
        ("iPhone 17 Pro, on its side", 874),
        ("iPad Pro 11, upright", 834),
        ("iPad Pro 11, on its side", 1194),
        ("iPad Pro 13, on its side", 1366),
    ]

    func testAPhoneHeldUprightIsOneColumn() {
        for s in screens where s.width <= 440 {
            XCTAssertEqual(ThroSpread.arrangement(forWidth: s.width), .stacked, s.name)
        }
    }

    func testATabletIsTwoColumnsEitherWayUp() {
        XCTAssertEqual(ThroSpread.arrangement(forWidth: 834), .sideBySide, "iPad upright")
        XCTAssertEqual(ThroSpread.arrangement(forWidth: 1194), .sideBySide, "iPad on its side")
    }

    func testNeitherColumnIsEverNarrowerThanItCanBeRead() {
        // Every component in THRØ is proven at an iPhone SE's 280 points of content, and a column is held
        // above that with margin. Anything narrower is two things crushed rather than two things shown.
        for s in screens where ThroSpread.arrangement(forWidth: s.width) == .sideBySide {
            XCTAssertGreaterThanOrEqual(ThroSpread.columnWidth(forWidth: s.width), ThroSpread.narrowestColumn,
                                        "\(s.name): a column this narrow is not worth splitting for")
        }
    }

    func testTwoColumnsNeverBecomeTwoRooms() {
        // A 13-inch tablet has 1366 points and no page should use all of them. The pair is capped, so the
        // columns stop growing and the room around them stays room (PD-052).
        XCTAssertEqual(ThroSpread.columnWidth(forWidth: 1366), ThroSpread.columnWidth(forWidth: 1194),
                       "past the cap, a wider screen must not widen the columns")
        XCTAssertLessThanOrEqual(ThroSpread.columnWidth(forWidth: 1366), ThroReadable.measure,
                                 "a column wider than the readable measure is the thing the measure exists to stop")
    }

    func testTheThresholdIsTwoColumnsWorthOfRoom() {
        // The rule and the reason have to agree: the narrowest spreading screen must still fit two columns
        // that clear the readable minimum. A threshold set below its own arithmetic is a number nobody
        // checked.
        XCTAssertGreaterThanOrEqual(ThroSpread.columnWidth(forWidth: ThroSpread.narrowest),
                                    ThroSpread.narrowestColumn)
        XCTAssertEqual(ThroSpread.arrangement(forWidth: ThroSpread.narrowest - 1), .stacked)
        XCTAssertEqual(ThroSpread.arrangement(forWidth: ThroSpread.narrowest), .sideBySide)
    }

    func testAScreenOfNoWidthDoesNotProduceANegativeColumn() {
        XCTAssertEqual(ThroSpread.arrangement(forWidth: 0), .stacked)
        XCTAssertGreaterThanOrEqual(ThroSpread.columnWidth(forWidth: 0), 0)
    }
}
