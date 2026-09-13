import Foundation
import XCTest
@testable import ThroNet

/// The notice about people's information (PD-094): what counts as one, who it speaks to, and that asking for it says
/// nothing about the person asking.
final class NoticeTests: XCTestCase {

    /// Answers in order and records what it was asked; with nothing left to say it behaves like no network.
    final class Script: Transport, @unchecked Sendable {
        var answers: [(Int, String)]
        var seen: [URLRequest] = []
        init(_ answers: [(Int, String)]) { self.answers = answers }
        func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
            seen.append(request)
            guard !answers.isEmpty else { throw URLError(.notConnectedToInternet) }
            let (code, body) = answers.removeFirst()
            return (Data(body.utf8), HTTPURLResponse(url: request.url!, statusCode: code, httpVersion: nil, headerFields: nil)!)
        }
    }

    private let web = URL(string: "https://web.example")!

    private func file(_ fields: String) -> Data { Data("{\(fields)}".utf8) }

    private let live = """
    "format": 1, "active": true, "id": "2026-10-01", "published": "2026-10-01T09:00:00Z",
    "title": "Somebody read THRØ's records", "summary": "What happened, in a sentence.", "body": ["More."],
    "under18": {"title": "Somebody saw some information", "summary": "What happened, shorter.", "body": ["More."]}
    """

    func testALiveNoticeIsReadWithWordsForBothReaders() {
        guard case .notice(let notice) = ServiceNotice.answer(from: file(live)) else {
            return XCTFail("a live notice was not read")
        }
        XCTAssertEqual(notice.id, "2026-10-01")
        XCTAssertEqual(notice.adult.title, "Somebody read THRØ's records")
        XCTAssertEqual(notice.under18.summary, "What happened, shorter.")
    }

    func testAnInactiveFileSaysThereIsNothingLive() {
        XCTAssertEqual(ServiceNotice.answer(from: file(#""format": 1, "active": false"#)), .nothingLive)
    }

    func testTheCommittedFileReadsAsNothingLive() throws {
        // The app, thro.js and check_notice.py read one file. This holds the app to the file actually published,
        // so a change to its shape cannot pass the web's checks and leave every phone reading it as unknown.
        var root = URL(fileURLWithPath: #filePath)
        for _ in 0..<5 { root.deleteLastPathComponent() }
        let committed = root.appendingPathComponent("apps/web/notice.json")
        XCTAssertEqual(ServiceNotice.answer(from: try Data(contentsOf: committed)), .nothingLive)
    }

    func testAnythingShortOfAReadableLiveNoticeIsNotANotice() {
        let when = #""published": "2026-10-01T09:00:00Z""#
        let adult = #""title": "t", "summary": "s", "body": ["b"]"#
        let young = #""under18": {"title": "t", "summary": "s", "body": ["b"]}"#
        let broken: [(String, String)] = [
            ("no words for under-18s", #""format": 1, "active": true, "id": "a", \#(when), \#(adult)"#),
            ("an empty paragraph", #""format": 1, "active": true, "id": "a", \#(when), "title": "t", "summary": "s", "body": ["  "], \#(young)"#),
            ("no body at all", #""format": 1, "active": true, "id": "a", \#(when), "title": "t", "summary": "s", "body": [], \#(young)"#),
            ("an empty title", #""format": 1, "active": true, "id": "a", \#(when), "title": "", "summary": "s", "body": ["b"], \#(young)"#),
            ("no id", #""format": 1, "active": true, \#(when), \#(adult), \#(young)"#),
            ("a date with no time", #""format": 1, "active": true, "id": "a", "published": "2026-10-01", \#(adult), \#(young)"#),
            ("a date nobody can read", #""format": 1, "active": true, "id": "a", "published": "yesterday", \#(adult), \#(young)"#),
            ("a format this build does not know", #""format": 2, "active": true"#),
            ("active written as a number", #""format": 1, "active": 1"#),
            ("no format", #""active": true"#),
        ]
        for (why, fields) in broken {
            XCTAssertEqual(ServiceNotice.answer(from: file(fields)), .unknown, why)
        }
        XCTAssertEqual(ServiceNotice.answer(from: Data("<html>not the file</html>".utf8)), .unknown,
                       "a site that answers every path with a page must not be read as a notice")
    }

    func testAnAdultReadsTheFullNoticeAndEverybodyElseTheUnderEighteenOne() {
        guard case .notice(let notice) = ServiceNotice.answer(from: file(live)) else { return XCTFail("not read") }
        XCTAssertEqual(notice.forReader(ageBand: "adult").words, notice.adult)
        XCTAssertFalse(notice.forReader(ageBand: "adult").underEighteen)
        XCTAssertTrue(notice.forReader(ageBand: "minor").underEighteen)
        XCTAssertTrue(notice.forReader(ageBand: "unknown").underEighteen, "an age nobody has said is not adult")
        XCTAssertTrue(notice.forReader(ageBand: nil).underEighteen, "nobody signed in is an age nobody has said")
        XCTAssertEqual(ServiceNotice.page(on: web, underEighteen: true).absoluteString, "https://web.example/notice-under-18.html")
        XCTAssertEqual(ServiceNotice.page(on: web, underEighteen: false).absoluteString, "https://web.example/notice.html")
    }

    func testAskingSaysNothingAboutWhoIsAsking() async {
        let script = Script([(200, "{\(live)}")])
        let answer = await ServiceNotice.ask(web, transport: script)
        guard case .notice = answer else { return XCTFail("the notice was not read") }
        let request = script.seen[0]
        XCTAssertEqual(request.url?.absoluteString, "https://web.example/notice.json")
        XCTAssertEqual(request.httpMethod, "GET")
        XCTAssertNil(request.value(forHTTPHeaderField: "X-Thro-Device"), "no device id")
        XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"), "no account")
        XCTAssertNil(request.value(forHTTPHeaderField: "Cookie"), "no cookie")
        XCTAssertFalse(request.httpShouldHandleCookies)
        XCTAssertEqual(request.cachePolicy, .reloadIgnoringLocalCacheData)
    }

    func testATakenDownFileIsNothingLiveAndAnUnreachableSiteIsUnknown() async {
        let gone = await ServiceNotice.ask(web, transport: Script([(404, "Not Found")]))
        XCTAssertEqual(gone, .nothingLive)
        let failing = await ServiceNotice.ask(web, transport: Script([(503, "")]))
        XCTAssertEqual(failing, .unknown)
        let offline = await ServiceNotice.ask(web, transport: Script([]))
        XCTAssertEqual(offline, .unknown)
    }
}
