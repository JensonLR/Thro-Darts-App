import CoreLocation
import Foundation
import ThroNet

// What is around the player, worked out on the phone.
//
// The server publishes venues with coordinates and never learns where a phone is: distance is a
// subtraction done here, from a location the player grants while the app is in use and that is
// read once per visit to Discover. "Around here" was a lie for anyone outside Teesside until this
// existed — the app had three leagues and called them local to everybody. Now it measures, and
// when the nearest league is a long way off it says so in miles rather than pretending.

/// The arithmetic, kept apart from CoreLocation so it can be tested without a location.
public enum NearbyLogic {
    /// Great-circle distance in kilometres (haversine, mean Earth radius 6,371 km).
    public static func distanceKm(fromLat a: Double, lon b: Double, toLat c: Double, lon d: Double) -> Double {
        let r = 6371.0
        let dLat = (c - a) * .pi / 180, dLon = (d - b) * .pi / 180
        let h = sin(dLat / 2) * sin(dLat / 2) + cos(a * .pi / 180) * cos(c * .pi / 180) * sin(dLon / 2) * sin(dLon / 2)
        return 2 * r * asin(min(1, sqrt(h)))
    }

    /// A league's distance: to its nearest venue with coordinates in the shown season. Nil when
    /// no venue is placed.
    public static func distanceKm(to league: PublicLeague, fromLat lat: Double, lon: Double) -> Double? {
        var best: Double?
        guard let season = league.shownSeason else { return nil }
        for division in season.divisions {
            for team in division.teams {
                guard let v = team.venue, let vlat = v.latitude, let vlon = v.longitude else { continue }
                let d = distanceKm(fromLat: lat, lon: lon, toLat: vlat, lon: vlon)
                if best == nil || d < best! { best = d }
            }
        }
        return best
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
    public static func headline(place: Place, leagues: [PublicLeague]?) -> (title: String, detail: String) {
        guard let leagues else { return ("Finding the leagues", "Reading THRØ's list of leagues and venues.") }
        if leagues.isEmpty { return ("No leagues listed yet", "THRØ has not been given any leagues yet.") }
        let teams = leagues.compactMap(\.shownSeason).flatMap(\.divisions).flatMap(\.teams).count
        switch place {
        case .located(let lat, let lon):
            let ranked = sorted(leagues, fromLat: lat, lon: lon)
            let near = ranked.filter { ($0.km ?? .infinity) <= farKm }
            if !near.isEmpty {
                let count = near.count == 1 ? "1 league" : "\(near.count) leagues"
                return ("\(count) near you", "\(near.flatMap { $0.league.shownSeason?.divisions ?? [] }.flatMap(\.teams).count) teams within \(Int(farKm * 0.621371)) miles. Nearest: \(near[0].league.shortName ?? near[0].league.name), \(miles(near[0].km ?? 0)).")
            }
            if let nearest = ranked.first, let km = nearest.km {
                return ("Nothing near you yet", "The nearest league THRØ knows is \(nearest.league.shortName ?? nearest.league.name), \(miles(km)) away. THRØ starts on Teesside; tell it about your league and it spreads.")
            }
            return ("\(leagues.count) leagues listed", "\(teams) teams. Their venues are not placed yet, so distance cannot be shown.")
        case .denied:
            return ("\(leagues.count) leagues listed", "\(teams) teams, on Teesside so far. Location is off for THRØ; turn it on in Settings to see how far they are.")
        case .unknown, .asking:
            return ("\(leagues.count) leagues listed", "\(teams) teams, on Teesside so far. Use your location to see which are near you.")
        }
    }

    public enum Place: Equatable, Sendable {
        case unknown
        case asking
        case denied
        case located(lat: Double, lon: Double)
    }
}

/// The Discover tab's knowledge: the leagues and events from the server, and where the phone is if
/// the player has said it may know. Loaded once per visit; location read once per grant.
@MainActor
public final class Nearby: NSObject, ObservableObject, CLLocationManagerDelegate {
    public enum Loading<T: Equatable>: Equatable { case loading, loaded(T), failed(String) }

    @Published public private(set) var leagues: Loading<[PublicLeague]> = .loading
    @Published public private(set) var events: Loading<[PublicEvent]> = .loading
    @Published public private(set) var place: NearbyLogic.Place = .unknown

    private var manager: CLLocationManager?
    private let makeManager: () -> CLLocationManager

    public init(makeManager: @escaping () -> CLLocationManager = { CLLocationManager() }) {
        self.makeManager = makeManager
        super.init()
    }

    /// For a test or a preview: knowledge handed in rather than fetched.
    public init(leagues: Loading<[PublicLeague]>, events: Loading<[PublicEvent]> = .loaded([]), place: NearbyLogic.Place = .unknown) {
        self.makeManager = { CLLocationManager() }
        super.init()
        self.leagues = leagues; self.events = events; self.place = place
    }

    public var leagueList: [PublicLeague]? { if case .loaded(let l) = leagues { return l } else { return nil } }

    public func load(_ api: ThroAPI?, force: Bool = false) async {
        guard let api else { leagues = .failed("This build names no server."); events = .failed("This build names no server."); return }
        if force || leagues != .loading && leagues.isFailed { leagues = .loading }
        if case .loading = leagues {
            do { leagues = .loaded(try await api.leagues()) } catch { leagues = .failed(LeaguesModel.explain(error)) }
        }
        if force || events.isFailed { events = .loading }
        if case .loading = events {
            do { events = .loaded(try await api.events()) } catch { events = .failed(LeaguesModel.explain(error, what: "the tournaments")) }
        }
        if place == .unknown { adopt(status: (manager ?? makeManager()).authorizationStatus) }
    }

    /// The player asks. Permission is requested here and nowhere else, so it is never asked for
    /// on a screen that has not explained what it is for.
    public func useMyLocation() {
        let m = manager ?? makeManager()
        manager = m
        m.delegate = self
        switch m.authorizationStatus {
        case .notDetermined: place = .asking; m.requestWhenInUseAuthorization()
        case .denied, .restricted: place = .denied
        default: place = .asking; m.requestLocation()
        }
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
        Task { @MainActor in self.adopt(status: status) }
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
