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

public struct DiscoverScreen: View {
    @ObservedObject private var nearby: Nearby
    private let clubs: [Club]
    private let badge: (Club) -> Image?
    private let onOpen: (Club) -> Void
    private let onCreate: () -> Void
    private let onLeague: (UUID?) -> Void
    private let onUseLocation: () -> Void
    private let onRetry: () -> Void

    public init(nearby: Nearby, clubs: [Club], badge: @escaping (Club) -> Image? = { _ in nil },
                onOpen: @escaping (Club) -> Void = { _ in }, onCreate: @escaping () -> Void = {},
                onLeague: @escaping (UUID?) -> Void = { _ in }, onUseLocation: @escaping () -> Void = {},
                onRetry: @escaping () -> Void = {}) {
        self.nearby = nearby
        self.clubs = clubs
        self.badge = badge
        self.onOpen = onOpen
        self.onCreate = onCreate
        self.onLeague = onLeague
        self.onUseLocation = onUseLocation
        self.onRetry = onRetry
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            TopBar("Discover", actions: clubs.isEmpty ? [] : [TopBar.Action(icon: .plus, label: "Start a team", action: onCreate)])
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    slate.padding(.top, ThroSpacing.spacing4)
                    leagues
                    tournaments
                    yours
                }
                .padding(.horizontal, ThroSpacing.spaceScreenGutter)
                .padding(.bottom, ThroSpacing.spacing6)
            }
        }
        .throEntrance(0)
        .background(ThroColor.colorBackgroundPrimary.ignoresSafeArea())
    }

    // MARK: the slate

    private var slate: some View {
        let words = NearbyLogic.headline(place: nearby.place, leagues: nearby.leagueList)
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

    @ViewBuilder private var leagues: some View {
        SectionHeader("Leagues", action: nearby.leagueList?.isEmpty == false ? "Map" : nil, onAction: { onLeague(nil) })
            .padding(.top, ThroSpacing.spaceSectionGap)
        switch nearby.leagues {
        case .loading:
            HStack { ProgressView(); Text("Reading the leagues").thro(ThroTypography.body).foregroundStyle(ThroColor.colorTextSecondary) }
                .padding(.vertical, ThroSpacing.spacing4)
        case .failed(let why):
            Snackbar(why, tone: .error, actionLabel: "Try again", onAction: onRetry)
                .padding(.top, ThroSpacing.spacing2)
        case .loaded(let list):
            if list.isEmpty {
                Text("None listed yet.").thro(ThroTypography.body).foregroundStyle(ThroColor.colorTextSecondary)
                    .padding(.vertical, ThroSpacing.spacing3)
            } else {
                ThroDivider().padding(.top, ThroSpacing.spacing2)
                ForEach(DiscoverScreen.ranked(list, place: nearby.place), id: \.league.id) { row in
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
            }
        }
    }

    static func ranked(_ leagues: [PublicLeague], place: NearbyLogic.Place) -> [(league: PublicLeague, km: Double?)] {
        if case .located(let lat, let lon) = place { return NearbyLogic.sorted(leagues, fromLat: lat, lon: lon) }
        return leagues.map { (league: $0, km: nil) }
    }

    static func initials(_ league: PublicLeague) -> String {
        let words = (league.shortName ?? league.name).split(separator: " ").filter { $0.first?.isUppercase == true }
        return String(words.prefix(2).compactMap(\.first)).uppercased()
    }

    /// "Thursday nights · 18 teams · Stockton-on-Tees". Distance goes on the trailing side.
    static func leagueMeta(_ league: PublicLeague, km: Double?) -> String {
        let teams = league.shownSeason?.divisions.flatMap(\.teams).count ?? 0
        return [league.playsOn.map { "\($0) nights" }, "\(teams) teams", league.locality].compactMap { $0 }.joined(separator: " · ")
    }

    // MARK: tournaments

    @ViewBuilder private var tournaments: some View {
        SectionHeader("Tournaments").padding(.top, ThroSpacing.spaceSectionGap)
        switch nearby.events {
        case .loading:
            HStack { ProgressView(); Text("Reading what is coming up").thro(ThroTypography.body).foregroundStyle(ThroColor.colorTextSecondary) }
                .padding(.vertical, ThroSpacing.spacing4)
        case .failed(let why):
            Text(why).thro(ThroTypography.body).foregroundStyle(ThroColor.colorTextSecondary).padding(.vertical, ThroSpacing.spacing3)
        case .loaded(let list):
            if list.isEmpty {
                Text("No open tournaments listed yet. When an organiser lists one with THRØ it appears here, with its venue and how many places are left.")
                    .thro(ThroTypography.body).foregroundStyle(ThroColor.colorTextSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.vertical, ThroSpacing.spacing3)
            } else {
                ThroDivider().padding(.top, ThroSpacing.spacing2)
                ForEach(list) { event in
                    OrganisationRow(initials: DiscoverScreen.initials(event.name), name: event.name,
                                    meta: DiscoverScreen.eventMeta(event), accent: ThroColor.throGreen,
                                    trailing: event.capacity.map { "\($0) places" }, image: nil)
                        .throRowTapTarget()
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
        SectionHeader("Yours", action: clubs.isEmpty ? nil : "Start another", onAction: onCreate)
            .padding(.top, ThroSpacing.spaceSectionGap)
        if clubs.isEmpty {
            Text("Teams you start stay on this phone until you choose otherwise. A team or league's front page is public; what is inside it — members, results, announcements — is not.")
                .thro(ThroTypography.body)
                .foregroundStyle(ThroColor.colorTextSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, ThroSpacing.spacing2)
            ThroButton("Start a team", variant: .secondary, size: .large, fullWidth: true, action: onCreate)
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
            Note("Joining somebody else's team needs an account, under Settings → Account and profile.")
                .padding(.top, ThroSpacing.spaceSectionGap)
        }
    }
}
