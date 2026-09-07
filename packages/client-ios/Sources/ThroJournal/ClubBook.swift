import Foundation
import SQLite3

/// Clubs, leagues and tournaments a person keeps on this phone (PD-009).
///
/// **A separate database from the journal, on purpose.** The journal is append-only evidence:
/// nothing in it is ever edited, and two triggers enforce that. A roster is the opposite kind of
/// thing — a member leaves, a fixture moves, a name is corrected — so it lives in its own file
/// rather than beside rows whose whole story is that they never change. The durability
/// configuration is the same, because there is no reason to write a captain's roster less carefully
/// than a leg.
///
/// **What this is not.** It is not a copy of a club held on a server: there is no server (Gate 6,
/// B4). It is the book a captain keeps — their club, their roster, their fixture list, on their
/// phone. When a server exists the server is authoritative and this becomes the device's side of the
/// reconciliation `packages/trust` already models. Nothing in it has been published and nothing in
/// it is anybody else's record, which is why the screens say so.
public enum ClubBookError: Error, Equatable, CustomStringConvertible {
    case blankName
    case badAccent(String)
    case unknownValue(field: String, value: String)
    case fixtureIsFinished(String)
    case noSuchClub(String)
    case noSuchFixture(String)
    case noSuchMember(String)
    case noSuchTeam(String)
    case pictureRefused(String)
    case notATeamFixture(String)
    case negativeScore
    case unitIsSettled(Int)
    case sqlite(String)

    public var description: String {
        switch self {
        case .blankName:
            return "a club needs a name it can be called by"
        case .badAccent(let v):
            return "an accent is six hex digits or nothing, not \(v.isEmpty ? "(empty)" : v)"
        case .unknownValue(let field, let value):
            return "\(value) is not a \(field) this build knows"
        case .fixtureIsFinished(let s):
            return "a fixture that is \(s) does not move again"
        case .noSuchClub(let id):
            return "no club \(id) on this device"
        case .noSuchFixture(let id):
            return "no fixture \(id) in that club"
        case .noSuchMember(let id):
            return "no member \(id) in that club"
        case .noSuchTeam(let id):
            return "no team \(id) in that league"
        case .notATeamFixture(let id):
            return "fixture \(id) is not between two teams, so it has no team result"
        case .negativeScore:
            return "a score is never negative"
        case .unitIsSettled(let results):
            return "this league already has \(results) result\(results == 1 ? "" : "s") in it, and "
                 + "changing what they are counted in would reinterpret every one of them"
        case .pictureRefused(let band):
            return band == "minor"
                ? "a member recorded as under 18 has no picture"
                : "a member whose age is not established has no picture, for the same reason a minor does not"
        case .sqlite(let m):
            return "club book: \(m)"
        }
    }
}

public struct StoredClub: Equatable, Sendable {
    public let id: String
    public let name: String
    /// `club`, `league` or `tournament`. Held as text because the words belong to the screens, and
    /// refused on write so a read never has to guess.
    public let kind: String
    /// Six hex digits, or nil when the club wears the brand's own accent.
    public let accentHex: String?
    public let createdAt: Date
    /// The club's badge, when it has one. Nil is the ordinary case and always will be for a club
    /// that would rather wear its initials.
    public let badgeAssetId: String?
    /// A tournament's shape (PD-021), nil for anything else. Chosen when it is made and never
    /// afterwards: a shape decides what every round means, so changing it would rewrite the meaning
    /// of matches already played.
    public let shape: String?
    /// What a win and a draw are worth in this league's table.
    ///
    /// **Stored rather than assumed.** Points per win differ between real leagues, and a constant
    /// buried in a table calculation would be THRØ deciding a league's rules for it. The default is
    /// the common one, the screen says which numbers it is using, and OD-022 asks the founder
    /// whether THRØ should have a standard at all.
    public let pointsForWin: Int
    public let pointsForDraw: Int
    /// What this league's results are counted in (PD-022): `legs`, `matches` or `points`.
    ///
    /// **Nil is a real answer**, not a default: a league made before this was asked has none, and it
    /// is not guessed at. `3–1` on its own does not mean anything, and a unit cannot be worked out
    /// afterwards — somebody would have to be asked what they meant.
    public let unit: String?
}

public struct StoredMember: Equatable, Sendable {
    public let clubId: String
    public let id: String
    public let name: String
    /// `member`, `official` or `admin`.
    public let role: String
    /// `adult`, `minor` or `unknown`. A value this build does not recognise reads back as `unknown`
    /// — never as `adult` — because the restrictive answer is the safe one and the permissive one
    /// would list a child.
    public let ageBand: String
    public let joinedAt: Date
    /// Their picture, when they have one. **Only an adult ever does** — see `ImagePolicy`.
    public let avatarAssetId: String?
}

public struct StoredFixture: Equatable, Sendable {
    public let clubId: String
    public let id: String
    public let title: String
    public let when: Date
    public let venue: String
    /// `scheduled`, `postponed`, `cancelled` or `played`.
    public let state: String
    /// The two teams, in a league (PD-019). Both nil in a club, whose fixtures are a title somebody
    /// typed — *"Home to The Bell"* — because a club's fixture list is not a competition between
    /// entities this device knows about. Either both or neither; one alone is refused on write.
    public let homeTeamId: String?
    public let awayTeamId: String?

    public var isBetweenTeams: Bool { homeTeamId != nil && awayTeamId != nil }
}

/// A team in a league (PD-019). A league's unit of competition is a team, not a person.
///
/// A team usually belongs to a club and is not the same thing as one: *The Feathers A* and
/// *The Feathers B* are two teams from one club, and a league that could not tell them apart is a
/// league that cannot run a fixture list.
public struct StoredTeam: Equatable, Sendable {
    public let clubId: String
    public let id: String
    public let name: String
    public let addedAt: Date
}

/// What happened in a fixture, and **where that came from** (PD-020).
///
/// The source is not decoration. A result taken from a match scored in THRØ carries every visit and
/// every dart behind it; a result an official typed carries their word. Both count for the table,
/// because a league that only worked when every player used THRØ would not be a product. Neither is
/// ever shown without saying which it is, and only the first may ever inform a rating.
public struct StoredResult: Equatable, Sendable {
    public let clubId: String
    public let fixtureId: String
    public let home: Int
    public let away: Int
    /// `scored` — from a match in the journal — or `recorded` — an official's word.
    public let source: String
    /// The match this came from. Present exactly when the source is `scored`, enforced by the table.
    public let matchId: String?
    /// Who says so. Present exactly when the source is `recorded`, enforced by the table.
    public let recordedBy: String?
    public let recordedAt: Date
}

public final class ClubBook {
    public static let kinds: Set<String> = ["club", "league", "tournament"]
    public static let roles: Set<String> = ["member", "official", "admin"]
    public static let ageBands: Set<String> = ["adult", "minor", "unknown"]
    public static let fixtureStates: Set<String> = ["scheduled", "postponed", "cancelled", "played"]
    /// The two a fixture never leaves, the same rule `packages/organisation` states in Kotlin.
    public static let finishedFixtureStates: Set<String> = ["cancelled", "played"]
    /// Where a result came from (PD-020). Exactly two, and a row must say which.
    public static let resultSources: Set<String> = ["scored", "recorded"]
    /// The four shapes a tournament may be (PD-021). All four were chosen at once deliberately: a
    /// shape added later is not a feature bolted on, it is a second design of the same screens.
    public static let tournamentShapes: Set<String> = ["knockout", "groups", "roundRobin", "doubleElimination"]
    /// What a league's results are counted in (PD-022). The three ways darts leagues actually run.
    public static let resultUnits: Set<String> = ["legs", "matches", "points"]
    /// What a win and a draw are worth when a league does not say. The common answer in pub and
    /// county darts, stated here once rather than spread through a table calculation.
    public static let defaultPointsForWin = 2
    public static let defaultPointsForDraw = 1

    private let handle: OpaquePointer
    public let configuration: DurabilityConfiguration

    public init(path: String, configuration: DurabilityConfiguration = .measured) throws {
        var db: OpaquePointer?
        guard sqlite3_open(path, &db) == SQLITE_OK, let h = db else {
            if let leaked = db { sqlite3_close(leaked) }
            throw ClubBookError.sqlite("could not open \(path)")
        }
        handle = h
        self.configuration = configuration
        do {
            try Journal.configure(h, configuration)
            try ClubBook.migrate(h)
        } catch let e as JournalError {
            throw ClubBookError.sqlite(e.description)
        }
    }

    deinit { sqlite3_close(handle) }

    // MARK: - schema

    static func migrate(_ h: OpaquePointer) throws {
        try Journal.exec(h, """
            CREATE TABLE IF NOT EXISTS club (
              club_id    TEXT PRIMARY KEY,
              name       TEXT NOT NULL,
              kind       TEXT NOT NULL,
              accent_hex TEXT,
              created_at TEXT NOT NULL
            );
            """)
        // Images arrived after clubs did (PD-014). ADD COLUMN is the one schema change SQLite makes
        // without rewriting a row, so a club written before this reads back with no badge — which is
        // what it has.
        let clubColumns = try Journal.columnNames(h, table: "club")
        if !clubColumns.contains("badge_asset_id") {
            try Journal.exec(h, "ALTER TABLE club ADD COLUMN badge_asset_id TEXT;")
        }
        // ON DELETE CASCADE, with foreign keys switched on in `configure`: removing a club must not
        // leave a roster behind with nothing to belong to.
        try Journal.exec(h, """
            CREATE TABLE IF NOT EXISTS club_member (
              club_id   TEXT NOT NULL REFERENCES club(club_id) ON DELETE CASCADE,
              member_id TEXT NOT NULL,
              name      TEXT NOT NULL,
              role      TEXT NOT NULL,
              age_band  TEXT NOT NULL,
              joined_at TEXT NOT NULL,
              PRIMARY KEY (club_id, member_id)
            );
            """)
        let memberColumns = try Journal.columnNames(h, table: "club_member")
        if !memberColumns.contains("avatar_asset_id") {
            try Journal.exec(h, "ALTER TABLE club_member ADD COLUMN avatar_asset_id TEXT;")
        }
        // The people who play on this device (ADR-016). Not a club's roster — those are members of
        // a club — but the device's own book: who has played here, so a match can say who its two
        // names referred to, and so a claim can later attach all of one person's matches at once.
        try Journal.exec(h, """
            CREATE TABLE IF NOT EXISTS person (
              person_id  TEXT PRIMARY KEY,
              name       TEXT NOT NULL,
              created_at TEXT NOT NULL
            );
            """)
        try Journal.exec(h, """
            CREATE TABLE IF NOT EXISTS club_fixture (
              club_id    TEXT NOT NULL REFERENCES club(club_id) ON DELETE CASCADE,
              fixture_id TEXT NOT NULL,
              title      TEXT NOT NULL,
              when_at    TEXT NOT NULL,
              venue      TEXT NOT NULL,
              state      TEXT NOT NULL,
              PRIMARY KEY (club_id, fixture_id)
            );
            """)

        // Leagues and tournaments arrived after the word for them did (PD-019, PD-020, PD-021).
        // Everything below is additive, so a club written before today reads back exactly as it was:
        // no shape, no teams, no results, and its fixtures still a title somebody typed.
        for column in ["shape TEXT", "points_win INTEGER", "points_draw INTEGER", "result_unit TEXT"]
        where !clubColumns.contains(String(column.split(separator: " ")[0])) {
            try Journal.exec(h, "ALTER TABLE club ADD COLUMN \(column);")
        }
        let fixtureColumns = try Journal.columnNames(h, table: "club_fixture")
        for column in ["home_team_id TEXT", "away_team_id TEXT"]
        where !fixtureColumns.contains(String(column.split(separator: " ")[0])) {
            try Journal.exec(h, "ALTER TABLE club_fixture ADD COLUMN \(column);")
        }

        // A league's teams (PD-019). Its own table rather than a flag on `club_member`, because a
        // team is not a person and a league's roster is a list of teams.
        try Journal.exec(h, """
            CREATE TABLE IF NOT EXISTS club_team (
              club_id  TEXT NOT NULL REFERENCES club(club_id) ON DELETE CASCADE,
              team_id  TEXT NOT NULL,
              name     TEXT NOT NULL,
              added_at TEXT NOT NULL,
              PRIMARY KEY (club_id, team_id)
            );
            """)

        // A result and where it came from (PD-020).
        //
        // **The CHECK is the point.** A scored result without a match to point at, or an official's
        // record with nobody's name on it, is a result whose provenance cannot be shown — and a
        // screen that cannot say which source a row came from is a screen that launders the weaker
        // through the stronger. The database refuses it rather than the view remembering to.
        try Journal.exec(h, """
            CREATE TABLE IF NOT EXISTS fixture_result (
              club_id     TEXT NOT NULL REFERENCES club(club_id) ON DELETE CASCADE,
              fixture_id  TEXT NOT NULL,
              home_score  INTEGER NOT NULL CHECK (home_score >= 0),
              away_score  INTEGER NOT NULL CHECK (away_score >= 0),
              source      TEXT NOT NULL,
              match_id    TEXT,
              recorded_by TEXT,
              recorded_at TEXT NOT NULL,
              PRIMARY KEY (club_id, fixture_id),
              CHECK ((source = 'scored'   AND match_id    IS NOT NULL AND recorded_by IS NULL)
                  OR (source = 'recorded' AND recorded_by IS NOT NULL AND match_id    IS NULL))
            );
            """)
    }

    // MARK: - clubs

    /// Starts a club, league or tournament.
    ///
    /// A **tournament** takes a shape and keeps it (PD-021): the shape decides what a round means,
    /// so it is asked once, at the start, and there is no write that changes it afterwards. A shape
    /// given for anything else is refused rather than ignored, because silently dropping what a
    /// caller asked for is how a screen and a store come to disagree.
    @discardableResult
    public func createClub(name: String, kind: String, accentHex: String? = nil, shape: String? = nil,
                           unit: String? = nil, id: String = UUID().uuidString,
                           createdAt: Date = Date()) throws -> StoredClub {
        let clean = try ClubBook.checkedName(name)
        let accent = try ClubBook.checkedAccent(accentHex)
        try ClubBook.check(kind, in: ClubBook.kinds, field: "kind")
        if let shape {
            guard kind == "tournament" else {
                throw ClubBookError.unknownValue(field: "shape for a \(kind)", value: shape)
            }
            try ClubBook.check(shape, in: ClubBook.tournamentShapes, field: "tournament shape")
        }
        if let unit {
            guard kind != "club" else {
                throw ClubBookError.unknownValue(field: "result unit for a club", value: unit)
            }
            try ClubBook.check(unit, in: ClubBook.resultUnits, field: "result unit")
        }
        try run("""
            INSERT INTO club (club_id, name, kind, accent_hex, created_at, shape, points_win,
                              points_draw, result_unit)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?);
            """,
                [.text(id), .text(clean), .text(kind),
                 accent.map { Journal.Param.text($0) } ?? .null,
                 .text(Journal.iso.string(from: createdAt)),
                 shape.map { Journal.Param.text($0) } ?? .null,
                 .int(Int64(ClubBook.defaultPointsForWin)), .int(Int64(ClubBook.defaultPointsForDraw)),
                 unit.map { Journal.Param.text($0) } ?? .null])
        return StoredClub(id: id, name: clean, kind: kind, accentHex: accent, createdAt: createdAt,
                          badgeAssetId: nil, shape: shape,
                          pointsForWin: ClubBook.defaultPointsForWin,
                          pointsForDraw: ClubBook.defaultPointsForDraw,
                          unit: unit)
    }

    /// Sets what this league's results are counted in (PD-022).
    ///
    /// **Refused once there is a result to reinterpret.** An admin who picked wrong on the first day
    /// can fix it; after the first result is in, changing the unit would silently turn every number
    /// already entered into a claim about something else. The store refuses it rather than the screen
    /// remembering to, and the refusal says how many results are in the way.
    public func setUnit(_ unit: String, on clubId: String) throws {
        try ClubBook.check(unit, in: ClubBook.resultUnits, field: "result unit")
        try requireClub(clubId)
        var results = 0
        try run("SELECT COUNT(*) FROM fixture_result WHERE club_id = ?;", [.text(clubId)]) { s in
            results = Int(sqlite3_column_int64(s, 0))
        }
        guard results == 0 else { throw ClubBookError.unitIsSettled(results) }
        try run("UPDATE club SET result_unit = ? WHERE club_id = ?;", [.text(unit), .text(clubId)])
    }

    /// What a win and a draw are worth in this league. Refused if either is negative — a league that
    /// docks points for winning is not a league, it is a typing mistake.
    public func setPoints(win: Int, draw: Int, on clubId: String) throws {
        guard win >= 0, draw >= 0 else { throw ClubBookError.negativeScore }
        try requireClub(clubId)
        try run("UPDATE club SET points_win = ?, points_draw = ? WHERE club_id = ?;",
                [.int(Int64(win)), .int(Int64(draw)), .text(clubId)])
    }

    /// Renames a club and/or changes its accent. A club is a thing people get wrong when they type it.
    public func updateClub(id: String, name: String, accentHex: String?) throws {
        let clean = try ClubBook.checkedName(name)
        let accent = try ClubBook.checkedAccent(accentHex)
        try requireClub(id)
        try run("UPDATE club SET name = ?, accent_hex = ? WHERE club_id = ?;",
                [.text(clean), accent.map { Journal.Param.text($0) } ?? .null, .text(id)])
    }

    public func deleteClub(id: String) throws {
        try run("DELETE FROM club WHERE club_id = ?;", [.text(id)])
    }

    public func clubs() throws -> [StoredClub] {
        var out: [StoredClub] = []
        try run("""
            SELECT club_id, name, kind, accent_hex, created_at, badge_asset_id, shape,
                   points_win, points_draw, result_unit
            FROM club ORDER BY name COLLATE NOCASE;
            """, []) { s in
            let kind = Journal.text(s, 2)
            let shape = sqlite3_column_type(s, 6) == SQLITE_NULL ? nil : Journal.text(s, 6)
            out.append(StoredClub(
                id: Journal.text(s, 0),
                name: Journal.text(s, 1),
                kind: kind,
                accentHex: sqlite3_column_type(s, 3) == SQLITE_NULL ? nil : Journal.text(s, 3),
                createdAt: Journal.iso.date(from: Journal.text(s, 4)) ?? Date(timeIntervalSince1970: 0),
                badgeAssetId: sqlite3_column_type(s, 5) == SQLITE_NULL ? nil : Journal.text(s, 5),
                // A shape belongs to a tournament. A shape on anything else is a row this build did
                // not write, and it is dropped rather than shown — the same treatment an unreadable
                // age band gets, and for the same reason: a read never guesses.
                shape: (kind == "tournament"
                        && shape.map { ClubBook.tournamentShapes.contains($0) } == true) ? shape : nil,
                pointsForWin: ClubBook.points(s, 7, or: ClubBook.defaultPointsForWin),
                pointsForDraw: ClubBook.points(s, 8, or: ClubBook.defaultPointsForDraw),
                // A unit this build does not know reads back as none, and a league says so rather
                // than the screens labelling every number with a word nobody chose.
                unit: {
                    guard sqlite3_column_type(s, 9) != SQLITE_NULL else { return nil }
                    let value = Journal.text(s, 9)
                    return ClubBook.resultUnits.contains(value) ? value : nil
                }()))
        }
        return out
    }

    // MARK: - members

    @discardableResult
    public func addMember(to clubId: String, name: String, role: String, ageBand: String,
                          id: String = UUID().uuidString, joinedAt: Date = Date()) throws -> StoredMember {
        let clean = try ClubBook.checkedName(name)
        try ClubBook.check(role, in: ClubBook.roles, field: "role")
        try ClubBook.check(ageBand, in: ClubBook.ageBands, field: "age band")
        try requireClub(clubId)
        try run("""
            INSERT INTO club_member (club_id, member_id, name, role, age_band, joined_at)
            VALUES (?, ?, ?, ?, ?, ?);
            """, [.text(clubId), .text(id), .text(clean), .text(role), .text(ageBand),
                  .text(Journal.iso.string(from: joinedAt))])
        return StoredMember(clubId: clubId, id: id, name: clean, role: role, ageBand: ageBand,
                            joinedAt: joinedAt, avatarAssetId: nil)
    }

    public func removeMember(_ memberId: String, from clubId: String) throws {
        try run("DELETE FROM club_member WHERE club_id = ? AND member_id = ?;", [.text(clubId), .text(memberId)])
    }

    /// Every member of a club, oldest joiner first. An age band this build does not recognise reads
    /// back as `unknown`: the restrictive answer is the safe one, and the permissive one lists a child.
    public func members(of clubId: String) throws -> [StoredMember] {
        var out: [StoredMember] = []
        try run("""
            SELECT club_id, member_id, name, role, age_band, joined_at, avatar_asset_id FROM club_member
            WHERE club_id = ? ORDER BY joined_at, name COLLATE NOCASE;
            """, [.text(clubId)]) { s in
            let band = Journal.text(s, 4)
            let role = Journal.text(s, 3)
            let safeBand = ClubBook.ageBands.contains(band) ? band : "unknown"
            out.append(StoredMember(
                clubId: Journal.text(s, 0),
                id: Journal.text(s, 1),
                name: Journal.text(s, 2),
                role: ClubBook.roles.contains(role) ? role : "member",
                ageBand: safeBand,
                joinedAt: Journal.iso.date(from: Journal.text(s, 5)) ?? Date(timeIntervalSince1970: 0),
                // Read through the policy, not around it. A row that has a picture and an age this
                // build reads as anything but adult does not get to show it — whether that came from
                // a later build, an edited file, or a bug of ours.
                avatarAssetId: (ImagePolicy.mayHavePicture(ageBand: safeBand)
                                && sqlite3_column_type(s, 6) != SQLITE_NULL) ? Journal.text(s, 6) : nil))
        }
        return out
    }

    // MARK: - fixtures

    /// Adds a fixture. In a league it is **between two teams** (PD-019); in a club it is a title
    /// somebody typed, because a club's fixture list is not a competition between things this device
    /// knows about.
    ///
    /// One team without the other is refused rather than stored as half a fixture: everything that
    /// reads a team fixture — the table, the result, the screen — needs both, and a row that has one
    /// is a row that breaks something later instead of here.
    @discardableResult
    public func addFixture(to clubId: String, title: String, when: Date, venue: String,
                           homeTeam: String? = nil, awayTeam: String? = nil,
                           id: String = UUID().uuidString) throws -> StoredFixture {
        let clean = try ClubBook.checkedName(title)
        try requireClub(clubId)
        switch (homeTeam, awayTeam) {
        case (nil, nil):
            break
        case let (home?, away?):
            try requireTeam(home, in: clubId)
            try requireTeam(away, in: clubId)
            guard home != away else {
                throw ClubBookError.unknownValue(field: "fixture", value: "a team does not play itself")
            }
        case let (one, other):
            throw ClubBookError.notATeamFixture(one ?? other ?? id)
        }
        try run("""
            INSERT INTO club_fixture (club_id, fixture_id, title, when_at, venue, state,
                                      home_team_id, away_team_id)
            VALUES (?, ?, ?, ?, ?, 'scheduled', ?, ?);
            """, [.text(clubId), .text(id), .text(clean), .text(Journal.iso.string(from: when)),
                  .text(venue.trimmingCharacters(in: .whitespacesAndNewlines)),
                  homeTeam.map { Journal.Param.text($0) } ?? .null,
                  awayTeam.map { Journal.Param.text($0) } ?? .null])
        return StoredFixture(clubId: clubId, id: id, title: clean, when: when,
                             venue: venue.trimmingCharacters(in: .whitespacesAndNewlines),
                             state: "scheduled", homeTeamId: homeTeam, awayTeamId: awayTeam)
    }

    /// Moves a fixture. Cancelled and played are terminal — the same rule the Kotlin domain states,
    /// kept here too so the client cannot offer a move the domain would refuse.
    public func moveFixture(_ fixtureId: String, in clubId: String, to state: String) throws {
        try ClubBook.check(state, in: ClubBook.fixtureStates, field: "fixture state")
        var current: String?
        try run("SELECT state FROM club_fixture WHERE club_id = ? AND fixture_id = ?;",
                [.text(clubId), .text(fixtureId)]) { s in current = Journal.text(s, 0) }
        guard let was = current else { throw ClubBookError.noSuchFixture(fixtureId) }
        if ClubBook.finishedFixtureStates.contains(was) { throw ClubBookError.fixtureIsFinished(was) }
        try run("UPDATE club_fixture SET state = ? WHERE club_id = ? AND fixture_id = ?;",
                [.text(state), .text(clubId), .text(fixtureId)])
    }

    public func fixtures(of clubId: String) throws -> [StoredFixture] {
        var out: [StoredFixture] = []
        try run("""
            SELECT club_id, fixture_id, title, when_at, venue, state, home_team_id, away_team_id
            FROM club_fixture WHERE club_id = ? ORDER BY when_at;
            """, [.text(clubId)]) { s in
            let state = Journal.text(s, 5)
            let home = sqlite3_column_type(s, 6) == SQLITE_NULL ? nil : Journal.text(s, 6)
            let away = sqlite3_column_type(s, 7) == SQLITE_NULL ? nil : Journal.text(s, 7)
            // Half a team fixture is not one. The write refuses to make one; a row that has one
            // anyway came from somewhere else, and reads back as the ordinary kind rather than as a
            // fixture whose missing side something downstream would have to invent.
            let both = home != nil && away != nil
            out.append(StoredFixture(
                clubId: Journal.text(s, 0),
                id: Journal.text(s, 1),
                title: Journal.text(s, 2),
                when: Journal.iso.date(from: Journal.text(s, 3)) ?? Date(timeIntervalSince1970: 0),
                venue: Journal.text(s, 4),
                state: ClubBook.fixtureStates.contains(state) ? state : "scheduled",
                homeTeamId: both ? home : nil, awayTeamId: both ? away : nil))
        }
        return out
    }

    // MARK: - teams (PD-019)

    /// Adds a team to a league. A team is a name — who plays for it is `club_member`'s business, and
    /// a league that has teams before it has players is the ordinary way a season is set up.
    @discardableResult
    public func addTeam(to clubId: String, name: String, id: String = UUID().uuidString,
                        addedAt: Date = Date()) throws -> StoredTeam {
        let clean = try ClubBook.checkedName(name)
        try requireClub(clubId)
        try run("INSERT INTO club_team (club_id, team_id, name, added_at) VALUES (?, ?, ?, ?);",
                [.text(clubId), .text(id), .text(clean), .text(Journal.iso.string(from: addedAt))])
        return StoredTeam(clubId: clubId, id: id, name: clean, addedAt: addedAt)
    }

    /// Removes a team, **and every fixture it was in**.
    ///
    /// Deliberate, and the alternative is worse: a fixture whose home side no longer exists is a row
    /// the table would have to guess about. A season that has started is a reason not to remove a
    /// team, which is a decision for whoever is holding the phone, and the screen says what will go.
    public func removeTeam(_ teamId: String, from clubId: String) throws {
        try run("""
            DELETE FROM fixture_result WHERE club_id = ? AND fixture_id IN
              (SELECT fixture_id FROM club_fixture
               WHERE club_id = ? AND (home_team_id = ? OR away_team_id = ?));
            """, [.text(clubId), .text(clubId), .text(teamId), .text(teamId)])
        try run("""
            DELETE FROM club_fixture
            WHERE club_id = ? AND (home_team_id = ? OR away_team_id = ?);
            """, [.text(clubId), .text(teamId), .text(teamId)])
        try run("DELETE FROM club_team WHERE club_id = ? AND team_id = ?;",
                [.text(clubId), .text(teamId)])
    }

    /// How many fixtures removing this team would take with it, so the screen can say the number
    /// before it happens rather than after.
    public func fixtureCount(forTeam teamId: String, in clubId: String) throws -> Int {
        var count = 0
        try run("""
            SELECT COUNT(*) FROM club_fixture
            WHERE club_id = ? AND (home_team_id = ? OR away_team_id = ?);
            """, [.text(clubId), .text(teamId), .text(teamId)]) { s in
            count = Int(sqlite3_column_int64(s, 0))
        }
        return count
    }

    public func teams(of clubId: String) throws -> [StoredTeam] {
        var out: [StoredTeam] = []
        try run("""
            SELECT club_id, team_id, name, added_at FROM club_team
            WHERE club_id = ? ORDER BY name COLLATE NOCASE;
            """, [.text(clubId)]) { s in
            out.append(StoredTeam(
                clubId: Journal.text(s, 0),
                id: Journal.text(s, 1),
                name: Journal.text(s, 2),
                addedAt: Journal.iso.date(from: Journal.text(s, 3)) ?? Date(timeIntervalSince1970: 0)))
        }
        return out
    }

    private func requireTeam(_ teamId: String, in clubId: String) throws {
        var found = false
        try run("SELECT 1 FROM club_team WHERE club_id = ? AND team_id = ?;",
                [.text(clubId), .text(teamId)]) { _ in found = true }
        guard found else { throw ClubBookError.noSuchTeam(teamId) }
    }

    // MARK: - results (PD-020)

    /// Records what happened in a fixture, **with where it came from**.
    ///
    /// Two sources and no third: a match scored in THRØ, or an official's word. The database refuses
    /// a row that cannot say which — see the CHECK on `fixture_result` — so no screen has to
    /// remember to ask.
    ///
    /// Recording a result puts the fixture in `played`, because that is what a result means. A
    /// cancelled fixture is refused: nobody threw, so there is nothing to record, and a result on a
    /// cancelled fixture would be a claim about a match that did not happen.
    public func recordResult(fixture fixtureId: String, in clubId: String, home: Int, away: Int,
                             source: String, matchId: String? = nil, recordedBy: String? = nil,
                             at when: Date = Date()) throws {
        guard home >= 0, away >= 0 else { throw ClubBookError.negativeScore }
        try ClubBook.check(source, in: ClubBook.resultSources, field: "result source")
        switch source {
        case "scored":
            guard matchId != nil, recordedBy == nil else {
                throw ClubBookError.unknownValue(field: "scored result",
                                                 value: "needs the match it came from and nobody's name")
            }
        default:
            guard recordedBy?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false,
                  matchId == nil else {
                throw ClubBookError.unknownValue(field: "recorded result",
                                                 value: "needs a name and no match")
            }
        }

        var state: String?
        var isTeamFixture = false
        try run("""
            SELECT state, home_team_id, away_team_id FROM club_fixture
            WHERE club_id = ? AND fixture_id = ?;
            """, [.text(clubId), .text(fixtureId)]) { s in
            state = Journal.text(s, 0)
            isTeamFixture = sqlite3_column_type(s, 1) != SQLITE_NULL
                         && sqlite3_column_type(s, 2) != SQLITE_NULL
        }
        guard let was = state else { throw ClubBookError.noSuchFixture(fixtureId) }
        guard was != "cancelled" else { throw ClubBookError.fixtureIsFinished(was) }
        guard isTeamFixture else { throw ClubBookError.notATeamFixture(fixtureId) }

        try run("""
            INSERT OR REPLACE INTO fixture_result
              (club_id, fixture_id, home_score, away_score, source, match_id, recorded_by, recorded_at)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?);
            """, [.text(clubId), .text(fixtureId), .int(Int64(home)), .int(Int64(away)),
                  .text(source),
                  matchId.map { Journal.Param.text($0) } ?? .null,
                  recordedBy.map { Journal.Param.text($0.trimmingCharacters(in: .whitespacesAndNewlines)) } ?? .null,
                  .text(Journal.iso.string(from: when))])
        if was != "played" {
            try run("UPDATE club_fixture SET state = 'played' WHERE club_id = ? AND fixture_id = ?;",
                    [.text(clubId), .text(fixtureId)])
        }
    }

    /// Every result in a league. A row whose source this build cannot read is **dropped, not
    /// guessed**: a result nobody can attribute is the one thing a table must not contain.
    public func results(of clubId: String) throws -> [StoredResult] {
        var out: [StoredResult] = []
        try run("""
            SELECT club_id, fixture_id, home_score, away_score, source, match_id, recorded_by, recorded_at
            FROM fixture_result WHERE club_id = ?;
            """, [.text(clubId)]) { s in
            let source = Journal.text(s, 4)
            guard ClubBook.resultSources.contains(source) else { return }
            let matchId = sqlite3_column_type(s, 5) == SQLITE_NULL ? nil : Journal.text(s, 5)
            let recordedBy = sqlite3_column_type(s, 6) == SQLITE_NULL ? nil : Journal.text(s, 6)
            guard source == "scored" ? matchId != nil : recordedBy != nil else { return }
            out.append(StoredResult(
                clubId: Journal.text(s, 0),
                fixtureId: Journal.text(s, 1),
                home: Int(sqlite3_column_int64(s, 2)),
                away: Int(sqlite3_column_int64(s, 3)),
                source: source,
                matchId: source == "scored" ? matchId : nil,
                recordedBy: source == "recorded" ? recordedBy : nil,
                recordedAt: Journal.iso.date(from: Journal.text(s, 7)) ?? Date(timeIntervalSince1970: 0)))
        }
        return out
    }

    /// Takes a result off a fixture. The fixture stays played — it was — and the table simply has
    /// one fewer result in it.
    public func clearResult(fixture fixtureId: String, in clubId: String) throws {
        try run("DELETE FROM fixture_result WHERE club_id = ? AND fixture_id = ?;",
                [.text(clubId), .text(fixtureId)])
    }

    /// A points column read back, or the default when the column is null — which it is for every
    /// league created before points were stored.
    static func points(_ s: OpaquePointer, _ index: Int32, or fallback: Int) -> Int {
        guard sqlite3_column_type(s, index) != SQLITE_NULL else { return fallback }
        let value = Int(sqlite3_column_int64(s, index))
        return value >= 0 ? value : fallback
    }

    // MARK: - images (PD-014)

    /// Sets or clears a club's badge. A club is not a person, so no age question arises.
    public func setBadge(_ assetId: String?, on clubId: String) throws {
        try requireClub(clubId)
        try run("UPDATE club SET badge_asset_id = ? WHERE club_id = ?;",
                [assetId.map { Journal.Param.text($0) } ?? .null, .text(clubId)])
    }

    /// Sets or clears a member's picture.
    ///
    /// **Refused for anybody not recorded as an adult**, including one whose age is not established,
    /// and refused at the point of writing rather than at the point of drawing — so there is no image
    /// of a child in the file to leak, whatever any screen later decides to render.
    public func setAvatar(_ assetId: String?, forMember memberId: String, in clubId: String) throws {
        guard let member = try members(of: clubId).first(where: { $0.id == memberId }) else {
            throw ClubBookError.noSuchMember(memberId)
        }
        if assetId != nil, !ImagePolicy.mayHavePicture(ageBand: member.ageBand) {
            throw ClubBookError.pictureRefused(member.ageBand)
        }
        try run("UPDATE club_member SET avatar_asset_id = ? WHERE club_id = ? AND member_id = ?;",
                [assetId.map { Journal.Param.text($0) } ?? .null, .text(clubId), .text(memberId)])
    }

    /// Every asset id anything currently points at. What is not in here is not referenced, which is
    /// how a deleted club's badge stops taking up space.
    public func referencedAssetIds() throws -> Set<String> {
        var out: Set<String> = []
        try run("SELECT badge_asset_id FROM club WHERE badge_asset_id IS NOT NULL;", []) { s in
            out.insert(Journal.text(s, 0))
        }
        try run("SELECT avatar_asset_id FROM club_member WHERE avatar_asset_id IS NOT NULL;", []) { s in
            out.insert(Journal.text(s, 0))
        }
        return out
    }

    // MARK: - people (ADR-016)

    /// Everybody the device knows, by name.
    public func people() throws -> [LocalPerson] {
        var out: [LocalPerson] = []
        try run("SELECT person_id, name FROM person ORDER BY name COLLATE NOCASE;", []) { s in
            out.append(LocalPerson(id: Journal.text(s, 0), name: Journal.text(s, 1)))
        }
        return out
    }

    /// The person this name refers to, adding them if the device has not seen them before.
    ///
    /// Matching is case- and space-insensitive on purpose: "jenson" typed at the oche on a Tuesday
    /// is the same player as "Jenson" typed on the Thursday, and a book that treated them as two
    /// people would split one person's history in half with nothing to say it had.
    ///
    /// It matches on the name alone, which is the honest limit of what a phone can know: two
    /// different people called Alex who both play here will share a row until somebody says
    /// otherwise. Nothing is lost by that today — the alternative is asking every stranger to
    /// disambiguate themselves, which nobody would do — and the day it matters is the day accounts
    /// exist, when a claim is a person saying which one is theirs.
    @discardableResult
    public func person(named name: String, id: String = UUID().uuidString,
                       createdAt: Date = Date()) throws -> LocalPerson {
        let clean = try ClubBook.checkedName(name)
        let key = ClubBook.fold(clean)
        for existing in try people() where ClubBook.fold(existing.name) == key { return existing }
        try run("INSERT INTO person (person_id, name, created_at) VALUES (?, ?, ?);",
                [.text(id), .text(clean), .text(Journal.iso.string(from: createdAt))])
        return LocalPerson(id: id, name: clean)
    }

    /// Corrects a person's name. Their matches follow, because the matches hold the id.
    public func renamePerson(_ personId: String, to name: String) throws {
        let clean = try ClubBook.checkedName(name)
        try run("UPDATE person SET name = ? WHERE person_id = ?;", [.text(clean), .text(personId)])
    }

    /// How two names are compared when deciding whether they are the same person.
    static func fold(_ name: String) -> String {
        name.lowercased().split(whereSeparator: { $0 == " " || $0 == "\t" }).joined(separator: " ")
    }

    // MARK: - guards

    static func checkedName(_ name: String) throws -> String {
        let clean = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { throw ClubBookError.blankName }
        return clean
    }

    /// Six hex digits or nothing, the same shape `Colour` refuses in Kotlin. A `#` is accepted and
    /// dropped, because a person typing a colour types the hash.
    static func checkedAccent(_ hex: String?) throws -> String? {
        guard let raw = hex?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else { return nil }
        let digits = raw.hasPrefix("#") ? String(raw.dropFirst()) : raw
        guard digits.count == 6, digits.allSatisfy({ $0.isHexDigit }) else { throw ClubBookError.badAccent(raw) }
        return digits.uppercased()
    }

    static func check(_ value: String, in allowed: Set<String>, field: String) throws {
        guard allowed.contains(value) else { throw ClubBookError.unknownValue(field: field, value: value) }
    }

    private func requireClub(_ id: String) throws {
        var found = false
        try run("SELECT 1 FROM club WHERE club_id = ?;", [.text(id)]) { _ in found = true }
        guard found else { throw ClubBookError.noSuchClub(id) }
    }

    /// For tests: run arbitrary SQL against this book's own connection, including SQL the guards
    /// above would refuse — which is the only way to prove what a read does with a row it cannot parse.
    func forTests(_ sql: String) throws { try Journal.exec(handle, sql) }

    // MARK: - sqlite

    /// The journal's binding rules, for the journal's reasons: text bound SQLITE_STATIC against
    /// buffers this function owns until the statement is finalised.
    private func run(_ sql: String, _ params: [Journal.Param], row: ((OpaquePointer) -> Void)? = nil) throws {
        var owned: [UnsafeMutablePointer<CChar>] = []
        defer { owned.forEach { free($0) } }

        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(handle, sql, -1, &stmt, nil) == SQLITE_OK, let s = stmt else {
            throw ClubBookError.sqlite("prepare failed: \(String(cString: sqlite3_errmsg(handle)))")
        }
        defer { sqlite3_finalize(s) }

        for (i, p) in params.enumerated() {
            let index = Int32(i + 1)
            switch p {
            case .text(let value):
                guard let c = strdup(value) else { throw ClubBookError.sqlite("strdup failed") }
                owned.append(c)
                sqlite3_bind_text(s, index, c, -1, nil)
            case .int(let value):
                sqlite3_bind_int64(s, index, value)
            case .null:
                sqlite3_bind_null(s, index)
            }
        }

        while true {
            let rc = sqlite3_step(s)
            if rc == SQLITE_ROW { row?(s); continue }
            if rc == SQLITE_DONE { return }
            throw ClubBookError.sqlite("\(sql.prefix(60))…: \(String(cString: sqlite3_errmsg(handle)))")
        }
    }
}
