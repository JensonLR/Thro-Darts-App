import CoreLocation
import Foundation
import ThroNet

// What is around the player, worked out on the phone.
//
// The server publishes venues with coordinates and never learns where a phone is: distance is a
// subtraction done here, from a location the player grants while the app is in use and that is
// read once per visit to Discover. "Around here" was a lie for anyone outside Teesside until this
// existed — the app had three leagues and called them local to everybody. Now it measures, and
// when the nearest league is a long way off it says so in miles rather than pretending. Since the
// directory import (V030) a league is measured from its own point when none of its pubs is placed,
// so the nearest league is rarely far — and the slate says plainly when its teams are not here yet.

/// The arithmetic, kept apart from CoreLocation so it can be tested without a location.
public enum NearbyLogic {
    /// Great-circle distance in kilometres (haversine, mean Earth radius 6,371 km).
    public static func distanceKm(fromLat a: Double, lon b: Double, toLat c: Double, lon d: Double) -> Double {
        let r = 6371.0
        let dLat = (c - a) * .pi / 180, dLon = (d - b) * .pi / 180
        let h = sin(dLat / 2) * sin(dLat / 2) + cos(a * .pi / 180) * cos(c * .pi / 180) * sin(dLon / 2) * sin(dLon / 2)
        return 2 * r * asin(min(1, sqrt(h)))
    }

    /// A league's distance: to its nearest venue with coordinates in the shown season, or, when no
    /// pub of its is placed yet, to the point the league itself gave (V030). Nil when it has neither.
    public static func distanceKm(to league: PublicLeague, fromLat lat: Double, lon: Double) -> Double? {
        var best: Double?
        for division in league.shownSeason?.divisions ?? [] {
            for team in division.teams {
                guard let v = team.venue, let vlat = v.latitude, let vlon = v.longitude else { continue }
                let d = distanceKm(fromLat: lat, lon: lon, toLat: vlat, lon: vlon)
                if best == nil || d < best! { best = d }
            }
        }
        if best == nil, let plat = league.latitude, let plon = league.longitude {
            best = distanceKm(fromLat: lat, lon: lon, toLat: plat, lon: plon)
        }
        return best
    }

    /// How many of these leagues have teams on THRØ. The directory places a league long before
    /// anyone has filled it in, and the slate says which is which rather than counting "0 teams".
    public static func filled(_ leagues: [PublicLeague]) -> Int {
        leagues.filter { ($0.shownSeason?.divisions.flatMap(\.teams).count ?? 0) > 0 }.count
    }

    /// What THRØ holds, counted apart (PD-126): run here, teams listed, and on the map only. Never one number for
    /// all three — "329 leagues" beside a THRØ mark reads as 329 leagues on THRØ.
    static func heldLine(_ leagues: [PublicLeague]) -> String {
        let run = leagues.filter { $0.held == .run }.count
        let listed = leagues.filter { $0.held == .teams }.count
        let placed = leagues.count - run - listed
        if run == 0 && listed == 0 {
            return placed == 1 ? "It is on the map from its own website; nothing of it is on THRØ yet."
                               : "All are on the map from their own websites; none is run on THRØ yet."
        }
        var parts: [String] = []
        if run > 0 { parts.append("\(run) \(run == 1 ? "is" : "are") run on THRØ.") }
        if listed > 0 { parts.append("\(listed)\(run > 0 ? " more" : "") \(listed == 1 ? "has its" : "have their") teams listed.") }
        if placed > 0 { parts.append(placed == 1 ? "The other is on the map from its own website." : "The other \(placed) are on the map from their own websites.") }
        return parts.joined(separator: " ")
    }

    /// Leagues nearest first; leagues with no placed venue last, in the order they came.
    public static func sorted(_ leagues: [PublicLeague], fromLat lat: Double, lon: Double) -> [(league: PublicLeague, km: Double?)] {
        let measured = leagues.map { ($0, distanceKm(to: $0, fromLat: lat, lon: lon)) }
        return measured.enumerated().sorted { a, b in
            switch (a.element.1, b.element.1) {
            case let (x?, y?): return x < y
            case (nil, nil): return a.offset < b.offset
            case (nil, _): return false
            case (_, nil): return true
            }
        }.map { (league: $0.element.0, km: $0.element.1) }
    }

    /// Beyond this, a league is not "near": nobody drives further than this for a Thursday night.
    public static let farKm: Double = 40

    /// Kilometres as the UK reads them: miles, to one place under ten and whole above.
    public static func miles(_ km: Double) -> String {
        let mi = km * 0.621371
        if mi < 0.1 { return "here" }
        if mi < 10 { return String(format: "%.1f mi", mi) }
        return "\(Int(mi.rounded())) mi"
    }

    /// What the slate says under AROUND YOU. It says how many leagues are near when some are, how far
    /// the nearest is when none are, and what to do when it cannot tell.
    /// `unreachable` is the difference between *not yet* and *not at all*, and without it there was
    /// none (PD-184): `leagueList` is nil while the read is in flight and nil again once it has
    /// failed, so the slate said **"Finding the leagues — Reading THRØ's list of leagues and
    /// venues"** for ever, directly above two sections that had already given up and were offering a
    /// retry. One screen, contradicting itself inside one scroll. It is the rule this file already
    /// states for `isLoading`, in the one place that had no way to obey it.
    public static func headline(place: Place, leagues: [PublicLeague]?,
                                trouble: String? = nil) -> (title: String, detail: String) {
        if leagues == nil, let trouble {
            return ("Nothing from THRØ yet", trouble)
        }
        guard let leagues else { return ("Finding the leagues", "Reading THRØ's list of leagues and venues.") }
        if leagues.isEmpty { return ("No leagues listed yet", "THRØ has not been given any leagues yet.") }
        let listed = leagues.count == 1 ? "1 league on the map" : "\(leagues.count) leagues on the map"
        switch place {
        case .located(let lat, let lon):
            let ranked = sorted(leagues, fromLat: lat, lon: lon)
            let near = ranked.filter { ($0.km ?? .infinity) <= farKm }
            if !near.isEmpty {
                let count = near.count == 1 ? "1 league" : "\(near.count) leagues"
                let teams = near.flatMap { $0.league.shownSeason?.divisions ?? [] }.flatMap(\.teams).count
                let within = Int(farKm * 0.621371)
                let line = teams > 0 ? "\(teams) teams within \(within) miles." : "Within \(within) miles; their teams are not on THRØ yet."
                return ("\(count) near you", "\(line) Nearest: \(near[0].league.shortName ?? near[0].league.name), \(miles(near[0].km ?? 0)).")
            }
            if let nearest = ranked.first, let km = nearest.km {
                return ("Nothing near you yet", "The nearest league THRØ knows is \(nearest.league.shortName ?? nearest.league.name), \(miles(km)) away. Start your own team here, or a league at thro.uk — a league is on the map the same day you make it public.")
            }
            return (listed, "None is placed yet, so distance cannot be shown.")
        case .denied:
            return (listed, "\(heldLine(leagues)) Location is off for THRØ; turn it on in Settings to see how far they are.")
        case .unknown, .asking:
            return (listed, "\(heldLine(leagues)) Use your location to see which are near you.")
        }
    }

    public enum Place: Equatable, Sendable {
        case unknown
        case asking
        case denied
        case located(lat: Double, lon: Double)
    }

    /// Whether the phone's location is being used **right now**, for the sign that says so (PD-086).
    ///
    /// The ICO's Children's code, Standard 10: geolocation off by default, and *"an obvious sign for
    /// children when location tracking is active"*. THRØ does not track — it asks once per grant and holds
    /// one fix — but the standard is about the child knowing, not about the technique, and a fix that is
    /// ordering the list in front of them is their location being used.
    public static func usingLocation(_ place: Place) -> Bool {
        switch place {
        case .asking, .located: return true
        case .unknown, .denied: return false
        }
    }

    /// The sign itself. Two states, because "finding you" and "using where you are" are different facts and
    /// a child reading one when the other is true has been told something untrue.
    public static func locationSign(_ place: Place) -> String? {
        switch place {
        case .asking: return "Finding where you are"
        case .located: return "Using your location to order this list"
        case .unknown, .denied: return nil
        }
    }
}

/// The Discover tab's knowledge: the leagues and events from the server, and where the phone is if
/// the player has said it may know. Loaded once per visit; location read once per grant.
@MainActor
public final class Nearby: NSObject, ObservableObject, CLLocationManagerDelegate {
    public enum Loading<T: Equatable>: Equatable {
        case loading, loaded(T), failed(String)
        /// True while the answer has not arrived. Read where a screen must say what it has, rather than
        /// what it would have (PD-148): a count of a list that has not been read is not a small count.
        public var isLoading: Bool { if case .loading = self { return true } else { return false } }
    }

    @Published public private(set) var leagues: Loading<[PublicLeague]> = .loading
    @Published public private(set) var events: Loading<[PublicEvent]> = .loading
    @Published public private(set) var place: NearbyLogic.Place = .unknown
    /// Why the server could not be read, in one sentence, when it could not. The sections under the
    /// slate carry what each of them has not got; this is the cause, and it is said once (PD-184).
    @Published public private(set) var trouble: String?

    private var manager: CLLocationManager?
    private let makeManager: () -> CLLocationManager
    private let defaults: UserDefaults

    /// Where "Stop" is remembered. The Discover tab makes a new `Nearby` on every visit and each one
    /// read iOS's permission afresh — which was still granted — so a player who pressed Stop found their
    /// location in use again the next time they looked, without asking. Stop now lasts until they press
    /// "Use my location" themselves.
    public static let stoppedKey = "thro.nearby.stopped"

    public init(makeManager: @escaping () -> CLLocationManager = { CLLocationManager() },
                defaults: UserDefaults = .standard) {
        self.makeManager = makeManager
        self.defaults = defaults
        super.init()
    }

    /// Whether the player has said to stop, and not since said to start.
    public var stoppedByPlayer: Bool { defaults.bool(forKey: Nearby.stoppedKey) }

    /// For a test or a preview: knowledge handed in rather than fetched.
    public init(leagues: Loading<[PublicLeague]>, events: Loading<[PublicEvent]> = .loaded([]), place: NearbyLogic.Place = .unknown) {
        self.makeManager = { CLLocationManager() }
        self.defaults = .standard
        super.init()
        self.leagues = leagues; self.events = events; self.place = place
    }

    public var leagueList: [PublicLeague]? { if case .loaded(let l) = leagues { return l } else { return nil } }

    public func load(_ api: ThroAPI?, force: Bool = false) async {
        guard let api else { leagues = .failed("This build names no server."); events = .failed("This build names no server."); return }
        if force || leagues != .loading && leagues.isFailed { leagues = .loading }
        if case .loading = leagues {
            do {
                leagues = .loaded(try await api.leagues())
                trouble = nil
            } catch {
                let t = LeaguesModel.trouble(error)
                leagues = .failed(t.missing)
                trouble = t.cause
            }
        }
        if force || events.isFailed { events = .loading }
        if case .loading = events {
            do {
                events = .loaded(try await api.events())
            } catch {
                let t = LeaguesModel.trouble(error, what: "the tournaments")
                events = .failed(t.missing)
                if trouble == nil { trouble = t.cause }
            }
        }
        if place == .unknown, !stoppedByPlayer { adopt(status: (manager ?? makeManager()).authorizationStatus) }
    }

    /// The player asks. Permission is requested here and nowhere else, so it is never asked for
    /// on a screen that has not explained what it is for.
    public func useMyLocation() {
        defaults.set(false, forKey: Nearby.stoppedKey)
        let m = manager ?? makeManager()
        manager = m
        m.delegate = self
        switch m.authorizationStatus {
        case .notDetermined: place = .asking; m.requestWhenInUseAuthorization()
        case .denied, .restricted: place = .denied
        default: place = .asking; m.requestLocation()
        }
    }

    /// Stops using the location and forgets the fix.
    ///
    /// **In the app, not only in Settings.** Standard 10 again: a child has to be able to turn it off where
    /// they turned it on. Sending them to iOS Settings to undo something they did on this screen is the
    /// kind of asymmetry the code exists to stop. No location was stored, so forgetting the fix is the whole
    /// of that — the list goes back to the order it had before. What IS kept is the choice, so the next visit
    /// to Discover does not quietly start again (`stoppedKey`).
    public func stopUsingLocation() {
        defaults.set(true, forKey: Nearby.stoppedKey)
        manager?.stopUpdatingLocation()
        place = .unknown
    }

    private func adopt(status: CLAuthorizationStatus) {
        switch status {
        case .authorizedWhenInUse, .authorizedAlways:
            let m = manager ?? makeManager(); manager = m; m.delegate = self
            place = .asking; m.requestLocation()
        case .denied, .restricted: place = .denied
        default: break
        }
    }

    nonisolated public func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor in if !self.stoppedByPlayer { self.adopt(status: status) } }
    }

    nonisolated public func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let last = locations.last else { return }
        let lat = last.coordinate.latitude, lon = last.coordinate.longitude
        Task { @MainActor in self.place = .located(lat: lat, lon: lon) }
    }

    nonisolated public func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in if case .asking = self.place { self.place = .unknown } }
    }
}

extension Nearby.Loading {
    var isFailed: Bool { if case .failed = self { return true } else { return false } }
}
