import Foundation
import XCTest
import ThroEngine
@testable import ThroApp
@testable import ThroJournal

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
            .init(liveActivitiesAllowed: true, liveActivityUp: true, matchInProgress: true,
                  appGroupReachable: true,
                  projectionWrittenAt: Date(), externalDisplayConfigured: true,
                  externalDisplayAttached: true, finishedMatches: 3,
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
                                        projectionWrittenAt: Date(), externalDisplayConfigured: true,
                                        spotlightAvailable: true, spotlightOn: true,
                                        brandFacesRegistered: true)
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

    /// **A match being open is not the scoreboard being up**, and the row said it was until
    /// ActivityKit was asked directly. The activity lives exactly as long as the scoring screen —
    /// leaving that screen takes it down, on purpose, because a scoreboard for a match nobody is
    /// throwing in is a scoreboard that lies. A row reading *Working* for a match somebody walked
    /// away from would send them to lock a phone with nothing on it.
    func testTheLockScreenIsWorkingOnlyWhileTheScoreboardIsActuallyUp() {
        XCTAssertEqual(find("lock", .init(liveActivitiesAllowed: true, liveActivityUp: true,
                                          matchInProgress: true)).state, .on)
        let walkedAway = find("lock", .init(liveActivitiesAllowed: true, liveActivityUp: false,
                                            matchInProgress: true))
        XCTAssertEqual(walkedAway.state, .waiting)
        XCTAssertEqual(walkedAway.go, .place("Back to the match", .continueLatest))
        XCTAssertEqual(find("lock", .init(liveActivitiesAllowed: true)).state, .waiting)
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

        let busy = ThroReadiness.Facts(liveActivitiesAllowed: true, liveActivityUp: true,
                                       matchInProgress: true,
                                       appGroupReachable: true, projectionWrittenAt: Date(),
                                       externalDisplayConfigured: true,
                                       externalDisplayAttached: true, finishedMatches: 1,
                                       notifications: .allowed, remindersSet: 1, calendar: .allowed,
                                       datedFixtures: 1, spotlightAvailable: true, spotlightOn: true,
                                       diagnosticsOn: true, diagnosticsHeld: 1,
                                       brandFacesRegistered: true)
        let working = ThroReadiness.surfaces(busy).filter { $0.state == .on }.count
        XCTAssertTrue(ThroReadiness.summary(ThroReadiness.surfaces(busy))
                        .contains("\(working) of these are working"))
    }

    // MARK: where a row can take you

    /// The button and the sentence must agree in both directions. A row offering **Open iPhone
    /// Settings** whose words do not mention iPhone Settings is a button with no explanation; a row
    /// whose words send somebody to iPhone Settings without offering to open it is two taps of
    /// friction for nothing.
    func testTheButtonAndTheSentenceAgreeAboutIPhoneSettings() {
        let all: [ThroReadiness.Facts] = [
            .init(),
            .init(notifications: .refused, calendar: .refused, spotlightAvailable: true),
            .init(liveActivitiesAllowed: true, liveActivityUp: true, matchInProgress: true,
                  appGroupReachable: true,
                  projectionWrittenAt: Date(), externalDisplayConfigured: true,
                  externalDisplayAttached: true, finishedMatches: 3,
                  notifications: .allowed, remindersSet: 2, calendar: .allowed, datedFixtures: 1,
                  spotlightAvailable: true, spotlightOn: true, diagnosticsOn: true,
                  diagnosticsHeld: 4, brandFacesRegistered: true),
        ]
        for facts in all {
            for surface in ThroReadiness.surfaces(facts) {
                let offers: Bool
                if case .phoneSettings = surface.go { offers = true } else { offers = false }
                XCTAssertEqual(offers, surface.detail.contains("iPhone Settings"),
                               "\(surface.id) offers iPhone Settings: \(offers), and says it: "
                             + "\(surface.detail.contains("iPhone Settings"))")
            }
        }
    }

    /// **Not yet asked is not a refusal**, and it must not be answered with a trip to iPhone
    /// Settings either: nothing has requested the permission, so there is no switch there to find.
    /// The thing that asks is the control under the fixture, which is where the row sends them.
    func testAnUnaskedPermissionIsSentToTheControlThatAsksAndNotToIPhoneSettings() {
        for row in [find("reminders", .init(notifications: .unasked)),
                    find("calendar", .init(calendar: .unasked))] {
            switch row.go {
            case .place(let label, .tab(.discover)):
                XCTAssertFalse(label.isEmpty)
            default:
                XCTFail("\(row.id) sends an unasked permission to \(String(describing: row.go))")
            }
        }
        for row in [find("reminders", .init(notifications: .refused)),
                    find("calendar", .init(calendar: .refused))] {
            guard case .phoneSettings = row.go else {
                return XCTFail("\(row.id) refuses to offer the one page that can fix it")
            }
        }
    }

    /// Four rows have nowhere to send anybody, and a button on them would have to apologise: no app
    /// may attach a display or start Screen Mirroring, the App Group is fixed in Xcode or in
    /// signing, and a domain is bought rather than tapped. A button appearing on one of these is a
    /// promise the app cannot keep.
    func testTheRowsWithNowhereToSendAnybodyOfferNothing() {
        let everything = ThroReadiness.Facts(
            liveActivitiesAllowed: true, liveActivityUp: true, matchInProgress: true,
            appGroupReachable: true,
            projectionWrittenAt: Date(), externalDisplayConfigured: true,
            externalDisplayAttached: true, finishedMatches: 3,
            notifications: .allowed, remindersSet: 2, calendar: .allowed, datedFixtures: 1,
            spotlightAvailable: true, spotlightOn: true, diagnosticsOn: true, diagnosticsHeld: 4,
            brandFacesRegistered: true)
        for facts in [ThroReadiness.Facts(), everything] {
            for id in ["wall", "widgets", "links", "fonts"] {
                XCTAssertNil(find(id, facts).go,
                             "\(id) grew a button, and there is nowhere for it to go")
            }
        }
    }

    /// A row that says *start a match* must send somebody to a new match, and one that says *under
    /// a fixture* to the tab clubs live on. A label naming one place while the route names another
    /// is worse than no button.
    func testEachRouteMatchesWhatItsRowIsAsking() {
        XCTAssertEqual(find("lock", .init(liveActivitiesAllowed: true)).go,
                       .place("Start a match", .newMatch))
        XCTAssertEqual(find("share", .init()).go, .place("Start a match", .newMatch))
        XCTAssertEqual(find("share", .init(finishedMatches: 1)).go, .place("Open Home", .tab(.home)))
        XCTAssertEqual(find("venue", .init()).go, .place("Open a club", .tab(.discover)))
        // A scoreboard that is up has nothing to tap: the next move is to lock the phone, and no
        // app may do that for anybody.
        XCTAssertNil(find("lock", .init(liveActivitiesAllowed: true, liveActivityUp: true,
                                        matchInProgress: true)).go)
    }

    // MARK: the two counts that come from this phone's own matches

    /// **The defect this pair was written to fix.** The first version excluded an abandoned match
    /// from the share-card count, reasoning that a match nobody won has no scoreline — true of the
    /// scoreline, false of the card. `MatchResultScreen` puts **Share the result** behind
    /// `session.isComplete` and nothing else, and `ThroShareCard` draws an abandoned match with no
    /// score and the sentence *"Nothing is claimed about who won."* So the row would have told the
    /// founder they had nothing to share, about a match with a share button under it — which is the
    /// exact class of failure this whole screen exists to stop.
    ///
    /// Built on a real journal rather than a hand-made record, for the reason `SpotlightTests`
    /// gives: a fixture proves the formatter, and the formatter is not the part that breaks.
    func testEveryCompleteMatchIsCountedAsShareableIncludingAnAbandonedOne() throws {
        let path = NSTemporaryDirectory() + "thro-readiness-\(UUID().uuidString).sqlite"
        defer { for s in ["", "-wal", "-shm"] { try? FileManager.default.removeItem(atPath: path + s) } }
        let journal = try Journal(path: path, deviceId: DeviceId("test-device"))
        let record = try journal.createMatch(NewMatch(homeName: "Ann", awayName: "Bea"))

        let won = AppStore.HomeMatch(record: record, legsHome: 2, legsAway: 1, complete: true,
                                     unreadable: nil)
        let retired = AppStore.HomeMatch(record: record, legsHome: 1, legsAway: 0, complete: true,
                                         unreadable: nil, ending: .retired(by: .away))
        let abandoned = AppStore.HomeMatch(record: record, legsHome: 1, legsAway: 1, complete: true,
                                           unreadable: nil, ending: .abandoned)
        let open = AppStore.HomeMatch(record: record, legsHome: 0, legsAway: 0, complete: false,
                                      unreadable: nil)
        // A match whose rows will not replay never reaches a result screen, so it has no button.
        let broken = AppStore.HomeMatch(record: record, legsHome: 0, legsAway: 0, complete: true,
                                        unreadable: "the rows will not replay")

        XCTAssertEqual(ThroReadiness.shareable([won, retired, abandoned, open, broken]), 3)
        XCTAssertEqual(ThroReadiness.shareable([abandoned]), 1,
                       "an abandoned match has a share button under it and gets a card without a "
                     + "scoreline; excluding it sends somebody looking for nothing")
        XCTAssertEqual(ThroReadiness.shareable([open, broken]), 0)

        XCTAssertTrue(ThroReadiness.beingScored([won, open]))
        XCTAssertFalse(ThroReadiness.beingScored([won, retired, abandoned]))
        XCTAssertFalse(ThroReadiness.beingScored([broken]),
                       "a match that will not replay has no remainders to put on a Lock Screen")
    }

    /// The wall screen is the one row with no button, because no app may attach a display. The row
    /// must not grow one, and must keep saying so.
    func testTheWallRowSaysTheAppCannotStartItself() {
        let row = find("wall", .init(externalDisplayConfigured: true, externalDisplayAttached: false))
        XCTAssertEqual(row.state, .waiting)
        XCTAssertTrue(row.detail.contains("Screen Mirroring"), row.detail)
        XCTAssertEqual(find("wall", .init(externalDisplayConfigured: true,
                                          externalDisplayAttached: true)).state, .on)
    }

    /// **The failure that reports itself nowhere else.** iOS hands an app an external display only
    /// if its scene manifest declares that role AND says the app can hold two scenes at once. Get
    /// either wrong and the cable mirrors the phone: no error, no log, and a row reading *Ready —
    /// plug something in* would send somebody looking for a board that cannot arrive. This build
    /// had the second key wrong until the screen was made to read it.
    func testAWallThatCannotBeGivenAScreenSaysSoRatherThanWaitingForACable() {
        let row = find("wall", .init(externalDisplayConfigured: false, externalDisplayAttached: true))
        XCTAssertEqual(row.state, .blocked, "an unconfigured build must not read as ready")
        XCTAssertTrue(row.detail.contains("Info.plist"), row.detail)
        XCTAssertFalse(row.detail.contains("iPhone Settings"),
                       "there is no switch on the phone for this, and saying so sends somebody "
                     + "hunting through Settings: \(row.detail)")
        XCTAssertNil(row.go, "there is nowhere to send anybody for a key in a build")
    }
}
