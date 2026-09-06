import XCTest
import SwiftUI
@testable import ThroDesign

final class AppearanceTests: XCTestCase {
    /// The stored value is a contract with every install that has already saved one.
    func testStoredValuesAreStable() {
        XCTAssertEqual(Appearance.system.rawValue, "system")
        XCTAssertEqual(Appearance.light.rawValue, "light")
        XCTAssertEqual(Appearance.dark.rawValue, "dark")
        XCTAssertEqual(Appearance.storageKey, "thro.appearance")
    }

    func testSystemMeansNoPreferenceAndTheOthersMeanWhatTheySay() {
        XCTAssertNil(Appearance.system.colorScheme)
        XCTAssertEqual(Appearance.light.colorScheme, .light)
        XCTAssertEqual(Appearance.dark.colorScheme, .dark)
    }

    func testAnUnknownStoredValueFallsBackToSystem() {
        XCTAssertEqual(Appearance(stored: "sepia"), .system)
        XCTAssertEqual(Appearance(stored: ""), .system)
        XCTAssertEqual(Appearance(stored: "dark"), .dark)
    }
}
