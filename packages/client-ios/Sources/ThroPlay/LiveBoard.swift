import Foundation
import ThroEngine
import ThroJournal
import ThroLiveKit

// Turning a match being scored into the two numbers a Lock Screen shows.
//
// The mapping lives here rather than in `ThroLiveKit`, so the Live Activity package stays ignorant
// of `MatchSession` — and therefore of the journal, the engine and SQLite, none of which belong in
// a widget extension.

extension MatchSession {
    /// This match, as the scoreboard shows it.
    ///
    /// The checkout route is carried rather than recomputed, because the rule tables are the
    /// engine's and an extension that linked the engine to work out a finish would be linking a
    /// scoring engine into a process that draws two numbers.
    public var liveState: ThroLiveState {
        let home = Seat.home
        let away = Seat.away
        return ThroLiveState(
            homeName: name(home),
            awayName: name(away),
            homeRemaining: remaining(home),
            awayRemaining: remaining(away),
            homeLegs: legsWon(home),
            awayLegs: legsWon(away),
            // Nobody is on the oche once the match is decided, and the surface must not draw one.
            thrower: winner == nil ? thrower.map(LiveSeat.init) : nil,
            checkout: throwerOnAFinish ? throwerRoute : [],
            winner: winner.map(LiveSeat.init))
    }

    /// "501 · first to 3 · double out" — the format, said once, in the attributes.
    public var liveFormat: String {
        let structure = record.legsMode == .firstTo ? "first to" : "best of"
        var parts = ["\(record.startingScore)", "\(structure) \(record.legsTarget)"]
        if record.inRule == .double { parts.append("double in") }
        parts.append(record.outRule == .double ? "double out"
                        : record.outRule == .master ? "master out" : "straight out")
        return parts.joined(separator: " · ")
    }
}

private extension LiveSeat {
    init(_ seat: Seat) { self = seat == .home ? .home : .away }
}
