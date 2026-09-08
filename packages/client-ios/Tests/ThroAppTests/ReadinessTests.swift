import XCTest
@testable import ThroApp

/// The screen that answers the founder's *"not sure I can see or test majority of this."*
///
/// Every test here is about the **wording and the state**, because that is the whole product: the
/// facts come from the phone, and what this code does with them is decide which of five states a
/// surface is in and what sentence tells somebody where to look. A row that says "Working" about
/// something they cannot find is worse than no screen at all — it moves the failure from "I cannot
/// find it" to "the app is lying to me".
final class ReadinessTests: XCTestCase {

    private func find(_ id: String, _ facts: ThroReadiness.Facts) -> ThroReadiness.Surface {
        let surface = ThroReadiness.surfaces(facts).first { $0.id == id }
        return surface ?? ThroReadiness.Surface(id: "missing", name: "missing", state: .absent,
                                                detail: "missing")
    }

    // MARK: what the screen promises about itself

    func testEveryRowSaysWhereToLookOrWhatIsStoppingIt() {
        // Two extremes and the default, so no row is exercised only in its happy state.
        let all: [ThroReadiness.Facts] = [
            .init(),
            .init(liveActivitiesAllowed: true, matchInProgress: true, appGroupReachable: true,
                  projectionWrittenAt: Date(), externalDisplayAttached: true, finishedMatches: 3,
                  notifications: .allowed, remindersSet: 2, calendar: .allowed, datedFixtures: 1,
                  spotlightAvailable: true, spotlightOn: true, diagnosticsOn: true,
                  diagnosticsHeld: 4, brandFacesRegistered: true),
            .init(notifications: .refused, calendar: .refused, spotlightAvailable: true),
        ]
        for facts in all {
            for surface in ThroReadiness.surfaces(facts) {
                XCTAssertFalse(surface.name.isEmpty, "a row with no name")
                XCTAssertGreaterThan(surface.detail.count, 40,
                                     "\(surface.id) says '\(surface.detail)', which is not enough "
                                   + "to find anything by")
            }
        }
    }

    func testNoTwoRowsShareAnIdentity() {
        let surfaces = ThroReadiness.surfaces(.init())
        XCTAssertEqual(Set(surfaces.map(\.id)).count, surfaces.count, "two rows share an id")
        XCTAssertEqual(Set(surfaces.map(\.name)).count, surfaces.count, "two rows share a name")
    }

    /// The states exist to be told apart. Two that read alike would be one state wearing two names,
    /// and the screen would be saying nothing by saying it twice.
    func testNoTwoStatesReadAlike() {
        let labels = ThroReadiness.State.allCases.map(\.label)
        XCTAssertEqual(Set(labels).count, ThroReadiness.State.allCases.count,
                       "two states read alike: \(labels)")
    }

    /// A blank phone must not read as a broken one. Nothing is set up, nothing has been asked, and
    /// the only thing that is genuinely unavailable is the domain nobody has bought.
    func testAFreshPhoneReportsNothingBrokenExceptWhatIsGenuinelyAbsent() {
        // A build with its App Group, its fonts and its Live Activities in order, on a phone where
        // the player has done nothing yet.
        let fresh = ThroReadiness.Facts(liveActivitiesAllowed: true, appGroupReachable: true,
                                        projectionWrittenAt: Date(), spotlightAvailable: true,
                                        spotlightOn: true, brandFacesRegistered: true)
        let blocked = ThroReadiness.surfaces(fresh).filter { $0.state == .blocked }
        XCTAssertEqual(blocked.map(\.id), [], "a fresh phone should have nothing blocked")
        XCTAssertEqual(ThroReadiness.surfaces(fresh).filter { $0.state == .absent }.map(\.id),
                       ["links"])
    }

    // MARK: the Lock Screen

    func testTheLockScreenIsBlockedWhenTheSystemHasTurnedLiveActivitiesOff() {
        let row = find("lock", .init(liveActivitiesAllowed: false, matchInProgress: true))
        XCTAssertEqual(row.state, .blocked)
        XCTAssertTrue(row.detail.contains("iPhone Settings"), row.detail)
    }

    func testTheLockScreenIsWorkingOnlyWhileAMatchIs() {
        XCTAssertEqual(find("lock", .init(liveActivitiesAllowed: true, matchInProgress: true)).state, .on)
        XCTAssertEqual(find("lock", .init(liveActivitiesAllowed: true, matchInProgress: false)).state, .waiting)
    }

    // MARK: the widgets

    func testTheWidgetsSayWhichXcodeCapabilityIsMissing() {
        let row = find("widgets", .init(appGroupReachable: false))
        XCTAssertEqual(row.state, .blocked)
        // The group id is the thing somebody has to type into Xcode, so it has to be on the screen.
        XCTAssertTrue(row.detail.contains("group.app.thro.darts"), row.detail)
    }

    /// The App Group can be reachable and the file not written yet — one launch, before the first
    /// projection lands. That is a wait, not a fault, and saying "Blocked" would send somebody into
    /// Xcode to fix something that is already right.
    func testAReachableAppGroupWithNothingInItIsAWaitAndNotAFault() {
        XCTAssertEqual(find("widgets", .init(appGroupReachable: true, projectionWrittenAt: nil)).state,
                       .waiting)
        XCTAssertEqual(find("widgets", .init(appGroupReachable: true, projectionWrittenAt: Date())).state,
                       .on)
    }

    // MARK: permissions

    /// The defect this three-state enum exists to prevent: an unasked permission reported as a
    /// refusal, sending a player to iPhone Settings to turn on something nothing has asked for.
    func testAnUnaskedPermissionIsNeverReportedAsARefusal() {
        for row in [find("reminders", .init(notifications: .unasked)),
                    find("calendar", .init(calendar: .unasked))] {
            XCTAssertNotEqual(row.state, .blocked, "\(row.id): unasked read as refused")
            XCTAssertFalse(row.detail.contains("iPhone Settings"),
                           "\(row.id) sends them to Settings before anything has asked: \(row.detail)")
        }
    }

    func testARefusedPermissionSaysSoAndSaysWhereToChangeIt() {
        for row in [find("reminders", .init(notifications: .refused)),
                    find("calendar", .init(calendar: .refused))] {
            XCTAssertEqual(row.state, .blocked, row.id)
            XCTAssertTrue(row.detail.contains("iPhone Settings"), "\(row.id): \(row.detail)")
        }
    }

    func testRemindersCountWhatThisPhoneIsActuallyHolding() {
        let none = find("reminders", .init(notifications: .allowed, remindersSet: 0))
        XCTAssertEqual(none.state, .waiting)
        let one = find("reminders", .init(notifications: .allowed, remindersSet: 1))
        XCTAssertEqual(one.state, .on)
        XCTAssertTrue(one.detail.contains("1 reminder is"), one.detail)
        let two = find("reminders", .init(notifications: .allowed, remindersSet: 2))
        XCTAssertTrue(two.detail.contains("2 reminders are"), two.detail)
    }

    // MARK: the fixture sentence

    /// Three rows share one route sentence, and it changes with the phone: telling somebody to look
    /// under a fixture when they have none is telling them to look at nothing.
    func testTheFixtureRouteChangesWhenThereIsNoFixtureToLookUnder() {
        let none = ThroReadiness.fixtureRoute(.init(datedFixtures: 0))
        let some = ThroReadiness.fixtureRoute(.init(datedFixtures: 1))
        XCTAssertNotEqual(none, some)
        XCTAssertTrue(none.contains("No fixture on this phone has a date"), none)
        for id in ["reminders", "calendar", "venue"] {
            XCTAssertTrue(find(id, .init(datedFixtures: 0)).detail.contains(none),
                          "\(id) does not carry the route sentence")
        }
    }

    // MARK: the two switches

    func testTheTwoSwitchesReadAsOffRatherThanBroken() {
        XCTAssertEqual(find("spotlight", .init(spotlightAvailable: true, spotlightOn: false)).state, .off)
        XCTAssertEqual(find("metrics", .init(diagnosticsOn: false)).state, .off)
    }

    func testPerformanceReportsSayThatNothingArrivesTwiceInADay() {
        let waiting = find("metrics", .init(diagnosticsOn: true, diagnosticsHeld: 0))
        XCTAssertEqual(waiting.state, .waiting)
        XCTAssertTrue(waiting.detail.contains("once a day"), waiting.detail)
        let held = find("metrics", .init(diagnosticsOn: true, diagnosticsHeld: 1))
        XCTAssertEqual(held.state, .on)
        XCTAssertTrue(held.detail.contains("1 report"), held.detail)
    }

    // MARK: what is honestly not there

    func testTheLinkRowSaysWhyTheEntitlementIsMissingRatherThanClaimingItWorks() {
        let row = find("links", .init())
        XCTAssertEqual(row.state, .absent)
        XCTAssertTrue(row.detail.contains("domain"), row.detail)
    }

    /// The watch is genuinely reachable — a Live Activity lands in the Smart Stack with no watch
    /// app — and the complication genuinely is not. Both halves have to be said, or the row is
    /// either a false promise or a false denial.
    func testTheWatchRowSaysBothWhatReachesItAndWhatDoesNot() {
        let row = find("watch", .init())
        XCTAssertTrue(row.detail.contains("Smart Stack"), row.detail)
        XCTAssertTrue(row.detail.contains("complication"), row.detail)
    }

    func testTheSummaryCountsWhatIsWorkingAndRefusesToCallItselfADemonstration() {
        let quiet = ThroReadiness.summary(ThroReadiness.surfaces(.init()))
        XCTAssertTrue(quiet.contains("0 of these are working"), quiet)
        XCTAssertTrue(quiet.contains("demonstration"), quiet)

        let busy = ThroReadiness.Facts(liveActivitiesAllowed: true, matchInProgress: true,
                                       appGroupReachable: true, projectionWrittenAt: Date(),
                                       externalDisplayAttached: true, finishedMatches: 1,
                                       notifications: .allowed, remindersSet: 1, calendar: .allowed,
                                       datedFixtures: 1, spotlightAvailable: true, spotlightOn: true,
                                       diagnosticsOn: true, diagnosticsHeld: 1,
                                       brandFacesRegistered: true)
        let working = ThroReadiness.surfaces(busy).filter { $0.state == .on }.count
        XCTAssertTrue(ThroReadiness.summary(ThroReadiness.surfaces(busy))
                        .contains("\(working) of these are working"))
    }

    /// The wall screen is the one row with no button, because no app may attach a display. The row
    /// must not grow one, and must keep saying so.
    func testTheWallRowSaysTheAppCannotStartItself() {
        let row = find("wall", .init(externalDisplayAttached: false))
        XCTAssertEqual(row.state, .waiting)
        XCTAssertTrue(row.detail.contains("Screen Mirroring"), row.detail)
        XCTAssertEqual(find("wall", .init(externalDisplayAttached: true)).state, .on)
    }
}
