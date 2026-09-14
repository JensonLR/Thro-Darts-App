import EventKit
import Foundation
import SwiftUI
import ThroDesign
import ThroTokens
import UserNotifications

// A fixture is a date, a place and a time, and the phone already knows what to do with all three.
//
// Three things a player wants from a fixture list, none of which needs a server, an account or a
// network call from this process:
//
//  - **A reminder**, scheduled on this device by `UNUserNotificationCenter` and delivered by it.
//    Nothing is sent anywhere; there is no push certificate and no token.
//  - **A calendar entry**, written with EventKit's **write-only** access — the least this can ask
//    for and still work. THRØ never reads the player's calendar, and the permission it requests is
//    the one that makes that a fact rather than a promise.
//  - **The venue, found in Maps.** A *search* for the venue exactly as it was typed, because the
//    venue column is free text somebody entered — "The Bell", "Kettering WMC" — and this app has no
//    idea where that is. No geocoding, which would be a network request; the search is Maps'.
//
// **What is decided here and what is performed elsewhere.** Everything below is a pure function
// from a fixture to a plan: what the reminder would say and when it would fire, what the calendar
// entry would carry, what URL Maps would open. Those are the parts that can be wrong — a reminder
// that fires in the past, an entry claiming a length nobody knows, a venue with an ampersand in it
// that breaks the link — and they are tested. The performers are the twenty lines underneath that
// hand a plan to the system.

public enum FixturePlan {

    /// How far ahead a reminder lands. Two hours, and the button says so — an unstated lead time is
    /// a promise the player cannot check against the notification when it arrives.
    public static let lead: TimeInterval = 2 * 60 * 60

    /// What a reminder would say, and when it would arrive.
    public struct Reminder: Equatable, Sendable {
        /// The fixture's own id. Scheduling the same fixture twice replaces rather than duplicates,
        /// and cancelling needs no second table to look the request up in.
        public let id: String
        public let title: String
        public let body: String
        public let fireAt: Date

        public init(id: String, title: String, body: String, fireAt: Date) {
            self.id = id
            self.title = title
            self.body = body
            self.fireAt = fireAt
        }
    }

    /// Why a fixture cannot be reminded about, in the words the screen shows.
    ///
    /// A disabled button with no reason is the failure mode this avoids: the player taps, nothing
    /// happens, and there is nothing on the screen to explain it.
    public enum NoReminder: Error, Equatable, Sendable {
        case noDate
        /// Carries the state's own label, so the sentence is right for a cancelled fixture, a
        /// postponed one and a played one rather than being right for one and odd for the others.
        case notScheduled(String)
        case alreadyPast
        case tooSoon

        public var reason: String {
            switch self {
            case .noDate:
                return "This fixture has no time on it yet."
            case .notScheduled(let state):
                return "This fixture is \(state.lowercased()), so there is nothing to remind you about."
            case .alreadyPast:
                return "This fixture has already happened."
            case .tooSoon:
                return "Less than two hours away — there is no reminder left to set."
            }
        }
    }

    /// The reminder for a fixture, or the reason there is none.
    ///
    /// **A reminder is never scheduled into the past**, and one whose lead time has already gone is
    /// refused rather than fired immediately: a notification that arrives the instant it is asked
    /// for looks like a defect, and the player has no way to tell it from one.
    public static func reminder(for fixture: Fixture, now: Date = Date()) -> Result<Reminder, NoReminder> {
        guard let at = fixture.at else { return .failure(.noDate) }
        guard fixture.state == .scheduled else { return .failure(.notScheduled(fixture.state.label)) }
        guard at > now else { return .failure(.alreadyPast) }
        let fireAt = at.addingTimeInterval(-lead)
        guard fireAt > now else { return .failure(.tooSoon) }
        return .success(Reminder(id: fixture.id,
                                 title: fixture.title,
                                 body: body(for: fixture, at: at),
                                 fireAt: fireAt))
    }

    /// What the notification says under the title. The venue and the time, and nothing else — a
    /// reminder is not a place to put a figure or a claim about who is favourite.
    static func body(for fixture: Fixture, at: Date) -> String {
        let time = clock.string(from: at)
        let venue = fixture.venue.trimmingCharacters(in: .whitespacesAndNewlines)
        return venue.isEmpty ? "Starts at \(time)." : "\(time) at \(venue)."
    }

    /// An entry for the player's own calendar.
    public struct CalendarEntry: Equatable, Sendable {
        public let title: String
        public let start: Date
        /// **An assumption, and named as one.** THRØ does not know how long a fixture runs; two
        /// hours is a guess the player can drag in Calendar. The alternative — a zero-length event
        /// — is a different guess wearing the appearance of a fact.
        public let end: Date
        public let location: String
        public let notes: String

        public init(title: String, start: Date, end: Date, location: String, notes: String) {
            self.title = title
            self.start = start
            self.end = end
            self.location = location
            self.notes = notes
        }
    }

    public static let assumedLength: TimeInterval = 2 * 60 * 60

    /// The entry for a fixture, or nil when there is no time to put one at.
    ///
    /// Offered for a fixture that has already happened, unlike a reminder: putting last Tuesday's
    /// match in your calendar is a reasonable thing to want, and unlike a notification it cannot
    /// arrive at the wrong moment.
    public static func calendarEntry(for fixture: Fixture) -> CalendarEntry? {
        guard let at = fixture.at, fixture.state != .cancelled else { return nil }
        return CalendarEntry(
            title: fixture.title,
            start: at,
            end: at.addingTimeInterval(assumedLength),
            location: fixture.venue.trimmingCharacters(in: .whitespacesAndNewlines),
            notes: "Added from THRØ. The length is an assumption — THRØ does not know how long this "
                 + "runs, so it is two hours. Change it if you know better.")
    }

    /// Maps, searching for the venue exactly as it was typed.
    ///
    /// **A search, not a location.** The venue is free text somebody entered into the fixture list;
    /// this app has never geocoded it and has no coordinates for it. Handing the words to Maps is
    /// the only honest interpretation, and it is what a person would do themselves.
    ///
    /// Escaped against a set narrower than `.urlQueryAllowed`, which permits `&`, `+` and `=` — a
    /// venue called *"Fox & Hounds"* would otherwise become two query parameters and search for
    /// *"Fox"*. That is the same failure `ThroLink.escape` exists for, and it is silent: the link
    /// opens, Maps searches, and the wrong pub comes up.
    public static func mapsURL(for venue: String) -> URL? {
        let trimmed = venue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        guard let escaped = trimmed.addingPercentEncoding(withAllowedCharacters: allowed) else { return nil }
        return URL(string: "https://maps.apple.com/?q=\(escaped)")
    }

    static let clock: DateFormatter = {
        let f = DateFormatter()
        f.setLocalizedDateFormatFromTemplate("EEE d MMM HH:mm")
        return f
    }()
}

// MARK: - the performers

/// Reminders this phone schedules for itself.
///
/// `UNUserNotificationCenter` delivers these locally. There is no token, no certificate and no
/// server: the request is stored by the system on this device and fired by it, which is why this
/// works in a pub with no signal and why nothing about a fixture leaves the phone to make it happen.
///
/// **Not covered by `swift test`**, deliberately: `UNUserNotificationCenter.current()` needs a real
/// application bundle and traps in a package test. Everything that decides *what* and *when* is in
/// `FixturePlan` above, where it is tested; what is left here is the handoff, and the app target is
/// compiled by CI on every push.
public enum FixtureReminders {

    /// Whether the player has agreed to be interrupted, without asking them.
    public static func status() async -> UNAuthorizationStatus {
        await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
    }

    /// Asks, once. Returns what the player said rather than swallowing it — a screen that offered a
    /// reminder after the player had refused notifications would be promising something the system
    /// will not deliver.
    public static func authorize() async -> Bool {
        (try? await UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .sound])) ?? false
    }

    /// Schedules one, replacing any earlier reminder for the same fixture.
    ///
    /// A calendar trigger rather than a time interval, so a reminder set today for next Tuesday
    /// still arrives at the right local time if the phone crosses a time zone or the clocks change
    /// in between — which they do, twice a year, in the middle of a darts season.
    @discardableResult
    public static func schedule(_ reminder: FixturePlan.Reminder) async -> Bool {
        let content = UNMutableNotificationContent()
        content.title = reminder.title
        content.body = reminder.body
        content.sound = .default

        let parts = Calendar.current.dateComponents(
            [.year, .month, .day, .hour, .minute], from: reminder.fireAt)
        let request = UNNotificationRequest(
            identifier: identifier(reminder.id),
            content: content,
            trigger: UNCalendarNotificationTrigger(dateMatching: parts, repeats: false))
        do {
            try await UNUserNotificationCenter.current().add(request)
            return true
        } catch {
            return false
        }
    }

    public static func cancel(fixtureId: String) {
        UNUserNotificationCenter.current()
            .removePendingNotificationRequests(withIdentifiers: [identifier(fixtureId)])
    }

    /// The fixtures this phone is currently holding a reminder for.
    public static func pending() async -> Set<String> {
        let requests = await UNUserNotificationCenter.current().pendingNotificationRequests()
        return Set(requests.compactMap { request in
            request.identifier.hasPrefix(prefix) ? String(request.identifier.dropFirst(prefix.count)) : nil
        })
    }

    private static let prefix = "thro.fixture."
    private static func identifier(_ fixtureId: String) -> String { prefix + fixtureId }
}

/// The player's own calendar, written to and never read.
///
/// **Write-only access on purpose.** `requestWriteOnlyAccessToEvents()` is the narrowest thing
/// EventKit offers that can still add an event, and it is the one this asks for: THRØ cannot see
/// what else is in the player's calendar, and the permission sheet the system shows says so. Full
/// access would work too and would be asking for something this app has no use for.
public enum FixtureCalendar {
    public enum Outcome: Equatable, Sendable {
        case added
        case refused
        case failed(String)
    }

    public static func add(_ entry: FixturePlan.CalendarEntry) async -> Outcome {
        let store = EKEventStore()
        let granted = (try? await store.requestWriteOnlyAccessToEvents()) ?? false
        guard granted else { return .refused }
        guard let calendar = store.defaultCalendarForNewEvents else {
            return .failed("This phone has no calendar to write to.")
        }
        let event = EKEvent(eventStore: store)
        event.title = entry.title
        event.startDate = entry.start
        event.endDate = entry.end
        event.location = entry.location.isEmpty ? nil : entry.location
        event.notes = entry.notes
        event.calendar = calendar
        do {
            try store.save(event, span: .thisEvent, commit: true)
            return .added
        } catch {
            return .failed("\(error.localizedDescription)")
        }
    }
}

// MARK: - the controls

/// What this phone offers to do with one fixture.
///
/// Three small controls, and each of them says what it will actually do. A reminder that cannot be
/// set says why rather than being greyed out in silence; the calendar button says the entry goes
/// into the player's own calendar, which is not this app and may well sync somewhere; and finding
/// the venue is named as the search it is, because the venue is free text and THRØ has never known
/// where it is.
struct FixturePlanControls: View {
    let fixture: Fixture

    @State private var reminded = false
    @State private var refused = false
    @State private var note: Notice?
    @Environment(\.openURL) private var openURL

    private struct Notice {
        let text: String
        let tone: Snackbar.Tone
    }

    private var plan: Result<FixturePlan.Reminder, FixturePlan.NoReminder> {
        FixturePlan.reminder(for: fixture)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: ThroSpacing.spacing2) {
            HStack(spacing: ThroSpacing.spacing2) {
                switch plan {
                case .success(let reminder):
                    ThroButton(reminded ? "Reminder set" : "Remind me",
                               variant: reminded ? .secondary : .ghost, size: .small) {
                        Task { await toggle(reminder) }
                    }
                case .failure:
                    EmptyView()
                }
                if let entry = FixturePlan.calendarEntry(for: fixture) {
                    ThroButton("Add to calendar", variant: .ghost, size: .small) {
                        Task { await add(entry) }
                    }
                }
                if let url = FixturePlan.mapsURL(for: fixture.venue) {
                    ThroButton("Find the venue", variant: .ghost, size: .small) { openURL(url) }
                }
                Spacer(minLength: 0)
            }

            // A control that is not there needs its reason on the screen, or the player is left
            // looking for a button somebody told them about.
            if case .failure(let why) = plan, fixture.state == .scheduled {
                Text(why.reason)
                    .thro(ThroTypography.metadata)
                    .foregroundStyle(ThroColor.colorTextSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if refused {
                Text("Notifications are off for THRØ, so a reminder would not arrive. Settings → "
                     + "Notifications turns them back on.")
                    .thro(ThroTypography.metadata)
                    .foregroundStyle(ThroColor.colorTextSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let note {
                Snackbar(note.text, tone: note.tone)
            }
        }
        .padding(.bottom, ThroSpacing.spacing3)
        .task(id: fixture.id) {
            reminded = await FixtureReminders.pending().contains(fixture.id)
        }
    }

    /// Sets the reminder, or takes it away. Asking a second time after a refusal does nothing the
    /// system will honour, so the screen says so instead of pretending the tap worked.
    private func toggle(_ reminder: FixturePlan.Reminder) async {
        if reminded {
            FixtureReminders.cancel(fixtureId: fixture.id)
            reminded = false
            note = Notice(text: "Reminder removed.", tone: .neutral)
            return
        }
        switch await FixtureReminders.status() {
        case .notDetermined:
            guard await FixtureReminders.authorize() else {
                refused = true
                return
            }
        case .denied:
            refused = true
            return
        default:
            break
        }
        refused = false
        if await FixtureReminders.schedule(reminder) {
            reminded = true
            note = Notice(text: "Two hours before, on this phone. Nothing was sent anywhere.", tone: .success)
        } else {
            note = Notice(text: "This phone would not take the reminder, so none is set.", tone: .error)
        }
    }

    private func add(_ entry: FixturePlan.CalendarEntry) async {
        switch await FixtureCalendar.add(entry) {
        case .added:
            note = Notice(text: "In your calendar, two hours long. Change the length there if you know it.",
                          tone: .success)
        case .refused:
            note = Notice(text: "THRØ has no permission to add to your calendar, so nothing was added.",
                          tone: .neutral)
        case .failed(let why):
            note = Notice(text: "Not added: \(why)", tone: .error)
        }
    }
}
