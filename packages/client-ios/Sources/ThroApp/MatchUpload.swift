import Foundation
import ThroJournal
import ThroNet

// Sending a match this phone scored to THRØ (PD-040).
//
// The phone sends the journal, not a summary: every visit and every retraction, in the order the
// device wrote them. A replayed total would be the app deciding what happened and discarding the
// record PD-004 exists to keep — and a board that showed a struck figure while the server never
// heard of it would be two accounts of one night.
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

    /// The kinds THRØ can receive today. Visits and the retractions that struck them.
    public static let sendable: Set<String> = ["visit", "retraction"]

    /// A match that ended short of its format cannot be sent yet, because the server has no event
    /// for it: uploading the visits alone would leave a record that says the match is still going.
    /// Better to refuse and say so than to store a lie about somebody's night.
    public static let endedEarly =
        "A match that was retired or abandoned cannot be sent yet. THRØ would have to record it as "
        + "still going, which is not what happened."

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
        if entries.contains(where: { $0.kind.rawValue == "retirement" || $0.kind.rawValue == "abandonment" }) {
            return .notYet(endedEarly)
        }
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
                    seat: entry.seat == .home ? "home" : "away",
                    visitTotal: entry.kind == .visit ? entry.visitTotal : nil,
                    correctsSeq: entry.correctsSeq,
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
        return .ready(rows)
    }

    /// What a person is told once it has gone. Counts, in words, and the one thing that matters
    /// about it: THRØ has one player's word for this and says so until the other confirms.
    public static func done(_ sent: ThroAPI.Sent) -> String {
        let parts = [
            sent.visits == 1 ? "1 visit" : "\(sent.visits) visits",
            sent.retractions > 0 ? (sent.retractions == 1 ? "1 undo" : "\(sent.retractions) undos") : nil,
        ].compactMap { $0 }
        let added = sent.visits == 0 && sent.retractions == 0
            ? "THRØ already had all of it."
            : "Sent " + parts.joined(separator: " and ") + "."
        return added + " It is recorded as your word for the match until the other player confirms it."
    }
}
