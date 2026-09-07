import Foundation
#if canImport(ActivityKit)
import ActivityKit
#endif

// The ActivityKit half. Everything here is behind `canImport`, so `ThroLiveKit` still builds — and
// `ThroLiveState` is still tested — on a build that has no ActivityKit at all.

#if canImport(ActivityKit)

/// The scoreboard on the Lock Screen and in the Dynamic Island.
///
/// **No server is involved, and that is not a limitation here — it is the design.** A Live Activity
/// can be started and updated entirely from the foreground app: `pushType` is optional, and the
/// throttling ActivityKit documents applies to its *push* notifications rather than to app-side
/// `update(_:)`. So THRØ's scoreboard costs no infrastructure, works in a pub with no signal, and
/// asks for no entitlement beyond a widget extension and one Info.plist key.
///
/// What it cannot do follows from the same fact: nothing updates while the app is not running. The
/// surface says so rather than showing a number it cannot vouch for — see `ThroLiveCopy.caption`.
public struct ThroMatchActivityAttributes: ActivityAttributes {
    public typealias ContentState = ThroLiveState

    /// The match, so a tap can open it. A route's own URL, like everything else addressable here.
    public let matchURL: String
    /// "501 · first to 3 · double out" — fixed for the life of the match, so it belongs here rather
    /// than in the state, where it would be re-sent on every visit against a 4 KB budget.
    public let format: String

    public init(matchURL: String, format: String) {
        self.matchURL = matchURL
        self.format = format
    }
}

#endif

#if canImport(ActivityKit)

/// Starts, updates and ends the one scoreboard.
///
/// **Where the honesty lives.** Every update carries a `staleDate` a little way ahead. While the app
/// is on screen the next visit renews it and the board stays current; the moment the app stops
/// running — pocketed, backgrounded, killed — the date passes, `context.isStale` becomes true and
/// the caption stops claiming the score is now. Nothing else would tell the player: a Live Activity
/// keeps drawing whatever it was last given, indefinitely, and looks exactly as authoritative when
/// it is ten minutes old.
///
/// The player can also turn Live Activities off for THRØ in the system's own Settings, so
/// `areActivitiesEnabled` is checked and a refusal is silent — there is nothing useful to say about
/// a preference they set deliberately.
public final class ThroLiveScoreboard {
    public static let shared = ThroLiveScoreboard()

    private var activity: Activity<ThroMatchActivityAttributes>?

    /// How long a score is allowed to look current before the surface admits it may not be. Long
    /// enough that a slow leg does not flicker into "out of date"; short enough that a phone put in
    /// a pocket stops asserting a score within about the time it takes to throw again.
    public static let freshness: TimeInterval = 150

    private init() {}

    public var isRunning: Bool { activity != nil }

    /// Puts the board up. Does nothing if one is already up, or if the player has turned Live
    /// Activities off for this app.
    public func start(matchURL: String, format: String, state: ThroLiveState) {
        guard activity == nil, ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        let attributes = ThroMatchActivityAttributes(matchURL: matchURL, format: format)
        let content = ActivityContent(state: state, staleDate: Date().addingTimeInterval(Self.freshness))
        // `pushType: nil` is the whole point: no server, no token, no entitlement.
        activity = try? Activity.request(attributes: attributes, content: content, pushType: nil)
    }

    public func update(_ state: ThroLiveState) {
        guard let activity else { return }
        let content = ActivityContent(state: state, staleDate: Date().addingTimeInterval(Self.freshness))
        Task { await activity.update(content) }
    }

    /// Takes the board down, leaving the final state up for a while.
    ///
    /// A result is worth reading after the darts are packed away, and dismissing it the instant the
    /// match ends would take it off the Lock Screen before either player looked. `staleDate` is
    /// deliberately nil here: a finished match does not go out of date.
    public func end(_ state: ThroLiveState, lingerFor linger: TimeInterval = 30 * 60) {
        guard let activity else { return }
        self.activity = nil
        let content = ActivityContent(state: state, staleDate: nil)
        Task {
            await activity.end(content, dismissalPolicy: .after(Date().addingTimeInterval(linger)))
        }
    }

    /// Ends anything left running from a previous launch, so a killed app does not leave a
    /// scoreboard on the Lock Screen for hours with a score nobody is keeping.
    public func endAnythingLeftOver() {
        for stray in Activity<ThroMatchActivityAttributes>.activities {
            Task { await stray.end(nil, dismissalPolicy: .immediate) }
        }
        activity = nil
    }
}

#endif
