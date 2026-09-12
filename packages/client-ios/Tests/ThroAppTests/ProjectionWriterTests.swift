import Foundation
import XCTest
import ThroJournal
import ThroLiveKit
import ThroPlay
@testable import ThroApp

/// What the app puts in the widgets' file.
///
/// The store side is tested in `ThroLiveKitTests`; this is the assembly — the decisions about what
/// a Home Screen is allowed to say. Two of them are worth holding: **only a fixture that is
/// actually happening**, and **counts rather than figures**.
final class ProjectionWriterTests: XCTestCase {

    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func fixture(_ id: String, in hours: Double, state: FixtureState = .scheduled,
                         title: String = "Home to The Bell") -> Fixture {
        Fixture(id: id, title: title, when: "the row's own wording",
                at: now.addingTimeInterval(hours * 3600), venue: "The Red Lion", state: state)
    }

    private func club(_ fixtures: [Fixture]) -> Club {
        Club(id: "c1", name: "The Feathers", kind: .team, meta: "", yourRole: .admin,
             fixtures: fixtures)
    }

    // MARK: the next fixture

    func testTheSoonestFixtureAheadIsTheOneShown() {
        let clubs = [club([fixture("late", in: 72), fixture("soon", in: 5), fixture("later", in: 200)])]
        XCTAssertEqual(ThroProjectionWriter.nextFixture(in: clubs, now: now)?.title, "Home to The Bell")
        let next = ThroProjectionWriter.nextFixture(in: clubs, now: now)
        XCTAssertEqual(next?.at, now.addingTimeInterval(5 * 3600), "the soonest one ahead")
        XCTAssertEqual(next?.venue, "The Red Lion")
    }

    /// **Only a fixture that is actually happening.** A cancelled one is not, and a postponed one
    /// has no time anybody trusts — putting either on a Home Screen is telling somebody to turn up.
    /// A played one is behind us whatever its clock says.
    func testOnlyAScheduledFixtureReachesTheHomeScreen() {
        for state in [FixtureState.cancelled, .postponed, .played] {
            XCTAssertNil(ThroProjectionWriter.nextFixture(in: [club([fixture("f", in: 5, state: state)])],
                                                          now: now),
                         "a \(state.label.lowercased()) fixture must not be shown as next")
        }
    }

    func testAFixtureThatHasPassedIsNotTheNextOne() {
        XCTAssertNil(ThroProjectionWriter.nextFixture(in: [club([fixture("gone", in: -1)])], now: now))
    }

    func testAFixtureWithNoInstantIsNotShownRatherThanShownAtAGuessedTime() {
        let undated = Fixture(id: "f", title: "Home to The Bell", when: "sometime", venue: "The Bell")
        XCTAssertNil(ThroProjectionWriter.nextFixture(in: [club([undated])], now: now))
    }

    func testAPhoneWithNoClubsHasNoNextFixture() {
        XCTAssertNil(ThroProjectionWriter.nextFixture(in: [], now: now))
    }

    /// Across every club, league and tournament this phone keeps — a player's next darts do not
    /// care which list they are on.
    func testTheNextFixtureIsFoundAcrossEveryCompetition() {
        let league = Club(id: "l1", name: "Kettering A", kind: .league, meta: "", yourRole: .admin,
                          fixtures: [fixture("league", in: 2, title: "Feathers v Bell")])
        let clubs = [club([fixture("club", in: 40)]), league]
        XCTAssertEqual(ThroProjectionWriter.nextFixture(in: clubs, now: now)?.title, "Feathers v Bell")
    }

    // MARK: the whole file

    /// **Counts, never averages.** A count carries its own sample; an average needs a basis a widget
    /// has no room for. This is the same rule the Live Activity and Spotlight are held to, on the
    /// third surface none of the honesty layer's machinery can reach.
    func testTheFileCarriesCountsAndTheLegThatIsBeingScored() {
        let leg = ThroLiveState(homeName: "Ann", awayName: "Bea",
                                homeRemaining: 141, awayRemaining: 220,
                                homeLegs: 1, awayLegs: 2, thrower: .home)
        let week = DeviceSummary.Week(matches: 3, legs: 9, unreadable: 0, figures: [], quietWeek: false)
        let assembled = ThroProjectionWriter.assemble(
            matches: [], week: week, clubs: [club([fixture("f", in: 5)])],
            live: leg, liveFormat: "501 · Best of 5 · Double out", now: now)

        XCTAssertEqual(assembled.live, leg)
        XCTAssertEqual(assembled.liveFormat, "501 · Best of 5 · Double out")
        XCTAssertEqual(assembled.legsThisWeek, 9)
        XCTAssertEqual(assembled.matches, 0)
        XCTAssertEqual(assembled.nextFixture?.title, "Home to The Bell")
        XCTAssertEqual(assembled.writtenAt, now, "the file says when it was written")
        XCTAssertEqual(assembled.version, ThroProjection.format)
    }

    /// A phone with nothing on it produces a readable file rather than none. The widget's empty
    /// state is a thing this app can say; a missing file is a thing it cannot explain.
    func testAnEmptyPhoneStillProducesAReadableFile() {
        let assembled = ThroProjectionWriter.assemble(matches: [], week: nil, clubs: [],
                                                      live: nil, liveFormat: "", now: now)
        XCTAssertTrue(assembled.isReadable)
        XCTAssertNil(assembled.live)
        XCTAssertNil(assembled.nextFixture)
        XCTAssertEqual(assembled.legsThisWeek, 0, "no week is nought legs, not an invented figure")
        XCTAssertEqual(ThroWidgetCopy.idle(assembled), "No matches on this phone yet")
    }

    // MARK: what the widget says

    /// The staleness rule, on a surface the app cannot renew: WidgetKit refreshes when it chooses,
    /// so a score on a Home Screen can be hours behind the phone it is on and look exactly as
    /// current as one written a second ago.
    func testAStaleWidgetSaysSoRatherThanAssertingAScore() {
        let leg = ThroLiveState(homeName: "Ann", awayName: "Bea", homeRemaining: 141,
                                awayRemaining: 220, homeLegs: 1, awayLegs: 2, thrower: .home)
        let p = ThroProjection(writtenAt: now, live: leg)
        XCTAssertEqual(ThroWidgetCopy.caption(p, now: now.addingTimeInterval(60)), "Ann to throw")
        let stale = ThroWidgetCopy.caption(p, now: now.addingTimeInterval(ThroProjection.freshness + 1))
        XCTAssertTrue(stale.lowercased().contains("out of date"), stale)
    }

    /// A decided match outranks staleness, because "Ann wins" does not go out of date.
    func testADecidedMatchIsNotCalledStale() {
        let done = ThroLiveState(homeName: "Ann", awayName: "Bea", homeRemaining: 0,
                                 awayRemaining: 220, homeLegs: 3, awayLegs: 1,
                                 thrower: nil, winner: .home)
        let p = ThroProjection(writtenAt: now, live: done)
        XCTAssertEqual(ThroWidgetCopy.caption(p, now: now.addingTimeInterval(86_400)), "Ann wins")
    }

    /// The idle line counts, in singular and plural, and says the two facts apart: a phone with
    /// matches and none this week is not the same as a phone with no matches.
    func testTheIdleLineCountsAndTellsAQuietWeekFromAnEmptyPhone() {
        func idle(_ matches: Int, _ legs: Int) -> String {
            ThroWidgetCopy.idle(ThroProjection(writtenAt: now, matches: matches, legsThisWeek: legs))
        }
        XCTAssertEqual(idle(0, 0), "No matches on this phone yet")
        XCTAssertEqual(idle(1, 0), "1 match · none this week")
        XCTAssertEqual(idle(4, 1), "4 matches · 1 leg this week")
        XCTAssertEqual(idle(4, 9), "4 matches · 9 legs this week")
    }
}
