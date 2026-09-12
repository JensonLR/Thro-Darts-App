import XCTest
import SwiftUI
@testable import ThroDesign

/// PD-006: the ten embedded faces, and the table that sends each type role's weight to one of them.
final class FontFaceTests: XCTestCase {
    /// Every role resolves to a face the app embeds; no weight falls through to a name that is not shipped.
    func testEveryRoleResolvesToAnEmbeddedFace() {
        for role in ThroTypography.all {
            let face = ThroFont.faceName(role.family, weight: role.weight)
            XCTAssertTrue(ThroFont.embeddedFaces.contains(face), "\(face) is not embedded")
        }
    }

    /// The sport family stops at Bold, so the heavier weights take Bold rather than a face that does not exist.
    func testSportWeightsAboveBoldTakeBold() {
        XCTAssertEqual(ThroFont.faceName(.sport, weight: .heavy), "IBMPlexSansCond-Bold")
        XCTAssertEqual(ThroFont.faceName(.sport, weight: .black), "IBMPlexSansCond-Bold")
        XCTAssertEqual(ThroFont.faceName(.ui, weight: .heavy), "Archivo-ExtraBold")
        XCTAssertEqual(ThroFont.faceName(.ui, weight: .black), "Archivo-Black")
    }

    /// The light weights the design never uses still resolve, to Regular, so a stray weight cannot break a layout.
    func testWeightsBelowRegularTakeRegular() {
        XCTAssertEqual(ThroFont.faceName(.ui, weight: .thin), "Archivo-Regular")
        XCTAssertEqual(ThroFont.faceName(.sport, weight: .light), "IBMPlexSansCond-Regular")
    }

    /// Ten faces, no duplicates: the same list the Info.plist ships, which check_fonts.py compares on every push.
    func testEmbeddedFacesAreTenDistinctNames() {
        XCTAssertEqual(ThroFont.embeddedFaces.count, 10)
        XCTAssertEqual(Set(ThroFont.embeddedFaces).count, 10)
    }
}
