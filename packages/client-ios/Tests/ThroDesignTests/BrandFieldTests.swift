import XCTest
@testable import ThroDesign

/// The brand field is the top of a page, on every screen it can be shown on (PD-060).
///
/// The number it used to be was measured on a phone held upright and applied everywhere, which made it the
/// whole screen the moment the phone was turned. These hold both halves: portrait does not move, and no
/// screen is ever swallowed.
final class BrandFieldTests: XCTestCase {

    /// The screens THRØ actually runs on, in points, tallest dimension first.
    private let phones: [(name: String, portrait: CGFloat, landscape: CGFloat)] = [
        ("iPhone SE", 568, 320),
        ("iPhone 13 mini", 812, 375),
        ("iPhone 17 Pro", 874, 402),
        ("iPhone 17 Pro Max", 956, 440),
    ]

    func testEveryPortraitPhoneIsUnchanged() {
        for phone in phones {
            let height = ThroBrandField.height(in: phone.portrait)
            // 400 exactly on all but the SE, which asks for 398 — the same screen to the eye, and the
            // point of choosing 0.7 rather than a share that would have redrawn a shipped layout.
            XCTAssertEqual(height, min(400, phone.portrait * 0.7), accuracy: 0.001, phone.name)
            XCTAssertGreaterThanOrEqual(height, 397, "\(phone.name) portrait should still be the full field")
        }
    }

    func testNoScreenIsEverSwallowedByTheField() {
        for phone in phones {
            let height = ThroBrandField.height(in: phone.landscape)
            XCTAssertLessThan(height, phone.landscape,
                              "\(phone.name) in landscape: the field must not be the whole page")
            // And the specific regression: a flat 400 was taller than the screen on every phone here.
            XCTAssertLessThan(height, ThroBrandField.tallest,
                              "\(phone.name) in landscape is shorter than the ceiling, so the ceiling must not apply")
        }
    }

    func testTheFieldIsStillTallEnoughToBeAField() {
        // It has to cover the clock and the header and leave room for a pull. The shortest screen THRØ
        // runs on is an SE on its side; 224 points is still two thirds of it and comfortably past a header.
        for phone in phones {
            XCTAssertGreaterThan(ThroBrandField.height(in: phone.landscape), 200,
                                 "\(phone.name) landscape: a field this short would read as a stripe")
        }
    }

    func testAContainerNotYetLaidOutFallsBackToTheCeiling() {
        // Zero is "no layout pass yet", not "a screen of no height". Returning zero here would draw paper
        // for one frame where the design says green.
        XCTAssertEqual(ThroBrandField.height(in: 0), ThroBrandField.tallest)
        XCTAssertEqual(ThroBrandField.height(in: -10), ThroBrandField.tallest)
    }
}
