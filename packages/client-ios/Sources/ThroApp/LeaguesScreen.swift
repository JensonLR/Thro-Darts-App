import MapKit
import SwiftUI
import ThroDesign
import ThroNet
import ThroTokens

// The real leagues around here (PD-033): what the server lists, and where it goes on a map.
//
// The model and the plotting live here; the screen is the leagues board in LeagueBoard.swift
// (PD-046, the third pass). Every row still says where it came from: the sources by name and date,
// and on each venue the basis it was connected to its team on. No person appears anywhere here,
// because none was read.

/// What the screen knows, loaded once per visit. Kept for the failure copy the Discover tab shares.
@MainActor
public final class LeaguesModel: ObservableObject {
    public enum State: Equatable {
        case loading
        case loaded([PublicLeague])
        case failed(String)
    }
    @Published public private(set) var state: State = .loading

    public init(state: State = .loading) { self.state = state }

    public func load(_ api: ThroAPI?) async {
        guard let api else { state = .failed("This build names no server."); return }
        state = .loading
        do { state = .loaded(try await api.leagues()) } catch {
            state = .failed(LeaguesModel.explain(error))
        }
    }

    static func explain(_ error: Error, what: String = "the leagues") -> String {
        if let e = error as? APIError {
            switch e {
            case .unreachable: return "No connection to THRØ just now. \(what.prefix(1).uppercased() + what.dropFirst()) are on the server, not on this phone yet."
            case .status(let code, _): return "The server answered \(code) instead of \(what)."
            default: break
            }
        }
        return "\(what.prefix(1).uppercased() + what.dropFirst()) could not be read: \(error.localizedDescription)"
    }
}

/// One pin: a venue, and the teams that play there — a pub with three sides is one pin, not three.
public struct PlottedVenue: Identifiable, Equatable, Sendable {
    /// A pub with teams at it, or a league placed by its own point with no pub placed yet. Drawn
    /// differently, because a ring on a map that says "pub" where there is only "somewhere round
    /// here" would be the map inventing a venue.
    public enum Kind: Sendable { case venue, league }

    public let id: UUID
    public let name: String
    public let postcode: String?
    public let locality: String?
    public let coordinate: CLLocationCoordinate2D
    public let teams: [String]
    public let inferred: Bool
    public let kind: Kind
    /// The league's own pages, on a league pin. Nil on a pub.
    public let link: String?

    init(id: UUID, name: String, postcode: String?, locality: String?, coordinate: CLLocationCoordinate2D,
         teams: [String], inferred: Bool, kind: Kind = .venue, link: String? = nil) {
        self.id = id; self.name = name; self.postcode = postcode; self.locality = locality
        self.coordinate = coordinate; self.teams = teams; self.inferred = inferred; self.kind = kind; self.link = link
    }

    public static func == (a: PlottedVenue, b: PlottedVenue) -> Bool {
        a.id == b.id && a.name == b.name && a.teams == b.teams && a.inferred == b.inferred && a.kind == b.kind
            && a.coordinate.latitude == b.coordinate.latitude && a.coordinate.longitude == b.coordinate.longitude
    }
}

public enum LeaguesPlot {
    /// The venues with coordinates across the shown season of every league, one pin per venue; and
    /// then, for every league with none of its pubs placed, one pin at the league's own point.
    public static func plotted(_ leagues: [PublicLeague]) -> [PlottedVenue] {
        var byVenue: [UUID: (PublicLeague.Venue, [String])] = [:]
        var order: [UUID] = []
        var pubbed: Set<UUID> = []
        for league in leagues {
            guard let season = league.shownSeason else { continue }
            for division in season.divisions {
                for team in division.teams {
                    guard let v = team.venue, v.latitude != nil, v.longitude != nil else { continue }
                    pubbed.insert(league.id)
                    if byVenue[v.venueId] == nil { order.append(v.venueId); byVenue[v.venueId] = (v, []) }
                    if !byVenue[v.venueId]!.1.contains(team.name) { byVenue[v.venueId]!.1.append(team.name) }
                }
            }
        }
        let venues = order.compactMap { id -> PlottedVenue? in
            guard let (v, teams) = byVenue[id], let lat = v.latitude, let lon = v.longitude else { return nil }
            return PlottedVenue(id: id, name: v.name, postcode: v.postcode, locality: v.locality,
                                coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lon),
                                teams: teams, inferred: v.basis?.hasPrefix("inferred") ?? false)
        }
        let placed = leagues.compactMap { league -> PlottedVenue? in
            guard !pubbed.contains(league.id), let lat = league.latitude, let lon = league.longitude else { return nil }
            return PlottedVenue(id: league.id, name: league.shortName ?? league.name, postcode: nil, locality: league.locality,
                                coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lon),
                                teams: [], inferred: false, kind: .league, link: league.website)
        }
        return venues + placed
    }

    /// The line under the sections for the leagues that are pins and nothing more yet.
    public static func unfilledLine(_ n: Int) -> String {
        n == 1 ? "1 more league is on the map with no teams listed yet. Tap its pin."
               : "\(n) more leagues are on the map with no teams listed yet. Tap a pin to see one."
    }

    /// The leagues that get a section under the map: those with teams to list, nearest first when
    /// the phone knows where it is. The rest are on the map as pins, and the note says how many.
    public static func sections(_ leagues: [PublicLeague], place: NearbyLogic.Place) -> [PublicLeague] {
        let filled = leagues.filter { ($0.shownSeason?.divisions.flatMap(\.teams).count ?? 0) > 0 }
        if case .located(let lat, let lon) = place { return NearbyLogic.sorted(filled, fromLat: lat, lon: lon).map(\.league) }
        return filled
    }

    /// Pins that would sit on top of each other at the map's current scale, gathered into one
    /// marker with a count. Two pubs on one street are one marker until you zoom in.
    public struct Cluster: Identifiable, Equatable {
        public let id: UUID
        public let coordinate: CLLocationCoordinate2D
        public let pins: [PlottedVenue]
        public var count: Int { pins.count }
        public static func == (a: Cluster, b: Cluster) -> Bool { a.id == b.id && a.pins == b.pins }
    }

    /// Greedy clustering by screen distance: `degreesPerPoint` is how many degrees of longitude one
    /// point of the map spans at the current camera; two pins closer than `radius` points join.
    /// Deterministic for the same input order, so the markers do not shuffle between frames.
    public static func clustered(_ pins: [PlottedVenue], degreesPerPoint: Double, radius: Double = 22) -> [Cluster] {
        guard degreesPerPoint > 0 else { return pins.map { Cluster(id: $0.id, coordinate: $0.coordinate, pins: [$0]) } }
        var out: [(centre: CLLocationCoordinate2D, pins: [PlottedVenue])] = []
        for pin in pins {
            let cosLat = max(0.2, cos(pin.coordinate.latitude * .pi / 180))
            if let i = out.firstIndex(where: { c in
                let dx = (c.centre.longitude - pin.coordinate.longitude) * cosLat / degreesPerPoint
                let dy = (c.centre.latitude - pin.coordinate.latitude) / degreesPerPoint
                return (dx * dx + dy * dy).squareRoot() < radius
            }) {
                out[i].pins.append(pin)
                let n = Double(out[i].pins.count)
                out[i].centre = CLLocationCoordinate2D(latitude: out[i].pins.map(\.coordinate.latitude).reduce(0, +) / n,
                                                       longitude: out[i].pins.map(\.coordinate.longitude).reduce(0, +) / n)
            } else {
                out.append((pin.coordinate, [pin]))
            }
        }
        return out.map { Cluster(id: $0.pins[0].id, coordinate: $0.centre, pins: $0.pins) }
    }

    /// What the map opens on: when the phone knows where it is, the player and the five pins
    /// nearest them — enough to choose between, close enough to read; otherwise every pin.
    public static func region(_ pins: [PlottedVenue], place: NearbyLogic.Place) -> MKCoordinateRegion {
        guard case .located(let lat, let lon) = place, !pins.isEmpty else { return region(pins) }
        let squash = max(0.2, cos(lat * .pi / 180))
        let reach = pins.map { max(abs($0.coordinate.latitude - lat), abs($0.coordinate.longitude - lon) * squash) }.sorted()
        let half = max(0.08, reach[min(reach.count - 1, 4)] * 1.3)
        return MKCoordinateRegion(center: CLLocationCoordinate2D(latitude: lat, longitude: lon),
                                  span: MKCoordinateSpan(latitudeDelta: 2 * half, longitudeDelta: 2 * half / squash))
    }

    /// A region that holds every pin with a margin, or the Tees valley when there is nothing to hold.
    public static func region(_ pins: [PlottedVenue]) -> MKCoordinateRegion { region(covering: pins.map(\.coordinate)) }

    /// A region that holds every point with a margin, or the Tees valley when there is nothing to hold.
    public static func region(covering points: [CLLocationCoordinate2D]) -> MKCoordinateRegion {
        guard let first = points.first else {
            return MKCoordinateRegion(center: CLLocationCoordinate2D(latitude: 54.57, longitude: -1.25),
                                      span: MKCoordinateSpan(latitudeDelta: 0.3, longitudeDelta: 0.5))
        }
        var minLat = first.latitude, maxLat = minLat, minLon = first.longitude, maxLon = minLon
        for p in points.dropFirst() {
            minLat = min(minLat, p.latitude); maxLat = max(maxLat, p.latitude)
            minLon = min(minLon, p.longitude); maxLon = max(maxLon, p.longitude)
        }
        return MKCoordinateRegion(center: CLLocationCoordinate2D(latitude: (minLat + maxLat) / 2, longitude: (minLon + maxLon) / 2),
                                  span: MKCoordinateSpan(latitudeDelta: max(0.02, (maxLat - minLat) * 1.4),
                                                         longitudeDelta: max(0.02, (maxLon - minLon) * 1.4)))
    }

    /// A close look at one pin.
    public static func region(around pin: PlottedVenue) -> MKCoordinateRegion {
        MKCoordinateRegion(center: pin.coordinate, span: MKCoordinateSpan(latitudeDelta: 0.012, longitudeDelta: 0.018))
    }

    /// The line under a league's name: its night and where it is.
    public static func meta(_ league: PublicLeague) -> String {
        [league.playsOn.map { "\($0) nights" }, league.locality].compactMap { $0 }.joined(separator: " · ")
    }

    /// Where the rows came from, said once per league in words a player can read.
    public static func provenance(_ league: PublicLeague) -> String {
        let read = league.sources.map { "\($0.source) (read \(LeaguesPlot.day($0.retrievedOn)))" }.joined(separator: ", ")
        return "From \(read). Venues are matched from OpenStreetMap (© OpenStreetMap contributors), most by the team's name; tell THRØ if one is wrong."
    }

    /// What a team's venue cell says: the pub and its postcode, with a mark when the pub was
    /// inferred rather than stated; or that no venue is known.
    public static func venueLine(_ venue: PublicLeague.Venue?) -> String {
        guard let venue else { return "venue not known" }
        let postcode = venue.postcode.map { " · \($0)" } ?? ""
        let inferred = (venue.basis?.hasPrefix("inferred") ?? false) ? " (by name)" : ""
        return venue.name + postcode + inferred
    }

    /// The banner over the map when the player is a long way from every pin, or nil when they are
    /// among them (or unlocated).
    public static func farAway(place: NearbyLogic.Place, pins: [PlottedVenue]) -> String? {
        guard case .located(let lat, let lon) = place, !pins.isEmpty else { return nil }
        let nearest = pins.map { NearbyLogic.distanceKm(fromLat: lat, lon: lon, toLat: $0.coordinate.latitude, lon: $0.coordinate.longitude) }.min() ?? 0
        guard nearest > NearbyLogic.farKm else { return nil }
        return "You are \(NearbyLogic.miles(nearest)) from the nearest league THRØ has listed. Tell THRØ about yours and it spreads."
    }

    static func day(_ iso: String) -> String {
        let parts = iso.split(separator: "-")
        guard parts.count == 3, let m = Int(parts[1]), let d = Int(parts[2]), (1...12).contains(m) else { return iso }
        let months = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
        return "\(d) \(months[m - 1]) \(parts[0])"
    }
}
