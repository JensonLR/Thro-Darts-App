import CoreSpotlight
import EventKit
import Foundation
import SwiftUI
import ThroDesign
import ThroLiveKit
import ThroTokens
import UserNotifications
#if os(iOS)
import ActivityKit
import UIKit
#endif

// What this build can actually do on the phone it is running on, and where to look for it.
//
// **Why this exists.** The founder, on a build carrying nine new surfaces: *"not sure I can see or
// test majority of this on the latest iphone build."* They were right, and that is a defect in the
// work rather than in their looking. Most of what was added is invisible until a condition is met
// that nothing tells you about:
//
//  - the Lock Screen scoreboard needs a match in progress **and** the phone locked;
//  - the widgets need an App Group the build may not have, then a widget added by hand;
//  - the wall screen needs an HDMI adapter or screen mirroring turned on;
//  - the share card needs a **finished** match;
//  - a fixture reminder needs a club fixture with a date on it, more than two hours off;
//  - performance reports are off by default and arrive at most once a day;
//  - universal links need a domain nobody has bought.
//
// A feature nobody can find has not been delivered. So this reads the real state of each one — the
// system's own answer — and says either where to look or what is stopping it.
//
// **Nothing here is a demonstration.** There is no sample match, no example fixture and no mock
// scoreboard: a screen that invented one to show a feature working would be showing a match that
// never happened, in an app whose whole argument is that it does not do that. Every row is a fact
// about this device, and a row with nothing to report says so.

public enum ThroReadiness {

    /// How a surface stands right now.
    ///
    /// Five states rather than a boolean, because "you cannot see it" has five different causes and
    /// only one of them is a fault. Collapsing them would tell a player their phone is broken when
    /// they have simply not plugged a cable in.
    public enum State: String, Equatable, Sendable, CaseIterable {
        /// Working, and reachable right now.
        case on
        /// Working, and waiting for something the player does — a match, a cable, a fixture.
        case waiting
        /// The player turned it off, or it is off until they turn it on.
        case off
        /// The system refused, or the build is missing something it needs.
        case blocked
        /// Not in this build at all, and honestly so.
        case absent

        public var label: String {
            switch self {
            case .on: return "Working"
            case .waiting: return "Ready"
            case .off: return "Off"
            case .blocked: return "Blocked"
            case .absent: return "Not built"
            }
        }

        public var tone: Tag.Tone {
            switch self {
            case .on: return .success
            case .waiting: return .info
            case .off: return .neutral
            case .blocked: return .warning
            case .absent: return .neutral
            }
        }
    }

    /// Whether the phone has been asked for something, and what it said.
    ///
    /// Three states, not two, because *not yet asked* is the common case on a fresh install and it
    /// is not a refusal. Told apart here rather than at each call site, so no row can accidentally
    /// report an unasked permission as denied.
    public enum Permission: String, Equatable, Sendable, CaseIterable {
        case unasked, allowed, refused
    }

    /// Where the app can take somebody, when it can take them anywhere.
    ///
    /// **Optional on purpose.** Four of the twelve rows have nowhere to send anyone: no app may
    /// attach a display or turn on Screen Mirroring, the App Group is fixed in Xcode or in signing,
    /// and a domain is bought rather than tapped. A button on those rows would be a button that
    /// apologises, which is worse than a sentence that explains.
    public enum Go: Equatable, Sendable {
        /// Somewhere inside THRØ. The label is what the button says, so it names the destination
        /// rather than the mechanism — "Start a match", not "Go".
        case place(String, ThroRoute)
        /// This app's own page in iPhone Settings: the only page any app may open, and the one
        /// every *turn it on in Settings* sentence on this screen actually means.
        case phoneSettings(String)

        public var label: String {
            switch self {
            case let .place(label, _), let .phoneSettings(label): return label
            }
        }
    }

    /// One thing this build added, and whether it can be seen.
    public struct Surface: Identifiable, Equatable, Sendable {
        public let id: String
        /// What it is called on this screen — the player's words, not the framework's.
        public let name: String
        public let state: State
        /// **Where to look, or what is stopping it.** Never neither: a row carrying a state and no
        /// sentence tells somebody their phone is wrong and nothing else.
        public let detail: String
        /// What the row can do about it, when anything can. `nil` is the honest answer for the
        /// four rows whose obstacle is outside the app.
        public let go: Go?

        public init(id: String, name: String, state: State, detail: String, go: Go? = nil) {
            self.id = id
            self.name = name
            self.state = state
            self.detail = detail
            self.go = go
        }
    }

    /// The facts every row is written from.
    ///
    /// Separated from the reading of them so the wording can be tested on a machine with no phone,
    /// no entitlement and no permission dialogs — which is every machine this repository's tests
    /// run on. `probe` fills the system half in; the app half is passed in by the caller that
    /// already holds it.
    public struct Facts: Equatable, Sendable {
        public var liveActivitiesAllowed: Bool
        /// Whether a Lock Screen scoreboard is up **right now**, asked of ActivityKit rather than
        /// inferred from a match being open. The two differ constantly: the activity lives as long
        /// as the scoring screen does, so a match somebody walked away from has no scoreboard.
        public var liveActivityUp: Bool
        public var matchInProgress: Bool
        public var appGroupReachable: Bool
        public var projectionWrittenAt: Date?
        /// Whether this build's scene manifest can be *given* a screen at all — a different
        /// question from whether one is plugged in, and the one that fails silently.
        public var externalDisplayConfigured: Bool
        public var externalDisplayAttached: Bool
        public var finishedMatches: Int
        public var notifications: Permission
        public var remindersSet: Int
        public var calendar: Permission
        public var datedFixtures: Int
        public var spotlightAvailable: Bool
        public var spotlightOn: Bool
        public var diagnosticsOn: Bool
        public var diagnosticsHeld: Int
        public var brandFacesRegistered: Bool

        public init(liveActivitiesAllowed: Bool = false, liveActivityUp: Bool = false,
                    matchInProgress: Bool = false,
                    appGroupReachable: Bool = false, projectionWrittenAt: Date? = nil,
                    externalDisplayConfigured: Bool = false,
                    externalDisplayAttached: Bool = false, finishedMatches: Int = 0,
                    notifications: Permission = .unasked, remindersSet: Int = 0,
                    calendar: Permission = .unasked, datedFixtures: Int = 0,
                    spotlightAvailable: Bool = false, spotlightOn: Bool = false,
                    diagnosticsOn: Bool = false, diagnosticsHeld: Int = 0,
                    brandFacesRegistered: Bool = false) {
            self.liveActivitiesAllowed = liveActivitiesAllowed
            self.liveActivityUp = liveActivityUp
            self.matchInProgress = matchInProgress
            self.appGroupReachable = appGroupReachable
            self.projectionWrittenAt = projectionWrittenAt
            self.externalDisplayConfigured = externalDisplayConfigured
            self.externalDisplayAttached = externalDisplayAttached
            self.finishedMatches = finishedMatches
            self.notifications = notifications
            self.remindersSet = remindersSet
            self.calendar = calendar
            self.datedFixtures = datedFixtures
            self.spotlightAvailable = spotlightAvailable
            self.spotlightOn = spotlightOn
            self.diagnosticsOn = diagnosticsOn
            self.diagnosticsHeld = diagnosticsHeld
            self.brandFacesRegistered = brandFacesRegistered
        }
    }

    /// Every surface, in the order somebody would try them.
    ///
    /// Scoring comes first because it is the one thing that needs no setup at all and everything
    /// else hangs off it: a match in progress lights the Lock Screen and the wall, and a finished
    /// one produces the share card.
    public static func surfaces(_ f: Facts) -> [Surface] {
        [
            lockScreen(f), wall(f), shareCard(f), widgets(f),
            reminders(f), calendarRow(f), venue(f),
            spotlight(f), siri(f), diagnostics(f), links(f), watch(f), typeFaces(f),
        ]
    }

    /// The one line at the top: how many of these are showing something right now.
    public static func summary(_ surfaces: [Surface]) -> String {
        let working = surfaces.filter { $0.state == .on }.count
        let stuck = surfaces.filter { $0.state == .blocked }.count
        let ready = surfaces.filter { $0.state == .waiting }.count
        var sentence = working == 1 ? "1 of these is working on this phone right now"
                                    : "\(working) of these are working on this phone right now"
        sentence += ready > 0 ? ", \(ready) are waiting on you" : ""
        sentence += stuck > 0 ? ", and \(stuck) cannot run on this build" : ""
        return sentence + ". Nothing on this screen is a demonstration — every line is read from "
             + "this phone, so a row that says it has nothing means it has nothing."
    }

    /// The whole screen as plain text, for sending to somebody who can act on it.
    ///
    /// **This closes the loop the screen opened.** The screen answers *what can this phone show me*;
    /// this answers *and here is that answer, in a message*. Without it the founder's move is
    /// thirteen screenshots, which is why a build's real state so rarely reaches the person who can
    /// change it.
    ///
    /// **Nothing in it is a match, a name or a figure.** The rows carry counts — how many finished
    /// matches, how many reminders — because a count is what decides a row's state, and no visit,
    /// no player and no score can reach this text. The last line says so, because a diagnostic that
    /// does not say what it contains is one nobody should send.
    public static func report(_ surfaces: [Surface], build: String, phone: String) -> String {
        let rows = surfaces.map { surface in
            // The sentence keeps its emphasis marks off: this is a message in somebody's chat app,
            // not a rendered screen, and `**` in plain text is noise.
            let detail = surface.detail.replacingOccurrences(of: "**", with: "")
            return "\(surface.name) — \(surface.state.label)\n    \(detail)"
        }
        return ("THRØ — what this build can do\n"
              + "Build \(build)\n"
              + "\(phone)\n\n"
              + rows.joined(separator: "\n\n")
              + "\n\nNothing above is a match, a name or a score — only which surfaces this phone "
              + "can show and why.")
    }

    static func lockScreen(_ f: Facts) -> Surface {
        let state: State
        let detail: String
        var go: Go?
        if !f.liveActivitiesAllowed {
            state = .blocked
            go = .phoneSettings("Open iPhone Settings")
            detail = "Live Activities are switched off for THRØ, so nothing will appear. "
                   + "iPhone Settings → THRØ → Live Activities."
        } else if f.liveActivityUp {
            state = .on
            // Nothing to tap: the next move is to lock the phone, which is not something an app
            // may do for you.
            detail = "The scoreboard is up now. Lock the phone: both remainders are on the Lock "
                   + "Screen, and on the Dynamic Island when the app is not in front."
        } else if f.matchInProgress {
            // **A match being open is not the same as the scoreboard being up**, and the row said
            // it was until ActivityKit was asked directly. The activity lives exactly as long as
            // the scoring screen: leaving that screen takes it down, deliberately, because a
            // scoreboard for a match nobody is throwing in is a scoreboard that lies. So a match
            // walked away from reads as ready rather than working, and the route is back into it.
            state = .waiting
            go = .place("Back to the match", .continueLatest)
            detail = "A match is open and the scoreboard is not up: it lasts exactly as long as the "
                   + "scoring screen does, so leaving that screen takes it down. Go back in, throw "
                   + "a visit, then lock the phone."
        } else {
            state = .waiting
            go = .place("Start a match", .newMatch)
            detail = "Start a match and throw one visit, then lock the phone. It clears itself when "
                   + "the match ends."
        }
        return Surface(id: "lock", name: "Lock Screen and Dynamic Island", state: state,
                       detail: detail, go: go)
    }

    static func wall(_ f: Facts) -> Surface {
        // Asked before the cable, because it is the failure nothing else would report. A build
        // whose manifest cannot take an external display scene mirrors the phone instead, and
        // `configurationForConnecting` is never called: no error, no log, nothing on the wall but
        // a large copy of the keypad.
        guard f.externalDisplayConfigured else {
            return Surface(id: "wall", name: "Club TV mode", state: .blocked,
                           detail: "This build cannot be given a screen. Its scene manifest does "
                                 + "not offer to take one, so a cable or Screen Mirroring would "
                                 + "only mirror the phone. That is in the app's `Info.plist` and "
                                 + "not a switch anywhere on this phone.")
        }
        if f.externalDisplayAttached {
            return Surface(id: "wall", name: "Club TV mode", state: .on,
                           detail: "A screen is attached now, and the board is on it — two names, "
                                 + "two remainders, at the size a room reads.")
        }
        return Surface(id: "wall", name: "Club TV mode", state: .waiting,
                       detail: "Plug in an HDMI adapter, or open Control Centre and turn on Screen "
                             + "Mirroring. No app can start either of those, so there is "
                             + "deliberately no button for it here.")
    }

    static func shareCard(_ f: Facts) -> Surface {
        guard f.finishedMatches > 0 else {
            return Surface(id: "share", name: "Share card", state: .waiting,
                           detail: "Finish a match. **Share the result** is under the score on the "
                                 + "result screen.",
                           go: .place("Start a match", .newMatch))
        }
        let held = f.finishedMatches == 1 ? "1 finished match" : "\(f.finishedMatches) finished matches"
        return Surface(id: "share", name: "Share card", state: .on,
                       detail: "\(held) on this phone. Open one from Home and tap **Share the "
                             + "result** under the score.",
                       go: .place("Open Home", .tab(.home)))
    }

    static func widgets(_ f: Facts) -> Surface {
        let name = "Home Screen and Lock Screen widgets"
        guard f.appGroupReachable else {
            // Two different causes, and the fix is different for each, so both are named. A build
            // run from Xcode is missing the capability on the two targets; a TestFlight build has
            // it in the source and lost it in signing. Naming only the first would send somebody
            // to a Mac they are not sitting at.
            return Surface(id: "widgets", name: name, state: .blocked,
                           detail: "This build cannot reach its App Group, so the widgets have "
                                 + "nothing to read and would show an empty board. **From Xcode**: "
                                 + "the **ThroDarts** target → Signing & Capabilities → **+ "
                                 + "Capability** → App Groups → tick `group.app.thro.darts`, then "
                                 + "the same on **ThroLive**. **From TestFlight**: nothing you can "
                                 + "do on the phone — the entitlement is in the source and did not "
                                 + "survive signing, which is a pipeline fix. Either way nothing "
                                 + "else in the app is affected by this.")
        }
        guard let written = f.projectionWrittenAt else {
            return Surface(id: "widgets", name: name, state: .waiting,
                           detail: "The App Group is there and nothing has been written to it yet. "
                                 + "Leave this screen and come back.")
        }
        return Surface(id: "widgets", name: name, state: .on,
                       detail: "Last written at \(clock.string(from: written)). Long-press the "
                             + "Home Screen → **+** → THRØ. There is a Lock Screen one too, under "
                             + "the clock.")
    }

    static func reminders(_ f: Facts) -> Surface {
        let name = "Fixture reminders"
        switch f.notifications {
        case .refused:
            return Surface(id: "reminders", name: name, state: .blocked,
                           detail: "Notifications are off for THRØ, so a reminder would never "
                                 + "arrive. iPhone Settings → THRØ → Notifications.",
                           go: .phoneSettings("Open iPhone Settings"))
        case .unasked:
            // Deliberately NOT iPhone Settings: nothing has asked yet, and the thing that asks is
            // the control under the fixture. Sending somebody to Settings here would be sending
            // them to switch on a permission the app has never requested, which is not where it is.
            return Surface(id: "reminders", name: name, state: .waiting,
                           detail: "THRØ has not asked yet — it asks the first time you tap "
                                 + "**Remind me** on a fixture. \(fixtureRoute(f))",
                           go: .place("Open a club", .tab(.discover)))
        case .allowed:
            guard f.remindersSet > 0 else {
                return Surface(id: "reminders", name: name, state: .waiting,
                               detail: "Allowed, and none set. \(fixtureRoute(f))",
                               go: .place("Open a club", .tab(.discover)))
            }
            let set = f.remindersSet == 1 ? "1 reminder is" : "\(f.remindersSet) reminders are"
            return Surface(id: "reminders", name: name, state: .on,
                           detail: "\(set) set on this phone, two hours before the throw. Nothing "
                                 + "was sent anywhere — the phone holds them and the phone fires "
                                 + "them.")
        }
    }

    static func calendarRow(_ f: Facts) -> Surface {
        let name = "Add a fixture to your calendar"
        switch f.calendar {
        case .refused:
            return Surface(id: "calendar", name: name, state: .blocked,
                           detail: "THRØ may not add to your calendar. iPhone Settings → THRØ → "
                                 + "Calendars. It only ever asks to **add** — it cannot read what "
                                 + "is already in there.",
                           go: .phoneSettings("Open iPhone Settings"))
        case .allowed:
            return Surface(id: "calendar", name: name, state: .on,
                           detail: "Allowed. \(fixtureRoute(f)) **Add to calendar** sits beside the "
                                 + "reminder, and puts two hours in your calendar.",
                           go: .place("Open a club", .tab(.discover)))
        case .unasked:
            return Surface(id: "calendar", name: name, state: .waiting,
                           detail: "\(fixtureRoute(f)) **Add to calendar** is beside the reminder, "
                                 + "and asks the first time you tap it.",
                           go: .place("Open a club", .tab(.discover)))
        }
    }

    static func venue(_ f: Facts) -> Surface {
        Surface(id: "venue", name: "Find the venue in Maps", state: .waiting,
                detail: "\(fixtureRoute(f)) **Find the venue** is there only on a fixture with a "
                      + "venue typed into it, and searches Maps for exactly what was typed — THRØ "
                      + "has never known where it is, and does not ask this phone where you are.",
                go: .place("Open a club", .tab(.discover)))
    }

    static func spotlight(_ f: Facts) -> Surface {
        let name = "Find matches in iPhone search"
        guard f.spotlightAvailable else {
            return Surface(id: "spotlight", name: name, state: .blocked,
                           detail: "This phone is not indexing at the moment. It usually comes back "
                                 + "on its own.")
        }
        guard f.spotlightOn else {
            return Surface(id: "spotlight", name: name, state: .off,
                           detail: "Turned off in Settings → **Search**. Turning it off also removed "
                                 + "what had already been indexed.")
        }
        return Surface(id: "spotlight", name: name, state: .on,
                       detail: "Swipe down on the Home Screen and type a player's name, or a "
                             + "club's. The index is on this phone and goes nowhere.")
    }

    /// **Two intents that nothing in the app mentions.** They are built, they are in the app
    /// target where Xcode's metadata extractor will find them, and until this row existed the only
    /// way to discover them was to read the source. That is the founder's complaint exactly, on a
    /// surface nobody had thought to count.
    ///
    /// Always *Ready*, and honestly so: `AppShortcutsProvider` offers nothing to ask at runtime, so
    /// claiming **Working** would be claiming something unverified on a screen whose whole point is
    /// that it does not. And no button — the Action Button lives in a Settings pane no app may open.
    static func siri(_ f: Facts) -> Surface {
        Surface(id: "siri", name: "Siri, Shortcuts and the Action Button", state: .waiting,
                detail: "Say \"Start a match in THRØ\" to Siri, or \"Continue my match in THRØ\". "
                      + "Both are in the Shortcuts app as **Start a match** and **Continue**, and "
                      + "either can go on the Action Button: iPhone Settings → Action Button → "
                      + "Shortcut → THRØ. There are two rather than ten because Siri matches these "
                      + "phrases literally and nothing else, so a longer list would mostly be "
                      + "phrases that do not work.")
    }

    static func diagnostics(_ f: Facts) -> Surface {
        let name = "Performance reports"
        guard f.diagnosticsOn else {
            return Surface(id: "metrics", name: name, state: .off,
                           detail: "Off until you turn it on — it is the one thing here you gain "
                                 + "nothing from. Settings → **How the app performs**.")
        }
        guard f.diagnosticsHeld > 0 else {
            return Surface(id: "metrics", name: name, state: .waiting,
                           detail: "On, and nothing has arrived. iOS delivers these **at most once "
                                 + "a day**, so there will be nothing to see today.")
        }
        let held = f.diagnosticsHeld == 1 ? "1 report" : "\(f.diagnosticsHeld) reports"
        return Surface(id: "metrics", name: name, state: .on,
                       detail: "\(held) on this phone, and nothing has been sent anywhere. Settings "
                             + "→ **How the app performs**.")
    }

    static func links(_ f: Facts) -> Surface {
        Surface(id: "links", name: "Links that open the app", state: .absent,
                detail: "There is no thro.app domain yet, and the entitlement is deliberately left "
                      + "out: claiming a domain nobody owns makes iOS fetch a file that is not "
                      + "there, after which the app silently never handles a link at all. The file "
                      + "a domain would serve is written and checked on every push, so this is a "
                      + "purchase away rather than a build away.")
    }

    static func watch(_ f: Facts) -> Surface {
        Surface(id: "watch", name: "Apple Watch", state: .waiting,
                detail: "There is no watch app, by decision. A Live Activity reaches the watch's "
                      + "Smart Stack on its own and reminders mirror to it — so start a match and "
                      + "look at your wrist. A watch-face complication needs a watch app, which "
                      + "needs the phone-to-watch transport that was deferred.",
                go: .place("Start a match", .newMatch))
    }

    static func typeFaces(_ f: Facts) -> Surface {
        f.brandFacesRegistered
            ? Surface(id: "fonts", name: "The brand type faces", state: .on,
                      detail: "Archivo and IBM Plex Sans Condensed are loaded. The Lock Screen and "
                            + "the widgets use the system face on purpose: an extension cannot see "
                            + "the app's fonts, and a wrong font is worse than an honest one.")
            : Surface(id: "fonts", name: "The brand type faces", state: .blocked,
                      detail: "Not registered, so every screen is drawing in the system face. The "
                            + "font files belong to the app target — this is a build problem "
                            + "rather than a setting.")
    }

    /// The sentence three rows share, written once. All three controls sit together under an
    /// upcoming fixture, so a player who cannot find that list cannot find any of them.
    static func fixtureRoute(_ f: Facts) -> String {
        f.datedFixtures > 0
            ? "Discover → a club → **Fixtures**, under one that has not been played yet."
            : "No fixture on this phone has a date on it yet. Discover → a club → Fixtures → "
            + "**+**, give it a date, and the three controls appear under it."
    }

    static let clock: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .none
        f.timeStyle = .short
        return f
    }()
}

public extension ThroReadiness {

    /// Asks this phone what it will actually allow, and returns the facts with the system half
    /// filled in.
    ///
    /// **The app half comes in rather than being read here.** How many matches are finished, how
    /// many fixtures carry a date, whether the two switches are on — the caller already holds all
    /// of that, and a second reader of the same data is a second thing that can disagree with the
    /// screen the player is looking at.
    ///
    /// Every line below is a question to a system framework with no default answer written down for
    /// it. Where a framework cannot be asked on the platform this is compiled for, the value passed
    /// in stands, and the sentence it produces says the surface is not there — which on a Mac is
    /// true.
    @MainActor
    static func probe(app: Facts) async -> Facts {
        var f = app
        f.appGroupReachable = ThroProjectionStore.url() != nil
        f.projectionWrittenAt = ThroProjectionStore.read()?.writtenAt
        f.spotlightAvailable = CSSearchableIndex.isIndexingAvailable()
        f.brandFacesRegistered = ThroFont.customFacesRegistered

        let centre = UNUserNotificationCenter.current()
        f.notifications = permission(await centre.notificationSettings().authorizationStatus)
        f.remindersSet = await FixtureReminders.pending().count
        f.calendar = permission(EKEventStore.authorizationStatus(for: .event))

        #if os(iOS)
        f.liveActivitiesAllowed = ActivityAuthorizationInfo().areActivitiesEnabled
        // The system's own list rather than this process's handle on one: an activity started
        // before the app was last killed is still on the Lock Screen, and a handle to it is not.
        f.liveActivityUp = !Activity<ThroMatchActivityAttributes>.activities.isEmpty
        // The scene the system creates when a screen is plugged in or mirrored. Asking the scenes
        // rather than `UIScreen.screens`, which has been deprecated since iOS 16 and answers a
        // question about hardware rather than about what this app was actually given.
        f.externalDisplayConfigured = sceneManifestTakesADisplay
        f.externalDisplayAttached = UIApplication.shared.connectedScenes.contains {
            $0.session.role == .windowExternalDisplayNonInteractive
        }
        #endif
        return f
    }

    /// Notifications: three answers, and the two that are not "yes" are not the same.
    ///
    /// `.provisional` counts as allowed because it is: a provisionally authorised reminder is
    /// delivered, quietly, to the notification centre. Saying "off" there would send a player to
    /// iPhone Settings to fix something that is working.
    static func permission(_ status: UNAuthorizationStatus) -> Permission {
        switch status {
        case .notDetermined: return .unasked
        case .denied: return .refused
        default: return .allowed
        }
    }

    /// The calendar's own three answers. `.writeOnly` is the one this app asks for, and it is a yes.
    static func permission(_ status: EKAuthorizationStatus) -> Permission {
        switch status {
        case .notDetermined: return .unasked
        case .fullAccess, .writeOnly: return .allowed
        default: return .refused
        }
    }
}

#if os(iOS)
public extension ThroReadiness {

    /// Whether this build is arranged to be handed an external display at all.
    ///
    /// **Read from the running bundle rather than assumed**, because the two keys involved are
    /// exactly the kind that are wrong for months without anything saying so. iOS creates the
    /// external-display scene only if the manifest declares that role, *and* only if the app says
    /// it can hold two scenes at once — which a board on a wall beside a keypad in somebody's hand
    /// plainly is. Get either wrong and the cable mirrors the phone, the delegate is never asked
    /// for a configuration, and nothing anywhere reports a problem. This build had the second one
    /// wrong until it was read here.
    static var sceneManifestTakesADisplay: Bool {
        guard let manifest = Bundle.main
                .object(forInfoDictionaryKey: "UIApplicationSceneManifest") as? [String: Any],
              manifest["UIApplicationSupportsMultipleScenes"] as? Bool == true,
              let roles = manifest["UISceneConfigurations"] as? [String: Any],
              let external = roles[UISceneSession.Role.windowExternalDisplayNonInteractive.rawValue]
                as? [[String: Any]]
        else { return false }
        return !external.isEmpty
    }

    /// The model identifier and the iOS version — *"iPhone17,3, iOS 26.1"*.
    ///
    /// The raw identifier rather than a marketing name: a table of marketing names is a table that
    /// goes stale every September, and the identifier is what a bug report can be looked up from.
    static var phone: String {
        var system = utsname()
        uname(&system)
        // `machine` is a C character tuple. Mirror walks it without any unsafe pointer work, which
        // matters here: this runs on a phone in somebody's hand to produce a diagnostic, and a
        // diagnostic is the last thing that should be able to crash.
        let model = Mirror(reflecting: system.machine).children.reduce(into: "") { name, part in
            guard let byte = part.value as? Int8, byte != 0 else { return }
            name.append(Character(UnicodeScalar(UInt8(byte))))
        }
        return "\(model.isEmpty ? "unknown model" : model), iOS \(UIDevice.current.systemVersion)"
    }

    /// This app's own page in iPhone Settings, which is the only page any app may open.
    ///
    /// Every *turn it on in Settings* sentence on this screen means this page, and nothing else can
    /// be linked: iOS has no address for the Notifications pane, or Search, or a specific switch.
    /// So the sentence still names the path and the button only saves the first two taps.
    static var phoneSettings: URL? { URL(string: UIApplication.openSettingsURLString) }
}
#endif

/// The two counts that come from this phone's own matches.
///
/// **They live here, next to the sentences they feed, because the first version of them got the
/// rule wrong.** It excluded an abandoned match from the share-card count, reasoning that a match
/// nobody won has no scoreline to print — which is true of the *scoreline* and false of the
/// *card*: `MatchResultScreen` offers **Share the result** on every complete match, and
/// `ThroShareCard` draws an abandoned one with no score and the sentence *"Nothing is claimed
/// about who won."* A readiness row saying somebody had nothing to share, about a match with a
/// share button under it, is the exact failure this whole screen exists to stop.
public extension ThroReadiness {

    /// How many matches on this phone have a share card behind them.
    ///
    /// Every **complete** match, whatever ended it — won, retired or abandoned — because that is
    /// precisely the condition the result screen puts the control behind. One exclusion: a match
    /// whose rows will not replay never reaches a result screen at all, so it has no button.
    static func shareable(_ matches: [AppStore.HomeMatch]) -> Int {
        matches.filter { $0.complete && $0.unreadable == nil }.count
    }

    /// Whether a match is open right now — the same question the Live Activity asks, since it
    /// follows the leg being scored. An unreadable match has no remainders to put on a Lock Screen.
    static func beingScored(_ matches: [AppStore.HomeMatch]) -> Bool {
        matches.contains { !$0.complete && $0.unreadable == nil }
    }
}

/// The screen that says what this build can do, and where to look for each of it.
///
/// It takes its facts through a closure rather than reading them, for the reason the whole app is
/// arranged this way: a screen that reaches for the device's data is a second owner of it. The
/// closure is `async` because two of the answers — notification authorisation and what is pending —
/// only come back that way.
public struct ReadinessScreen: View {
    private let onBack: () -> Void
    private let gather: @MainActor () async -> ThroReadiness.Facts
    private let onGo: (ThroReadiness.Go) -> Void
    @State private var facts: ThroReadiness.Facts?

    public init(onBack: @escaping () -> Void,
                gather: @escaping @MainActor () async -> ThroReadiness.Facts,
                onGo: @escaping (ThroReadiness.Go) -> Void = { _ in }) {
        self.onBack = onBack
        self.gather = gather
        self.onGo = onGo
    }

    public var body: some View {
        VStack(spacing: 0) {
            TopBar("What this build can do", onBack: onBack, large: true)
            ScrollView {
                VStack(alignment: .leading, spacing: ThroSpacing.spacing4) {
                    if let facts {
                        let surfaces = ThroReadiness.surfaces(facts)
                        Text(ThroReadiness.summary(surfaces))
                            .thro(ThroTypography.body)
                            .foregroundStyle(ThroColor.colorTextSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                        ForEach(surfaces) { row(for: $0) }
                        send(surfaces)
                    } else {
                        // Before the first answer comes back. It says what it is waiting for rather
                        // than showing twelve rows that would all have to be wrong for a moment.
                        Text("Asking this phone what it will allow…")
                            .thro(ThroTypography.body)
                            .foregroundStyle(ThroColor.colorTextSecondary)
                    }
                }
                .padding(.horizontal, ThroSpacing.spaceScreenGutter)
                .padding(.vertical, ThroSpacing.spacing4)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .throEntrance(0)
        .background(ThroColor.colorBackgroundPrimary.ignoresSafeArea())
        // Every time it opens, not once: a player who goes to iPhone Settings, turns something on
        // and comes back must see the new answer rather than the one from before they left.
        .task { facts = await gather() }
    }

    /// The whole screen as a message.
    ///
    /// **Without this the answer stops on the phone.** Thirteen rows of state are exactly what
    /// somebody who can fix a build needs and exactly what nobody transcribes; a share sheet turns
    /// *I am not sure I can see this* into a message that says which nine of them are working and
    /// why the other four are not. A `ShareLink` rather than a copy button, because the phone
    /// already has every way of sending it and the app should not pick one.
    @ViewBuilder
    private func send(_ surfaces: [ThroReadiness.Surface]) -> some View {
        VStack(alignment: .leading, spacing: ThroSpacing.spacing2) {
            ShareLink(item: ThroReadiness.report(surfaces, build: BuildInfo.label,
                                                 phone: phoneDescription)) {
                ThroButtonFace("Send this", variant: .secondary, size: .medium, fullWidth: true)
            }
            .buttonStyle(ThroPressStyle(radius: ThroSpacing.radiusControl))
            .accessibilityHint("Makes a plain-text copy of this screen to send to somebody.")
            Text("Every line above, plus the build and the phone's model. No match, no name and no "
                 + "score goes with it.")
                .thro(ThroTypography.metadata)
                .foregroundStyle(ThroColor.colorTextSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, ThroSpacing.spacing3)
    }

    /// What phone this is, or an honest shrug off iOS.
    private var phoneDescription: String {
        #if os(iOS)
        return ThroReadiness.phone
        #else
        return "not an iPhone"
        #endif
    }

    @ViewBuilder
    private func row(for surface: ThroReadiness.Surface) -> some View {
        VStack(alignment: .leading, spacing: ThroSpacing.spacing2) {
            HStack(alignment: .firstTextBaseline, spacing: ThroSpacing.spacing3) {
                Text(surface.name)
                    .thro(ThroTypography.label)
                    .foregroundStyle(ThroColor.colorTextPrimary)
                Spacer(minLength: ThroSpacing.spacing2)
                Tag(surface.state.label, tone: surface.state.tone)
            }
            Text(surface.detail)
                .thro(ThroTypography.metadata)
                .foregroundStyle(ThroColor.colorTextSecondary)
                .fixedSize(horizontal: false, vertical: true)
            // On the rows that have somewhere to send you. Four do not, and they draw nothing
            // rather than a control that would have to apologise: no app may attach a display or
            // start Screen Mirroring, the App Group is fixed in Xcode or in signing, and a domain
            // is bought rather than tapped.
            if let go = surface.go {
                ThroButton(go.label, variant: .ghost, size: .small) { onGo(go) }
                    .padding(.top, ThroSpacing.spacing1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(ThroSpacing.spacing4)
        .background(
            RoundedRectangle(cornerRadius: ThroSpacing.radiusCard, style: .continuous)
                .fill(ThroColor.colorBackgroundSecondary)
        )
        .overlay(
            RoundedRectangle(cornerRadius: ThroSpacing.radiusCard, style: .continuous)
                .stroke(ThroColor.colorBorderDefault, lineWidth: 1)
        )
        // `.contain` rather than `.combine`: the state and the sentence are read as one thing by
        // the label and hint below, and the button stays a button. `.combine` would fold a control
        // into the text and leave a VoiceOver user with a row they can hear and cannot operate.
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(surface.name), \(surface.state.label)")
        .accessibilityHint(surface.detail)
    }
}
