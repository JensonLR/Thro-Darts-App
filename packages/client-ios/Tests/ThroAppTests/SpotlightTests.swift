import Foundation
import XCTest
import ThroEngine
@testable import ThroApp
@testable import ThroJournal

/// What this phone puts in its own search index, and — more to the point — what it does not.
///
/// The index is on-device, private to the device owner and never synced, so the exposure is the same
/// names Home already shows. What is worth testing is the two rules that would be easy to break:
/// every entry must be an address that still resolves, and no entry may carry a figure. A search
/// result reading *"Dave — 62.4 average"* would be a statistic with no sample attached, on a surface
/// none of the honesty layer's machinery can reach.
///
/// Built on a real journal rather than a hand-made record, for the reason `AppStoreTests` gives: a
/// fixture proves the formatter, and the formatter is not the part that breaks.
final class SpotlightTests: XCTestCase {

    private var path = ""

    override func setUp() {
        super.setUp()
        path = NSTemporaryDirectory() + "thro-spotlight-\(UUID().uuidString).sqlite"
    }

    override func tearDown() {
        for suffix in ["", "-wal", "-shm"] { try? FileManager.default.removeItem(atPath: path + suffix) }
        super.tearDown()
    }

    private func journal() throws -> Journal {
        try Journal(path: path, deviceId: DeviceId("test-device"))
    }

    private let club = Club(id: "c1", name: "The Red Lion", kind: .club, meta: "",
                            yourRole: .admin)

    /// Every indexed item is addressed by its own route's URL, so a tap is a parse rather than a
    /// lookup and there is no second table to fall out of step with the index.
    func testEveryEntryIsAnAddressThatStillResolves() throws {
        let j = try journal()
        _ = try j.createMatch(NewMatch(homeName: "Ann", awayName: "Bea"))
        _ = try j.createMatch(NewMatch(homeName: "Cal", awayName: "Dee"))
        let store = AppStore(journal: j)

        let entries = ThroSpotlight.entries(matches: store.matches,
                                            people: [LocalPerson(id: "p1", name: "Ann")],
                                            clubs: [club])
        XCTAssertEqual(entries.count, 4)
        for entry in entries {
            guard let url = URL(string: entry.id), let route = ThroRoute(url: url) else {
                return XCTFail("\(entry.id) is not an address")
            }
            XCTAssertEqual(route.url.absoluteString, entry.id, "the address does not round-trip")
        }
    }

    /// The three kinds are in three domains, so one kind can be forgotten without the others.
    func testTheKindsAreSeparableFromEachOther() throws {
        let j = try journal()
        _ = try j.createMatch(NewMatch(homeName: "Ann", awayName: "Bea"))
        let entries = ThroSpotlight.entries(matches: AppStore(journal: j).matches,
                                            people: [LocalPerson(id: "p1", name: "Ann")],
                                            clubs: [club])
        XCTAssertEqual(Set(entries.map(\.domain)).count, 3)
    }

    /// A match still being played says so. A result reading "3–1" for a match at 1–1 would be a
    /// scoreline invented by a search index.
    func testAMatchInProgressSaysSoRatherThanShowingAScore() throws {
        let j = try journal()
        let live = try j.createMatch(NewMatch(homeName: "Cal", awayName: "Dee"))
        let store = AppStore(journal: j)

        let inProgress = ThroSpotlight.entries(matches: store.matches, people: [], clubs: [])
        XCTAssertEqual(inProgress.first?.subtitle?.contains("In progress"), true)
        XCTAssertEqual(inProgress.first?.title, "Cal v Dee")

        // The same record, presented as a finished match, shows its legs and nothing else.
        let finished = AppStore.HomeMatch(record: live, legsHome: 3, legsAway: 1,
                                          complete: true, unreadable: nil)
        let entry = ThroSpotlight.entries(matches: [finished], people: [], clubs: []).first
        XCTAssertEqual(entry?.subtitle?.contains("3–1"), true)
        XCTAssertEqual(entry?.subtitle?.contains("In progress"), false)
    }

    /// **No figure reaches the index.** Averages, checkout percentages and 180 counts all carry a
    /// basis and a sample everywhere else in this app; a Spotlight subtitle can carry neither, so it
    /// carries none of them.
    func testNoStatisticIsIndexed() throws {
        let j = try journal()
        _ = try j.createMatch(NewMatch(homeName: "Ann", awayName: "Bea"))
        let entries = ThroSpotlight.entries(matches: AppStore(journal: j).matches,
                                            people: [LocalPerson(id: "p1", name: "Ann")],
                                            clubs: [club])
        for entry in entries {
            let text = ([entry.title, entry.subtitle ?? ""] + entry.keywords)
                .joined(separator: " ").lowercased()
            for banned in ["average", "avg", "checkout", "180", "form", "rating", "rank"] {
                XCTAssertFalse(text.contains(banned), "\(banned) reached the index in: \(text)")
            }
        }
    }

    /// A tapped result hands back exactly the identifier that was indexed. The key and the activity
    /// type are written as their literal values, so this states the strings the system actually
    /// uses rather than trusting the import to agree with itself.
    func testATappedResultNamesThePlaceItWasIndexedFor() {
        let activity = NSUserActivity(activityType: "com.apple.corespotlightitem")
        activity.userInfo = ["kCSSearchableItemActivityIdentifier":
                                ThroRoute.person("p1").url.absoluteString]
        XCTAssertEqual(ThroSpotlight.route(for: activity), .person("p1"))
    }

    /// An activity that is not a Spotlight tap names nowhere, so an unrelated Handoff or a malformed
    /// payload cannot move the screen.
    func testAnUnrelatedActivityNamesNowhere() {
        let other = NSUserActivity(activityType: "app.thro.darts.something-else")
        other.userInfo = ["kCSSearchableItemActivityIdentifier":
                            ThroRoute.person("p1").url.absoluteString]
        XCTAssertNil(ThroSpotlight.route(for: other))

        XCTAssertNil(ThroSpotlight.route(for: NSUserActivity(activityType: "com.apple.corespotlightitem")))
    }
}
