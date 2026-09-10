import MapKit
import SwiftUI
import ThroDesign
import ThroNet
import ThroTokens

// The real leagues around here (PD-033), second pass.
//
// The first version was a map with pins nobody could touch over one long list. This one is a
// map you can use — tap a pin and the pub, its postcode, the sides that play there and a way to
// get there come up under it; tap a team in the list and the map goes to its pub — and a list
// folded by league, open on the league you came for. Distances appear when the phone knows where
// it is. Every row still says where it came from: the sources by name and date, and on each venue
// the basis it was connected to its team on. No person appears anywhere here, because none was read.

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
    public let id: UUID
    public let name: String
    public let postcode: String?
    public let locality: String?
    public let coordinate: CLLocationCoordinate2D
    public let teams: [String]
    public let inferred: Bool

    public static func == (a: PlottedVenue, b: PlottedVenue) -> Bool {
        a.id == b.id && a.name == b.name && a.teams == b.teams && a.inferred == b.inferred
            && a.coordinate.latitude == b.coordinate.latitude && a.coordinate.longitude == b.coordinate.longitude
    }
}

public enum LeaguesPlot {
    /// The venues with coordinates across the shown season of every league, one pin per venue.
    public static func plotted(_ leagues: [PublicLeague]) -> [PlottedVenue] {
        var byVenue: [UUID: (PublicLeague.Venue, [String])] = [:]
        var order: [UUID] = []
        for league in leagues {
            guard let season = league.shownSeason else { continue }
            for division in season.divisions {
                for team in division.teams {
                    guard let v = team.venue, v.latitude != nil, v.longitude != nil else { continue }
                    if byVenue[v.venueId] == nil { order.append(v.venueId); byVenue[v.venueId] = (v, []) }
                    if !byVenue[v.venueId]!.1.contains(team.name) { byVenue[v.venueId]!.1.append(team.name) }
                }
            }
        }
        return order.compactMap { id in
            guard let (v, teams) = byVenue[id], let lat = v.latitude, let lon = v.longitude else { return nil }
            return PlottedVenue(id: id, name: v.name, postcode: v.postcode, locality: v.locality,
                                coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lon),
                                teams: teams, inferred: v.basis?.hasPrefix("inferred") ?? false)
        }
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

    /// A region that holds every pin with a margin, or the Tees valley when there is nothing to hold.
    public static func region(_ pins: [PlottedVenue]) -> MKCoordinateRegion {
        guard let first = pins.first else {
            return MKCoordinateRegion(center: CLLocationCoordinate2D(latitude: 54.57, longitude: -1.25),
                                      span: MKCoordinateSpan(latitudeDelta: 0.3, longitudeDelta: 0.5))
        }
        var minLat = first.coordinate.latitude, maxLat = minLat, minLon = first.coordinate.longitude, maxLon = minLon
        for p in pins.dropFirst() {
            minLat = min(minLat, p.coordinate.latitude); maxLat = max(maxLat, p.coordinate.latitude)
            minLon = min(minLon, p.coordinate.longitude); maxLon = max(maxLon, p.coordinate.longitude)
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
        return "From \(read). Venues are matched from OpenStreetMap, most by the team's name; tell THRØ if one is wrong."
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
        return "You are \(NearbyLogic.miles(nearest)) from the nearest venue THRØ knows. Showing Teesside, where it starts."
    }

    static func day(_ iso: String) -> String {
        let parts = iso.split(separator: "-")
        guard parts.count == 3, let m = Int(parts[1]), let d = Int(parts[2]), (1...12).contains(m) else { return iso }
        let months = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
        return "\(d) \(months[m - 1]) \(parts[0])"
    }
}

@MainActor
public struct LeaguesScreen: View {
    @ObservedObject private var nearby: Nearby
    private let api: ThroAPI?
    private let focus: UUID?
    private let onBack: () -> Void
    @State private var camera: MapCameraPosition = .automatic
    @State private var selected: UUID?
    @State private var open: Set<UUID> = []
    @State private var framed = false
    /// Degrees of longitude per point at the current camera, from the last camera change; the
    /// clustering reads it. Starts at the Tees valley's framing width over a phone's width.
    @State private var degreesPerPoint: Double = 0.5 / 360

    public init(nearby: Nearby, api: ThroAPI?, focus: UUID? = nil, onBack: @escaping () -> Void) {
        self.nearby = nearby
        self.api = api
        self.focus = focus
        self.onBack = onBack
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            TopBar("Local leagues", eyebrow: "Around you", onBack: onBack)
            switch nearby.leagues {
            case .loading:
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            case .failed(let why):
                ErrorState(title: "The leagues could not be read", what: why,
                           safe: "Nothing on this phone is affected.",
                           todo: "Try again with a connection.",
                           actionLabel: "Try again", onAction: { Task { await nearby.load(api, force: true) } })
                    .padding(ThroSpacing.spaceScreenGutter)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            case .loaded(let leagues):
                if leagues.isEmpty {
                    EmptyState(title: "No leagues yet", message: "THRØ has not been given any leagues for this area.")
                        .padding(ThroSpacing.spaceScreenGutter)
                } else {
                    loaded(leagues)
                }
            }
        }
        .background(ThroColor.colorBackgroundPrimary.ignoresSafeArea())
        .task {
            if case .loading = nearby.leagues { await nearby.load(api) }
            if let focus { open.insert(focus) } else if let first = nearby.leagueList?.first { open.insert(first.id) }
        }
    }

    private func loaded(_ leagues: [PublicLeague]) -> some View {
        let pins = LeaguesPlot.plotted(leagues)
        let selectedPin = pins.first { $0.id == selected }
        return ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                map(pins)
                if let far = LeaguesPlot.farAway(place: nearby.place, pins: pins) {
                    Note(far, icon: .info)
                        .padding(.horizontal, ThroSpacing.spaceScreenGutter)
                        .padding(.top, ThroSpacing.spacing3)
                }
                if let pin = selectedPin {
                    venueCard(pin)
                        .padding(.horizontal, ThroSpacing.spaceScreenGutter)
                        .padding(.top, ThroSpacing.spacing4)
                        .transition(.opacity)
                }
                ForEach(leagues) { league in
                    leagueSection(league)
                }
                Note("Season dates are read from the season's name where the league publishes none. Nothing here is a person: players join a team in THRØ by choosing to, never by being listed.")
                    .padding(.horizontal, ThroSpacing.spaceScreenGutter)
                    .padding(.top, ThroSpacing.spaceSectionGap)
                    .padding(.bottom, ThroSpacing.spacing6)
            }
        }
        .animation(.easeOut(duration: ThroMotion.motionDurationFast), value: selected)
        .onAppear {
            guard !framed else { return }
            framed = true
            camera = .region(LeaguesPlot.region(pins))
        }
    }

    private func map(_ pins: [PlottedVenue]) -> some View {
        let clusters = LeaguesPlot.clustered(pins, degreesPerPoint: degreesPerPoint)
        return Map(position: $camera, selection: $selected) {
            ForEach(clusters) { cluster in
                if cluster.count == 1, let pin = cluster.pins.first {
                    Annotation(pin.name, coordinate: pin.coordinate, anchor: .center) {
                        // A pin is a small board: the lit stop when chosen, the field otherwise, the
                        // mark in chalk. Board tokens, so it is the same pin in both appearances.
                        ZStack {
                            Circle().fill(pin.id == selected ? ThroColor.colorBoardLit : ThroColor.colorBoardField)
                            Circle().strokeBorder(ThroColor.colorMarkOnBoard, lineWidth: pin.id == selected ? 3 : 2)
                            ThroMark().fill(ThroColor.colorMarkOnBoard).padding(pin.id == selected ? 7 : 8)
                        }
                        .frame(width: pin.id == selected ? 40 : 32, height: pin.id == selected ? 40 : 32)
                        .accessibilityLabel("\(pin.name), \(pin.teams.count == 1 ? "one team" : "\(pin.teams.count) teams")")
                    }
                    .tag(pin.id)
                } else {
                    // Several pubs within a thumb of each other: one marker, the count on it, and
                    // a tap that zooms in until they come apart.
                    Annotation("\(cluster.count) venues", coordinate: cluster.coordinate, anchor: .center) {
                        Button { zoom(into: cluster) } label: {
                            ZStack {
                                Circle().fill(ThroColor.colorBoardField)
                                Circle().strokeBorder(ThroColor.colorMarkOnBoard, lineWidth: 2)
                                Text("\(cluster.count)")
                                    .thro(ThroTypography.label.family(.sport).weight(.bold))
                                    .foregroundStyle(ThroColor.colorTextOnBoard)
                            }
                            .frame(width: 36, height: 36)
                            .throTapTarget()
                        }
                        .buttonStyle(ThroPressStyle(radius: 22))
                        .accessibilityLabel("\(cluster.count) venues close together; zooms in")
                    }
                }
            }
            if case .located = nearby.place { UserAnnotation() }
        }
        .mapStyle(.standard(pointsOfInterest: .excludingAll))
        .onMapCameraChange(frequency: .continuous) { context in
            degreesPerPoint = max(1e-7, context.region.span.longitudeDelta / 400)
        }
        .frame(height: 300)
        .accessibilityLabel("Map of \(pins.count) venues; tap a pin for its teams")
    }

    private func zoom(into cluster: LeaguesPlot.Cluster) {
        let lats = cluster.pins.map(\.coordinate.latitude), lons = cluster.pins.map(\.coordinate.longitude)
        let span = MKCoordinateSpan(latitudeDelta: max(0.004, ((lats.max() ?? 0) - (lats.min() ?? 0)) * 2.2),
                                    longitudeDelta: max(0.006, ((lons.max() ?? 0) - (lons.min() ?? 0)) * 2.2))
        withAnimation(.easeOut(duration: ThroMotion.motionDurationStandard)) {
            camera = .region(MKCoordinateRegion(center: cluster.coordinate, span: span))
        }
    }

    private func venueCard(_ pin: PlottedVenue) -> some View {
        ThroSlate(seed: UInt32(truncatingIfNeeded: pin.id.hashValue)) {
            VStack(alignment: .leading, spacing: ThroSpacing.spacing2) {
                HStack(alignment: .firstTextBaseline) {
                    Text(pin.name)
                        .thro(ThroTypography.heading2.family(.sport).weight(.bold).tracking(em: 0))
                        .foregroundStyle(ThroColor.colorTextOnBoard)
                    Spacer()
                    Button { selected = nil } label: {
                        Icon(.x, size: 18).foregroundStyle(ThroColor.colorTextOnBoardSecondary).throTapTarget()
                    }
                    .buttonStyle(ThroPressStyle(radius: 22, pressedFill: ThroColor.colorBoardSunken))
                    .accessibilityLabel("Close")
                }
                Text([pin.locality, pin.postcode, distanceLine(pin)].compactMap { $0 }.joined(separator: " · "))
                    .thro(ThroTypography.label)
                    .foregroundStyle(ThroColor.colorTextOnBoardSecondary)
                Text(pin.teams.joined(separator: " · "))
                    .thro(ThroTypography.bodyLarge.weight(.semibold))
                    .foregroundStyle(ThroColor.colorTextOnBoard)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, ThroSpacing.spacing1)
                if pin.inferred {
                    Text("Matched to the team by its name — tell THRØ if this is the wrong pub.")
                        .thro(ThroTypography.metadata)
                        .foregroundStyle(ThroColor.colorTextOnBoardSecondary)
                }
                Button { LeaguesScreen.directions(to: pin) } label: {
                    Text("DIRECTIONS")
                        .thro(ThroTypography.labelStrong.uppercase(true).tracking(em: 0.06))
                        .foregroundStyle(ThroColor.colorTextOnBoard)
                        .padding(.horizontal, ThroSpacing.spacing4)
                }
                .buttonStyle(ChalkKeyStyle(.lit, minHeight: ThroSpacing.touchTargetMinimum, seedAngle: 83))
                .fixedSize()
                .padding(.top, ThroSpacing.spacing2)
            }
            .padding(ThroSpacing.spacing5)
        }
    }

    private func distanceLine(_ pin: PlottedVenue) -> String? {
        guard case .located(let lat, let lon) = nearby.place else { return nil }
        return NearbyLogic.miles(NearbyLogic.distanceKm(fromLat: lat, lon: lon, toLat: pin.coordinate.latitude, lon: pin.coordinate.longitude))
    }

    static func directions(to pin: PlottedVenue) {
        let item = MKMapItem(placemark: MKPlacemark(coordinate: pin.coordinate))
        item.name = pin.name
        item.openInMaps(launchOptions: [MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeDriving])
    }

    private func leagueSection(_ league: PublicLeague) -> some View {
        let isOpen = open.contains(league.id)
        return VStack(alignment: .leading, spacing: 0) {
            Button {
                if isOpen { open.remove(league.id) } else { open.insert(league.id) }
            } label: {
                HStack(alignment: .firstTextBaseline, spacing: ThroSpacing.spacing3) {
                    VStack(alignment: .leading, spacing: ThroSpacing.spacing1) {
                        Text(league.name)
                            .thro(ThroTypography.heading3)
                            .foregroundStyle(ThroColor.colorTextPrimary)
                            .multilineTextAlignment(.leading)
                        Text(LeaguesScreen.seasonLine(league))
                            .thro(ThroTypography.label)
                            .foregroundStyle(ThroColor.colorTextSecondary)
                    }
                    Spacer()
                    Icon(.chevronRight, size: 18).rotationEffect(.degrees(isOpen ? -90 : 90)).foregroundStyle(ThroColor.colorTextSecondary)
                }
                .padding(.vertical, ThroSpacing.spacing4)
                .throRowTapTarget()
            }
            .buttonStyle(ThroPressStyle(radius: ThroSpacing.radiusCard, pressedFill: ThroColor.colorSurfaceSecondary, scales: false))
            .accessibilityAddTraits(.isHeader)
            .accessibilityHint(isOpen ? "Hides its teams" : "Shows its teams")
            if isOpen, let season = league.shownSeason {
                ForEach(season.divisions) { division in
                    if season.divisions.count > 1 {
                        Eyebrow(division.name).padding(.top, ThroSpacing.spacing2)
                    }
                    ThroDivider().padding(.top, ThroSpacing.spacing2)
                    ForEach(division.teams) { team in
                        teamRow(team)
                        ThroDivider()
                    }
                }
                Text(LeaguesPlot.provenance(league))
                    .thro(ThroTypography.metadata)
                    .foregroundStyle(ThroColor.colorTextSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, ThroSpacing.spacing3)
            }
        }
        .padding(.horizontal, ThroSpacing.spaceScreenGutter)
        .padding(.top, ThroSpacing.spacing3)
    }

    static func seasonLine(_ league: PublicLeague) -> String {
        let meta = LeaguesPlot.meta(league)
        guard let season = league.shownSeason else { return meta }
        let teams = season.divisions.flatMap(\.teams).count
        return "\(meta) · \(season.label)\(season.current ? " · this season" : "") · \(teams) teams"
    }

    private func teamRow(_ team: PublicLeague.Team) -> some View {
        Button {
            guard let v = team.venue, v.latitude != nil, v.longitude != nil else { return }
            selected = v.venueId
            if let lat = v.latitude, let lon = v.longitude {
                camera = .region(MKCoordinateRegion(center: CLLocationCoordinate2D(latitude: lat, longitude: lon),
                                                    span: MKCoordinateSpan(latitudeDelta: 0.012, longitudeDelta: 0.018)))
            }
        } label: {
            HStack(alignment: .firstTextBaseline) {
                Text(team.name)
                    .thro(ThroTypography.bodyLarge.weight(.semibold))
                    .foregroundStyle(ThroColor.colorTextPrimary)
                Spacer(minLength: ThroSpacing.spacing3)
                Text(LeaguesPlot.venueLine(team.venue))
                    .thro(ThroTypography.body)
                    .foregroundStyle(team.venue != nil && team.venue?.venueId == selected ? ThroColor.colorTextBrand : ThroColor.colorTextSecondary)
                    .multilineTextAlignment(.trailing)
            }
            .padding(.vertical, ThroSpacing.spacing3)
            .throRowTapTarget()
        }
        .buttonStyle(ThroPressStyle(radius: ThroSpacing.radiusCard, pressedFill: ThroColor.colorSurfaceSecondary, scales: false))
        .disabled(team.venue?.latitude == nil)
        .accessibilityElement(children: .combine)
        .accessibilityHint(team.venue?.latitude == nil ? "" : "Shows its venue on the map")
    }
}
