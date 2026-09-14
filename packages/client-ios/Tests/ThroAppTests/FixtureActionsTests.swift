import Foundation
import XCTest
@testable import ThroApp

/// What the phone offers to do with a fixture, and — more to the point — when it refuses.
///
/// The refusals are the half worth testing. A reminder that fires the instant it is asked for, a
/// calendar entry for a cancelled match, a venue with an ampersand in it that searches for half its
/// name: each of those looks like the feature working and is not, and none of them would fail
/// anything else in this repository.
final class FixtureActionsTests: XCTestCase {

    private let now = Date(timeIntervalSince1970: 1_800_000_000)   // a fixed instant, so nothing drifts

    private func fixture(in hours: Double, state: FixtureState = .scheduled,
                         venue: String = "The Red Lion") -> Fixture {
        Fixture(id: "f1", title: "Home to The Bell",
                when: "irrelevant — the row's own wording",
                at: now.addingTimeInterval(hours * 3600),
                venue: venue, state: state)
    }

    // MARK: the reminder

    func testAReminderLandsTwoHoursBeforeAndSaysWhereAndWhen() throws {
        let f = fixture(in: 48)
        let reminder = try XCTUnwrap(try? FixturePlan.reminder(for: f, now: now).get())
        XCTAssertEqual(reminder.id, "f1", "keyed on the fixture, so a second one replaces it")
        XCTAssertEqual(reminder.title, "Home to The Bell")
        XCTAssertEqual(reminder.fireAt, f.at!.addingTimeInterval(-FixturePlan.lead))
        XCTAssertEqual(FixturePlan.lead, 7200, accuracy: 0.001, "the button says two hours")
        XCTAssertTrue(reminder.body.contains("The Red Lion"), reminder.body)
    }

    /// **Never into the past.** A notification that arrives the moment it is asked for looks like a
    /// defect and the player has no way to tell it from one, so a fixture inside the lead time is
    /// refused — with the reason, because a disabled control that says nothing is the failure this
    /// whole enum exists to avoid.
    func testAFixtureInsideTheLeadTimeIsRefusedWithItsReason() {
        switch FixturePlan.reminder(for: fixture(in: 1), now: now) {
        case .success(let r): XCTFail("scheduled a reminder for \(r.fireAt), which is behind us")
        case .failure(let why):
            XCTAssertEqual(why, .tooSoon)
            XCTAssertTrue(why.reason.contains("two hours"), why.reason)
        }
    }

    func testAFixtureThatHasHappenedGetsNoReminder() {
        XCTAssertEqual(FixturePlan.reminder(for: fixture(in: -3), now: now).failure, .alreadyPast)
    }

    /// A cancelled or postponed fixture is not going ahead, so there is nothing to be reminded
    /// about — and a played one has already happened whatever its clock says.
    func testOnlyAScheduledFixtureIsRemindedAbout() {
        for state in [FixtureState.cancelled, .postponed, .played] {
            let why = FixturePlan.reminder(for: fixture(in: 48, state: state), now: now).failure
            XCTAssertEqual(why, .notScheduled(state.label), "\(state) should not be reminded about")
            // The sentence has to be right for each of them, not right for one and odd for the rest.
            XCTAssertEqual(why?.reason.contains(state.label.lowercased()), true, why?.reason ?? "")
        }
    }

    func testAFixtureWithNoInstantGetsNoReminderRatherThanOneAtAGuessedTime() {
        let undated = Fixture(id: "f2", title: "Home to The Bell", when: "sometime", venue: "The Bell")
        XCTAssertEqual(FixturePlan.reminder(for: undated, now: now).failure, .noDate)
    }

    /// Every refusal has words on it. An unreachable case here would be a control the player taps
    /// with nothing to explain why it did nothing.
    func testEveryRefusalHasAReason() {
        for why in [FixturePlan.NoReminder.noDate, .notScheduled("Cancelled"), .alreadyPast, .tooSoon] {
            XCTAssertFalse(why.reason.isEmpty, "\(why) has no words")
        }
    }

    /// A reminder carries where and when and nothing else. It is not a place for a figure, a form
    /// number or a guess about who is favourite — none of which could carry a basis on a
    /// notification.
    func testAReminderMakesNoClaimAboutTheDarts() throws {
        let reminder = try XCTUnwrap(try? FixturePlan.reminder(for: fixture(in: 48), now: now).get())
        let text = (reminder.title + " " + reminder.body).lowercased()
        for banned in ["average", "favourite", "rating", "form", "expect", "should win"] {
            XCTAssertFalse(text.contains(banned), "\(banned) reached a notification: \(text)")
        }
    }

    // MARK: the calendar entry

    func testTheEntryCarriesWhatIsKnownAndNamesTheLengthAsAnAssumption() throws {
        let f = fixture(in: 48)
        let entry = try XCTUnwrap(FixturePlan.calendarEntry(for: f))
        XCTAssertEqual(entry.title, "Home to The Bell")
        XCTAssertEqual(entry.start, f.at!)
        XCTAssertEqual(entry.end, f.at!.addingTimeInterval(FixturePlan.assumedLength))
        XCTAssertEqual(entry.location, "The Red Lion")
        XCTAssertTrue(entry.notes.contains("assumption"), entry.notes)
        XCTAssertTrue(entry.notes.contains("two hours"), entry.notes)
    }

    /// A fixture that has already been played can still be put in a calendar — unlike a reminder,
    /// an entry cannot arrive at the wrong moment — but a cancelled one cannot, because it is not
    /// happening and an entry saying it is would be wrong in somebody else's app.
    func testAPastFixtureMayBeAddedAndACancelledOneMayNot() {
        XCTAssertNotNil(FixturePlan.calendarEntry(for: fixture(in: -100, state: .played)))
        XCTAssertNil(FixturePlan.calendarEntry(for: fixture(in: 48, state: .cancelled)))
        XCTAssertNil(FixturePlan.calendarEntry(
            for: Fixture(id: "f3", title: "t", when: "sometime", venue: "v")))
    }

    func testAnEmptyVenueBecomesNoLocationRatherThanAnEmptyOne() throws {
        let entry = try XCTUnwrap(FixturePlan.calendarEntry(for: fixture(in: 48, venue: "   ")))
        XCTAssertEqual(entry.location, "")
    }

    // MARK: finding the venue

    /// **The ampersand is the whole test.** `.urlQueryAllowed` permits `&`, `+` and `=`, so a venue
    /// called "Fox & Hounds" would become two query parameters and Maps would search for "Fox".
    /// The link opens, the search runs, and the wrong pub comes up — a silent wrong answer, which is
    /// the same failure `ThroLink.escape` was written for.
    func testAVenueWithAnAmpersandSearchesForTheWholeName() throws {
        let url = try XCTUnwrap(FixturePlan.mapsURL(for: "Fox & Hounds"))
        XCTAssertFalse(url.absoluteString.dropFirst(8).contains("&"), url.absoluteString)
        let query = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?.first(where: { $0.name == "q" })?.value)
        XCTAssertEqual(query, "Fox & Hounds")
    }

    func testAwkwardVenuesSurviveTheTrip() throws {
        for venue in ["The Bell", "Café Royal", "Kettering W.M.C.", "A+B Club", "100% Darts",
                      "St John's #2", "Fox & Hounds, Corby"] {
            let url = try XCTUnwrap(FixturePlan.mapsURL(for: venue), venue)
            let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                .queryItems?.first(where: { $0.name == "q" })?.value
            XCTAssertEqual(query, venue, "\(venue) did not survive")
        }
    }

    func testAVenueNobodyTypedOpensNothing() {
        XCTAssertNil(FixturePlan.mapsURL(for: ""))
        XCTAssertNil(FixturePlan.mapsURL(for: "   \n "))
    }

    /// A search, not a location. Nothing here geocodes, which would be a network request from an
    /// app whose README says it makes none.
    func testTheLinkIsASearchForWhatWasTyped() throws {
        let url = try XCTUnwrap(FixturePlan.mapsURL(for: "The Bell"))
        XCTAssertEqual(url.host, "maps.apple.com")
        XCTAssertEqual(url.scheme, "https")
        XCTAssertTrue(url.query?.hasPrefix("q=") == true, url.absoluteString)
    }
}

private extension Result {
    /// The failure, or nil. Reads better than a `switch` in a one-line assertion.
    var failure: Failure? {
        if case let .failure(error) = self { return error }
        return nil
    }
}
