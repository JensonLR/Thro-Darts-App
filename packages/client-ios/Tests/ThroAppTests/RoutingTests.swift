import XCTest
import ThroDesign
import ThroJournal
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
}
