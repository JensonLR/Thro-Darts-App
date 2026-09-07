import XCTest
import SwiftUI
import ThroTokens
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

    // MARK: - PD-015: how far a figure can be trusted, drawn

    /// The guarantee is in the type. It is not possible to put a dash or a range on a screen
    /// without saying why it is one, because `unavailable` and `range` take the reason as a
    /// non-optional argument and there is no other way to build a `StatItem` that is not exact.
    func testAnUnavailableFigureCannotBeDrawnWithoutAReason() {
        let missing = StatItem.unavailable("Checkout %", why: "No visit has begun on a finish.")
        XCTAssertEqual(missing.value, "—", "never a zero, which would read as bad at darts")
        XCTAssertEqual(missing.confidence, .unavailable)
        XCTAssertNotNil(missing.note)

        let ranged = StatItem.range("3-dart average", "58.4–61.2", why: "One visit did not record its darts.")
        XCTAssertEqual(ranged.confidence, .range)
        XCTAssertNotNil(ranged.note)

        // Only the exact case may go without one, and only because an exact figure explains itself.
        XCTAssertNil(StatItem.exact("180s", "3").note)
    }

    /// The gap PD-015 closes. Before it, all three bases were drawn in `colorTextPrimary` at the same
    /// weight, so the one thing the honesty layer exists to say was the one thing the screen did not.
    func testTheThreeBasesAreNotDrawnTheSame() {
        XCTAssertEqual(StatGrid.valueColour(.exact), ThroColor.colorTextPrimary)
        XCTAssertEqual(StatGrid.valueColour(.range), ThroColor.colorTextPrimary)
        XCTAssertEqual(StatGrid.valueColour(.unavailable), ThroColor.colorTextSecondary,
                       "a figure that is not a fact must not be drawn at full strength")
        XCTAssertNotEqual(StatGrid.valueColour(.exact), StatGrid.valueColour(.unavailable))
    }

    /// Colour is not available to a screen reader, so the basis is spoken. "Dash" would tell
    /// somebody nothing at all, and a range read out as "58.4 to 61.2" is a different claim from
    /// "58.4 dash 61.2", which is what the raw string would give.
    func testAScreenReaderIsToldTheBasisInWords() {
        let missing = StatGrid.spoken(.unavailable("Checkout %", why: "No visit has begun on a finish."))
        XCTAssertTrue(missing.contains("not available"), missing)
        XCTAssertFalse(missing.contains("—"), "the dash is never read out")
        XCTAssertTrue(missing.contains("No visit"), "and the reason is read with it")

        let ranged = StatGrid.spoken(.range("3-dart average", "58.4–61.2", why: "One visit is unknown."))
        XCTAssertTrue(ranged.contains("between 58.4 and 61.2"), ranged)
        XCTAssertFalse(ranged.contains("–"), "the en dash is spoken as a word")

        let exact = StatGrid.spoken(.exact("180s", "3"))
        XCTAssertEqual(exact, "180s, 3", "the common case is not qualified")
    }

    // MARK: - PD-015: pressed, focus and haptics

    /// A press goes in by exactly as much as the design says an impact comes out. Derived from the
    /// token rather than typed, so the two can never drift apart.
    func testAPressIsTheInverseOfTheImpactScale() {
        XCTAssertEqual(ThroPressStyle.pressedScale, 2 - ThroMotion.motionScaleImpact, accuracy: 0.0001)
        XCTAssertLessThan(ThroPressStyle.pressedScale, 1, "a press goes in, not out")
        XCTAssertGreaterThan(ThroMotion.motionScaleImpact, 1, "and an impact comes out")
    }

    /// Four events, four sensations. A keypad that buzzed identically for a digit and for a bust
    /// would be telling the player nothing they could use without looking at the screen — which is
    /// the entire reason a haptic is worth having at a dartboard.
    func testTheFourHapticsAreFourDifferentThings() {
        let all: [ThroHaptics.Event] = [.key, .commit, .refused, .legWon]
        XCTAssertEqual(Set(all.map(ThroHaptics.weight)).count, 4)
        XCTAssertNotEqual(ThroHaptics.weight(.refused), ThroHaptics.weight(.legWon),
                          "something went wrong and something went right are not the same sensation")
        XCTAssertNotEqual(ThroHaptics.weight(.key), ThroHaptics.weight(.commit),
                          "a digit and a saved visit are not the same event")
    }

    /// The player's answer is stored under a key that is a contract with every install that has
    /// saved one. `ScoringPreferences` forwards to this, so Settings and the keypad cannot disagree
    /// about which switch they are reading.
    func testTheHapticsSettingHasOneKey() {
        XCTAssertEqual(ThroHaptics.enabledKey, "thro.haptics")
    }

    // MARK: - PD-015: the Dynamic Type contract

    /// The contract in `docs/design/DYNAMIC_TYPE.md`: reading screens go all the way, and the one
    /// screen that must fit without scrolling stops. A ceiling that quietly became the same value
    /// everywhere would be the contract failing in the direction that costs the most — a player who
    /// needs large text losing it on every screen rather than on one.
    func testTheScoringCeilingIsBelowTheReadingCeiling() {
        XCTAssertEqual(ThroDynamicType.scoringCeiling, .accessibility1)
        XCTAssertEqual(ThroDynamicType.readingCeiling, .accessibility5)
        XCTAssertLessThan(ThroDynamicType.scoringCeiling, ThroDynamicType.readingCeiling)
        XCTAssertGreaterThan(ThroDynamicType.scoringCeiling, DynamicTypeSize.large,
                             "the ceiling is an ACCESSIBILITY size, not a cap on ordinary text")
    }

    // MARK: - PD-024: the scoring screen reflows instead of stopping

    /// **The screen changes shape at exactly the size text used to stop growing.**
    ///
    /// That is the property that makes this an addition rather than a redesign: no size loses
    /// anything it had, and no size below the threshold gains a scrolling region it never needed. A
    /// threshold that drifted below it would put a scroll view under the thumb of a player scoring at
    /// an ordinary text size, which is the thing the ceiling existed to prevent.
    func testTheScreenReflowsAtExactlyTheSizeTextUsedToStop() {
        for size in [DynamicTypeSize.xSmall, .large, .xxxLarge, .accessibility1] {
            XCTAssertFalse(ThroDynamicType.reflows(at: size),
                           "\(size) scored without scrolling before and must still")
            XCTAssertEqual(ThroDynamicType.ceiling(reflowing: false), ThroDynamicType.scoringCeiling)
        }
        for size in [DynamicTypeSize.accessibility2, .accessibility3, .accessibility4, .accessibility5] {
            XCTAssertTrue(ThroDynamicType.reflows(at: size),
                          "\(size) is past the old cap, so it reflows rather than being clamped")
        }
    }

    /// A reflowing screen grows all the way. The point of PD-024 is that a player who needs
    /// `.accessibility5` gets it on the numbers they read — so a ceiling that reflowed and then
    /// stopped somewhere short would be the change without the benefit.
    func testAReflowingScreenGrowsToTheReadingCeiling() {
        XCTAssertEqual(ThroDynamicType.ceiling(reflowing: true), ThroDynamicType.readingCeiling)
        XCTAssertEqual(ThroDynamicType.ceiling(reflowing: true), .accessibility5)
        XCTAssertGreaterThan(ThroDynamicType.ceiling(reflowing: true),
                             ThroDynamicType.ceiling(reflowing: false),
                             "reflowing must buy the player something")
    }
}
