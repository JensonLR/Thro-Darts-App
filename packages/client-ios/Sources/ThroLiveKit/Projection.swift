import Foundation

// What a widget is allowed to know, and where it is kept.
//
// **The journal does not move.** ADR-006 measured `Application Support/THRO/journal.sqlite` under a
// specific durability configuration, and moving a measured file into a shared container to make a
// widget convenient would put the app's one durable record somewhere the measurement no longer
// describes — for a surface whose whole job is to draw four numbers. So the journal stays, and a
// **small read-only projection of it** is written into the App Group container beside it.
//
// Three properties follow from "projection", and each of them is the point rather than a caveat:
//
//  - **It is regenerable.** Nothing here is a source of truth. Delete the file and the app rewrites
//    it from the journal on its next look; a widget that reads a missing file draws its empty state.
//    No migration, no repair, no second thing that can be corrupt in a way that matters.
//  - **It is written by the app and never by the extension.** A widget process that could write
//    would be a second writer to a file the app assumes it owns, and it has nothing to say anyway.
//  - **It carries no figure that cannot carry its sample.** A widget is small. An average with no
//    room for the number of darts behind it is a claim, which is the thing this product does not
//    ship — so what goes here is what a scoreboard shows and what can be counted.
//
// **And it says how old it is.** The system refreshes a widget on its own schedule, not the app's:
// what is on the Home Screen can be minutes or hours behind the phone it is on, and it looks
// exactly as current as something written a second ago. Same rule as the Lock Screen and the wall,
// same mechanism — a timestamp and a freshness window, so the surface can say *may be out of date*
// instead of asserting a score.

/// The next thing in somebody's diary, as a widget shows it.
public struct ThroProjectedFixture: Codable, Equatable, Sendable {
    public let title: String
    public let at: Date
    public let venue: String

    public init(title: String, at: Date, venue: String) {
        self.title = title
        self.at = at
        self.venue = venue
    }
}

/// Everything the widgets on this phone are allowed to draw.
public struct ThroProjection: Codable, Equatable, Sendable {
    /// The format this file is written in. A widget from a newer build reading an older file — or
    /// the other way round after an app update the system has not yet reloaded the extension for —
    /// must refuse rather than decode half of it: a scoreboard assembled from a file it does not
    /// understand is the one outcome worse than an empty widget.
    public static let format = 1

    public let version: Int
    /// When the app last wrote this. Everything about staleness is derived from it.
    public let writtenAt: Date
    /// The leg being scored on this phone, if one is.
    public let live: ThroLiveState?
    /// The format that leg is being played under — "501 · Best of 5 · Double out".
    public let liveFormat: String
    /// The next fixture this phone knows about, if there is one ahead.
    public let nextFixture: ThroProjectedFixture?
    /// Matches on this phone, all of them. **A count, not an average**: a count carries its own
    /// sample, which is the only kind of figure that fits on a surface with no room for a basis.
    public let matches: Int
    /// Legs recorded in the last seven days, on the same reasoning.
    public let legsThisWeek: Int

    /// **`writtenAt` is stamped through the format it will be written in.**
    ///
    /// A `Date` carries sub-millisecond precision and the ISO-8601 string this file is written in
    /// does not, so a projection built from `Date()` did not read back as itself: what the file said
    /// and what the app believed it had said were different instants. Harmless here — nothing
    /// compares them — right up until something does, which is exactly how the journal's own
    /// timestamp bug reached a player. The same fix, for the same reason: the instant this claims to
    /// have been written is the instant the file will actually say.
    public init(version: Int = ThroProjection.format,
                writtenAt: Date,
                live: ThroLiveState? = nil,
                liveFormat: String = "",
                nextFixture: ThroProjectedFixture? = nil,
                matches: Int = 0,
                legsThisWeek: Int = 0) {
        self.version = version
        self.writtenAt = ThroProjection.stamped(writtenAt)
        self.live = live
        self.liveFormat = liveFormat
        self.nextFixture = nextFixture
        self.matches = matches
        self.legsThisWeek = legsThisWeek
    }

    /// The instant, as the file can express it. Anything finer is lost on the way to disk, so it is
    /// lost here too rather than being carried in memory as a difference nobody can see.
    public static func stamped(_ date: Date) -> Date {
        let iso = ISO8601DateFormatter()
        return iso.date(from: iso.string(from: date)) ?? date
    }

    /// How long a widget's contents may be presented as current.
    ///
    /// Longer than the Live Activity's 150 seconds, and deliberately: a Live Activity is refreshed
    /// by the app on every visit while the app is on screen, and a widget is refreshed by the system
    /// when the system feels like it. Fifteen minutes is the window inside which WidgetKit will
    /// normally have come back at least once; past it, the surface says so rather than asserting a
    /// score nobody has checked.
    public static let freshness: TimeInterval = 15 * 60

    public func isStale(now: Date = Date()) -> Bool {
        now.timeIntervalSince(writtenAt) > ThroProjection.freshness
    }

    /// Whether this file is one this build can read at all.
    public var isReadable: Bool { version == ThroProjection.format }
}

/// The App Group container, and the one file in it.
///
/// **`containerURL` returns nil when the entitlement is absent**, which is the normal state of a
/// package test, a build without the App Groups capability, and a target that has no business
/// reading this. Every path here treats that as *there is nothing to say* rather than as an error:
/// the app skips the write, the widget draws its empty state, and nothing anywhere throws.
public enum ThroProjectionStore {
    /// The group both the app and its extension are in. It appears in two entitlements files and
    /// here, and nowhere else; `tools/check_app_group.py` holds the three in agreement, because a
    /// typo in one of them produces a widget that is permanently empty and no error anywhere.
    public static let groupId = "group.app.thro.darts"

    public static let filename = "projection.json"

    /// Where the file goes, or nil when this process has no App Group.
    public static func url(groupId: String = ThroProjectionStore.groupId) -> URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: groupId)?
            .appendingPathComponent(filename)
    }

    /// Writes it, atomically. Returns whether it landed — a caller may want to know, and silently
    /// swallowing the answer is how a widget stays empty for a week without anybody finding out.
    @discardableResult
    public static func write(_ projection: ThroProjection, to url: URL? = ThroProjectionStore.url()) -> Bool {
        guard let url else { return false }
        do {
            let data = try encoder.encode(projection)
            try data.write(to: url, options: .atomic)
            return true
        } catch {
            return false
        }
    }

    /// Reads it, or nil when there is nothing to read, when the file is unreadable, or when it was
    /// **written in a format this build does not understand**. Nil in every one of those cases on
    /// purpose: the widget's empty state is honest, and a scoreboard assembled from half a file is
    /// not.
    public static func read(from url: URL? = ThroProjectionStore.url()) -> ThroProjection? {
        guard let url, let data = try? Data(contentsOf: url),
              let projection = try? decoder.decode(ThroProjection.self, from: data),
              projection.isReadable else { return nil }
        return projection
    }

    /// Removes it. Called when the app has nothing to project — the alternative is a widget still
    /// showing a match that was deleted.
    public static func clear(at url: URL? = ThroProjectionStore.url()) {
        guard let url else { return }
        try? FileManager.default.removeItem(at: url)
    }

    static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return e
    }()

    static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()
}
