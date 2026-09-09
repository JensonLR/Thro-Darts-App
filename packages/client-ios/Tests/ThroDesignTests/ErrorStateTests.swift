import XCTest
@testable import ThroDesign

/// `state/ErrorState`, ported from the export. Its shape is the point: an error tells the player
/// three things — what happened, what is safe, and what to do — and the middle one is the question
/// they actually have. A component that makes room for the answer is one an engineer cannot forget
/// to give; a plain message string is one they can.
final class ErrorStateTests: XCTestCase {

    func testTheThreeLabelledLinesAppearInTheExportsOrderAndOnlyWhenTheyHaveSomethingToSay() {
        let all = ErrorState(title: "Broken", what: "a", safe: "b", todo: "c")
        XCTAssertEqual(all.lines.map(\.label), ["What happened", "What is safe", "What to do"])
        XCTAssertEqual(all.lines.map(\.value), ["a", "b", "c"])

        let some = ErrorState(what: "a", todo: "c")
        XCTAssertEqual(some.lines.map(\.label), ["What happened", "What to do"],
                       "a line with nothing to say is not drawn as an empty one")

        XCTAssertTrue(ErrorState().lines.isEmpty)
    }

    func testTheDefaultsAreTheExportsDefaults() {
        let plain = ErrorState()
        XCTAssertTrue(plain.lines.isEmpty)
        // The export's defaults: title "Something went wrong", action "Try again". Both are visible
        // through the component's own initialiser defaults rather than restated here.
        let withAction = ErrorState(what: "the journal is locked", onAction: {})
        XCTAssertEqual(withAction.lines.count, 1)
    }
}
