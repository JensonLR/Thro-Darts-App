import Foundation
import ThroNet

// The leagues as a player asks of them (PD-046): which league a team is in, who else is in its
// division and how far their pubs are, which teams play at a pub, and which team or pub a name
// means. Built once per load from what the server lists, and pure, so it is tested rather than
// looked at. Nothing here is a person: the wire carries teams and pubs, and so does this.

public struct LeagueAtlas: Sendable {
    /// One team, with everything the map says about it when it is chosen.
    public struct Entry: Identifiable, Equatable, Sendable {
        public let team: PublicLeague.Team
        public let leagueId: UUID
        /// The league's short name where it has one: this is a line on a phone, not a letterhead.
        public let league: String
        public let playsOn: String?
        public let season: String
        public let divisionId: UUID
        public let division: String
        public let divisionOrdinal: Int
        /// Whether its league runs more than one division; a line names the division only then.
        public let divided: Bool
        /// The league's place in the atlas, and so the chalk it is drawn in.
        public let leagueIndex: Int
        public var id: UUID { team.teamId }
        public var venue: PublicLeague.Venue? { team.venue }
        public var chalk: Int { leagueIndex % LeagueAtlas.chalks }
        /// Whether its pub has a place on the map.
        public var placed: Bool { team.venue?.latitude != nil && team.venue?.longitude != nil }
    }

    /// A league in the atlas's order, with its chalk and how many teams it lists.
    public struct League: Identifiable, Equatable, Sendable {
        public let id: UUID
        public let name: String
        public let index: Int
        public let teams: Int
        public var chalk: Int { index % LeagueAtlas.chalks }
    }

    /// Another team in the same division, and how far its pub is from this one's.
    public struct Rival: Identifiable, Equatable, Sendable {
        public let entry: Entry
        /// Kilometres between the two pubs; nil when either is not on the map.
        public let km: Double?
        public var id: UUID { entry.id }
    }

    /// One of a league's divisions in its shown season, with its teams by name.
    public struct Division: Identifiable, Equatable, Sendable {
        public let id: UUID
        public let name: String
        public let teams: [Entry]
    }

    /// What a search finds: a team, or a pub with the teams that play there.
    public enum Hit: Identifiable, Equatable, Sendable {
        case team(Entry)
        case venue(PublicLeague.Venue, [Entry])

        public var id: String {
            switch self {
            case .team(let e): return "team-\(e.id)"
            case .venue(let v, _): return "venue-\(v.venueId)"
            }
        }

        var name: String {
            switch self {
            case .team(let e): return e.team.name
            case .venue(let v, _): return v.name
            }
        }
    }

    /// How many chalks there are to draw leagues in. A league's chalk is its place in the atlas,
    /// round again after the last, so two leagues side by side are never drawn alike.
    public static let chalks = 6

    public let entries: [Entry]
    public let leagues: [League]
    private let byTeam: [UUID: Int]
    private let byVenue: [UUID: [Int]]
    private let byDivision: [UUID: [Int]]

    /// Every team of every league's shown season — the running one, else the newest (PD-033). A
    /// league with no teams listed is a pin on the map and not a line here.
    public init(_ leagues: [PublicLeague]) {
        var entries: [Entry] = []
        var keys: [League] = []
        for league in leagues {
            guard let season = league.shownSeason else { continue }
            let count = season.divisions.reduce(0) { $0 + $1.teams.count }
            guard count > 0 else { continue }
            let index = keys.count
            let name = league.shortName ?? league.name
            keys.append(League(id: league.leagueId, name: name, index: index, teams: count))
            let divided = season.divisions.count > 1
            for division in season.divisions {
                for team in division.teams {
                    entries.append(Entry(team: team, leagueId: league.leagueId, league: name, playsOn: league.playsOn,
                                         season: season.label, divisionId: division.divisionId, division: division.name,
                                         divisionOrdinal: division.ordinal, divided: divided, leagueIndex: index))
                }
            }
        }
        var byTeam: [UUID: Int] = [:], byVenue: [UUID: [Int]] = [:], byDivision: [UUID: [Int]] = [:]
        for (i, e) in entries.enumerated() {
            if byTeam[e.team.teamId] == nil { byTeam[e.team.teamId] = i }
            if let v = e.team.venue { byVenue[v.venueId, default: []].append(i) }
            byDivision[e.divisionId, default: []].append(i)
        }
        self.entries = entries
        self.leagues = keys
        self.byTeam = byTeam
        self.byVenue = byVenue
        self.byDivision = byDivision
    }

    public func entry(_ teamId: UUID) -> Entry? { byTeam[teamId].map { entries[$0] } }

    /// The teams that play at a pub: by league, then division, then name.
    public func teams(at venueId: UUID) -> [Entry] {
        (byVenue[venueId] ?? []).map { entries[$0] }.sorted(by: LeagueAtlas.order)
    }

    /// The other teams in [teamId]'s division, nearest pub first. A team whose pub is not on the
    /// map comes last, by name: it is still a rival, only not one the map can point at.
    public func rivals(of teamId: UUID) -> [Rival] {
        guard let me = entry(teamId) else { return [] }
        return (byDivision[me.divisionId] ?? []).map { entries[$0] }
            .filter { $0.team.teamId != teamId }
            .map { Rival(entry: $0, km: LeagueAtlas.km(me.venue, $0.venue)) }
            .sorted { a, b in
                switch (a.km, b.km) {
                case let (x?, y?) where x != y: return x < y
                case (.some, .none): return true
                case (.none, .some): return false
                default: return a.entry.team.name < b.entry.team.name
                }
            }
    }

    /// The chalks a pub is drawn in: one for each league that plays there, in the atlas's order. A
    /// pub with sides in two leagues wears two, as a pub with two league nights chalks up both.
    public func chalks(at venueId: UUID) -> [Int] {
        teams(at: venueId).reduce(into: [Int]()) { seen, e in if !seen.contains(e.chalk) { seen.append(e.chalk) } }
    }

    /// A league's divisions in the order it runs them, each with its teams by name.
    public func divisions(of leagueId: UUID) -> [Division] {
        var order: [UUID] = []
        var byId: [UUID: (name: String, ordinal: Int, teams: [Entry])] = [:]
        for e in entries where e.leagueId == leagueId {
            if byId[e.divisionId] == nil { order.append(e.divisionId); byId[e.divisionId] = (e.division, e.divisionOrdinal, []) }
            byId[e.divisionId]?.teams.append(e)
        }
        return order
            .compactMap { id in byId[id].map { (ordinal: $0.ordinal, division: Division(id: id, name: $0.name, teams: $0.teams.sorted { $0.team.name < $1.team.name })) } }
            .sorted { $0.ordinal < $1.ordinal }
            .map(\.division)
    }

    /// Teams and pubs whose names hold [query], case and accents aside, those that begin with it
    /// first. Nothing for fewer than two letters, which would match half the map.
    public func search(_ query: String, limit: Int = 8) -> [Hit] {
        let q = LeagueAtlas.fold(query.trimmingCharacters(in: .whitespacesAndNewlines))
        guard q.count >= 2 else { return [] }
        var venues: [UUID: (venue: PublicLeague.Venue, teams: [Entry])] = [:]
        var venueOrder: [UUID] = []
        var teams: [Hit] = []
        for e in entries {
            if LeagueAtlas.fold(e.team.name).contains(q) { teams.append(.team(e)) }
            if let v = e.team.venue, LeagueAtlas.fold(v.name).contains(q) {
                if venues[v.venueId] == nil { venueOrder.append(v.venueId); venues[v.venueId] = (v, []) }
                venues[v.venueId]?.teams.append(e)
            }
        }
        let pubs: [Hit] = venueOrder.compactMap { id in venues[id].map { Hit.venue($0.venue, $0.teams.sorted(by: LeagueAtlas.order)) } }
        let ranked = (teams + pubs).enumerated().sorted { a, b in
            let pa = LeagueAtlas.fold(a.element.name).hasPrefix(q), pb = LeagueAtlas.fold(b.element.name).hasPrefix(q)
            return pa != pb ? pa : a.offset < b.offset
        }
        return ranked.prefix(limit).map(\.element)
    }

    /// What a chosen team's line says: its league, its division where the league has more than one,
    /// and its night. "Stockton Thursday · Division One · Thursday nights".
    public static func line(_ e: Entry) -> String {
        [e.league, e.divided ? e.division : nil, e.playsOn.map { "\($0) nights" }].compactMap { $0 }.joined(separator: " · ")
    }

    /// What a pub says under its name in a list: how many teams play there, and in which leagues.
    /// "3 teams · Stockton Thursday, Redcar Monday Darts League".
    public static func pubLine(_ teams: [Entry]) -> String {
        let leagues = teams.reduce(into: [String]()) { seen, e in if !seen.contains(e.league) { seen.append(e.league) } }
        let count = teams.count == 1 ? "1 team" : "\(teams.count) teams"
        return leagues.isEmpty ? count : "\(count) · \(leagues.joined(separator: ", "))"
    }

    /// Leagues whose name holds [query] — every league the server lists, and not only those with
    /// teams in the atlas, because a player whose league has no teams on THRØ yet is looking for it
    /// too. Names that begin with it first; nothing for fewer than two letters.
    public static func leaguesNamed(_ query: String, in leagues: [PublicLeague], limit: Int = 3) -> [PublicLeague] {
        let q = fold(query.trimmingCharacters(in: .whitespacesAndNewlines))
        guard q.count >= 2 else { return [] }
        func names(_ l: PublicLeague) -> [String] { [l.name, l.shortName].compactMap { $0 }.map(fold) }
        let hits = leagues.filter { names($0).contains { $0.contains(q) } }
        let begins = hits.filter { names($0).contains { $0.hasPrefix(q) } }
        let rest = hits.filter { l in !names(l).contains { $0.hasPrefix(q) } }
        return Array((begins + rest).prefix(limit))
    }

    static func order(_ a: Entry, _ b: Entry) -> Bool {
        if a.leagueIndex != b.leagueIndex { return a.leagueIndex < b.leagueIndex }
        if a.divisionOrdinal != b.divisionOrdinal { return a.divisionOrdinal < b.divisionOrdinal }
        return a.team.name < b.team.name
    }

    static func km(_ a: PublicLeague.Venue?, _ b: PublicLeague.Venue?) -> Double? {
        guard let la = a?.latitude, let lo = a?.longitude, let lb = b?.latitude, let lob = b?.longitude else { return nil }
        return NearbyLogic.distanceKm(fromLat: la, lon: lo, toLat: lb, lon: lob)
    }

    static func fold(_ s: String) -> String { s.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil) }
}
