import XCTest
import SwiftUI
@testable import ThroDesign

final class DesignTests: XCTestCase {

    // MARK: icons

    /// Every registered glyph parses to something, and stays inside the 24×24 grid it was drawn on.
    /// A path that escapes the grid means a command was misread — an arc flag taken as a coordinate,
    /// a relative move treated as absolute — and the glyph would render wrong without failing.
    func testEveryIconParsesInsideTheGrid() {
        for icon in ThroIcon.allCases {
            let path = LucideMarkup.path(icon.markup)
            XCTAssertFalse(path.isEmpty, "\(icon.rawValue) parsed to nothing")
            let b = path.boundingRect
            XCTAssertGreaterThanOrEqual(b.minX, -0.5, "\(icon.rawValue) escapes left: \(b)")
            XCTAssertGreaterThanOrEqual(b.minY, -0.5, "\(icon.rawValue) escapes top: \(b)")
            XCTAssertLessThanOrEqual(b.maxX, 24.5, "\(icon.rawValue) escapes right: \(b)")
            XCTAssertLessThanOrEqual(b.maxY, 24.5, "\(icon.rawValue) escapes bottom: \(b)")
        }
    }

    /// An arc must land exactly on its endpoint, or every glyph with a curve is subtly wrong.
    func testArcLandsOnItsEndpoint() {
        let path = SVGPathData.path("M0 0 A5 5 0 0 1 10 0")
        let end = path.currentPoint
        XCTAssertNotNil(end)
        XCTAssertEqual(end!.x, 10, accuracy: 1e-6)
        XCTAssertEqual(end!.y, 0, accuracy: 1e-6)
        // a semicircle of radius 5 reaches 5 away from the chord, on one side or the other
        let b = path.boundingRect
        XCTAssertEqual(max(abs(b.minY), abs(b.maxY)), 5, accuracy: 0.05, "semicircle height wrong: \(b)")
        XCTAssertEqual(b.width, 10, accuracy: 0.05)
    }

    /// The sweep flag chooses the side. Same arc, opposite flag, mirrored.
    func testSweepFlagChoosesTheSide() {
        let a = SVGPathData.path("M0 0 A5 5 0 0 1 10 0").boundingRect
        let b = SVGPathData.path("M0 0 A5 5 0 0 0 10 0").boundingRect
        XCTAssertEqual(a.minY, -b.maxY, accuracy: 0.05)
        XCTAssertEqual(a.maxY, -b.minY, accuracy: 0.05)
    }

    /// Relative commands accumulate from the current point, not from the origin.
    func testRelativeCommandsAccumulate() {
        let path = SVGPathData.path("M2 3 l4 0 l0 4 h-4 v-4")
        XCTAssertEqual(path.boundingRect, CGRect(x: 2, y: 3, width: 4, height: 4))
    }

    /// SVG's compact number syntax: `5-5` is two numbers, so is `.5.5`.
    func testCompactNumberSyntaxIsTwoNumbers() {
        let tokens = SVGPathData.tokenize("M5-5 .5.5")
        var numbers: [CGFloat] = []
        for t in tokens { if case .number(let v) = t { numbers.append(v) } }
        XCTAssertEqual(numbers, [5, -5, 0.5, 0.5])
    }

    func testCircleElementBecomesAnEllipseOfTheRightSize() {
        let path = LucideMarkup.path(#"<circle cx="12" cy="12" r="10"></circle>"#)
        let b = path.boundingRect
        XCTAssertEqual(b.minX, 2, accuracy: 1e-6)
        XCTAssertEqual(b.minY, 2, accuracy: 1e-6)
        XCTAssertEqual(b.width, 20, accuracy: 1e-6)
        XCTAssertEqual(b.height, 20, accuracy: 1e-6)
    }

    func testRectElementHonoursItsCorners() {
        let path = LucideMarkup.path(#"<rect width="14" height="20" x="5" y="2" rx="2" ry="2"></rect>"#)
        XCTAssertEqual(path.boundingRect, CGRect(x: 5, y: 2, width: 14, height: 20))
    }

    // MARK: typography

    /// The approved type scale, from TOKEN_HEALTH.md. A role at any other size is an off-scale
    /// bypass, which the design's own gate rejects in every platform source.
    func testEveryRoleIsOnTheApprovedScale() {
        let scale: Set<CGFloat> = [13, 14, 15, 17, 18, 21, 25, 32, 40, 56, 72, 96]
        for role in ThroTypography.all {
            XCTAssertTrue(scale.contains(role.size), "role at \(role.size)px is off the approved scale")
            XCTAssertGreaterThanOrEqual(role.lineHeight, role.size * 0.9, "line height below size for \(role.size)px")
        }
    }

    /// `.thro-eyebrow`, exactly as the class defines it.
    func testEyebrowMatchesTheClass() {
        let e = ThroTypography.eyebrow
        XCTAssertEqual(e.size, 13)
        XCTAssertEqual(e.lineHeight, 16)
        XCTAssertEqual(e.trackingEm, 0.09, accuracy: 1e-9)
        XCTAssertTrue(e.uppercase)
        XCTAssertEqual(e.weight, .semibold)
        XCTAssertEqual(e.family, .ui)
    }

    /// Every sport figure is tabular, so a changing score does not jitter.
    func testSportRolesAreTabular() {
        for role in [ThroTypography.scoreHero, ThroTypography.sportHero, ThroTypography.ratingHero] {
            XCTAssertEqual(role.family, .sport)
            XCTAssertTrue(role.tabularNumerals, "\(role.size)px sport role is not tabular")
        }
        XCTAssertTrue(ThroTypography.heading3.family(.sport).tabularNumerals, "switching to sport must turn tabular on")
    }

    /// The hero numerals have negative tracking, as the tokens state; nothing else does.
    func testTrackingFollowsTheTokens() {
        XCTAssertEqual(ThroTypography.scoreHero.trackingEm, -0.03, accuracy: 1e-9)
        XCTAssertEqual(ThroTypography.sportHero.trackingEm, -0.02, accuracy: 1e-9)
        XCTAssertEqual(ThroTypography.body.trackingEm, 0, accuracy: 1e-9)
        XCTAssertEqual(ThroTypography.scoreHero.tracking, 96 * -0.03, accuracy: 1e-9)
    }

    /// A missing font is reported, never silently substituted: the check exists and is honest about
    /// this machine. (Whether the faces are present here is a fact about the runner, not a pass/fail.)
    func testFontRegistrationIsAQueryNotAnAssumption() {
        _ = ThroFont.customFacesRegistered
        XCTAssertFalse(ThroFont.isRegistered("A Font Family That Does Not Exist"))
    }

    /// Every verification label has the design's wording, as a sentence.
    func testVerificationLabelsCarryTheDesignsWording() {
        for state in VerificationLabel.allCases {
            XCTAssertFalse(state.label.isEmpty)
            XCTAssertTrue(state.help.hasSuffix("."), "\(state.rawValue) help is not a sentence: \(state.help)")
        }
        XCTAssertEqual(VerificationLabel.selfReported.help, "Entered by a player. Not independently confirmed.")
        XCTAssertEqual(VerificationLabel.throVerified.help, "Recorded in THRØ and confirmed by the organiser.")
    }
}
