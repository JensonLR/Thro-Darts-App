import Foundation
import ThroNet

// What the wall has been told, and how often it asks (PD-079).
//
// **It never signs in.** Every route this reads — the leagues, a season's table, a season's fixtures — is
// public, by decision and not by accident: PD-054 and PD-056 say a league's published competition is public
// because it is published. So the wall is given a session store that cannot outlive the process, and a pub
// screen therefore has no credential to leak, nothing to sign out of, and no way to be pointed at somebody's
// private data by whoever picks up the remote.
//
// What it cannot show, for the same reason, is a **live leg**: `stream.match` is authenticated, and a public
// stream of a match is a safeguarding decision rather than a plumbing one — an under-18 fixture on a pub wall
// with names on it is exactly the thing that needs deciding before it is built, not after. A room that wants
// the live board today gets it the way it already works: the phone, by cable or AirPlay, drawing
// `ThroVenueBoard` on the same screen (PD-041).

/// A season, on a wall.
@MainActor
public final class ThroVenueWall: ObservableObject {
    @Published public private(set) var standings: LeagueStandings?
    @Published public private(set) var fixtures: LeagueFixtures?
    /// When the wall last heard anything at all. Everything about staleness is derived from it, and it is
    /// the wall's own clock — the same rule the wrist and the external display already follow.
    @Published public private(set) var heardAt: Date?
    /// Said on screen rather than logged. Nobody is looking at a console in a pub.
    @Published public private(set) var trouble: String?

    private let api: ThroAPI

    public init(api: ThroAPI) {
        self.api = api
    }

    /// How often the wall asks again.
    ///
    /// **Two minutes, and the relationship to `ThroVenueWords.heard`'s fifteen is the point** — the same
    /// shape as the live stream's ping against the proxy timeout (PLATFORM.md). The refresh must be well
    /// inside the window after which the screen calls itself out of date, or a single slow night would have
    /// a working wall accusing itself. Seven missed reads before it says so is a wide margin on purpose: a
    /// pub's Wi-Fi drops one request often and stays down rarely.
    public static let refresh: TimeInterval = 120

    /// Reads once. Separate from the loop so a test and a first paint can both use it.
    public func read(season: UUID) async {
        do {
            async let table = api.standings(season: season)
            async let list = api.fixtures(season: season)
            let (gotTable, gotList) = try await (table, list)
            standings = gotTable
            fixtures = gotList
            heardAt = Date()
            trouble = nil
        } catch {
            // **What is on screen stays on screen.** A failed read is not news that the league has no
            // table; the last one is still the best thing known, and `heardAt` not moving is what tells
            // the room how old it is. Blanking the wall on a dropped request would turn a flaky
            // connection into an empty screen.
            trouble = ThroVenueWords.trouble(error)
        }
    }

    /// Reads, then keeps reading, until cancelled.
    public func watch(season: UUID) async {
        while !Task.isCancelled {
            await read(season: season)
            try? await Task.sleep(nanoseconds: UInt64(Self.refresh * 1_000_000_000))
        }
    }
}

/// The leagues to choose from, for the one screen anybody in a venue actually operates.
@MainActor
public final class ThroVenueLeagues: ObservableObject {
    @Published public private(set) var leagues: [PublicLeague] = []
    @Published public private(set) var trouble: String?
    @Published public private(set) var read = false

    private let api: ThroAPI

    public init(api: ThroAPI) { self.api = api }

    public func load() async {
        do {
            leagues = try await api.leagues()
            trouble = nil
        } catch {
            trouble = ThroVenueWords.trouble(error)
        }
        read = true
    }
}

/// Which season this screen was pointed at, remembered across a power cut.
///
/// A pub's TV is unplugged at closing and switched on at opening by somebody who is not going to set it up
/// again. `UserDefaults` and not the keychain: this is a public identifier, not a secret, and the wall
/// deliberately holds nothing that is.
public struct ThroVenueChoice {
    static let key = "app.thro.venue.season"

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    public var season: UUID? {
        get { defaults.string(forKey: Self.key).flatMap(UUID.init(uuidString:)) }
        nonmutating set {
            guard let newValue else { return defaults.removeObject(forKey: Self.key) }
            defaults.set(newValue.uuidString, forKey: Self.key)
        }
    }
}

/// This screen's own identifier.
///
/// Every `ThroAPI` needs one, and a venue screen has no journal to take one from. It is written to
/// `UserDefaults` on first run so a wall that is switched off at closing is the same screen in the morning —
/// **and it is a random UUID and nothing else**: not the hardware's identifier, not the venue's, nothing a
/// pub television could be used to correlate with a person.
public enum ThroVenueDevice {
    static let key = "app.thro.venue.device"

    public static var id: UUID { remembered(in: .standard) }

    /// Not a second `id` overload: two members of one name, one public and one not, is exactly the
    /// shape that reads as "public" to everything except the compiler.
    static func remembered(in defaults: UserDefaults) -> UUID {
        if let existing = defaults.string(forKey: key).flatMap(UUID.init(uuidString:)) { return existing }
        let fresh = UUID()
        defaults.set(fresh.uuidString, forKey: key)
        return fresh
    }
}

extension ThroVenueWords {
    /// A failure, said to a room rather than to a log.
    ///
    /// Deliberately short and free of anything a person in a pub cannot act on: no status codes, no host
    /// names, no "decoding error". The two things worth distinguishing are *this screen cannot reach THRØ*
    /// and *THRØ answered something this screen could not use*, because the first is the landlord's router
    /// and the second is not.
    public static func trouble(_ error: Error) -> String {
        if let api = error as? APIError, case .status = api { return "THRØ answered, but not with this season" }
        return "Cannot reach THRØ"
    }
}
