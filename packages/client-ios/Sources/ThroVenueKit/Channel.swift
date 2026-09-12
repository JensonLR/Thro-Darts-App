import Foundation
import ThroNet

// What a screen on a pub wall shows, and in what order (PD-079).
//
// **Nobody is holding this one.** Every other surface in THRØ is read by a person who can scroll it, tap
// it, or put it down; a wall screen is read across a room by people with darts in their hands. Three rules
// follow from that and they are the whole design:
//
//   1. **It never scrolls.** A table that does not fit is shown in pages, because a page turns by itself
//      and a scroll view waits forever for a finger that is not coming.
//   2. **It never shows an empty panel.** Twenty seconds of "no fixtures" on a wall is twenty seconds of a
//      screen that looks broken. A panel with nothing on it is not in the rotation at all.
//   3. **It says when it last heard.** The same rule as the Lock Screen, the wall board and the wrist: a
//      table on a wall all evening is exactly the kind of thing that quietly stops being true.
//
// The rotation is worked out here, apart from the drawing, because it is the part that can be wrong while
// nothing fails.

/// One screenful.
public enum ThroVenuePanel: Equatable, Identifiable {
    /// A division's table, and which page of it — a league with fourteen teams is two screens, not a scroll.
    case table(division: String, page: Int, of: Int, rows: [LeagueStandings.Row])
    /// Fixtures still to play, soonest first.
    case toPlay(page: Int, of: Int, fixtures: [LeagueFixtures.Fixture])
    /// Results, most recent first.
    case results(page: Int, of: Int, fixtures: [LeagueFixtures.Fixture])

    public var id: String {
        switch self {
        case let .table(division, page, _, _): return "table:\(division):\(page)"
        case let .toPlay(page, _, _): return "toPlay:\(page)"
        case let .results(page, _, _): return "results:\(page)"
        }
    }
}

/// The rules that turn a season into a rotation.
public enum ThroVenueRota {
    /// Rows on one page of a table. Twelve at the size a room reads from; a Premier-sized division of
    /// fourteen therefore turns once rather than being shrunk until nobody at the bar can read it.
    public static let tableRows = 12
    /// Fixtures on one page. Fewer, because each is two team names, a date and a venue.
    public static let fixtureRows = 8
    /// How long one panel holds. Long enough to read a table twice from six metres away, short enough
    /// that somebody glancing up twice in an evening sees a different thing.
    public static let dwell: TimeInterval = 20
    /// The most recent results worth showing. A wall is a notice board, not an archive: last week's
    /// results are what people argue about, and the season's history is in the app.
    public static let recentResults = 16

    /// Every panel with something on it, in reading order: the table first, then what is still to play,
    /// then what has just been played.
    ///
    /// **Order is the argument.** Somebody looking up wants to know where their team is, then whether they
    /// are on next, and only then how last week went. A rotation that opened on results would be showing
    /// the least urgent thing to the most people.
    public static func panels(standings: LeagueStandings?, fixtures: LeagueFixtures?) -> [ThroVenuePanel] {
        var panels: [ThroVenuePanel] = []

        for division in standings?.divisions ?? [] where !division.rows.isEmpty {
            let pages = paginate(division.rows, per: tableRows)
            for (index, page) in pages.enumerated() {
                panels.append(.table(division: division.name, page: index + 1, of: pages.count, rows: page))
            }
        }

        let toPlay = fixtures?.toPlay ?? []
        for (index, page) in paginate(toPlay, per: fixtureRows).enumerated() {
            panels.append(.toPlay(page: index + 1, of: pageCount(toPlay.count, per: fixtureRows), fixtures: page))
        }

        let decided = Array((fixtures?.decided ?? []).prefix(recentResults))
        for (index, page) in paginate(decided, per: fixtureRows).enumerated() {
            panels.append(.results(page: index + 1, of: pageCount(decided.count, per: fixtureRows), fixtures: page))
        }

        return panels
    }

    /// The panel showing at a given moment, given when the rotation started. Nil when there is nothing to
    /// show — which is a state with its own screen, not a blank one.
    public static func showing(_ panels: [ThroVenuePanel], since started: Date, now: Date) -> ThroVenuePanel? {
        guard !panels.isEmpty else { return nil }
        let elapsed = max(0, now.timeIntervalSince(started))
        let step = Int(elapsed / dwell) % panels.count
        return panels[step]
    }

    static func pageCount(_ count: Int, per: Int) -> Int {
        max(1, Int((Double(count) / Double(per)).rounded(.up)))
    }

    static func paginate<T>(_ items: [T], per: Int) -> [[T]] {
        guard !items.isEmpty else { return [] }
        return stride(from: 0, to: items.count, by: per).map { Array(items[$0..<min($0 + per, items.count)]) }
    }
}

/// What the wall says.
public enum ThroVenueWords {
    /// A fixture's line: who is playing, or what is known when a side is not named.
    ///
    /// **A private team is still a fixture.** The server does not name it, and hiding the row would leave a
    /// hole in a league's own calendar on the one screen everybody in the room is looking at. So the night
    /// is shown and the side is called what it honestly is.
    public static func sides(_ fixture: LeagueFixtures.Fixture) -> String {
        "\(fixture.home ?? "Not named") v \(fixture.away ?? "Not named")"
    }

    /// The result, in the form a notice board uses. Never a bare pair of numbers for something nobody
    /// played: an award and a walkover are how a fixture *ended*, not how it went.
    public static func outcome(_ fixture: LeagueFixtures.Fixture) -> String {
        guard let decided = fixture.decided else { return "" }
        switch decided.kind {
        case "awarded", "walkover":
            let who = decided.awardedToHome == true ? fixture.home : fixture.away
            let word = decided.kind == "walkover" ? "Walkover" : "Awarded"
            return "\(word) — \(who ?? "not named")"
        default:
            guard let home = decided.legsHome, let away = decided.legsAway else { return "Played" }
            // **Where a result came from, on the result.** A scoreline an official declared is the league's
            // result and belongs on the board — but it is not a match anybody threw, and every other surface
            // in THRØ says which is which. A wall is the one place a stranger reads a scoreline with nobody
            // to ask, so it is also the one place the distinction cannot be left out.
            let said = decided.kind == "played" ? "" : " · \(decided.kind)"
            return "\(home)–\(away)\(said)"
        }
    }

    /// Whether a fixture's night has been and gone with nothing entered — the line an organiser needs to
    /// see and a room will notice for them.
    public static func awaiting(_ fixture: LeagueFixtures.Fixture, now: Date = Date()) -> Bool {
        fixture.decided == nil && fixture.scheduledAt < now && fixture.state != "postponed"
    }

    /// When the screen last heard from THRØ, said the way every other surface says it.
    ///
    /// A wall screen is left on for an evening and nobody reloads it. `nil` before the first read; after
    /// that it is a plain sentence, and past the freshness window it says so rather than presenting a
    /// table nobody has checked in an hour as this evening's.
    public static func heard(at heardAt: Date?, now: Date = Date(), stale: TimeInterval = 15 * 60) -> String {
        guard let heardAt else { return "Reading…" }
        let ago = now.timeIntervalSince(heardAt)
        if ago > stale { return "Out of date — check the connection" }
        let minutes = Int(ago / 60)
        if minutes < 1 { return "Just now" }
        return "\(minutes) minute\(minutes == 1 ? "" : "s") ago"
    }

    public static let nothingYet = "Nothing to show yet"
    public static let nothingYetHint = "When this league has a table or a fixture list, it appears here."
    public static let toPlay = "To play"
    public static let results = "Results"
    public static let awaitingResult = "Awaiting result"
}
