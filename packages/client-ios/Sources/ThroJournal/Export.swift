import Foundation

// An export the player controls (PD-017).
//
// The file is the whole of what this device holds about a player's darts: every match, every row of
// the journal as written, every person the device knows and every club it keeps. JSON, because a
// player should be able to open it and read it, and because a tool that imports it one day should
// not have to reverse-engineer a binary.

/// The exported document. Versioned, because a format that cannot say which one it is cannot be
/// read safely by a later build — which is the same lesson the journal's `unknown` row kind taught.
public struct ExportDocument: Codable, Equatable, Sendable {
    /// Bumped whenever a reader would need to behave differently. A reader that does not know a
    /// version refuses rather than guessing.
    public static let currentFormat = 1

    public let format: Int
    public let app: String
    public let exportedAt: String
    /// The device that wrote it, which is the device whose `deviceSeq` the rows are numbered under.
    public let deviceId: String
    /// FNV-1a over the canonical text of `matches`, `journal`, `people` and `clubs`.
    ///
    /// **What it does and does not prove.** It detects a file that has been corrupted or casually
    /// edited between the phone and wherever it ended up. It proves nothing about who wrote the rows
    /// or when: this device computed it over rows in a file this device's owner can edit, so a
    /// determined forger simply recomputes it. ADR-016 says the same thing about a claimed local
    /// history — attributable, never verified — and this is the same claim, no larger.
    public let digest: String

    public let matches: [Match]
    public let journal: [Row]
    public let people: [Person]
    public let clubs: [Club]
    /// Assets the device holds that are **not in this file**: badges and pictures are image bytes,
    /// and naming them is more honest than silently dropping them. A reader knows what is missing.
    public let assetsNotIncluded: [String]

    public struct Match: Codable, Equatable, Sendable {
        public let id: String
        public let homeName: String, awayName: String
        public let homePlayerId: String?, awayPlayerId: String?
        public let startingScore: Int
        public let inRule: String, outRule: String
        public let legsMode: String
        public let legsTarget: Int
        public let throwFirst: String
        public let startedAt: String
        /// How it ended short, if it did (PD-016): `retired-home`, `retired-away`, `abandoned`, or
        /// absent when it was played out or is still going.
        public let ending: String?
    }

    public struct Row: Codable, Equatable, Sendable {
        public let matchId: String
        public let deviceId: String
        public let deviceSeq: Int64
        public let commandId: String
        public let kind: String
        public let seat: String
        public let visitTotal: Int
        public let dartsUsed: Int?
        public let dartsAtDouble: Int?
        public let correctsSeq: Int64?
        public let occurredAt: String
    }

    public struct Person: Codable, Equatable, Sendable {
        public let id: String
        public let name: String
    }

    public struct Club: Codable, Equatable, Sendable {
        public let id: String
        public let name: String
        public let kind: String
        public let accentHex: String?
        public let members: [Member]
        public let fixtures: [Fixture]

        public struct Member: Codable, Equatable, Sendable {
            public let id: String, name: String, role: String, ageBand: String, joined: String
        }
        public struct Fixture: Codable, Equatable, Sendable {
            public let id: String, title: String, when: String, venue: String, state: String
        }
    }
}

public enum ExportError: Error, Equatable, CustomStringConvertible {
    /// The file says it is a format this build does not know. Refused rather than half-read, for
    /// the same reason the journal refuses a row kind it cannot interpret.
    case unknownFormat(Int)
    case notAnExport(String)
    /// The digest does not match the content. The file has changed since it was written.
    case digestMismatch(expected: String, found: String)

    public var description: String {
        switch self {
        case let .unknownFormat(v):
            return "This file was written by a later version of THRØ (format \(v)). Update the app to read it."
        case let .notAnExport(why):
            return "This is not a THRØ export: \(why)"
        case let .digestMismatch(expected, found):
            return "This file has changed since it was exported (expected \(expected), found \(found))."
        }
    }
}

public enum Export {

    /// Everything this device holds, as one document.
    ///
    /// `clubs` is passed in rather than read here because the club book is a different database in a
    /// different module, and `ThroJournal` has no business knowing where it lives — the same
    /// separation ADR-006 gives for why the two are separate files at all.
    public static func make(_ journal: Journal, clubs: [ExportDocument.Club] = [],
                            people: [LocalPerson] = [], assetsNotIncluded: [String] = [],
                            at now: Date = Date()) throws -> ExportDocument {
        var matches: [ExportDocument.Match] = []
        var rows: [ExportDocument.Row] = []

        for record in try journal.matches() {
            let ending = try journal.ending(for: record.id)
            matches.append(ExportDocument.Match(
                id: record.id.value,
                homeName: record.homeName, awayName: record.awayName,
                homePlayerId: record.homePlayerId, awayPlayerId: record.awayPlayerId,
                startingScore: record.startingScore,
                inRule: record.inRule.rawValue, outRule: record.outRule.rawValue,
                legsMode: record.legsMode == .firstTo ? "firstTo" : "bestOf",
                legsTarget: record.legsTarget,
                throwFirst: record.throwFirst.rawValue,
                startedAt: Journal.iso.string(from: record.startedAt),
                ending: Export.name(ending)))
            // Every row, including retractions, attestations and endings — not just the visits that
            // stand. An export that dropped the struck rows would be a tidier record of a different
            // match, and the whole point of an append-only journal is that the corrections are in it.
            for e in try journal.entries(for: record.id) {
                rows.append(ExportDocument.Row(
                    matchId: e.matchId.value, deviceId: e.deviceId.value, deviceSeq: e.deviceSeq,
                    commandId: e.commandId, kind: e.kind.rawValue, seat: e.seat.rawValue,
                    visitTotal: e.visitTotal, dartsUsed: e.dartsUsed, dartsAtDouble: e.dartsAtDouble,
                    correctsSeq: e.correctsSeq, occurredAt: Journal.iso.string(from: e.occurredAt)))
            }
        }

        let peopleOut = people.map { ExportDocument.Person(id: $0.id, name: $0.name) }
        return ExportDocument(
            format: ExportDocument.currentFormat,
            app: "THRØ",
            exportedAt: Journal.iso.string(from: now),
            deviceId: journal.deviceId.value,
            digest: digest(matches: matches, rows: rows, people: peopleOut, clubs: clubs),
            matches: matches, journal: rows, people: peopleOut, clubs: clubs,
            assetsNotIncluded: assetsNotIncluded)
    }

    static func name(_ ending: Ending?) -> String? {
        switch ending {
        case let .retired(by): return "retired-\(by.rawValue)"
        case .abandoned: return "abandoned"
        case nil: return nil
        }
    }

    /// The bytes written to disk. Sorted keys and pretty printing, so the same device state produces
    /// the same file — a diffable export is worth more to somebody trying to find a discrepancy than
    /// a compact one.
    public static func data(_ document: ExportDocument) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(document)
    }

    /// Reads an export back, refusing a format it does not know and reporting a digest that does not
    /// match. **It does not write anything into the journal**, and there is deliberately no function
    /// here that does: merging two append-only journals with their own gapless per-device sequences
    /// is the reconciliation ADR-006 specifies for sync, and sync is not built. An import that
    /// pretended to do it would produce a journal whose sequence lies about what this device wrote.
    public static func read(_ data: Data) throws -> ExportDocument {
        let document: ExportDocument
        do {
            document = try JSONDecoder().decode(ExportDocument.self, from: data)
        } catch {
            throw ExportError.notAnExport("\(error)")
        }
        guard document.format == ExportDocument.currentFormat else {
            throw ExportError.unknownFormat(document.format)
        }
        let recomputed = digest(matches: document.matches, rows: document.journal,
                                people: document.people, clubs: document.clubs)
        guard recomputed == document.digest else {
            throw ExportError.digestMismatch(expected: document.digest, found: recomputed)
        }
        return document
    }

    /// A one-line summary of a file, for the screen that shows what was found before anything is done
    /// with it.
    public static func summary(_ d: ExportDocument) -> String {
        let visits = d.journal.filter { $0.kind == "visit" }.count
        return "\(d.matches.count) match\(d.matches.count == 1 ? "" : "es"), "
             + "\(visits) visit\(visits == 1 ? "" : "s"), "
             + "\(d.people.count) player\(d.people.count == 1 ? "" : "s"), "
             + "\(d.clubs.count) club\(d.clubs.count == 1 ? "" : "s"), "
             + "exported \(d.exportedAt)."
    }

    /// FNV-1a over the canonical encoding of the content, excluding the header. Excluding it is what
    /// lets the digest be computed before the header that carries it exists, and means re-exporting
    /// the same matches a second later gives the same digest — which is the property that makes two
    /// exports comparable.
    static func digest(matches: [ExportDocument.Match], rows: [ExportDocument.Row],
                       people: [ExportDocument.Person], clubs: [ExportDocument.Club]) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        var hash: UInt64 = 0xcbf29ce484222325
        func absorb(_ data: Data) {
            for byte in data {
                hash ^= UInt64(byte)
                hash = hash &* 0x100000001b3
            }
        }
        // Encoded separately and in a fixed order, so a person moving between two lists could never
        // hash the same as one staying put.
        for part in [try? encoder.encode(matches), try? encoder.encode(rows),
                     try? encoder.encode(people), try? encoder.encode(clubs)] {
            absorb(part ?? Data())
            absorb(Data([0]))
        }
        return String(format: "%016llx", hash)
    }

    /// What a file is called when it is shared. Dated, because a player with three of them wants to
    /// know which is which without opening them.
    public static func filename(at now: Date = Date()) -> String {
        let stamp = DateFormatter()
        stamp.dateFormat = "yyyy-MM-dd"
        stamp.timeZone = TimeZone(identifier: "UTC")
        stamp.locale = Locale(identifier: "en_US_POSIX")
        return "THRO-darts-\(stamp.string(from: now)).json"
    }
}

public extension ClubBook {
    /// This book as export rows (PD-017).
    ///
    /// Lives here rather than in `Export` because the shape of a stored club is the book's business,
    /// and the export document should not have to know how a roster is kept. Image *bytes* are not
    /// included — see `ExportDocument.assetsNotIncluded`, which names what is missing rather than
    /// dropping it silently.
    func exportRows() throws -> [ExportDocument.Club] {
        try clubs().map { club in
            ExportDocument.Club(
                id: club.id, name: club.name, kind: club.kind, accentHex: club.accentHex,
                members: try members(of: club.id).map {
                    ExportDocument.Club.Member(id: $0.id, name: $0.name, role: $0.role,
                                               ageBand: $0.ageBand,
                                               joined: Journal.iso.string(from: $0.joinedAt))
                },
                fixtures: try fixtures(of: club.id).map {
                    ExportDocument.Club.Fixture(id: $0.id, title: $0.title,
                                                when: Journal.iso.string(from: $0.when),
                                                venue: $0.venue, state: $0.state)
                })
        }
    }
}

/// What a player is told when they open an export file to check it (PD-017).
///
/// **Why this exists at all.** `Export.read` and `Export.summary` were written, tested ten ways, and
/// wired to nothing — `summary`'s own doc comment described "the screen that shows what was found",
/// and there was no such screen. An export nobody can read back is a file a player has to *trust*
/// worked, which is exactly the posture this repository is built to avoid. So the file can be opened
/// and inspected.
///
/// **It writes nothing**, and there is no path from here that does. That is PD-017's decision, not a
/// limitation of this type: merging an exported journal into a live one is the reconciliation ADR-006
/// specifies for sync, and sync is not built.
public enum ExportInspection: Equatable, Sendable {
    /// The file is a THRØ export and its digest matches its content.
    case readable(Readable)
    /// It is not, or it has changed since it was written. The reason is the player's to read.
    case refused(String)

    public struct Readable: Equatable, Sendable {
        public let summary: String
        public let matches: Int
        public let visits: Int
        public let people: Int
        public let clubs: Int
        public let exportedAt: String
        /// The device that wrote it. **Not** necessarily this one — a file can come from a phone
        /// somebody no longer has, which is most of the point of having it.
        public let deviceId: String
        /// Whether it came from this device. Said rather than assumed either way.
        public let fromThisDevice: Bool
        /// Assets the file names but does not carry.
        public let assetsNotIncluded: Int
    }

    /// Reads and describes a file. Never throws: a refusal is an answer, and one that reaches the
    /// screen as a sentence rather than as an error the view has to interpret.
    public static func of(_ data: Data, thisDevice: DeviceId? = nil) -> ExportInspection {
        do {
            let d = try Export.read(data)
            return .readable(Readable(
                summary: Export.summary(d),
                matches: d.matches.count,
                visits: d.journal.filter { $0.kind == "visit" }.count,
                people: d.people.count,
                clubs: d.clubs.count,
                exportedAt: d.exportedAt,
                deviceId: d.deviceId,
                fromThisDevice: thisDevice.map { $0.value == d.deviceId } ?? false,
                assetsNotIncluded: d.assetsNotIncluded.count))
        } catch let error as ExportError {
            return .refused(error.description)
        } catch {
            return .refused("This file could not be read: \(error)")
        }
    }
}
