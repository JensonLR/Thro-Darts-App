import XCTest
import ThroDesign
import ThroJournal
import ThroLiveKit
@testable import ThroApp

/// An address has to survive being written down and read back, and it has to refuse a link it does
/// not understand rather than guessing.
///
/// The second half is the one worth testing. A parser that falls back to Home on anything it cannot
/// read looks friendlier and is worse: a mistyped or truncated link would open the app somewhere
/// arbitrary, and the player would have no way to tell that from the app deciding to move on its
/// own. Every unreadable case here asserts `nil`.
final class RoutingTests: XCTestCase {

    private let every: [ThroRoute] = BottomBar.Tab.allCases.map { .tab($0) } + [
        .settings,
        .match(MatchId("7F2A-9C31")),
        .person("person-1"),
        .club("club-1"),
        .newMatch,
        .continueLatest,
    ]

    /// Every route can be written as a link and read back as itself.
    func testEveryRouteRoundTrips() {
        for route in every {
            let url = route.url
            XCTAssertEqual(ThroRoute(url: url), route, "\(url) did not read back as \(route)")
        }
    }

    /// The scheme is ASCII and is not the product name — ADR-011 fixes both, because `Ø` cannot
    /// appear in a URL scheme and a rename must not invalidate every link ever shared.
    func testTheSchemeIsAsciiAndNotTheProductName() {
        XCTAssertEqual(ThroRoute.scheme, "thro")
        XCTAssertTrue(ThroRoute.scheme.allSatisfy { $0.isASCII })
        XCTAssertEqual(ThroRoute.scheme, ThroRoute.scheme.lowercased())
        for route in every {
            XCTAssertEqual(route.url.scheme, "thro")
        }
    }

    /// The path grammar is the contract, not the scheme. The same parser reads the custom scheme
    /// this build ships and the `https://` paths ADR-011 fixed, so universal links become a hosting
    /// decision rather than a code change.
    func testTheSamePathsWorkUnderHttps() {
        let pairs = [
            ("thro://m/7F2A", "https://thro.app/m/7F2A"),
            ("thro://p/person-1", "https://thro.app/p/person-1"),
            ("thro://e/club-1", "https://thro.app/e/club-1"),
            ("thro://tab/live", "https://thro.app/tab/live"),
            ("thro://settings", "https://thro.app/settings"),
        ]
        for (custom, web) in pairs {
            let a = ThroRoute(url: URL(string: custom)!)
            let b = ThroRoute(url: URL(string: web)!)
            XCTAssertNotNil(a, custom)
            XCTAssertEqual(a, b, "\(custom) and \(web) should name the same place")
        }
    }

    /// ADR-011's short shapes and the spelled-out ones are the same address.
    func testTheLongFormsAreAliases() {
        XCTAssertEqual(ThroRoute(url: URL(string: "thro://match/7F2A")!), .match(MatchId("7F2A")))
        XCTAssertEqual(ThroRoute(url: URL(string: "thro://person/p1")!), .person("p1"))
        XCTAssertEqual(ThroRoute(url: URL(string: "thro://club/c1")!), .club("c1"))
    }

    /// The two addresses a Shortcut and the Action Button use. `continue` is late-bound on purpose:
    /// a Shortcut saved in March must still mean *the one I am in the middle of* in December, which
    /// naming a match id would freeze at the moment the Shortcut was made.
    func testTheActionAddressesAreNamedNotFrozen() {
        XCTAssertEqual(ThroRoute(url: URL(string: "thro://new")!), .newMatch)
        XCTAssertEqual(ThroRoute(url: URL(string: "thro://continue")!), .continueLatest)
        XCTAssertEqual(ThroRoute.continueLatest.url.absoluteString, "thro://continue")
        XCTAssertNotEqual(ThroRoute.continueLatest, ThroRoute.match(MatchId("continue")))
    }

    /// A link this build cannot read opens nothing.
    func testAnUnreadableLinkIsRefusedRatherThanGuessed() {
        let bad = [
            "thro://",                    // nothing at all
            "thro://elsewhere",           // a head this build has no case for
            "thro://m",                   // a match with no id
            "thro://m/",                  // an id that is empty
            "thro://tab/rankings",        // a tab that does not exist (and, under OD-001, must not)
            "https://thro.app/",          // a bare domain
            "https://thro.app/nothing/1",
        ]
        for text in bad {
            guard let url = URL(string: text) else { continue }
            XCTAssertNil(ThroRoute(url: url), "\(text) should name nowhere")
        }
    }

    /// A percent-encoded identifier survives the trip. Club ids come from a database this device's
    /// owner can edit, so neither half of the round trip may assume they are tidy.
    ///
    /// The writing half is the one that had the bug: the identifier was interpolated raw and
    /// `URL(string:)` was left to refuse it, which turned an awkward id into a link to Home — a
    /// wrong address that looks like a working one.
    func testAnIdentifierWithAwkwardCharactersSurvivesBothWays() {
        XCTAssertEqual(ThroRoute(url: URL(string: "thro://e/club%20one")!), .club("club one"))
        for awkward in ["club one", "a/b", "a?b", "a#b", "café", "100%", "a b/c?d#e"] {
            let route = ThroRoute.club(awkward)
            XCTAssertEqual(ThroRoute(url: route.url), route, "\(awkward) did not survive")
            XCTAssertEqual(route.url.scheme, "thro", "\(awkward) fell back to another scheme")
        }
    }

    /// A slash inside an identifier must not become a path separator, or an id could forge an
    /// address for somewhere else entirely.
    func testASlashInAnIdentifierCannotForgeAPath() {
        let route = ThroRoute.club("c1/../m/7F2A")
        XCTAssertFalse(route.url.absoluteString.contains("/../"))
        XCTAssertEqual(ThroRoute(url: route.url), route)
    }

    /// The router hands a route over exactly once. A second application would send a player back to
    /// the same place on every re-evaluation of the view.
    func testARouteIsTakenOnce() {
        let router = ThroRouter()
        XCTAssertNil(router.take())
        router.open(URL(string: "thro://tab/you")!)
        XCTAssertEqual(router.pending, .tab(.you))
        XCTAssertEqual(router.take(), .tab(.you))
        XCTAssertNil(router.pending)
        XCTAssertNil(router.take())
    }

    /// A link that names nothing leaves whatever was already waiting alone, and says nothing to the
    /// player: there is no honest message about a link they did not knowingly follow.
    func testAnUnreadableLinkDoesNotDisturbAWaitingRoute() {
        let router = ThroRouter()
        router.go(.settings)
        router.open(URL(string: "thro://elsewhere")!)
        XCTAssertEqual(router.pending, .settings)
    }

    // MARK: the widgets' own links

    /// **A widget's tap has to go where the widget is pointing.**
    ///
    /// Both widgets sent every tap to *continue the match*, in all three of the states they draw. On
    /// the one showing a live scoreboard that is right. On the one reading *Tuesday · Feathers v
    /// Bell · 8pm* it opened the Play tab with nothing on it — no crash, no error, and nothing to do
    /// with the fixture somebody had just tapped. A destination that ignores what is drawn above it
    /// is a link to somebody else's content.
    ///
    /// This test is the whole loop: the URL the widget would carry, parsed by the app that receives
    /// it. Either half alone would pass while the two disagreed — which is exactly how a widget
    /// comes to open the wrong screen with every test green.
    func testEachWidgetStateLinksToTheScreenThatHoldsWhatItIsShowing() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        func route(_ projection: ThroProjection?) -> ThroRoute? {
            ThroRoute(url: ThroWidgetCopy.destination(projection, now: now))
        }

        let leg = ThroLiveState(homeName: "Ann", awayName: "Bea", homeRemaining: 141,
                                awayRemaining: 220, homeLegs: 1, awayLegs: 2, thrower: .home)
        let scoring = ThroProjection(writtenAt: now, live: leg, liveFormat: "501",
                                     nextFixture: nil, matches: 3, legsThisWeek: 9)
        XCTAssertEqual(route(scoring), .continueLatest, "the match being scored")

        let ahead = ThroProjectedFixture(title: "Feathers v Bell",
                                         at: now.addingTimeInterval(3 * 60 * 60), venue: "The Bell")
        let waiting = ThroProjection(writtenAt: now, live: nil, liveFormat: "",
                                     nextFixture: ahead, matches: 3, legsThisWeek: 9)
        XCTAssertEqual(route(waiting), .tab(.live),
                       "the fixture it is showing lives on the Live tab, not on Play")

        // A fixture that has gone past is not shown, so it must not be linked to either.
        let over = ThroProjection(writtenAt: now, live: nil, liveFormat: "",
                                  nextFixture: ThroProjectedFixture(title: "Last week",
                                                                    at: now.addingTimeInterval(-60),
                                                                    venue: ""),
                                  matches: 3, legsThisWeek: 9)
        XCTAssertEqual(route(over), .newMatch)

        let empty = ThroProjection(writtenAt: now, live: nil, liveFormat: "", nextFixture: nil,
                                   matches: 0, legsThisWeek: 0)
        XCTAssertEqual(route(empty), .newMatch, "nothing to continue and nothing coming")
        XCTAssertEqual(route(nil), .newMatch, "and a phone whose file has never been written")
    }
}
