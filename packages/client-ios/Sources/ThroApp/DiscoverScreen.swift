import SwiftUI
import ThroDesign
import ThroNet
import ThroTokens

// The Discover tab, rethought (PD-033, the founder's second pass).
//
// It opens on a slate that says what is around the player and how it knows — measured from the
// phone's location when the player has granted it, and honest in miles when the nearest league is
// on the other side of the country. Under it: the leagues nearest first, the open tournaments
// THRØ has been told about, and the player's own teams. The old screen was a list of the player's
// own clubs with a note that nothing here had left the phone; that is still true of their clubs,
// and it is now one section of a screen about darts around here rather than the whole of it.

/// What a section of Discover shows when it could not be read.
///
/// **There was one cause and three presentations.** With no connection to THRØ the screen showed a red
/// Snackbar with a Try again button for the leagues, a line of grey prose for the tournaments, and
/// another line of grey prose for your teams — three different answers to one question, on one screen,
/// at one moment, and only one of them offering the tap that fixes all three. A player is left to
/// decide whether the red one is worse than the grey ones. It is not. It is the same thing.
///
/// One shape now, and a quiet one. Three red alarms for a phone that is off the network is shouting
/// about something the player did not do and can fix with one tap, so the shape is the one the "not
/// asked yet" state already used here: the reason, and the control that tries again.
struct DiscoverTrouble: View {
    let why: String
    let label: String
    let onRetry: () -> Void

    init(_ why: String, label: String = DiscoverScreen.tryAgain, onRetry: @escaping () -> Void) {
        self.why = why
        self.label = label
        self.onRetry = onRetry
    }

    var body: some View {
        VStack(alignment: .leading, spacing: ThroSpacing.spacing2) {
            Text(why)
                .thro(ThroTypography.body)
                .foregroundStyle(ThroColor.colorTextSecondary)
                .fixedSize(horizontal: false, vertical: true)
            ThroTextButton(label, action: onRetry)
        }
        .padding(.vertical, ThroSpacing.spacing3)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

public struct DiscoverScreen: View {
    @ObservedObject private var nearby: Nearby
    @ObservedObject private var teams: TeamsModel
    private let signedIn: Bool
    private let onServerTeam: (UUID) -> Void
    private let onJoinOrStart: () -> Void
    private let clubs: [Club]
    private let badge: (Club) -> Image?
    private let onOpen: (Club) -> Void
    private let onCreate: () -> Void
    private let onLeague: (UUID?) -> Void
    private let onEvent: (UUID) -> Void
    private let onUseLocation: () -> Void
    private let onStopLocation: () -> Void
    private let onRetry: () -> Void

    public init(nearby: Nearby, teams: TeamsModel, signedIn: Bool = false, clubs: [Club],
                badge: @escaping (Club) -> Image? = { _ in nil },
                onOpen: @escaping (Club) -> Void = { _ in }, onCreate: @escaping () -> Void = {},
                onLeague: @escaping (UUID?) -> Void = { _ in }, onEvent: @escaping (UUID) -> Void = { _ in },
                onServerTeam: @escaping (UUID) -> Void = { _ in }, onJoinOrStart: @escaping () -> Void = {},
                onUseLocation: @escaping () -> Void = {},
                onStopLocation: @escaping () -> Void = {},
                onRetry: @escaping () -> Void = {}) {
        self.nearby = nearby
        self.teams = teams
        self.signedIn = signedIn
        self.onServerTeam = onServerTeam
        self.onJoinOrStart = onJoinOrStart
        self.clubs = clubs
        self.badge = badge
        self.onOpen = onOpen
        self.onCreate = onCreate
        self.onLeague = onLeague
        self.onEvent = onEvent
        self.onUseLocation = onUseLocation
        self.onStopLocation = onStopLocation
        self.onRetry = onRetry
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Large, as the approved export draws it (`screens-discover.jsx`: `large: true`) and as Play and Live already
            // are (PD-092). It went compact in 4d3b225 with no decision recorded; turned sideways the large bar now folds to
            // this same compact row, so the height it costs is only spent on an upright phone.
            TopBar("Discover", actions: signedIn ? [TopBar.Action(icon: .plus, label: "Join or start a team", action: onJoinOrStart)] : [],
                   large: true)
            // Discover is two things, and says so on a screen with room for two (PD-062): what is out
            // there — the leagues near you and the tournaments taking entries — and what is yours. On a
            // phone they run one after the other as they always have; on a tablet the second half stops
            // being a scroll away from the first, and the glass beside a 560-point column stops being
            // empty. The width comes from out here because a geometry reader inside a scroll view takes
            // all the height it can reach.
            GeometryReader { proxy in
                ScrollView {
                    ThroBeside(width: proxy.size.width) {
                        VStack(alignment: .leading, spacing: 0) {
                            slate.padding(.top, ThroSpacing.spacing4)
                            leagues
                            tournaments
                        }
                    } aside: {
                        VStack(alignment: .leading, spacing: 0) { yours }
                    }
                    .padding(.horizontal, ThroSpacing.spaceScreenGutter)
                    .padding(.bottom, ThroSpacing.spacing6)
                }
            }
        }
        .throEntrance(0)
        .background(ThroColor.colorBackgroundPrimary.ignoresSafeArea())
    }

    // MARK: the slate

    private var slate: some View {
        let words = NearbyLogic.headline(place: nearby.place, leagues: nearby.leagueList,
                                         trouble: nearby.trouble)
        return ThroSlate(seed: 21) {
            VStack(alignment: .leading, spacing: ThroSpacing.spacing3) {
                HStack {
                    Eyebrow("Around you", color: ThroColor.colorTextOnBoardSecondary)
                    Spacer()
                    ThroMark().fill(ThroColor.colorMarkOnBoard).frame(width: 22, height: 22).accessibilityHidden(true)
                }
                Text(words.title)
                    .thro(ThroTypography.heading1.family(.sport).weight(.bold).tracking(em: 0))
                    .foregroundStyle(ThroColor.colorTextOnBoard)
                    .fixedSize(horizontal: false, vertical: true)
                Text(words.detail)
                    .thro(ThroTypography.body)
                    .foregroundStyle(ThroColor.colorTextOnBoardSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                // The sign, whenever the phone's location is in use, with the way to stop beside it. Never
                // a passive line: a child who can see that it is on and cannot turn it off here has been
                // told, not given a choice (Children's code Standard 10, PD-086).
                if let sign = NearbyLogic.locationSign(nearby.place) {
                    HStack(spacing: ThroSpacing.spacing2) {
                        Icon(.compass, size: 14)
                        Text(sign)
                            .thro(ThroTypography.metadata)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: ThroSpacing.spacing2)
                        Button(action: onStopLocation) {
                            Text("Stop")
                                .thro(ThroTypography.labelStrong.uppercase(true).tracking(em: 0.06))
                                .padding(.horizontal, ThroSpacing.spacing2)
                                .frame(minHeight: ThroSpacing.touchTargetMinimum)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(ChalkKeyStyle(.field, minHeight: ThroSpacing.touchTargetMinimum, seedAngle: 7))
                        .fixedSize()
                    }
                    .foregroundStyle(ThroColor.colorTextOnBoard)
                    .padding(.top, ThroSpacing.spacing1)
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("\(sign). Double tap Stop to turn it off.")
                }
                if DiscoverScreen.offersLocation(nearby.place) {
                    Button(action: onUseLocation) {
                        HStack(spacing: ThroSpacing.spacing2) {
                            Icon(.compass, size: 16)
                            Text(nearby.place == .denied ? "Location is off for THRØ" : "Use my location")
                                .thro(ThroTypography.labelStrong.uppercase(true).tracking(em: 0.06))
                        }
                        .foregroundStyle(ThroColor.colorTextOnBoard)
                        .padding(.vertical, ThroSpacing.spacing2)
                        .padding(.horizontal, ThroSpacing.spacing3)
                        .frame(minHeight: ThroSpacing.touchTargetMinimum)
                    }
                    .buttonStyle(ChalkKeyStyle(.field, minHeight: ThroSpacing.touchTargetMinimum, seedAngle: 19))
                    .fixedSize()
                    .disabled(nearby.place == .denied)
                    .padding(.top, ThroSpacing.spacing1)
                }
            }
            .padding(ThroSpacing.spacing5)
        }
    }

    /// The location button is offered until the phone has said where it is. When permission was
    /// refused it stays, disabled, saying so — a control that vanished would leave the player
    /// wondering why the distances never came.
    static func offersLocation(_ place: NearbyLogic.Place) -> Bool {
        switch place {
        case .located: return false
        case .unknown, .asking, .denied: return true
        }
    }

    // MARK: leagues

    /// The words on every retry on this screen. One control, one name for it.
    static let tryAgain = "Try again"

    @ViewBuilder private var leagues: some View {
        SectionHeader("Leagues", action: nearby.leagueList?.isEmpty == false ? "Map" : nil, onAction: { onLeague(nil) })
            .padding(.top, ThroSpacing.spaceSectionGap)
        switch nearby.leagues {
        case .loading:
            HStack { ProgressView(); Text("Reading the leagues").thro(ThroTypography.body).foregroundStyle(ThroColor.colorTextSecondary) }
                .padding(.vertical, ThroSpacing.spacing4)
        case .failed(let why):
            DiscoverTrouble(why, onRetry: onRetry)
        case .loaded(let list):
            if list.isEmpty {
                Text("None listed yet.").thro(ThroTypography.body).foregroundStyle(ThroColor.colorTextSecondary)
                    .padding(.vertical, ThroSpacing.spacing3)
            } else {
                ThroDivider().padding(.top, ThroSpacing.spacing2)
                ForEach(DiscoverScreen.shortlist(list, place: nearby.place), id: \.league.id) { row in
                    Button { onLeague(row.league.id) } label: {
                        OrganisationRow(initials: DiscoverScreen.initials(row.league),
                                        name: row.league.shortName ?? row.league.name,
                                        meta: DiscoverScreen.leagueMeta(row.league, km: row.km),
                                        accent: ThroColor.throGreen,
                                        trailing: row.km.map(NearbyLogic.miles),
                                        image: nil)
                            .throRowTapTarget()
                    }
                    .buttonStyle(ThroPressStyle(radius: ThroSpacing.radiusCard, pressedFill: ThroColor.colorSurfaceSecondary, scales: false))
                    ThroDivider()
                }
                if list.count > DiscoverScreen.shortlistLength {
                    Button { onLeague(nil) } label: {
                        HStack(spacing: ThroSpacing.spacing3) {
                            Text("All \(list.count) leagues on the map")
                                .thro(ThroTypography.labelStrong)
                                .foregroundStyle(ThroColor.throGreen)
                            Spacer()
                            Icon(.chevronRight, size: 18).foregroundStyle(ThroColor.colorTextSecondary)
                        }
                        .padding(.vertical, ThroSpacing.spacing3)
                        .throRowTapTarget()
                    }
                    .buttonStyle(ThroPressStyle(radius: ThroSpacing.radiusCard, pressedFill: ThroColor.colorSurfaceSecondary, scales: false))
                    ThroDivider()
                }
            }
        }
    }

    /// How many leagues Discover lists before pointing at the map. Six is a screen's worth; the
    /// directory lists hundreds, and a list of hundreds under a slate is the long static list the
    /// founder asked to be rid of.
    static let shortlistLength = 6

    /// The leagues Discover shows: nearest first when the phone knows where it is; otherwise the
    /// ones with teams on THRØ first, so the list opens on something a player can join and not on
    /// whichever league is first in the alphabet.
    static func shortlist(_ leagues: [PublicLeague], place: NearbyLogic.Place) -> [(league: PublicLeague, km: Double?)] {
        let rows = ranked(leagues, place: place)
        if case .located = place { return Array(rows.prefix(shortlistLength)) }
        return Array((rows.filter { $0.league.held == .run } + rows.filter { $0.league.held == .teams }
                      + rows.filter { $0.league.held == .placed }).prefix(shortlistLength))
    }

    static func ranked(_ leagues: [PublicLeague], place: NearbyLogic.Place) -> [(league: PublicLeague, km: Double?)] {
        if case .located(let lat, let lon) = place { return NearbyLogic.sorted(leagues, fromLat: lat, lon: lon) }
        return leagues.map { (league: $0, km: nil) }
    }

    static func initials(_ league: PublicLeague) -> String {
        let words = (league.shortName ?? league.name).split(separator: " ").filter { $0.first?.isUppercase == true }
        return String(words.prefix(2).compactMap(\.first)).uppercased()
    }

    /// "Run on THRØ · 12 fixtures, 4 results · Thursday nights · Yarm". What THRØ holds comes first (PD-126),
    /// because it is the difference between a league a player can follow here and a pin on a map; distance goes
    /// on the trailing side.
    static func leagueMeta(_ league: PublicLeague, km: Double?) -> String {
        let held: String
        switch league.held {
        case .run:
            let fixtures = league.shownSeason?.fixtures ?? 0, results = league.shownSeason?.results ?? 0
            held = "Run on THRØ · " + (fixtures == 0 ? "no fixtures yet"
                : "\(LeagueBoardWords.count(fixtures, "fixture")), \(LeagueBoardWords.count(results, "result"))")
        case .teams:
            held = "\(LeagueBoardWords.count(league.shownSeason?.divisions.flatMap(\.teams).count ?? 0, "team")) listed"
        case .placed:
            held = "On the map only"
        }
        return [held, league.playsOn.map { "\($0) nights" }, league.locality].compactMap { $0 }.joined(separator: " · ")
    }

    /// Under one of your teams: its league line where it is in a league THRØ lists, else its town;
    /// then how many are on it. "Stockton Thursday · Division One · Thursday nights · 3 members" (PD-046).
    static func teamMeta(_ team: TeamSummary, atlas: LeagueAtlas) -> String {
        let place = atlas.entry(team.teamId).map(LeagueAtlas.line) ?? team.locality
        return [place, team.members == 1 ? "1 member" : "\(team.members) members"].compactMap { $0 }.joined(separator: " · ")
    }

    // MARK: tournaments

    @ViewBuilder private var tournaments: some View {
        SectionHeader("Tournaments").padding(.top, ThroSpacing.spaceSectionGap)
        switch nearby.events {
        case .loading:
            HStack { ProgressView(); Text("Reading what is coming up").thro(ThroTypography.body).foregroundStyle(ThroColor.colorTextSecondary) }
                .padding(.vertical, ThroSpacing.spacing4)
        case .failed(let why):
            DiscoverTrouble(why, onRetry: onRetry)
        case .loaded(let list):
            if list.isEmpty {
                Text("No tournament is taking entries on THRØ just now. One opened on the organiser's desk at thro.uk shows here the moment it opens.")
                    .thro(ThroTypography.body).foregroundStyle(ThroColor.colorTextSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.vertical, ThroSpacing.spacing3)
            } else {
                ThroDivider().padding(.top, ThroSpacing.spacing2)
                ForEach(list) { event in
                    // A row that names a tournament opens it (PD-126): the page, who is in, and the way in.
                    Button { onEvent(event.eventId) } label: {
                        OrganisationRow(initials: DiscoverScreen.initials(event.name), name: event.name,
                                        meta: DiscoverScreen.eventMeta(event), accent: ThroColor.throGreen,
                                        trailing: event.capacity.map { "\($0) places" }, image: nil)
                            .throRowTapTarget()
                    }
                    .buttonStyle(ThroPressStyle(radius: ThroSpacing.radiusCard, pressedFill: ThroColor.colorSurfaceSecondary, scales: false))
                    ThroDivider()
                }
            }
        }
    }

    static func initials(_ name: String) -> String {
        String(name.split(separator: " ").prefix(2).compactMap(\.first)).uppercased()
    }

    static func eventMeta(_ event: PublicEvent) -> String {
        let when = event.startsAt.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated).hour().minute())
        let venue = event.venue?.name ?? event.venueLabel
        return [when, venue].compactMap { $0 }.joined(separator: " · ")
    }

    // MARK: yours

    @ViewBuilder private var yours: some View {
        // Teams on THRØ first — the connected ones — then what this phone keeps on its own.
        //
        // **No top gap of its own.** `ThroBeside` puts the gutter between the two halves when they stack,
        // and adding one here as well made it 64 points on a phone and pushed this column 32 below the
        // other one on a tablet. One source for the gap, and it is the thing that knows which arrangement
        // the screen is in (PD-062).
        SectionHeader("Your teams on THRØ", action: signedIn ? "Join or start" : nil, onAction: onJoinOrStart)
        if !signedIn {
            Text("Sign in to join a team by its code or start one. A team on THRØ has a roster, a home venue and its place in a league.")
                .thro(ThroTypography.body).foregroundStyle(ThroColor.colorTextSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, ThroSpacing.spacing2)
            // The way there, not a sentence about where it is (PD-126).
            ThroButton("Sign in", variant: .primary, size: .large, fullWidth: true) { ThroRouter.shared.go(.tab(.you)) }
                .padding(.top, ThroSpacing.spacing4)
        } else {
            switch teams.mine {
            case .loading:
                HStack { ProgressView(); Text("Reading your teams").thro(ThroTypography.body).foregroundStyle(ThroColor.colorTextSecondary) }
                    .padding(.vertical, ThroSpacing.spacing3)
            // Idle is not reading: nothing has been asked yet. A spinner here would spin for ever if the ask never came.
            case .idle:
                DiscoverTrouble("Your teams have not been read yet.",
                                label: "Read them now", onRetry: onRetry)
            case .failed(let why):
                DiscoverTrouble(why, onRetry: onRetry)
            case .loaded(let list):
                if list.isEmpty {
                    Text("None yet. Join one with your captain's code, or start one and become its admin.")
                        .thro(ThroTypography.body).foregroundStyle(ThroColor.colorTextSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, ThroSpacing.spacing2)
                    ThroButton("Join or start a team", variant: .primary, size: .large, fullWidth: true, action: onJoinOrStart)
                        .padding(.top, ThroSpacing.spacing4)
                } else {
                    ThroDivider().padding(.top, ThroSpacing.spacing2)
                    let atlas = LeagueAtlas(nearby.leagueList ?? [])
                    ForEach(list) { team in
                        Button { onServerTeam(team.teamId) } label: {
                            OrganisationRow(initials: DiscoverScreen.initials(team.name), name: team.name,
                                            meta: DiscoverScreen.teamMeta(team, atlas: atlas),
                                            accent: ThroColor.throGreen, trailing: TeamFrontScreen.roleLabel(team.role), image: nil)
                                .throRowTapTarget()
                        }
                        .buttonStyle(ThroPressStyle(radius: ThroSpacing.radiusCard, pressedFill: ThroColor.colorSurfaceSecondary, scales: false))
                        ThroDivider()
                    }
                }
            }
        }
        SectionHeader("Kept on this phone", action: clubs.isEmpty ? nil : "Start another", onAction: onCreate)
            .padding(.top, ThroSpacing.spaceSectionGap)
        if clubs.isEmpty {
            Text("A team, league or tournament kept on this phone alone: roster, fixtures and results, without an account. Nothing here leaves the phone.")
                .thro(ThroTypography.body)
                .foregroundStyle(ThroColor.colorTextSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, ThroSpacing.spacing2)
            ThroButton("Keep one on this phone", variant: .secondary, size: .large, fullWidth: true, action: onCreate)
                .padding(.top, ThroSpacing.spacing4)
        } else {
            ThroDivider().padding(.top, ThroSpacing.spacing2)
            ForEach(clubs) { club in
                Button { onOpen(club) } label: {
                    OrganisationRow(initials: club.initials, name: club.name,
                                    meta: "\(club.shape?.label ?? club.kind.label) · \(club.meta)",
                                    accent: club.accentHex.flatMap { Color.thro(hex: $0) },
                                    trailing: club.yourRole?.label,
                                    image: badge(club))
                        .throRowTapTarget()
                }
                .buttonStyle(ThroPressStyle(radius: ThroSpacing.radiusCard, pressedFill: ThroColor.colorSurfaceSecondary, scales: false))
                ThroDivider()
            }
            Note("These stay on this phone. A team on THRØ, above, is the one your side shares.")
                .padding(.top, ThroSpacing.spaceSectionGap)
        }
    }
}
