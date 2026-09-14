import Foundation
import ThroDesign
#if os(iOS)
import MetricKit
#endif

// What this phone can honestly say about how the app performed on it.
//
// **Why on-device at all.** Xcode Organizer is the usual answer and is frequently empty at this
// scale — it aggregates across an installed base THRØ does not yet have. MetricKit delivers to the
// app itself: metrics at most once a day, diagnostics immediately, carrying launch time to first
// draw, hang rate, hitch ratio, peak memory, terminations and call stack trees. It needs no backend,
// which is the same reason the Live Activity and the widgets need none.
//
// It also fits what this repository already does: measured rather than assumed. The opening's frame
// timing was argued from a judgement and a browser port; this is the mechanism that would have given
// it a number from a real phone.
//
// **Three rules, and the guard is that they are small enough to state.**
//
//  - **Nothing is sent anywhere.** Payloads are written to a folder on this phone and stay there
//    until the player shares them. There is no endpoint, no key and no upload — the same sentence
//    the rest of the app makes, and it stays true.
//  - **They are not in the journal.** ADR-006 measured the journal's durability configuration for
//    *darts*; telemetry does not belong in the file that holds what somebody threw, and a payload
//    that failed to write must never be able to affect a visit that did.
//  - **They are capped and they expire.** A folder that only grows is a folder that eventually
//    matters. The newest thirty are kept and the rest are deleted, so the worst case is bounded and
//    the player is told the number rather than left to guess.

/// The diagnostics this phone is holding.
public enum ThroDiagnostics {

    /// The player's answer, stored. **Default off**, and that is deliberate: this is the one thing
    /// in the app the player gains nothing from, so it is theirs to turn on rather than theirs to
    /// discover and turn off.
    public static let enabledKey = "thro.diagnostics"

    /// How many payloads are kept. MetricKit delivers a metric payload at most daily, so thirty is
    /// about a month — long enough to see a change after a release and short enough that the folder
    /// never becomes something anybody has to think about.
    public static let keep = 30

    /// What the folder holds, as a screen shows it.
    public struct Held: Equatable, Sendable {
        public let count: Int
        public let bytes: Int
        public let newest: Date?

        public init(count: Int, bytes: Int, newest: Date?) {
            self.count = count
            self.bytes = bytes
            self.newest = newest
        }
    }

    /// Where they live: beside the journal, inside the one directory PD-017's backup decision
    /// already covers.
    static func folder(in container: URL) throws -> URL {
        let dir = container.appendingPathComponent("diagnostics", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// Writes one payload and trims the folder back to the cap. Returns whether it landed.
    ///
    /// The filename carries the instant, so the folder sorts by time without anything having to
    /// read the files — which is what makes trimming cheap and what makes a corrupt payload
    /// harmless: it is a file with a date on it and nothing depends on its contents.
    @discardableResult
    static func store(_ data: Data, kind: String, at: Date, index: Int = 0, in folder: URL) -> Bool {
        // The index matters: MetricKit hands over an ARRAY, and every payload in one delivery
        // carries the same instant. Without it the second payload would overwrite the first and a
        // delivery of three would leave one file, silently.
        let name = "\(Self.stamp.string(from: at))-\(index)-\(kind).json"
        do {
            try data.write(to: folder.appendingPathComponent(name), options: .atomic)
        } catch {
            return false
        }
        trim(folder)
        return true
    }

    /// Keeps the newest `keep` and deletes the rest.
    static func trim(_ folder: URL, keep: Int = ThroDiagnostics.keep) {
        let files = payloads(in: folder)
        guard files.count > keep else { return }
        for url in files.dropFirst(keep) {
            try? FileManager.default.removeItem(at: url)
        }
    }

    /// The payload files, newest first. Sorted by **name**, which is the timestamp: a file's
    /// modification date can be changed by a restore, and the name cannot.
    static func payloads(in folder: URL) -> [URL] {
        let contents = (try? FileManager.default.contentsOfDirectory(at: folder,
                                                                     includingPropertiesForKeys: nil))
        return (contents ?? [])
            .filter { $0.pathExtension == "json" }
            .sorted { $0.lastPathComponent > $1.lastPathComponent }
    }

    /// What Settings shows: how many, how big, and when the last one arrived.
    static func held(in folder: URL) -> Held {
        let files = payloads(in: folder)
        let bytes = files.reduce(0) { total, url in
            total + ((try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
        }
        let newest = files.first.flatMap { stamp.date(from: String($0.lastPathComponent.prefix(stampLength))) }
        return Held(count: files.count, bytes: bytes, newest: newest)
    }

    /// Deletes every payload. The switch going off removes what was collected rather than only
    /// stopping new arrivals — the same rule Spotlight's switch follows, for the same reason: a
    /// switch that left the old data behind would be a switch that lies.
    static func forget(in folder: URL) {
        for url in payloads(in: folder) { try? FileManager.default.removeItem(at: url) }
    }

    /// The sentence Settings shows. Says the number, says where it is, and says it has gone nowhere.
    public static func sentence(_ held: Held) -> String {
        guard held.count > 0 else {
            return "Nothing collected yet. iOS delivers these at most once a day, and only while "
                 + "this is on."
        }
        let size = ByteCountFormatter.string(fromByteCount: Int64(held.bytes), countStyle: .file)
        let report = held.count == 1 ? "1 report" : "\(held.count) reports"
        let last = held.newest.map { ", the last on \(day.string(from: $0))" } ?? ""
        return "\(report), \(size)\(last), on this phone. Nothing has been sent anywhere — sharing "
             + "them is yours to do."
    }

    static let day: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .none
        return f
    }()

    /// The name a written payload gets. `yyyyMMdd-HHmmss-SSS` is twenty characters, sorts
    /// lexicographically in time order, and contains nothing a file system objects to.
    /// How many characters a stamp takes, computed rather than counted by hand: the format is
    /// nineteen characters, and a hand-written 20 read one character too many and parsed nothing.
    static let stampLength = stamp.string(from: Date(timeIntervalSince1970: 0)).count

    static let stamp: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyyMMdd-HHmmss-SSS"
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        return f
    }()
}

#if os(iOS)
/// The subscriber MetricKit hands payloads to.
///
/// **Not covered by `swift test`**: `MXMetricManager.shared` needs a real application. Everything
/// that decides what is written, what is kept and what Settings says is in `ThroDiagnostics` above,
/// where it is tested; what is left here is the handoff, and the app target is compiled by CI on
/// every push.
public final class ThroMetricSubscriber: NSObject, MXMetricManagerSubscriber {
    public static let shared = ThroMetricSubscriber()

    private var folder: URL?
    private var subscribed = false

    /// Starts collecting, if the player has asked for it. Idempotent: MetricKit keeps one
    /// registration per object and adding twice is harmless, but the flag makes the intent legible.
    public func start(in container: URL) {
        folder = try? ThroDiagnostics.folder(in: container)
        guard !subscribed else { return }
        MXMetricManager.shared.add(self)
        subscribed = true
    }

    public func stop() {
        guard subscribed else { return }
        MXMetricManager.shared.remove(self)
        subscribed = false
    }

    public func didReceive(_ payloads: [MXMetricPayload]) {
        write(payloads.map { $0.jsonRepresentation() }, kind: "metric")
    }

    public func didReceive(_ payloads: [MXDiagnosticPayload]) {
        write(payloads.map { $0.jsonRepresentation() }, kind: "diagnostic")
    }

    private func write(_ payloads: [Data], kind: String) {
        guard let folder else { return }
        let at = Date()
        for (index, payload) in payloads.enumerated() {
            ThroDiagnostics.store(payload, kind: kind, at: at, index: index, in: folder)
        }
    }
}
#endif
