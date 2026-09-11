import MapKit
import SwiftUI
import ThroDesign
import ThroNet
import ThroTokens

// The leagues, third pass (PD-046): a map of the leagues with a board over it.
//
// The second pass was a 300-point map over a folded list, and a team chosen from the list said only
// which pub it played at. A player asks a map of the leagues other things: which league is this team
// in, who else is in its division and how far are they, who plays at this pub, where is my team. So
// the map is the whole screen; every league with teams is drawn in a chalk of its own, a pub ringed
// in the chalk of each league that plays there; and a board rises from the bottom to say what was
// chosen. Choose a team and the map writes its name and its league over its pub and chalks a line to
// every pub in its division, nearest first on the board. Choose a pub and the board lists who plays
// there and in what. Choose a league and its pubs light while the rest sink. Nothing is faded (the
// board law), and nothing here is a person: teams and pubs, never who plays for them.

@MainActor
public struct LeaguesScreen: View {
    @ObservedObject private var nearby: Nearby
    @ObservedObject private var teams: TeamsModel
    private let api: ThroAPI?
    private let signedIn: Bool
    private let focus: UUID?
    private let onBack: () -> Void

    @State private var choice: LeagueChoice = .none
    @State private var query = ""
    @State private var expanded = false
    @State private var allRivals = false
    @State private var camera: MapCameraPosition = .automatic
    @State private var framed = false
    @State private var askedWhereIAm = false
    @State private var degreesPerPoint: Double = 0.5 / 360
    @State private var cardHeight: CGFloat = 180
    @State private var drawerHeight: CGFloat = 260
    @State private var screenHeight: CGFloat = 800
    @State private var sheet: Sheet?
    @FocusState private var searching: Bool
    @Environment(\.openURL) private var openURL

    enum Sheet: Identifiable, Hashable {
        case team(UUID)
        case join
        var id: Self { self }
    }

    /// What one load of the leagues is, drawn: the atlas, the pins, and the list they came from.
    private struct Board {
        let atlas: LeagueAtlas
        let pins: [PlottedVenue]
        let leagues: [PublicLeague]
    }

    public init(nearby: Nearby, teams: TeamsModel, api: ThroAPI?, signedIn: Bool = false, focus: UUID? = nil,
                onBack: @escaping () -> Void) {
        self.nearby = nearby
        self.teams = teams
        self.api = api
        self.signedIn = signedIn
        self.focus = focus
        self.onBack = onBack
    }

    public var body: some View {
        Group {
            switch nearby.leagues {
            case .failed(let why):
                paper {
                    ErrorState(title: "The leagues could not be read", what: why, safe: "Nothing on this phone is affected.",
                               todo: "Try again with a connection.", actionLabel: "Try again",
                               onAction: { Task { await nearby.load(api, force: true) } })
                }
            case .loaded(let leagues) where leagues.isEmpty:
                paper { EmptyState(title: "No leagues yet", message: "THRØ has not been given any leagues for this area.") }
            case .loading:
                board(Board(atlas: LeagueAtlas([]), pins: [], leagues: []))
            case .loaded(let leagues):
                board(Board(atlas: LeagueAtlas(leagues), pins: LeaguesPlot.plotted(leagues), leagues: leagues))
            }
        }
        .task { if case .loading = nearby.leagues { await nearby.load(api) } }
        .sheet(item: $sheet) { s in
            switch s {
            case .team(let id):
                TeamFrontScreen(teams: teams, teamId: id, api: api, onBack: { sheet = nil })
            case .join:
                JoinOrStartTeamScreen(teams: teams, api: api, onBack: { sheet = nil }) { made in sheet = .team(made.teamId) }
            }
        }
    }

    /// A failure or an empty directory is said on paper, as everywhere else; the board is for leagues.
    private func paper<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(spacing: 0) {
            TopBar("Local leagues", eyebrow: "Around you", onBack: onBack)
            content()
                .padding(ThroSpacing.spaceScreenGutter)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .background(ThroColor.colorBackgroundPrimary.ignoresSafeArea())
    }

    // MARK: - the board

    private func board(_ b: Board) -> some View {
        ZStack(alignment: .bottom) {
            map(b)
                .ignoresSafeArea(edges: .top)
                .ignoresSafeArea(.keyboard)
            VStack {
                HStack {
                    ThroCoinButton(.chevronLeft, label: "Back", action: onBack)
                    Spacer()
                    ThroCoinButton(.compass, label: isLocated ? "Around me" : "Use my location") { whereAmI(b) }
                }
                .padding(.horizontal, ThroSpacing.spaceScreenGutter)
                .padding(.top, ThroSpacing.spacing2)
                Spacer()
            }
            drawer(b)
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { drawerHeight = $0 }
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { screenHeight = $0 }
        .background(ThroColor.colorBackgroundPrimary)
        .animation(.easeOut(duration: ThroMotion.motionDurationStandard), value: choice)
        .animation(.easeOut(duration: ThroMotion.motionDurationFast), value: expanded)
        .onAppear { frameFirst(b) }
        .onChange(of: b.leagues.count) { frameFirst(b) }
        .onChange(of: nearby.place) {
            guard askedWhereIAm, case .located = nearby.place else { return }
            askedWhereIAm = false
            withAnimation(.easeInOut(duration: ThroMotion.motionDurationEmphasis)) {
                camera = .region(LeaguesPlot.region(b.pins, place: nearby.place))
            }
        }
        .task(id: choice) {
            allRivals = false
            if case .team(let id) = choice { await teams.show(id, api) }
        }
    }

    private var isLocated: Bool { if case .located = nearby.place { return true } else { return false } }

    // MARK: map

    private func map(_ b: Board) -> some View {
        let light = lighting(b.atlas)
        let bright = b.pins.filter { light.lit.contains($0.id) }
        let rest = b.pins.filter { !light.lit.contains($0.id) }
        let clusters = LeaguesPlot.clustered(rest, degreesPerPoint: degreesPerPoint)
        return Map(position: $camera) {
            web(b.atlas)
            ForEach(clusters) { cluster in
                if cluster.count == 1, let pin = cluster.pins.first {
                    marker(pin, b, light: light.sinkOthers ? .sunken : .field, size: light.sinkOthers ? 20 : 30, titled: false)
                } else {
                    Annotation("", coordinate: cluster.coordinate, anchor: .center) {
                        clusterMarker(cluster, chalks: Array(Set(cluster.pins.flatMap { b.atlas.chalks(at: $0.id) })).sorted(),
                                      sunk: light.sinkOthers)
                    }
                }
            }
            ForEach(bright) { pin in
                marker(pin, b, light: .lit, size: pin.id == light.chosen ? 44 : 34, titled: pin.id != light.chosen)
            }
            flag(b.atlas)
            if isLocated { UserAnnotation() }
        }
        .mapStyle(.standard(elevation: .flat, emphasis: .muted, pointsOfInterest: .excludingAll))
        .onMapCameraChange(frequency: .onEnd) { context in
            degreesPerPoint = max(1e-7, context.region.span.longitudeDelta / 400)
        }
        // The map frames what is chosen in the part of it the drawer leaves uncovered, and keeps its
        // logo and legal link above the drawer's corner, where Apple's terms ask for them to be seen.
        .safeAreaPadding(.bottom, drawerHeight)
        // And below the status bar and the two coins, so nothing framed lands under them.
        .safeAreaPadding(.top, 104)
        .accessibilityLabel("Map of \(b.pins.count) leagues and pubs")
    }

    /// Which pins are in the light, which one is chosen, and whether the rest sink.
    private func lighting(_ atlas: LeagueAtlas) -> (lit: Set<UUID>, chosen: UUID?, sinkOthers: Bool) {
        switch choice {
        case .none:
            return ([], nil, false)
        case .league(let id):
            let pubs = atlas.entries.filter { $0.leagueId == id && $0.placed }.compactMap { $0.venue?.venueId }
            return (Set(pubs).union([id]), nil, true)
        case .team(let id):
            guard let me = atlas.entry(id) else { return ([], nil, false) }
            let home = me.placed ? me.venue?.venueId : nil
            let pubs = atlas.rivals(of: id).compactMap { $0.entry.placed ? $0.entry.venue?.venueId : nil }
            return (Set(pubs + [home].compactMap { $0 }), home, true)
        case .pub(let id), .bare(let id):
            return ([id], id, false)
        }
    }

    private func marker(_ pin: PlottedVenue, _ b: Board, light: BoardPin.Light, size: CGFloat, titled: Bool) -> some MapContent {
        Annotation(titled ? pin.name : "", coordinate: pin.coordinate, anchor: .center) {
            Button { choose(pin: pin, b) } label: {
                BoardPin(pin.kind == .venue ? .pub : .league,
                         chalks: pin.kind == .venue ? b.atlas.chalks(at: pin.id) : [], light: light, size: size)
                    .throTapTarget()
            }
            .buttonStyle(ThroPressStyle(radius: 22))
            .accessibilityLabel(pin.kind == .venue
                                ? "\(pin.name): \(b.atlas.teams(at: pin.id).map { "\($0.team.name), \($0.league)" }.joined(separator: "; "))"
                                : "\(pin.name), a league with no teams on THRØ yet")
        }
    }

    private func clusterMarker(_ cluster: LeaguesPlot.Cluster, chalks: [Int], sunk: Bool) -> some View {
        Button { zoom(into: cluster) } label: {
            BoardPin(.count(cluster.count), chalks: chalks, light: sunk ? .sunken : .field, size: sunk ? 28 : 38)
                .throTapTarget()
        }
        .buttonStyle(ThroPressStyle(radius: 22))
        .accessibilityLabel("\(cluster.count) places close together; zooms in")
    }

    /// The chosen team's division, chalked from its pub to every other pub in it: a dark band under a
    /// dotted chalk line, so the chalk reads on the light map and the dark one alike.
    @MapContentBuilder private func web(_ atlas: LeagueAtlas) -> some MapContent {
        if case .team(let id) = choice, let me = atlas.entry(id), let home = Self.point(me.venue) {
            let ends = atlas.rivals(of: id).compactMap { r in Self.point(r.entry.venue).map { (id: r.id, at: $0) } }
            ForEach(ends, id: \.id) { end in
                MapPolyline(coordinates: [home, end.at])
                    .stroke(ThroColor.colorBoardSunken, style: StrokeStyle(lineWidth: 6, lineCap: .round))
            }
            ForEach(ends, id: \.id) { end in
                MapPolyline(coordinates: [home, end.at])
                    .stroke(LeagueChalk.color(me.chalk), style: StrokeStyle(lineWidth: 2.5, lineCap: .round, dash: [4, 6]))
            }
        }
    }

    /// Over the chosen team's pub, the map says which team and which league.
    @MapContentBuilder private func flag(_ atlas: LeagueAtlas) -> some MapContent {
        if case .team(let id) = choice, let me = atlas.entry(id), let at = Self.point(me.venue) {
            Annotation("", coordinate: at, anchor: .bottom) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(me.team.name)
                        .thro(ThroTypography.labelStrong.family(.sport).weight(.bold))
                        .foregroundStyle(ThroColor.colorTextOnBoard)
                    Text(LeagueBoardWords.teamEyebrow(me))
                        .thro(ThroTypography.metadata)
                        .foregroundStyle(LeagueChalk.color(me.chalk))
                }
                .lineLimit(1)
                .padding(.horizontal, ThroSpacing.spacing3)
                .padding(.vertical, ThroSpacing.spacing2)
                .background(ThroColor.colorBoardField)
                .overlay(ChalkBox(weight: 2, seedAngle: 41).fill(LeagueChalk.color(me.chalk)))
                .padding(.bottom, 30)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
            }
        }
    }

    // MARK: drawer

    private func drawer(_ b: Board) -> some View {
        ThroDrawer(seed: 23, onDrag: drag) {
            ScrollView {
                card(b)
                    .padding(.horizontal, ThroSpacing.spaceScreenGutter)
                    .padding(.bottom, ThroSpacing.spacing4)
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { cardHeight = $0 }
            }
            .scrollBounceBehavior(.basedOnSize)
            .scrollDismissesKeyboard(.interactively)
            .frame(height: min(cardHeight, screenHeight * (expanded || searching ? 0.64 : 0.6)))
        }
    }

    private func drag(_ direction: ThroDrawerDrag) {
        switch direction {
        case .up:
            if choice == .none { expanded = true }
        case .down:
            if searching { searching = false } else if expanded { expanded = false } else if choice != .none { choice = .none }
        }
    }

    @ViewBuilder private func card(_ b: Board) -> some View {
        switch choice {
        case .none:
            browse(b)
        case .league(let id):
            if let league = b.leagues.first(where: { $0.id == id }), let key = b.atlas.leagues.first(where: { $0.id == id }) {
                LeagueSummaryCard(league: league, chalk: key.chalk, divisions: b.atlas.divisions(of: id),
                                  distance: miles(to: league), onTeam: { choose(.team($0), b) }, onClose: close)
            } else { browse(b) }
        case .pub(let id):
            let here = b.atlas.teams(at: id)
            if let venue = here.first?.venue {
                LeaguePubCard(venue: venue, teams: here, distance: miles(to: venue), onTeam: { choose(.team($0), b) },
                              onDirections: { Self.directions(to: venue) }, onClose: close)
            } else { browse(b) }
        case .team(let id):
            if let e = b.atlas.entry(id) {
                LeagueTeamCard(entry: e, rivals: b.atlas.rivals(of: id), onThro: LeagueBoardWords.onThro(front(of: id)),
                               distance: miles(to: e.venue), allRivals: $allRivals, onRival: { choose(.team($0), b) },
                               onPage: { sheet = .team(id) },
                               onDirections: e.placed ? { if let v = e.venue { Self.directions(to: v) } } : nil,
                               onJoin: signedIn ? { sheet = .join } : nil,
                               // Only a team nobody runs, and only once its front has been read (PD-047).
                               onAdopt: (signedIn && front(of: id).map { $0.roster.isEmpty && $0.yourRole == nil } == true)
                                   ? { Task { await teams.adopt(id, api) } } : nil,
                               onClose: close)
            } else { browse(b) }
        case .bare(let id):
            if let league = b.leagues.first(where: { $0.id == id }) {
                BareLeagueCard(league: league, distance: miles(to: league),
                               onWebsite: league.website.flatMap(URL.init(string:)).map { url in { openURL(url) } },
                               onClose: close)
            } else { browse(b) }
        }
    }

    /// The team's front once it has loaded and is this team's — never a front for another team,
    /// which would say somebody plays for a side they do not.
    private func front(of teamId: UUID) -> TeamFront? {
        if case .loaded(let f) = teams.front(for: teamId), f.teamId == teamId { return f } else { return nil }
    }

    // MARK: browse

    private func browse(_ b: Board) -> some View {
        let typed = query.trimmingCharacters(in: .whitespacesAndNewlines).count >= 2
        return VStack(alignment: .leading, spacing: ThroSpacing.spacing3) {
            HStack(alignment: .center) {
                Eyebrow("Leagues on THRØ", color: ThroColor.colorTextOnBoardSecondary)
                Spacer()
                if !typed && !b.atlas.leagues.isEmpty {
                    Button { expanded.toggle() } label: {
                        HStack(spacing: ThroSpacing.spacing1) {
                            Text(expanded ? "Less" : "Every league").thro(ThroTypography.labelStrong)
                            Icon(.chevronRight, size: 14).rotationEffect(.degrees(expanded ? 90 : -90))
                        }
                        .foregroundStyle(ThroColor.colorTextOnBoardSecondary)
                        .throTapTarget(.trailing)
                    }
                    .buttonStyle(ThroPressStyle(radius: ThroSpacing.radiusStatus))
                }
            }
            searchField
            if typed {
                results(b)
            } else {
                chips(b)
                if case .loading = nearby.leagues {
                    HStack(spacing: ThroSpacing.spacing2) {
                        ProgressView().tint(ThroColor.colorMarkOnBoard)
                        Text("Reading the leagues").thro(ThroTypography.label).foregroundStyle(ThroColor.colorTextOnBoardSecondary)
                    }
                } else {
                    Text(LeagueBoardWords.census(b.atlas, bare: b.leagues.count - b.atlas.leagues.count))
                        .thro(ThroTypography.metadata).foregroundStyle(ThroColor.colorTextOnBoardSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    if let far = LeaguesPlot.farAway(place: nearby.place, pins: b.pins) {
                        Text(far).thro(ThroTypography.metadata).foregroundStyle(ThroColor.colorStatusWarningOnBoard)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                if expanded { details(b) }
            }
        }
    }

    private var searchField: some View {
        HStack(spacing: ThroSpacing.spacing2) {
            Icon(.search, size: 18).foregroundStyle(ThroColor.colorTextOnBoardSecondary)
            TextField("", text: $query, prompt: Text("Find your team, pub or league").foregroundStyle(ThroColor.colorTextOnBoardSecondary))
                .thro(ThroTypography.bodyLarge)
                .foregroundStyle(ThroColor.colorTextOnBoard)
                .tint(ThroColor.colorMarkOnBoard)
                .focused($searching)
                .submitLabel(.search)
                .autocorrectionDisabled()
            if !query.isEmpty {
                Button { query = "" } label: {
                    Icon(.x, size: 16).foregroundStyle(ThroColor.colorTextOnBoardSecondary).throTapTarget()
                }
                .buttonStyle(ThroPressStyle(radius: 22))
                .accessibilityLabel("Clear the search")
            }
        }
        .padding(.leading, ThroSpacing.spacing3)
        .padding(.trailing, query.isEmpty ? ThroSpacing.spacing3 : 0)
        .frame(minHeight: ThroSpacing.touchTargetMinimum)
        .background(ThroColor.colorBoardSunken)
        .overlay(ChalkBox(weight: 2, seedAngle: 29).fill(ThroColor.colorMarkOnBoard).allowsHitTesting(false))
    }

    /// One chalk key per league with teams: its chalk, its name, how many teams.
    private func chips(_ b: Board) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: ThroSpacing.spacing2) {
                ForEach(b.atlas.leagues) { l in
                    Button { choose(.league(l.id), b) } label: {
                        HStack(spacing: ThroSpacing.spacing2) {
                            ChalkDot(chalk: l.chalk)
                            Text(l.name).thro(ThroTypography.labelStrong).foregroundStyle(ThroColor.colorTextOnBoard).lineLimit(1)
                            Text("\(l.teams)").thro(ThroTypography.label.family(.sport)).foregroundStyle(ThroColor.colorTextOnBoardSecondary)
                        }
                        .padding(.horizontal, ThroSpacing.spacing3)
                        .frame(minHeight: ThroSpacing.touchTargetMinimum)
                        .background(ThroColor.colorBoardField)
                        .overlay(ChalkBox(weight: 2, seedAngle: Double(l.index * 37 + 11)).fill(LeagueChalk.color(l.chalk)))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(ThroPressStyle(radius: 0))
                    .accessibilityLabel("\(l.name), \(LeagueBoardWords.count(l.teams, "team"))")
                    .accessibilityHint("Shows the league on the map")
                }
            }
            .padding(.vertical, 2)
        }
        .scrollClipDisabled()
    }

    private func results(_ b: Board) -> some View {
        let hits = b.atlas.search(query, limit: 6)
        let named = LeagueAtlas.leaguesNamed(query, in: b.leagues)
        return VStack(alignment: .leading, spacing: 0) {
            ForEach(hits) { hit in
                switch hit {
                case .team(let e):
                    LeagueTeamRow(entry: e) { choose(.team(e.id), b) }
                case .venue(let v, let here):
                    LeaguePlaceRow(pin: BoardPin(.pub, chalks: b.atlas.chalks(at: v.venueId), size: 26), name: v.name,
                                   line: LeagueAtlas.pubLine(here)) {
                        choose(here.count == 1 ? .team(here[0].id) : .pub(v.venueId), b)
                    }
                }
            }
            ForEach(named) { league in
                let key = b.atlas.leagues.first { $0.id == league.id }
                LeaguePlaceRow(pin: BoardPin(key == nil ? .league : .pub, chalks: key.map { [$0.chalk] } ?? [], size: 26),
                               name: league.name,
                               line: key.map { "League · \(LeagueBoardWords.count($0.teams, "team"))" } ?? "League · no teams on THRØ yet") {
                    choose(key == nil ? .bare(league.id) : .league(league.id), b)
                }
            }
            if hits.isEmpty && named.isEmpty {
                Text("Nothing on the map goes by that name yet. If your team or league is missing, tell THRØ and it fills in.")
                    .thro(ThroTypography.body).foregroundStyle(ThroColor.colorTextOnBoardSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.vertical, ThroSpacing.spacing2)
            }
        }
    }

    private func details(_ b: Board) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(b.atlas.leagues) { key in
                if let league = b.leagues.first(where: { $0.id == key.id }) {
                    LeaguePlaceRow(pin: BoardPin(.pub, chalks: [key.chalk], size: 26), name: league.name,
                                   line: LeagueBoardWords.leagueMeta(league, teams: key.teams,
                                                                     divisions: league.shownSeason?.divisions.count ?? 0,
                                                                     distance: miles(to: league))) {
                        choose(.league(key.id), b)
                    }
                }
            }
            Text("Nothing here is a person: players join a team on THRØ by choosing to, never by being listed. Season dates are read from the season's name where the league publishes none.")
                .thro(ThroTypography.metadata).foregroundStyle(ThroColor.colorTextOnBoardSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, ThroSpacing.spacing3)
        }
    }

    // MARK: choosing and framing

    private func choose(pin: PlottedVenue, _ b: Board) {
        switch pin.kind {
        case .venue:
            let here = b.atlas.teams(at: pin.id)
            choose(here.count == 1 ? .team(here[0].id) : .pub(pin.id), b)
        case .league:
            choose(b.atlas.leagues.contains { $0.id == pin.id } ? .league(pin.id) : .bare(pin.id), b)
        }
    }

    private func choose(_ next: LeagueChoice, _ b: Board) {
        searching = false
        query = ""
        expanded = false
        choice = next
        frame(next, b)
    }

    private func close() { choice = .none }

    private func frame(_ c: LeagueChoice, _ b: Board) {
        let region: MKCoordinateRegion?
        switch c {
        case .none:
            region = nil
        case .league(let id):
            let points = b.atlas.entries.filter { $0.leagueId == id }.compactMap { Self.point($0.venue) }
            region = points.isEmpty ? b.pins.first { $0.id == id }.map { LeaguesPlot.region(around: $0) } : LeaguesPlot.region(covering: points)
        case .team(let id):
            let points = b.atlas.entry(id).map { me in ([me.venue] + b.atlas.rivals(of: id).map(\.entry.venue)).compactMap(Self.point) } ?? []
            region = points.isEmpty ? nil : LeaguesPlot.region(covering: points)
        case .pub(let id):
            region = b.pins.first { $0.id == id }.map { LeaguesPlot.region(around: $0) }
        case .bare(let id):
            region = b.pins.first { $0.id == id }.map {
                MKCoordinateRegion(center: $0.coordinate, span: MKCoordinateSpan(latitudeDelta: 0.35, longitudeDelta: 0.5))
            }
        }
        guard let region else { return }
        withAnimation(.easeInOut(duration: ThroMotion.motionDurationEmphasis)) { camera = .region(region) }
    }

    /// What the map opens on: the league Discover sent the player for; else around the player when
    /// the phone knows where it is; else the pubs of the leagues with teams — the part of the map
    /// with something to touch — rather than every league pin in the country.
    private func frameFirst(_ b: Board) {
        guard !framed, !b.leagues.isEmpty else { return }
        framed = true
        if let focus {
            choose(b.atlas.leagues.contains { $0.id == focus } ? .league(focus) : .bare(focus), b)
            return
        }
        let pubs = b.atlas.entries.compactMap { Self.point($0.venue) }
        camera = .region(isLocated || pubs.isEmpty ? LeaguesPlot.region(b.pins, place: nearby.place) : LeaguesPlot.region(covering: pubs))
    }

    private func whereAmI(_ b: Board) {
        if isLocated {
            withAnimation(.easeInOut(duration: ThroMotion.motionDurationEmphasis)) {
                camera = .region(LeaguesPlot.region(b.pins, place: nearby.place))
            }
        } else {
            askedWhereIAm = true
            nearby.useMyLocation()
        }
    }

    private func zoom(into cluster: LeaguesPlot.Cluster) {
        let lats = cluster.pins.map(\.coordinate.latitude), lons = cluster.pins.map(\.coordinate.longitude)
        let span = MKCoordinateSpan(latitudeDelta: max(0.004, ((lats.max() ?? 0) - (lats.min() ?? 0)) * 2.2),
                                    longitudeDelta: max(0.006, ((lons.max() ?? 0) - (lons.min() ?? 0)) * 2.2))
        withAnimation(.easeOut(duration: ThroMotion.motionDurationStandard)) {
            camera = .region(MKCoordinateRegion(center: cluster.coordinate, span: span))
        }
    }

    // MARK: places

    static func point(_ venue: PublicLeague.Venue?) -> CLLocationCoordinate2D? {
        guard let lat = venue?.latitude, let lon = venue?.longitude else { return nil }
        return CLLocationCoordinate2D(latitude: lat, longitude: lon)
    }

    private func miles(to venue: PublicLeague.Venue?) -> String? {
        guard case .located(let lat, let lon) = nearby.place, let p = Self.point(venue) else { return nil }
        return NearbyLogic.miles(NearbyLogic.distanceKm(fromLat: lat, lon: lon, toLat: p.latitude, lon: p.longitude))
    }

    private func miles(to league: PublicLeague) -> String? {
        guard case .located(let lat, let lon) = nearby.place, let la = league.latitude, let lo = league.longitude else { return nil }
        return NearbyLogic.miles(NearbyLogic.distanceKm(fromLat: lat, lon: lon, toLat: la, lon: lo))
    }

    static func directions(to venue: PublicLeague.Venue) {
        guard let at = point(venue) else { return }
        let item = MKMapItem(placemark: MKPlacemark(coordinate: at))
        item.name = venue.name
        item.openInMaps(launchOptions: [MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeDriving])
    }
}
