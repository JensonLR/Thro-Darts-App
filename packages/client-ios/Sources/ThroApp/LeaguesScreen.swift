import MapKit
import SwiftUI
import ThroDesign
import ThroNet
import ThroTokens

// The real leagues around here (PD-033).
//
// What the founder asked for: the local leagues with their official teams, on a map. What the
// screen is careful about: every row on it was READ from a league's public pages and from
// OpenStreetMap, not entered by the people who run the league, and the screen says so — the
// sources by name, the date they were read, and on each venue the basis it was connected to its
// team on. "Blue Bell plays at The Blue Bell" is an inference from a name, and a good one, and a
// player can see that it is one. No person appears anywhere on this screen, because none was read.

/// What the screen knows, loaded once per visit. Held apart from the view so it can be tested
/// without a network: `LeaguesScreen.Model.plotted` is what the map draws.
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

    static func explain(_ error: Error) -> String {
        if let e = error as? APIError {
            switch e {
            case .unreachable: return "No connection to THRØ just now. The leagues are on the server, not on this phone yet."
            case .status(let code, _): return "The server answered \(code) instead of the leagues."
            default: break
            }
        }
        return "The leagues could not be read: \(error.localizedDescription)"
    }
}

/// One pin: a venue, and the teams that play there — a pub with three sides is one pin, not three.
public struct PlottedVenue: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let name: String
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
            return PlottedVenue(id: id, name: v.name, coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lon),
                                teams: teams, inferred: v.basis?.hasPrefix("inferred") ?? false)
        }
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

    static func day(_ iso: String) -> String {
        let parts = iso.split(separator: "-")
        guard parts.count == 3, let m = Int(parts[1]), let d = Int(parts[2]), (1...12).contains(m) else { return iso }
        let months = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
        return "\(d) \(months[m - 1]) \(parts[0])"
    }
}

@MainActor
public struct LeaguesScreen: View {
    @StateObject private var model: LeaguesModel
    private let api: ThroAPI?
    private let onBack: () -> Void

    public init(api: ThroAPI?, onBack: @escaping () -> Void, model: LeaguesModel? = nil) {
        self.api = api
        self.onBack = onBack
        // Made here and not as a default argument: a default argument is evaluated in the caller's
        // context, which is not the main actor's, and the model is.
        let made = model ?? LeaguesModel()
        self._model = StateObject(wrappedValue: made)
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            TopBar("Local leagues", eyebrow: "Around here", onBack: onBack)
            switch model.state {
            case .loading:
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            case .failed(let why):
                ErrorState(title: "The leagues could not be read", what: why,
                           safe: "Nothing on this phone is affected.",
                           todo: "Try again with a connection.",
                           actionLabel: "Try again", onAction: { Task { await model.load(api) } })
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
        .task { if case .loading = model.state { await model.load(api) } }
    }

    private func loaded(_ leagues: [PublicLeague]) -> some View {
        let pins = LeaguesPlot.plotted(leagues)
        return ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Map(initialPosition: .region(LeaguesPlot.region(pins))) {
                    ForEach(pins) { pin in
                        Marker(pin.name, systemImage: "target", coordinate: pin.coordinate)
                            .tint(ThroColor.throGreen)
                    }
                }
                .frame(height: 280)
                .accessibilityLabel("Map of \(pins.count) venues")
                ForEach(leagues) { league in
                    VStack(alignment: .leading, spacing: ThroSpacing.spacing1) {
                        Text(league.name)
                            .thro(ThroTypography.heading2)
                            .foregroundStyle(ThroColor.colorTextPrimary)
                        Text(LeaguesPlot.meta(league))
                            .thro(ThroTypography.body)
                            .foregroundStyle(ThroColor.colorTextSecondary)
                        if let season = league.shownSeason {
                            Text("\(season.label)\(season.current ? " · this season" : "")")
                                .thro(ThroTypography.label.uppercase(true).tracking(em: 0.06))
                                .foregroundStyle(ThroColor.colorTextSecondary)
                                .padding(.top, ThroSpacing.spacing1)
                            ForEach(season.divisions) { division in
                                if season.divisions.count > 1 {
                                    Eyebrow(division.name).padding(.top, ThroSpacing.spacing4)
                                }
                                ThroDivider().padding(.top, ThroSpacing.spacing2)
                                ForEach(division.teams) { team in
                                    HStack(alignment: .firstTextBaseline) {
                                        Text(team.name)
                                            .thro(ThroTypography.bodyLarge.weight(.semibold))
                                            .foregroundStyle(ThroColor.colorTextPrimary)
                                        Spacer(minLength: ThroSpacing.spacing3)
                                        Text(LeaguesPlot.venueLine(team.venue))
                                            .thro(ThroTypography.body)
                                            .foregroundStyle(ThroColor.colorTextSecondary)
                                            .multilineTextAlignment(.trailing)
                                    }
                                    .padding(.vertical, ThroSpacing.spacing3)
                                    .accessibilityElement(children: .combine)
                                    ThroDivider()
                                }
                            }
                        }
                        Text(LeaguesPlot.provenance(league))
                            .thro(ThroTypography.metadata)
                            .foregroundStyle(ThroColor.colorTextSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.top, ThroSpacing.spacing3)
                    }
                    .padding(.horizontal, ThroSpacing.spaceScreenGutter)
                    .padding(.top, ThroSpacing.spaceSectionGap)
                }
                Note("Season dates are read from the season's name where the league publishes none. Nothing here is a person: players join a team in THRØ by choosing to, never by being listed.")
                    .padding(.horizontal, ThroSpacing.spaceScreenGutter)
                    .padding(.top, ThroSpacing.spaceSectionGap)
                    .padding(.bottom, ThroSpacing.spacing6)
            }
        }
    }

}
