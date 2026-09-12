import Foundation
import ThroJournal
import ThroLiveKit
import ThroWatchKit

/// The one place `ThroPlay` talks to ActivityKit, so every platform guard is here rather than
/// scattered through a view.
///
/// Off iOS every call is a no-op and the scoring screen is none the wiser. That is the point of
/// putting the guard behind a type: a view riddled with conditional compilation is a view nobody can
/// read. The guard is `#if os(iOS)` and not `canImport(ActivityKit)` — the module exists on macOS
/// with every entry point marked unavailable, so `canImport` lets the code in and the compiler then
/// refuses each call.
public struct LiveBoard {
    public init() {}

    /// Puts the scoreboard up for a match that is still being played — on the Lock Screen, and on
    /// the wall if the organiser has a screen plugged in.
    func start(_ session: MatchSession) {
        guard session.winner == nil, session.ending == nil else { return }
        ThroVenue.shared.show(session.liveState, format: session.liveFormat)
        ThroWristLink.shared.send(session.liveState, format: session.liveFormat)
        #if os(iOS)
        // A finished match gets no scoreboard: there is nothing live about it, and the result
        // screen is where a result belongs.
        guard session.winner == nil, session.ending == nil else { return }
        ThroLiveScoreboard.shared.start(matchURL: ThroLink.match(session.record.id.value).absoluteString,
                                        format: session.liveFormat,
                                        state: session.liveState)
        #endif
    }

    func update(_ state: ThroLiveState) {
        ThroVenue.shared.show(state, format: ThroVenue.shared.format)
        ThroWristLink.shared.send(state, format: ThroVenue.shared.format)
        #if os(iOS)
        ThroLiveScoreboard.shared.update(state)
        #endif
    }

    /// Takes it down, leaving a decided match up long enough to be read.
    ///
    /// The wall screen is cleared outright rather than left on the final leg: a room reading a
    /// finished scoreline as though it were live is the failure this whole surface has to avoid, and
    /// unlike the Lock Screen there is nobody holding it to notice.
    func finish(_ session: MatchSession) {
        ThroVenue.shared.clear()
        // The wrist is sent the finished leg rather than cleared, and is the one outside surface
        // treated that way. A wall screen is read by a room who did not see it happen; a watch is on
        // the arm of somebody who did, and *"Ann wins"* is what they want on it for the walk back to
        // the table. `ThroLiveCopy` names the winner instead of a thrower, so it cannot be misread
        // as still running — which is exactly why the Lock Screen lingers too.
        ThroWristLink.shared.send(session.liveState, format: session.liveFormat)
        #if os(iOS)
        ThroLiveScoreboard.shared.end(session.liveState)
        #endif
    }

    /// Clears anything a previous launch left behind.
    public static func clearStale() {
        ThroVenue.shared.clear()
        ThroWristLink.shared.send(nil, format: "")
        #if os(iOS)
        ThroLiveScoreboard.shared.endAnythingLeftOver()
        #endif
    }

    /// Opens the link to the watch, if this phone has one. Once, at launch, and before anything is
    /// sent: the context a watch is handed on waking is whatever was last left on an activated
    /// session, so a phone that never activated leaves nothing and a wrist opened mid-leg is blank.
    public static func openTheWrist() {
        ThroWristLink.shared.start()
    }
}
