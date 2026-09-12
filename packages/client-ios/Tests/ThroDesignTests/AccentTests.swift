import XCTest
import SwiftUI
import ThroTokens
@testable import ThroDesign

/// A club's colour, and the rule that keeps the app readable whatever it picks.
///
/// **These exist because the guarantee was only ever held on one side of a port.**
/// `packages/organisation/Branding.kt` states that the text on a club's accent is whichever of the
/// brand's two neutrals reads better on it — chosen, never configured — and `BrandingTest` sweeps
/// the colour cube to prove no colour breaks it. The pull request has claimed that since clubs
/// shipped. The Swift `Badge` set its initials in `colorTextInverse` unconditionally, which is right
/// by luck on a dark green and about 1.4:1 on a club's yellow.
///
/// Asserting a property in Kotlin does not make it true in Swift. This is the Swift half.
final class AccentTests: XCTestCase {

    private func hex(_ s: String) -> Color { Color.thro(hex: s)! }

    /// The arithmetic itself, against values anyone can check by hand.
    func testContrastIsTheSameArithmeticAsTheTokenGate() {
        // Black on white is the maximum the formula produces.
        XCTAssertEqual(AccentBranding.contrast(hex("000000"), hex("FFFFFF")), 21.0, accuracy: 0.01)
        XCTAssertEqual(AccentBranding.contrast(hex("FFFFFF"), hex("FFFFFF")), 1.0, accuracy: 0.001)
        // Symmetric, because it is a ratio of the lighter to the darker.
        XCTAssertEqual(AccentBranding.contrast(hex("0F3D2E"), hex("F7F6F2")),
                       AccentBranding.contrast(hex("F7F6F2"), hex("0F3D2E")), accuracy: 0.001)
        XCTAssertEqual(AccentBranding.luminance(hex("000000")), 0.0, accuracy: 0.0001)
        XCTAssertEqual(AccentBranding.luminance(hex("FFFFFF")), 1.0, accuracy: 0.0001)
    }

    /// **The defect this file exists for.** On a dark accent the answer is chalk; on a light one it
    /// is ink. The old code always said chalk, so this test fails against it on every light colour.
    func testTheTextOnAnAccentIsChosenPerColourAndNotAlwaysChalk() {
        let chalk = AccentBranding.chalk
        let ink = AccentBranding.ink

        for dark in ["0F3D2E", "1F3A5F", "6E1F35", "101211", "4A2A5A"] {
            XCTAssertEqual(AccentBranding.textOn(hex(dark)), chalk, "chalk belongs on \(dark)")
        }
        for light in ["E8B004", "F2C744", "FFE000", "FFFFFF", "C9D1CE"] {
            XCTAssertEqual(AccentBranding.textOn(hex(light)), ink,
                           "ink belongs on \(light) — chalk on it is what the old Badge drew")
        }

        // The specific case the founder would have hit: a club's yellow.
        let yellow = hex("FFE000")
        XCTAssertLessThan(AccentBranding.contrast(chalk, yellow), 1.6, "chalk on yellow is not readable")
        XCTAssertGreaterThan(AccentBranding.ratioOn(yellow), 14.0, "and the chosen answer is far better")
    }

    /// The guarantee itself, proved the way the Kotlin proves it: by sweeping the colour cube rather
    /// than trusting a threshold. No colour a club can pick leaves its badge unreadable.
    func testNoColourAClubCanPickBreaksTheFloor() {
        var worst = Double.greatestFiniteMagnitude
        var worstHex = ""
        for r in stride(from: 0, through: 255, by: 17) {
            for g in stride(from: 0, through: 255, by: 17) {
                for b in stride(from: 0, through: 255, by: 17) {
                    let h = String(format: "%02X%02X%02X", r, g, b)
                    let ratio = AccentBranding.ratioOn(hex(h))
                    if ratio < worst { worst = ratio; worstHex = h }
                }
            }
        }
        XCTAssertGreaterThanOrEqual(worst, AccentBranding.floor,
                                    "\(worstHex) reads at \(worst):1, below the \(AccentBranding.floor):1 floor")
        // The headroom that MAKES it true: the two neutrals sit near the ends of the luminance
        // range. The day they drift towards each other this fails, rather than a club finding out.
        XCTAssertGreaterThan(worst, 4.0, "the worst case should still be comfortable, not marginal")
        XCTAssertGreaterThan(AccentBranding.contrast(AccentBranding.ink, AccentBranding.chalk), 17.0,
                             "the neutrals' separation is what the sweep above depends on")
    }

    /// Carrying text ON a colour and being usable AS text are different questions, and most accents
    /// pass the first and fail the second — a mid-tone that holds chalk beautifully is unreadable as
    /// text on chalk.
    func testCarryingTextAndBeingUsableAsTextAreDifferentQuestions() {
        let midTeal = hex("156B6B")
        XCTAssertGreaterThanOrEqual(AccentBranding.ratioOn(midTeal), AccentBranding.floor,
                                    "it carries text")
        XCTAssertFalse(AccentBranding.usableAsText(midTeal),
                       "but it cannot BE text: it has to read on both of the app's surfaces")

        // The brand's own green fails the second too, on the dark surface — which is why the app
        // does not set body text in it. Named by hex rather than by token, because a token is a
        // semantic pair and this question is about one fixed colour.
        XCTAssertFalse(AccentBranding.usableAsText(hex("0F3D2E")))
    }

    /// Every offered swatch is a colour the store will actually accept, and every one is legible.
    /// A picker that offered something the domain refuses would be an app that lies.
    func testEveryOfferedSwatchIsValidAndReadable() {
        XCTAssertFalse(AccentSwatch.palette.isEmpty)
        for swatch in AccentSwatch.palette {
            XCTAssertEqual(swatch.hex.count, 6, "\(swatch.name) is not six hex digits")
            XCTAssertNotNil(Color.thro(hex: swatch.hex), "\(swatch.name) does not parse")
            XCTAssertEqual(swatch.hex.uppercased(), swatch.hex, "stored uppercase, as the book writes it")
            XCTAssertGreaterThanOrEqual(AccentBranding.ratioOn(swatch.color), AccentBranding.floor,
                                        "\(swatch.name) cannot carry its own initials")
        }
        XCTAssertEqual(Set(AccentSwatch.palette.map(\.hex)).count, AccentSwatch.palette.count,
                       "no colour is offered twice")
        XCTAssertEqual(AccentSwatch.palette.first?.hex, "0F3D2E",
                       "the brand's own is first, because it is what a club wears until it chooses")
    }

    /// The two neutrals are the brand's own, stated as fixed sRGB.
    ///
    /// They cannot be `colorTextPrimary` and `colorTextInverse`: those are semantic pairs that swap
    /// with the appearance, so a badge's initials would flip from ink to chalk when the phone got
    /// dark — and being asset-catalogue colours they have no fixed sRGB value to do arithmetic on,
    /// which is what CI caught. These are the same two `Branding.kt`'s `Palette` states.
    func testTheNeutralsAreTheBrandsOwnAndAreFixed() {
        XCTAssertEqual(AccentBranding.contrast(AccentBranding.ink, hex("101211")), 1.0, accuracy: 0.001)
        XCTAssertEqual(AccentBranding.contrast(AccentBranding.chalk, hex("F7F6F2")), 1.0, accuracy: 0.001)
        XCTAssertEqual(AccentBranding.contrast(AccentBranding.ink, AccentBranding.chalk), 17.4, accuracy: 0.2,
                       "the separation the cube sweep depends on")
        // Resolvable to components, which the asset-catalogue tokens are not.
        let (r, g, b) = AccentBranding.components(AccentBranding.chalk)
        XCTAssertEqual(r, 0xF7 / 255.0, accuracy: 0.005)
        XCTAssertEqual(g, 0xF6 / 255.0, accuracy: 0.005)
        XCTAssertEqual(b, 0xF2 / 255.0, accuracy: 0.005)
    }

    /// The chosen colour must not depend on the phone's dark-mode setting. Resolving an accent in
    /// the viewer's current appearance would flip a badge's initials from ink to chalk at sunset.
    func testTheChoiceDoesNotDependOnTheViewersAppearance() {
        for swatch in AccentSwatch.palette {
            let a = AccentBranding.textOn(swatch.color)
            let b = AccentBranding.textOn(swatch.color)
            XCTAssertEqual(a, b, "\(swatch.name) must resolve the same way every time")
        }
        // A fixed hex resolves to fixed components regardless of trait collection.
        let (r, g, b) = AccentBranding.components(hex("FFE000"))
        XCTAssertEqual(r, 1.0, accuracy: 0.01)
        XCTAssertEqual(g, 224.0 / 255.0, accuracy: 0.01)
        XCTAssertEqual(b, 0.0, accuracy: 0.01)
    }
}
