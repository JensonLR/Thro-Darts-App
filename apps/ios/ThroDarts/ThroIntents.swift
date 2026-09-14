import AppIntents
import ThroApp

// Siri, Shortcuts, the Action Button and Spotlight's top hit.
//
// **These live in the app target, not in `ThroApp`, and that is deliberate.** App Intents are
// discovered by a metadata extraction step Xcode runs over the app target at build time. Declaring
// them inside a Swift package that the app merely links has a history of the extractor not finding
// them — and the failure is silent: the app builds, the tests pass, and the shortcut simply never
// appears. That is precisely the shape `tools/check_screens_reachable.py` exists to prevent
// elsewhere, and nothing here can check it, so the safe placement is the one Xcode is certain to
// scan.
//
// The cost is that these two shims are not covered by `swift test`. What they contain is a single
// call each into `ThroRouter`, which is covered; the app target is compiled by CI on every push, so
// a mistake in them fails the build rather than reaching a phone.

/// Opens THRØ ready to set up a match.
struct StartMatchIntent: AppIntent {
    static var title: LocalizedStringResource = "Start a match"
    static var description = IntentDescription(
        "Opens THRØ at the setup for a new match between two people on this phone.")

    /// Scoring happens on the screen, at a board, with two people. There is nothing here to perform
    /// in the background — the honest result of "start a match" is the app, open, at the setup.
    static var openAppWhenRun: Bool { true }

    @MainActor
    func perform() async throws -> some IntentResult {
        ThroRouter.shared.go(.newMatch)
        return .result()
    }
}

/// Picks up the match this phone walked away from.
struct ContinueMatchIntent: AppIntent {
    static var title: LocalizedStringResource = "Continue my match"
    static var description = IntentDescription(
        "Opens the match in progress on this phone, where it left off.")

    static var openAppWhenRun: Bool { true }

    @MainActor
    func perform() async throws -> some IntentResult {
        ThroRouter.shared.go(.continueLatest)
        return .result()
    }
}

/// The phrases Siri listens for.
///
/// Every phrase carries `\(.applicationName)`, which the system requires — a phrase naming the app
/// as a literal is one Siri will not match. Two shortcuts rather than ten: without an Apple
/// Intelligence schema domain to conform to (and there is no sports, scoring or competition domain
/// for a darts app to adopt), Siri matches these literal phrases and nothing else, so a long list
/// would be a long list of things that mostly do not work.
struct ThroShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: StartMatchIntent(),
            phrases: [
                "Start a match in \(.applicationName)",
                "Start a game of \(.applicationName)",
                "New match in \(.applicationName)",
            ],
            shortTitle: "Start a match",
            systemImageName: "target")
        AppShortcut(
            intent: ContinueMatchIntent(),
            phrases: [
                "Continue my match in \(.applicationName)",
                "Carry on in \(.applicationName)",
            ],
            shortTitle: "Continue",
            systemImageName: "arrow.trianglehead.clockwise")
    }
}
