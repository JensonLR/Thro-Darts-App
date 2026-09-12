import Foundation
import ThroEngine
import ThroJournal
import ThroNet

// Sending a match this phone scored to THRØ (PD-040).
//
// The phone sends the journal, not a summary: every visit and every retraction, in the order the
// device wrote them. A replayed total would be the app deciding what happened and discarding the
// record PD-004 exists to keep — and a board that showed a struck figure while the server never
// heard of it would be two accounts of one night.
//
// A match that ended short (PD-016) is sent as it ended: the retirement or abandonment row goes last,
// and the server adds nothing after it (V034). The first version refused such a match, because the
// server had no event for an ending and the visits alone would have said the match was still going.
//
// Nothing here remembers how far a previous attempt got, and that is deliberate. The server is
// unique on (match, device, deviceSeq), so sending the lot again adds only what is missing. A phone
// that keeps its own high-water mark is a phone that can be wrong about it.

/// Turning a match's journal into what the wire takes, and saying plainly when it cannot.
public enum MatchUpload {

    /// Whether a match can be sent, and what to send.
    public enum Ready: Equatable {
        case ready([ThroAPI.UploadRow])
        /// It cannot go yet, and this is the reason a person is shown.
        case notYet(String)
    }

    /// The kinds THRØ can receive: visits, the retractions that struck them, and an ending.
    public static let sendable: Set<String> = ["visit", "retraction", "retirement", "abandonment"]

    /// The two ways a match ends short of its format (PD-016).
    static let endings: Set<String> = ["retirement", "abandonment"]

    public static let nothingToSend = "There is nothing in this match to send yet."

    /// The instant format the server parses. Its own, rather than the journal's internal one, so a
    /// change to how the journal writes a date cannot silently change what goes on the wire.
    static let instant: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        f.timeZone = TimeZone(secondsFromGMT: 0)
        return f
    }()

    /// The rows for a match, or the reason it cannot go.
    public static func rows(from entries: [JournalEntry], zone: TimeZone = .current) -> Ready {
        guard !entries.isEmpty else { return .notYet(nothingToSend) }
        // A row written by a LATER build. Sending it as anything would be guessing what it meant.
        if entries.contains(where: { $0.kind == .unknown }) {
            return .notYet("This match has a row written by a newer version of THRØ. Update the app and try again.")
        }
        let rows = entries
            .filter { sendable.contains($0.kind.rawValue) }
            .sorted { $0.deviceSeq < $1.deviceSeq }
            .map { entry in
                ThroAPI.UploadRow(
                    deviceSeq: entry.deviceSeq,
                    kind: entry.kind.rawValue,
                    // For a retirement, the seat that retired. An abandonment names nobody; the
                    // journal's own placeholder goes, and the server reads nothing from it.
                    seat: entry.seat == .home ? "home" : "away",
                    visitTotal: entry.kind == .visit ? entry.visitTotal : nil,
                    correctsSeq: entry.kind == .retraction ? entry.correctsSeq : nil,
                    occurredAt: MatchUpload.instant.string(from: entry.occurredAt),
                    occurredTz: zone.identifier)
            }
        guard !rows.isEmpty else { return .notYet(nothingToSend) }
        // A retraction whose visit was filtered out would be refused by the server, and the reason
        // it gave would be about a row this phone chose not to send. Say it here instead.
        let visits = Set(rows.filter { $0.kind == "visit" }.map { (row: ThroAPI.UploadRow) in row.deviceSeq })
        if rows.contains(where: { $0.kind == "retraction" && !visits.contains($0.correctsSeq ?? -1) }) {
            return .notYet("This match has an undo whose visit is missing from the record. THRØ will not send half of it.")
        }
        // The journal refuses anything after an ending, so this only fires on a record that has been
        // damaged — and a record that disagrees with itself is not one to put on anybody's account.
        if let end = rows.firstIndex(where: { endings.contains($0.kind) }), end != rows.count - 1 {
            return .notYet("This match has a row written after it ended. THRØ will not send a record that disagrees with itself.")
        }
        return .ready(rows)
    }

    /// What a person is told once it has gone. Counts, in words, and the one thing that matters
    /// about it: THRØ has one player's word for this and says so until the other confirms.
    public static func done(_ sent: ThroAPI.Sent) -> String {
        var parts: [String] = []
        if sent.visits > 0 { parts.append(sent.visits == 1 ? "1 visit" : "\(sent.visits) visits") }
        if sent.retractions > 0 { parts.append(sent.retractions == 1 ? "1 undo" : "\(sent.retractions) undos") }
        if let ending = sent.ending { parts.append(ending == "retired" ? "the retirement" : "the abandonment") }
        let added = parts.isEmpty ? "THRØ already had all of it." : "Sent " + sentence(parts) + "."
        return added + " It is recorded as your word for the match until the other player confirms it."
    }

    /// The format, in the server's words.
    ///
    /// **Spelled out, not described.** The first version wrote `String(describing: legsMode).lowercased()`,
    /// which for the engine's `.bestOf` is `bestof` — and the server reads `best_of` — so every match a
    /// phone sent came back *"that match format is not one THRØ can read"*. It was found reading this code
    /// to share a match live, not by a send: the upload's tests built their own wire. The rules are the
    /// engine's raw values, which are the server's words already.
    public static func format(for record: MatchRecord) -> ThroAPI.UploadFormat {
        ThroAPI.UploadFormat(
            startingScore: record.startingScore,
            inRule: record.inRule.rawValue,
            outRule: record.outRule.rawValue,
            legsMode: record.legsMode == .bestOf ? "best_of" : "first_to",
            legsTarget: record.legsTarget,
            throwFirst: record.throwFirst == .home ? "home" : "away")
    }

    /// Which seat is the signed-in person's: the one whose name, typed at the oche, is the name on
    /// their profile — compared as a person would, case and surrounding spaces aside. Nil when neither
    /// is, because a match filed under the wrong player is worse than one not filed at all.
    public static func seat(of mine: String, home: String, away: String) -> String? {
        func same(_ a: String, _ b: String) -> Bool {
            a.trimmingCharacters(in: .whitespaces).caseInsensitiveCompare(b.trimmingCharacters(in: .whitespaces)) == .orderedSame
        }
        if same(home, mine) { return "home" }
        if same(away, mine) { return "away" }
        return nil
    }

    /// "a", "a and b", "a, b and c".
    static func sentence(_ parts: [String]) -> String {
        guard parts.count > 1 else { return parts.first ?? "" }
        return parts.dropLast().joined(separator: ", ") + " and " + parts[parts.count - 1]
    }
}
