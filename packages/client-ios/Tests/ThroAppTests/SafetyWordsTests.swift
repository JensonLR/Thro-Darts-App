import XCTest
@testable import ThroApp
import ThroNet

/// What the reporting screens promise (PD-050). A report's whole worth to the person raising it is that
/// somebody reads it and says when — so the sentence that makes that promise is tested, not looked at.
final class SafetyWordsTests: XCTestCase {

    private func raised(urgent: Bool, due: String) throws -> ThroAPI.ReportRaised {
        let json = #"""
        {"reportId":"77777777-7777-7777-7777-777777777771","subjectKind":"team",
         "subjectId":"44444444-4444-4444-4444-444444444443","urgent":\#(urgent),"answerDueAt":"\#(due)"}
        """#
        return try Wire.decoder.decode(ThroAPI.ReportRaised.self, from: Data(json.utf8))
    }

    func testAReportSaysWhenItWillBeAnswered() throws {
        let ordinary = try raised(urgent: false, due: "2026-09-12T21:00:00Z")
        let said = ReportWords.answeredBy(ordinary)
        XCTAssertTrue(said.hasPrefix("It will be answered by "), said)
        XCTAssertFalse(said.contains("24"), "a person is told an hour, not a policy: \(said)")
    }

    func testAReportAboutAChildIsNotLeftToSit() throws {
        let urgent = try raised(urgent: true, due: "2026-09-12T09:00:00Z")
        let said = ReportWords.answeredBy(urgent)
        XCTAssertTrue(said.contains("looked at first"), said)
        XCTAssertTrue(said.contains("never left to sit"), said)
    }

    func testABlockedAccountIsNamedByNobody() {
        let id = UUID(uuidString: "5C4EE45E-1234-4000-8000-00000000000A")!
        let line = ReportWords.blockedLine(id)
        XCTAssertEqual(line, "Account 5c4ee45e")
        XCTAssertFalse(line.contains("1234"), "enough of the id to tell two apart, and no more")
    }
}
