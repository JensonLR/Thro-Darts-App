import Foundation

// Clubs, leagues and tournaments on the phone (PD-009, PD-010).
//
// These are the same rules `packages/organisation` states in Kotlin, restated here because a screen
// has to know what to draw before anything has been asked of a server. **The Kotlin is the
// reference and, when a server exists, the server is authoritative**: this copy decides what a
// screen shows, never what a person may do. That is the same division the rest of the client keeps —
// the engine decides an outcome, the journal records it, and the screen renders what it is told.
//
// `ClubStateTests` holds both copies to the same three assertions, which is the cheapest guard
// available while the two cannot be run against one corpus.

public enum OrgKind: String, Sendable, CaseIterable {
    case club, league, tournament

    public var label: String {
        switch self {
        case .club: return "Club"
        case .league: return "League"
        case .tournament: return "Tournament"
        }
    }
}

public enum OrgRole: String, Sendable, Comparable {
    case member, official, admin

    private var rank: Int {
        switch self { case .member: return 0; case .official: return 1; case .admin: return 2 }
    }
    public static func < (a: OrgRole, b: OrgRole) -> Bool { a.rank < b.rank }

    public var label: String {
        switch self {
        case .member: return "Member"
        case .official: return "Official"
        case .admin: return "Admin"
        }
    }
}

/// The age dimension, as `packages/authz` defines it: unknown is a value, and it is treated as the
/// most restrictive case, because the thing not known is whether this is a child.
public enum AgeBand: String, Sendable { case unknown, minor, adult }

public struct ClubMember: Identifiable, Equatable, Sendable {
    public let id: String
    public let name: String
    public let role: OrgRole
    public let ageBand: AgeBand
    public let joined: String
    /// Nil when the figure cannot be computed honestly, which is a fact and not an absence.
    public let threeDartAverage: Double?
    /// Their picture, when they have one. **Only ever an adult** (PD-014): the store refuses to
    /// write one for anybody else and refuses to hand one back if the age stops saying adult.
    public let avatarAssetId: String?

    public init(id: String, name: String, role: OrgRole, ageBand: AgeBand = .adult,
                joined: String, threeDartAverage: Double? = nil, avatarAssetId: String? = nil) {
        self.avatarAssetId = avatarAssetId
        self.id = id
        self.name = name
        self.role = role
        self.ageBand = ageBand
        self.joined = joined
        self.threeDartAverage = threeDartAverage
    }

    public var initials: String {
        name.split(separator: " ").prefix(2).compactMap { $0.first }.map(String.init).joined().uppercased()
    }
}

public enum FixtureState: String, Sendable {
    case scheduled, postponed, cancelled, played

    public var label: String { rawValue.capitalized }
    public var isTerminal: Bool { self == .cancelled || self == .played }
}

public struct Fixture: Identifiable, Equatable, Sendable {
    public let id: String
    public let title: String
    public let when: String
    public let venue: String
    public let state: FixtureState
    /// The two teams, in a league (PD-019). Nil in a club, whose fixtures are a typed title.
    public let homeTeamId: String?
    public let awayTeamId: String?
    /// What happened, with where that came from (PD-020). Nil until somebody says.
    public let result: MatchResult?

    public init(id: String, title: String, when: String, venue: String, state: FixtureState = .scheduled,
                homeTeamId: String? = nil, awayTeamId: String? = nil, result: MatchResult? = nil) {
        self.id = id
        self.title = title
        self.when = when
        self.venue = venue
        self.state = state
        self.homeTeamId = homeTeamId
        self.awayTeamId = awayTeamId
        self.result = result
    }

    public var isBetweenTeams: Bool { homeTeamId != nil && awayTeamId != nil }
    /// Played, and nobody has said what happened. The one row a league admin has to act on, and the
    /// reason the league screen leads with it rather than with the table.
    public var awaitsResult: Bool { state == .played && result == nil }
}

/// A team in a league (PD-019). A league's unit of competition is a team, not a person.
public struct Team: Identifiable, Equatable, Sendable {
    public let id: String
    public let name: String

    public init(id: String, name: String) {
        self.id = id
        self.name = name
    }

    /// The same rule a club's badge uses, so *The Feathers A* and *The Feathers B* keep the letter
    /// that tells them apart.
    public var initials: String {
        let words = name.split(whereSeparator: { $0 == " " || $0 == "-" })
            .filter { !["the", "of", "and", "&"].contains($0.lowercased()) }
        return String(words.compactMap { $0.first }.map { String($0).uppercased() }.joined().prefix(3))
    }
}

/// Where a result came from, and it is never not said (PD-020).
public enum ResultSource: Equatable, Sendable {
    /// A match scored in THRØ. Every visit and every dart is behind it.
    case scored(matchId: String)
    /// An official's word. It counts for the table and it can never move a rating (OD-001).
    case recorded(by: String)

    /// The word on the screen. Short, because it sits on a row.
    public var label: String {
        switch self {
        case .scored: return "Scored in THRØ"
        case let .recorded(by): return "Recorded by \(by)"
        }
    }

    /// The sentence under a table, said once rather than on every row.
    public var explanation: String {
        switch self {
        case .scored:
            return "Every dart of this is in the journal on the phone that scored it."
        case .recorded:
            return "Somebody typed what happened. That is their word — nothing checked it, and it "
                 + "cannot move a rating."
        }
    }

    public var isEvidenced: Bool { if case .scored = self { return true }; return false }
}

/// What happened in a fixture, and where that came from. Never one without the other.
public struct MatchResult: Equatable, Sendable {
    public let home: Int
    public let away: Int
    public let source: ResultSource

    public init(home: Int, away: Int, source: ResultSource) {
        self.home = home
        self.away = away
        self.source = source
    }

    public var isDraw: Bool { home == away }
    /// True when the home team won. Nil on a draw, because "not a home win" is two different things.
    public var homeWon: Bool? { home == away ? nil : home > away }
}

/// What a league's results are counted in (PD-022).
///
/// **`3–1` on its own does not mean anything.** Three legs, three matches and three points are three
/// different claims, and one league's table cannot be compared with another's unless both say which.
/// It is asked when a league is made because it is the one thing here that **cannot be answered
/// afterwards**: a stored number with no unit on it cannot be reinterpreted, and by the time anybody
/// asks, nobody remembers what they meant.
public enum ResultUnit: String, CaseIterable, Equatable, Sendable {
    case legs, matches, points

    public var label: String { rawValue.capitalized }

    /// The word beside a single number — "7 legs", "1 point".
    public func counted(_ n: Int) -> String {
        switch self {
        case .legs: return n == 1 ? "1 leg" : "\(n) legs"
        case .matches: return n == 1 ? "1 match" : "\(n) matches"
        case .points: return n == 1 ? "1 point" : "\(n) points"
        }
    }

    /// What it means, in the words somebody running a pub league would use.
    public var summary: String {
        switch self {
        case .legs: return "Legs won across the night. A 7–2 is nine legs played."
        case .matches: return "Individual matches won within the fixture. A 5–4 is a nine-match card."
        case .points: return "Whatever your own points system awards for the fixture."
        }
    }

    /// The column headings a table uses for what a team scored and conceded.
    public var forAgainst: (String, String) {
        switch self {
        case .legs: return ("LF", "LA")
        case .matches: return ("MF", "MA")
        case .points: return ("PF", "PA")
        }
    }
}

/// The four shapes a tournament may be (PD-021).
public enum TournamentShape: String, CaseIterable, Equatable, Sendable {
    case knockout, groups, roundRobin, doubleElimination

    public var label: String {
        switch self {
        case .knockout: return "Knockout"
        case .groups: return "Groups, then knockout"
        case .roundRobin: return "Round robin"
        case .doubleElimination: return "Double elimination"
        }
    }

    /// What it means, in the words somebody running a pub tournament would use.
    public var summary: String {
        switch self {
        case .knockout:
            return "Lose once and you are out. A field that is not 4, 8, 16 or 32 gets byes in the "
                 + "first round, given to the top seeds."
        case .groups:
            return "Groups first, everybody in a group plays everybody, then the top of each group "
                 + "goes into a knockout."
        case .roundRobin:
            return "Everybody plays everybody. One table, and the top of it wins."
        case .doubleElimination:
            return "Lose once and you drop to the losers' side. Lose twice and you are out."
        }
    }

    /// How many matches a field of this size plays, or nil where the shape needs more than a number
    /// to say — groups, whose size and qualifying places are set before it starts.
    public func matches(forEntrants n: Int) -> Int? {
        guard n >= 2 else { return 0 }
        switch self {
        case .knockout: return n - 1
        case .roundRobin: return n * (n - 1) / 2
        // Every entrant but the winner loses twice, and the winner may lose once — so it is either
        // 2n−2 or 2n−1, and which one is not known until the final is played.
        case .doubleElimination: return 2 * n - 2
        case .groups: return nil
        }
    }

    /// A knockout of `n` needs a bracket of the next power of two, and the difference is byes.
    public static func byes(forEntrants n: Int) -> Int {
        guard n >= 2 else { return 0 }
        var bracket = 1
        while bracket < n { bracket *= 2 }
        return bracket - n
    }
}

public struct Announcement: Identifiable, Equatable, Sendable {
    public let id: String
    public let subject: String
    public let author: String
    public let ago: String
    public let reached: Int
    public let of: Int

    public init(id: String, subject: String, author: String, ago: String, reached: Int, of: Int) {
        self.id = id
        self.subject = subject
        self.author = author
        self.ago = ago
        self.reached = reached
        self.of = of
    }
}

/// Why an announcement will not reach somebody. Counted and named on the compose screen before it is
/// sent, because an official who thinks they have told everybody has been failed by the app.
public struct Withheld: Equatable, Sendable {
    public let minors: Int
    public let ageNotGiven: Int

    public var total: Int { minors + ageNotGiven }

    /// One line per reason, in the order the screen shows them. Empty when nobody is withheld.
    public var lines: [(count: String, why: String)] {
        var out: [(String, String)] = []
        if minors > 0 {
            out.append(("\(minors) member\(minors == 1 ? "" : "s") under 18",
                        "nobody under 18 is sent a message until THRØ has taken safeguarding advice."))
        }
        if ageNotGiven > 0 {
            out.append(("\(ageNotGiven) member\(ageNotGiven == 1 ? "" : "s") whose age is not given",
                        "treated the same way, because what is not known is whether they are a child."))
        }
        return out
    }

    public static func == (a: Withheld, b: Withheld) -> Bool {
        a.minors == b.minors && a.ageNotGiven == b.ageNotGiven
    }
}

public struct Club: Identifiable, Equatable, Sendable {
    public let id: String
    public let name: String
    public let kind: OrgKind
    public let meta: String
    /// The club's accent as six hex digits. Nil means it has chosen none and wears the brand's.
    public let accentHex: String?
    public let verified: Bool
    /// The club's badge, when it has one (PD-014). Nil is ordinary: a club may prefer its initials.
    public let badgeAssetId: String?
    /// The viewer's own role here, or nil if they are not a member. PD-009: a stranger sees the front.
    public let yourRole: OrgRole?
    public let members: [ClubMember]
    public let fixtures: [Fixture]
    public let announcements: [Announcement]
    /// A league's teams (PD-019). Empty for a club and a tournament.
    public let teams: [Team]
    /// A tournament's shape (PD-021). Nil for anything else.
    public let shape: TournamentShape?
    /// What this league's results are counted in (PD-022). **Nil is a real answer** — a league made
    /// before this was asked has none, and nothing guesses one for it.
    public let unit: ResultUnit?
    /// What a win and a draw are worth here. Stored on the league rather than assumed, and said on
    /// the table rather than left to be inferred from the arithmetic.
    public let pointsForWin: Int
    public let pointsForDraw: Int

    public init(id: String, name: String, kind: OrgKind, meta: String, accentHex: String? = nil,
                verified: Bool = false, yourRole: OrgRole? = nil, members: [ClubMember] = [],
                fixtures: [Fixture] = [], announcements: [Announcement] = [],
                badgeAssetId: String? = nil, teams: [Team] = [], shape: TournamentShape? = nil,
                pointsForWin: Int = 2, pointsForDraw: Int = 1, unit: ResultUnit? = nil) {
        self.teams = teams
        self.shape = shape
        self.unit = unit
        self.pointsForWin = pointsForWin
        self.pointsForDraw = pointsForDraw
        self.badgeAssetId = badgeAssetId
        self.id = id
        self.name = name
        self.kind = kind
        self.meta = meta
        self.accentHex = accentHex
        self.verified = verified
        self.yourRole = yourRole
        self.members = members
        self.fixtures = fixtures
        self.announcements = announcements
    }

    /// A badge carries at most three letters, and "The Feathers A" is FA rather than TFA: the words
    /// a club's name shares with every other club's carry no information at that size.
    /// "A" is NOT here, and that is the point: Feathers A and Feathers B are different clubs, and a
    /// badge that dropped the letter would give them the same one.
    private static let skipped: Set<String> = ["the", "of", "and", "&"]
    public var initials: String {
        let words = name.split(whereSeparator: { $0 == " " || $0 == "-" })
            .filter { !Club.skipped.contains($0.lowercased()) }
        let letters = words.compactMap { $0.first }.map { String($0).uppercased() }.joined()
        return String(letters.prefix(3))
    }

    // MARK: - PD-009

    /// Whether the viewer is inside. A stranger sees the front and nothing else.
    public var isMember: Bool { yourRole != nil }

    /// Who the viewer may see on the membership list.
    ///
    /// A member recorded as a minor — or whose age is not established, treated the same way — is
    /// listed **only to an admin**, and not to an official either: running a club is not a reason to
    /// see a child. A property rather than a convention, so a screen cannot render the list without it.
    public var visibleMembers: [ClubMember] {
        guard let role = yourRole else { return [] }
        if role == .admin { return members }
        return members.filter { $0.ageBand == .adult }
    }

    /// How many members the list is not showing, and why. Shown rather than a quietly shorter list.
    public var hiddenMembers: Int { members.count - visibleMembers.count }

    /// Still to come, newest first. `postponed` counts: it has not been played and it is still on.
    public var upcomingFixtures: [Fixture] { fixtures.filter { !$0.state.isTerminal } }

    /// Played, most recent first. **Cancelled is not played** — nobody threw — so it is in neither
    /// list, which is why these two do not sum to `fixtures`.
    public var playedFixtures: [Fixture] { fixtures.filter { $0.state == .played } }

    /// Whether this organisation has ever had a fixture at all. Distinct from having nothing
    /// scheduled: the club page used to show the second as the first, so a club with a season behind
    /// it and nothing booked read as one that had never played.
    public var hasEverHadAFixture: Bool { !fixtures.isEmpty }

    public var mayAnnounce: Bool { (yourRole ?? .member) >= .official && isMember }
    public var mayManageFixtures: Bool { (yourRole ?? .member) >= .official && isMember }
    public var mayManageMembers: Bool { yourRole == .admin }
    /// Adding and removing teams (PD-019), and a tournament's entrants, which are the same stored
    /// thing under a different word — an entrant of one player is a team of one. An admin's, the
    /// same standing as a club's roster.
    public var mayManageTeams: Bool { yourRole == .admin && kind != .club }

    /// What this organisation calls the things that compete in it. A league has teams; a tournament
    /// has entrants; a club has neither, because a club is not a competition.
    public var competitorNoun: (one: String, many: String) {
        kind == .tournament ? ("entrant", "Entrants") : ("team", "Teams")
    }
    /// Saying what happened in a fixture (PD-020). An **official's**, not only an admin's — the
    /// person at the venue on the night is usually not the person who set the league up, and a
    /// league where only one person can enter results is a league that stops when they are away.
    public var mayRecordResults: Bool { (yourRole ?? .member) >= .official && isMember }
    /// Changing the club's own name, colour and badge, and deleting it. An admin's, like the roster:
    /// what a club is *called* is not an official's to change.
    public var mayEditIdentity: Bool { yourRole == .admin }

    // MARK: - the table (PD-019, PD-020)

    /// The league table, computed from results rather than stored.
    ///
    /// **Nothing here is remembered.** A table that were stored could drift from the results under
    /// it — the classic way a league's standings come to disagree with its own fixture list — so it
    /// is derived on every read from the fixtures this device holds, and there is no write that can
    /// set a row.
    ///
    /// Both sources count (PD-020) and every row carries how many of its results were **evidenced**,
    /// so the screen can say which parts of a standing are backed by darts and which are somebody's
    /// word. They are never averaged and never merged.
    public var table: [TableRow] { kind == .league ? computedTable : [] }

    /// A round robin's standings. **The one tournament shape that has a table**, because it is the
    /// one where everybody plays everybody — a knockout's standing is the round somebody went out
    /// in, and drawing it a table would be drawing it a league.
    public var standings: [TableRow] {
        (kind == .tournament && shape == .roundRobin) ? computedTable : []
    }

    private var computedTable: [TableRow] {
        var rows: [String: TableRow.Tally] = [:]
        for team in teams { rows[team.id] = TableRow.Tally() }
        for fixture in fixtures {
            guard let home = fixture.homeTeamId, let away = fixture.awayTeamId,
                  let result = fixture.result,
                  rows[home] != nil, rows[away] != nil else { continue }
            rows[home]?.add(scored: result.home, conceded: result.away, source: result.source)
            rows[away]?.add(scored: result.away, conceded: result.home, source: result.source)
        }
        return teams.compactMap { team -> TableRow? in
            guard let tally = rows[team.id] else { return nil }
            return TableRow(team: team, tally: tally,
                            pointsForWin: pointsForWin, pointsForDraw: pointsForDraw)
        }
        .sorted(by: TableRow.before)
    }

    /// Fixtures somebody has to act on: played, and nobody has said what happened. The league screen
    /// leads with these, because a table with results missing is a table that is quietly wrong and
    /// the only person who can fix it is looking at it.
    public var fixturesAwaitingResults: [Fixture] { fixtures.filter(\.awaitsResult) }

    /// Whether the unit may still be changed (PD-022): only while there is nothing to reinterpret.
    public var unitIsStillOpen: Bool { !fixtures.contains { $0.result != nil } }

    /// Whether this league has enough to show a table at all. Two teams and one result: below that
    /// a table is a list of zeroes, which looks like a season nobody has won a game in.
    public var tableIsWorthShowing: Bool {
        kind == .league && teams.count >= 2 && fixtures.contains { $0.result != nil }
    }

    /// Who an announcement would reach, and who it would not.
    public var delivery: (reaches: Int, of: Int, withheld: Withheld) {
        let minors = members.filter { $0.ageBand == .minor }.count
        let unknown = members.filter { $0.ageBand == .unknown }.count
        let withheld = Withheld(minors: minors, ageNotGiven: unknown)
        return (members.count - withheld.total, members.count, withheld)
    }
}


/// One team's line in a league table (PD-019, PD-020).
public struct TableRow: Identifiable, Equatable, Sendable {
    /// The running counts, before they are turned into a row. Separate from `TableRow` so that the
    /// arithmetic happens in one place and a row cannot be constructed with figures that disagree.
    struct Tally: Equatable {
        var won = 0, drawn = 0, lost = 0
        var scoreFor = 0, scoreAgainst = 0
        var evidenced = 0

        mutating func add(scored: Int, conceded: Int, source: ResultSource) {
            scoreFor += scored
            scoreAgainst += conceded
            if scored > conceded { won += 1 } else if scored == conceded { drawn += 1 } else { lost += 1 }
            if source.isEvidenced { evidenced += 1 }
        }
    }

    public let team: Team
    public let won: Int
    public let drawn: Int
    public let lost: Int
    public let scoreFor: Int
    public let scoreAgainst: Int
    public let points: Int
    /// How many of this row's results came from a match scored in THRØ. The rest are somebody's
    /// word, and the screen says so rather than presenting one number as if it were all the same.
    public let evidenced: Int

    public var id: String { team.id }
    public var played: Int { won + drawn + lost }
    public var difference: Int { scoreFor - scoreAgainst }
    /// Results in this row that nothing checked. Named rather than computed at the call site,
    /// because "played minus evidenced" is the kind of arithmetic a screen gets subtly wrong.
    public var unevidenced: Int { played - evidenced }

    init(team: Team, tally: Tally, pointsForWin: Int, pointsForDraw: Int) {
        self.team = team
        self.won = tally.won
        self.drawn = tally.drawn
        self.lost = tally.lost
        self.scoreFor = tally.scoreFor
        self.scoreAgainst = tally.scoreAgainst
        self.evidenced = tally.evidenced
        self.points = tally.won * pointsForWin + tally.drawn * pointsForDraw
    }

    /// Points, then difference, then what they scored, then the name.
    ///
    /// **This ordering is a convention, not a law**, and it is the one league sport uses almost
    /// everywhere. A league that separates its teams differently — head-to-head first is the common
    /// alternative — cannot say so yet, and that is part of OD-022 rather than something engineering
    /// decided was universal. The name is last so the order is total: two teams level on everything
    /// come out in a stable order rather than in whatever order the dictionary happened to hold.
    static func before(_ a: TableRow, _ b: TableRow) -> Bool {
        if a.points != b.points { return a.points > b.points }
        if a.difference != b.difference { return a.difference > b.difference }
        if a.scoreFor != b.scoreFor { return a.scoreFor > b.scoreFor }
        return a.team.name.localizedCaseInsensitiveCompare(b.team.name) == .orderedAscending
    }
}
