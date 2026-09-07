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
}

public struct StoredFixture: Equatable, Sendable {
    public let clubId: String
    public let id: String
    public let title: String
    public let when: Date
    public let venue: String
    /// `scheduled`, `postponed`, `cancelled` or `played`.
    public let state: String
}

public final class ClubBook {
    public static let kinds: Set<String> = ["club", "league", "tournament"]
    public static let roles: Set<String> = ["member", "official", "admin"]
    public static let ageBands: Set<String> = ["adult", "minor", "unknown"]
    public static let fixtureStates: Set<String> = ["scheduled", "postponed", "cancelled", "played"]
    /// The two a fixture never leaves, the same rule `packages/organisation` states in Kotlin.
    public static let finishedFixtureStates: Set<String> = ["cancelled", "played"]

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
    }

    // MARK: - clubs

    @discardableResult
    public func createClub(name: String, kind: String, accentHex: String? = nil,
                           id: String = UUID().uuidString, createdAt: Date = Date()) throws -> StoredClub {
        let clean = try ClubBook.checkedName(name)
        let accent = try ClubBook.checkedAccent(accentHex)
        try ClubBook.check(kind, in: ClubBook.kinds, field: "kind")
        try run("INSERT INTO club (club_id, name, kind, accent_hex, created_at) VALUES (?, ?, ?, ?, ?);",
                [.text(id), .text(clean), .text(kind),
                 accent.map { Journal.Param.text($0) } ?? .null,
                 .text(Journal.iso.string(from: createdAt))])
        return StoredClub(id: id, name: clean, kind: kind, accentHex: accent, createdAt: createdAt)
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
        try run("SELECT club_id, name, kind, accent_hex, created_at FROM club ORDER BY name COLLATE NOCASE;", []) { s in
            out.append(StoredClub(
                id: Journal.text(s, 0),
                name: Journal.text(s, 1),
                kind: Journal.text(s, 2),
                accentHex: sqlite3_column_type(s, 3) == SQLITE_NULL ? nil : Journal.text(s, 3),
                createdAt: Journal.iso.date(from: Journal.text(s, 4)) ?? Date(timeIntervalSince1970: 0)))
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
        return StoredMember(clubId: clubId, id: id, name: clean, role: role, ageBand: ageBand, joinedAt: joinedAt)
    }

    public func removeMember(_ memberId: String, from clubId: String) throws {
        try run("DELETE FROM club_member WHERE club_id = ? AND member_id = ?;", [.text(clubId), .text(memberId)])
    }

    /// Every member of a club, oldest joiner first. An age band this build does not recognise reads
    /// back as `unknown`: the restrictive answer is the safe one, and the permissive one lists a child.
    public func members(of clubId: String) throws -> [StoredMember] {
        var out: [StoredMember] = []
        try run("""
            SELECT club_id, member_id, name, role, age_band, joined_at FROM club_member
            WHERE club_id = ? ORDER BY joined_at, name COLLATE NOCASE;
            """, [.text(clubId)]) { s in
            let band = Journal.text(s, 4)
            let role = Journal.text(s, 3)
            out.append(StoredMember(
                clubId: Journal.text(s, 0),
                id: Journal.text(s, 1),
                name: Journal.text(s, 2),
                role: ClubBook.roles.contains(role) ? role : "member",
                ageBand: ClubBook.ageBands.contains(band) ? band : "unknown",
                joinedAt: Journal.iso.date(from: Journal.text(s, 5)) ?? Date(timeIntervalSince1970: 0)))
        }
        return out
    }

    // MARK: - fixtures

    @discardableResult
    public func addFixture(to clubId: String, title: String, when: Date, venue: String,
                           id: String = UUID().uuidString) throws -> StoredFixture {
        let clean = try ClubBook.checkedName(title)
        try requireClub(clubId)
        try run("""
            INSERT INTO club_fixture (club_id, fixture_id, title, when_at, venue, state)
            VALUES (?, ?, ?, ?, ?, 'scheduled');
            """, [.text(clubId), .text(id), .text(clean), .text(Journal.iso.string(from: when)),
                  .text(venue.trimmingCharacters(in: .whitespacesAndNewlines))])
        return StoredFixture(clubId: clubId, id: id, title: clean, when: when,
                             venue: venue.trimmingCharacters(in: .whitespacesAndNewlines), state: "scheduled")
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
            SELECT club_id, fixture_id, title, when_at, venue, state FROM club_fixture
            WHERE club_id = ? ORDER BY when_at;
            """, [.text(clubId)]) { s in
            let state = Journal.text(s, 5)
            out.append(StoredFixture(
                clubId: Journal.text(s, 0),
                id: Journal.text(s, 1),
                title: Journal.text(s, 2),
                when: Journal.iso.date(from: Journal.text(s, 3)) ?? Date(timeIntervalSince1970: 0),
                venue: Journal.text(s, 4),
                state: ClubBook.fixtureStates.contains(state) ? state : "scheduled"))
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
