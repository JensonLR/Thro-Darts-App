import Foundation
import ThroJournal
import ThroLiveKit

/// The one place `ThroPlay` talks to ActivityKit, so every `#if canImport` guard is here rather than
/// scattered through a view.
///
/// On a platform with no ActivityKit — a Linux-shaped build, a macOS test run — every call is a
/// no-op and the scoring screen is none the wiser. That is the point of putting the guard behind a
/// type: a view riddled with conditional compilation is a view nobody can read.
public struct LiveBoard {
    public init() {}

    /// Puts the scoreboard up for a match that is still being played.
    func start(_ session: MatchSession) {
        #if canImport(ActivityKit)
        // A finished match gets no scoreboard: there is nothing live about it, and the result
        // screen is where a result belongs.
        guard session.winner == nil, session.ending == nil else { return }
        ThroLiveScoreboard.shared.start(matchURL: ThroLink.match(session.record.id.value).absoluteString,
                                        format: session.liveFormat,
                                        state: session.liveState)
        #endif
    }

    func update(_ state: ThroLiveState) {
        #if canImport(ActivityKit)
        ThroLiveScoreboard.shared.update(state)
        #endif
    }

    /// Takes it down, leaving a decided match up long enough to be read.
    func finish(_ session: MatchSession) {
        #if canImport(ActivityKit)
        ThroLiveScoreboard.shared.end(session.liveState)
        #endif
    }

    /// Clears anything a previous launch left behind.
    public static func clearStale() {
        #if canImport(ActivityKit)
        ThroLiveScoreboard.shared.endAnythingLeftOver()
        #endif
    }
}
