import Foundation
import XCTest
@testable import ThroApp
@testable import ThroNet

/// How Home holds the notice (PD-094): when it asks, what keeps a notice up, and what takes it down.
@MainActor
final class ServiceNoticesTests: XCTestCase {

    private let web = URL(string: "https://web.example")!
    private var clock = Date(timeIntervalSince1970: 1_800_000_000)

    private func freshDefaults() -> UserDefaults {
        let name = "service-notices-\(UUID().uuidString)"
        addTeardownBlock { UserDefaults().removePersistentDomain(forName: name) }
        return UserDefaults(suiteName: name)!
    }

    private func live(_ id: String) -> (Int, String) {
        (200, """
        {"format": 1, "active": true, "id": "\(id)", "published": "2026-10-01T09:00:00Z",
         "title": "A notice", "summary": "What happened.", "body": ["More."],
         "under18": {"title": "A notice", "summary": "What happened, shorter.", "body": ["More."]}}
        """)
    }

    private func notices(_ script: NoticeTests.Script, defaults: UserDefaults? = nil) -> ServiceNotices {
        ServiceNotices(web: web, transport: script, defaults: defaults ?? freshDefaults(), now: { [unowned self] in self.clock })
    }

    private func later() { clock = clock.addingTimeInterval(ServiceNotices.interval) }

    func testALiveNoticeShowsAndStaysAwayOnceItIsPutAway() async {
        let store = freshDefaults()
        let first = notices(NoticeTests.Script([live("a")]), defaults: store)
        await first.refresh()
        XCTAssertEqual(first.showing?.id, "a")
        first.putAway()
        XCTAssertNil(first.showing)
        // The next launch reads the same notice and keeps it put away.
        let next = notices(NoticeTests.Script([live("a")]), defaults: store)
        await next.refresh()
        XCTAssertNotNil(next.current)
        XCTAssertNil(next.showing)
    }

    func testAnUpdatedNoticeComesBackAfterTheOldOneWasPutAway() async {
        let held = notices(NoticeTests.Script([live("a"), live("a-updated")]))
        await held.refresh()
        held.putAway()
        later()
        await held.refresh()
        XCTAssertEqual(held.showing?.id, "a-updated", "an update must not stay hidden behind the notice it replaced")
    }

    func testAnInactiveFileOrATakenDownOneTakesTheNoticeDown() async {
        for ending in [(200, #"{"format": 1, "active": false}"#), (404, "Not Found")] {
            let held = notices(NoticeTests.Script([live("a"), ending]))
            await held.refresh()
            later()
            await held.refresh()
            XCTAssertNil(held.current, "the site answered \(ending.0)")
        }
    }

    func testANoticeAlreadyReadStaysUpWhenTheSiteCannotBeReached() async {
        let held = notices(NoticeTests.Script([live("a"), (503, "")]))
        await held.refresh()
        later()
        await held.refresh()  // the site is failing
        later()
        await held.refresh()  // and then there is no network at all
        XCTAssertEqual(held.showing?.id, "a", "losing signal in a pub is not the notice being withdrawn")
    }

    func testTheSiteIsAskedAtMostOnceAMinute() async {
        let script = NoticeTests.Script([live("a"), live("b")])
        let held = notices(script)
        await held.refresh()
        clock = clock.addingTimeInterval(ServiceNotices.interval / 2)
        await held.refresh()
        XCTAssertEqual(script.seen.count, 1, "a return to the front inside a minute does not ask again")
        clock = clock.addingTimeInterval(ServiceNotices.interval)
        await held.refresh()
        XCTAssertEqual(script.seen.count, 2)
        XCTAssertEqual(held.showing?.id, "b")
    }

    func testABuildThatNamesNoWebSiteAsksNothing() async {
        let script = NoticeTests.Script([live("a")])
        let held = ServiceNotices(web: nil, transport: script, defaults: freshDefaults(), now: { Date() })
        await held.refresh()
        XCTAssertTrue(script.seen.isEmpty)
        XCTAssertNil(held.showing)
        XCTAssertNil(held.page(underEighteen: true))
    }

    func testThePageFollowsTheReader() {
        let held = ServiceNotices(web: web, transport: NoticeTests.Script([]), defaults: freshDefaults())
        XCTAssertEqual(held.page(underEighteen: true)?.lastPathComponent, "notice-under-18.html")
        XCTAssertEqual(held.page(underEighteen: false)?.lastPathComponent, "notice.html")
    }
}
