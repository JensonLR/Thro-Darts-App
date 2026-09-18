import SwiftUI
import ThroDesign
import ThroNet
import ThroTokens

// The Team OS on the phone (plan §6, the first rows): your teams on the server, a team's front,
// starting one, and getting the side in by code. Local teams kept on the phone (the club book)
// stay what they were; these are the connected ones, and the screen says which is which.

/// What the phone knows of the caller's server teams.
@MainActor
public final class TeamsModel: ObservableObject {
    public enum Loading<T: Equatable>: Equatable { case idle, loading, loaded(T), failed(String) }
    @Published public private(set) var mine: Loading<[TeamSummary]> = .idle
    @Published public private(set) var front: Loading<TeamFront> = .idle
    /// Which team `front` is for. The front is one slot, and the first version loaded it only while it
    /// was empty — so after one team had been opened, opening a second showed the first.
    @Published public private(set) var frontFor: UUID?
    @Published public private(set) var invite: TeamInvite?
    @Published public private(set) var note: String?

    public init() {}

    public var list: [TeamSummary]? { if case .loaded(let l) = mine { return l } else { return nil } }

    /// The front, when it is for [teamId]; nil while another team's is still held.
    public func front(for teamId: UUID) -> Loading<TeamFront> {
        frontFor == teamId ? front : .loading
    }

    /// Shows [teamId]'s front: loads it unless it is already the one held, or on its way.
    public func show(_ teamId: UUID, _ api: ThroAPI?) async {
        if frontFor == teamId {
            switch front {
            case .loaded, .loading: return
            case .idle, .failed: break
            }
        }
        await open(teamId, api)
    }

    public func loadMine(_ api: ThroAPI?, signedIn: Bool) async {
        guard let api, signedIn else { mine = .idle; return }
        mine = .loading
        do { mine = .loaded(try await api.myTeams()) } catch { mine = .failed(ThroAPI.refusal(error) ?? LeaguesModel.explain(error, what: "your teams")) }
    }

    public func open(_ teamId: UUID, _ api: ThroAPI?) async {
        frontFor = teamId
        guard let api else { front = .failed("This build names no server."); return }
        front = .loading; invite = nil; note = nil
        do { front = .loaded(try await api.teamFront(teamId)) } catch { front = .failed(ThroAPI.refusal(error) ?? LeaguesModel.explain(error, what: "the team")) }
    }

    /// True when the team was made; the note says why when it was not.
    @discardableResult
    public func create(name: String, locality: String?, _ api: ThroAPI?) async -> TeamSummary? {
        guard let api else { note = "This build names no server."; return nil }
        do {
            let made = try await api.createTeam(name: name, locality: locality)
            mine = .loaded([made] + (list ?? []))
            note = nil
            return made
        } catch { note = ThroAPI.refusal(error) ?? "The team could not be started just now."; return nil }
    }

    public func makeInvite(_ teamId: UUID, _ api: ThroAPI?) async {
        guard let api else { return }
        do { invite = try await api.inviteToTeam(teamId); note = nil } catch { note = ThroAPI.refusal(error) ?? "A code could not be made just now." }
    }

    /// Names a captain or vice-captain, or makes somebody a player again (PD-045). The front comes
    /// back as the admin reads it; a refusal is the server's own sentence.
    public func assign(_ teamId: UUID, memberId: UUID, role: String, _ api: ThroAPI?) async {
        guard let api else { note = "This build names no server."; return }
        do {
            front = .loaded(try await api.assignRole(teamId, memberId: memberId, role: role))
            frontFor = teamId
            note = nil
        } catch { note = ThroAPI.refusal(error) ?? "That could not be changed just now." }
    }

    /// Takes on a listed league team nobody runs (PD-047): the caller becomes its admin, by their own
    /// say. The front is read again after, because it now carries their role and a code to give the side.
    @discardableResult
    public func adopt(_ teamId: UUID, _ api: ThroAPI?) async -> TeamSummary? {
        guard let api else { note = "This build names no server."; return nil }
        do {
            let took = try await api.adoptTeam(teamId)
            mine = .loaded([took] + (list ?? []).filter { $0.teamId != took.teamId })
            note = nil
            await open(teamId, api)
            return took
        } catch { note = ThroAPI.refusal(error) ?? "That team could not be taken on just now."; return nil }
    }

    /// The team says which league it plays in (PD-049). The front comes back carrying it, so the screen
    /// reads the server's answer rather than assuming its own.
    public func saysItPlaysIn(_ teamId: UUID, league: UUID, _ api: ThroAPI?) async {
        guard let api else { note = "This build names no server."; return }
        do {
            front = .loaded(try await api.sayLeague(teamId, leagueId: league))
            frontFor = teamId
            note = nil
        } catch { note = ThroAPI.refusal(error) ?? "That could not be said just now." }
    }

    /// And stops saying it. The claim is kept on the server, marked withdrawn; the front stops showing it.
    public func stopsSayingItPlaysIn(_ teamId: UUID, league: UUID, _ api: ThroAPI?) async {
        guard let api else { note = "This build names no server."; return }
        do {
            front = .loaded(try await api.stopSayingLeague(teamId, leagueId: league))
            frontFor = teamId
            note = nil
        } catch { note = ThroAPI.refusal(error) ?? "That could not be changed just now." }
    }

    @discardableResult
    public func join(code: String, _ api: ThroAPI?) async -> TeamSummary? {
        guard let api else { note = "This build names no server."; return nil }
        do {
            let joined = try await api.joinTeam(code: code)
            mine = .loaded([joined] + (list ?? []).filter { $0.teamId != joined.teamId })
            note = nil
            return joined
        } catch { note = ThroAPI.refusal(error) ?? "The code could not be used just now."; return nil }
    }

    static func normalised(_ raw: String) -> String { raw.uppercased().filter { !$0.isWhitespace && $0 != "-" } }

    // MARK: home venue

    @Published public private(set) var venueMatches: [PublicLeague.Venue] = []
    /// Set when the last search could not be run at all, which is not the same as finding nothing (PD-137).
    @Published public private(set) var venueSearchSaid: String?

    public func searchVenues(_ query: String, _ api: ThroAPI?) async {
        guard let api, query.trimmingCharacters(in: .whitespaces).count >= 2 else {
            venueMatches = []; venueSearchSaid = nil; return
        }
        do { venueMatches = try await api.venues(matching: query); venueSearchSaid = nil }
        catch {
            venueMatches = []
            venueSearchSaid = ThroAPI.refusal(error) ?? "Venues could not be searched just now."
        }
    }

    /// Sets the home and shows the refreshed front. The note carries a refusal.
    public func setHome(_ teamId: UUID, venueId: UUID?, name: String?, locality: String?, _ api: ThroAPI?) async {
        guard let api else { return }
        do { front = .loaded(try await api.setTeamHome(teamId, venueId: venueId, name: name, locality: locality)); note = nil; venueMatches = [] }
        catch { note = ThroAPI.refusal(error) ?? "The home could not be set just now." }
    }
}

/// A team's front: the slate, the seasons, the roster, and — for its admin or captain — the code.
@MainActor
public struct TeamFrontScreen: View {
    @ObservedObject private var teams: TeamsModel
    private let teamId: UUID
    private let api: ThroAPI?
    private let onBack: () -> Void
    @State private var choosingHome = false
    @State private var venueQuery = ""
    @State private var newVenueName = ""
    @State private var newVenueTown = ""
    /// PD-050: reporting is this screen's own state. Nothing else on the phone needs it, and a report keeps
    /// nothing worth holding once it is sent — the record of it lives where it was sent to.
    @StateObject private var safety = SafetyModel()
    @State private var reporting = false
    /// Who is about to be blocked, while the confirmation is up (PD-141).
    @State private var blocking: (playerId: UUID, name: String)?
    /// Said after a block, because the person who did it should see that it took.
    @State private var blocked: String?
    /// The signed-in player, read once: `ThroAPI.session` belongs to the client's actor, and a view body
    /// runs on the main one. Held so a roster row never offers to block the person reading it.
    @State private var mePlayerId: UUID?
    /// PD-106: the season whose fixtures are open, and the team's name to say them under.
    @State private var fixturesIn: TeamFront.SeasonLine?
    @State private var teamName = "The team"

    public init(teams: TeamsModel, teamId: UUID, api: ThroAPI?, onBack: @escaping () -> Void) {
        self.teams = teams
        self.teamId = teamId
        self.api = api
        self.onBack = onBack
    }

    public var body: some View {
        if let line = fixturesIn, let api {
            TeamFixturesScreen(api: api, teamId: teamId, teamName: teamName, season: line, onBack: { fixturesIn = nil })
        } else {
            front
        }
    }

    private var front: some View {
        VStack(spacing: 0) {
            TopBar("Team", eyebrow: "On THRØ", onBack: onBack)
            switch teams.front(for: teamId) {
            case .idle, .loading:
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            case .failed(let why):
                ErrorState(title: "The team could not be read", what: why, safe: "Nothing on this phone is affected.",
                           todo: "Try again with a connection.", actionLabel: "Try again", onAction: { Task { await teams.open(teamId, api) } })
                    .padding(ThroSpacing.spaceScreenGutter)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            case .loaded(let front):
                loaded(front)
            }
        }
        .background(ThroColor.colorBackgroundPrimary.ignoresSafeArea())
        // Keyed on the team, so a second team opened after the first is loaded rather than shown as the first.
        .task(id: teamId) { await teams.show(teamId, api) }
    }

    private func loaded(_ front: TeamFront) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                ThroSlate(seed: UInt32(truncatingIfNeeded: front.teamId.hashValue)) {
                    VStack(alignment: .leading, spacing: ThroSpacing.spacing3) {
                        HStack {
                            Eyebrow(TeamFrontScreen.eyebrow(front), color: ThroColor.colorTextOnBoardSecondary)
                            Spacer()
                            ThroMark().fill(ThroColor.colorMarkOnBoard).frame(width: 22, height: 22).accessibilityHidden(true)
                        }
                        Text(front.name)
                            .thro(ThroTypography.display.family(.sport).weight(.bold).tracking(em: 0))
                            .foregroundStyle(ThroColor.colorTextOnBoard)
                            .lineLimit(2).minimumScaleFactor(0.6)
                        Text(TeamFrontScreen.placeLine(front))
                            .thro(ThroTypography.body).foregroundStyle(ThroColor.colorTextOnBoardSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                        if front.adopted == true {
                            // How this team came to be run is on its front, in the words it happened in.
                            Text("Run on THRØ by one of its own players, by their own say. Nobody appointed them.")
                                .thro(ThroTypography.metadata).foregroundStyle(ThroColor.colorTextOnBoardSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        if let invite = teams.invite {
                            Text(invite.spoken)
                                .thro(ThroTypography.heading1.family(.sport).weight(.bold).tracking(em: 0.08))
                                .foregroundStyle(ThroColor.colorTextOnBoard)
                                .accessibilityLabel("Team code, \(invite.code.map(String.init).joined(separator: " "))")
                            Text("Say it to the side or share it. Good until \(invite.expiresAt.formatted(.dateTime.day().month(.abbreviated))), for up to \(invite.maxUses) people.")
                                .thro(ThroTypography.metadata).foregroundStyle(ThroColor.colorTextOnBoardSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                            // The team's address goes with the code (PD-127): it opens the team in the app, or its page for whoever has none.
                            ShareLink(item: "Join \(front.name) on THRØ: the team code is \(invite.spoken). Enter it in THRØ under Discover → Join or start. \(ThroRoute.team(front.teamId).shared.absoluteString)") {
                                Text("SHARE").thro(ThroTypography.labelStrong.uppercase(true).tracking(em: 0.06))
                                    .foregroundStyle(ThroColor.colorTextOnBoard).padding(.horizontal, ThroSpacing.spacing4)
                            }
                            .buttonStyle(ChalkKeyStyle(.lit, minHeight: ThroSpacing.touchTargetMinimum, seedAngle: 61))
                            .fixedSize()
                        } else if TeamFrontScreen.runsIt(front.yourRole) {
                            Button { Task { await teams.makeInvite(front.teamId, api) } } label: {
                                Text("TEAM CODE").thro(ThroTypography.labelStrong.uppercase(true).tracking(em: 0.06))
                                    .foregroundStyle(ThroColor.colorTextOnBoard).padding(.horizontal, ThroSpacing.spacing4)
                            }
                            .buttonStyle(ChalkKeyStyle(.lit, minHeight: ThroSpacing.touchTargetMinimum, seedAngle: 67))
                            .fixedSize()
                        }
                        if let note = teams.note {
                            Text(note).thro(ThroTypography.metadata).foregroundStyle(ThroColor.colorStatusWarningOnBoard)
                        }
                    }
                    .padding(ThroSpacing.spacing5)
                }
                .padding(.top, ThroSpacing.spacing4)

                if TeamFrontScreen.runsIt(front.yourRole) {
                    SectionHeader("Home venue", action: choosingHome ? "Done" : (front.venue == nil ? "Set" : "Change"),
                                  onAction: { choosingHome.toggle() })
                        .padding(.top, ThroSpacing.spaceSectionGap)
                    if choosingHome { homePicker(front) }
                }
                SectionHeader("Playing in").padding(.top, ThroSpacing.spaceSectionGap)
                if front.seasons.isEmpty {
                    Text("No league season yet. When a league accepts the team it appears here.")
                        .thro(ThroTypography.body).foregroundStyle(ThroColor.colorTextSecondary).fixedSize(horizontal: false, vertical: true)
                } else {
                    ThroDivider().padding(.top, ThroSpacing.spacing2)
                    ForEach(Array(front.seasons.enumerated()), id: \.offset) { _, line in
                        // A season the league published is where the team's fixtures are (PD-106): the row opens them.
                        Button { if line.leagueSeasonId != nil, api != nil { teamName = front.name; fixturesIn = line } } label: {
                            HStack {
                                Text(line.league).thro(ThroTypography.bodyLarge.weight(.semibold)).foregroundStyle(ThroColor.colorTextPrimary)
                                Spacer()
                                Text([line.label, line.division, line.accepted == false ? "waiting" : nil].compactMap { $0 }.joined(separator: " · "))
                                    .thro(ThroTypography.body).foregroundStyle(ThroColor.colorTextSecondary)
                                if line.leagueSeasonId != nil { Icon(.chevronRight, size: 16).foregroundStyle(ThroColor.colorTextSecondary) }
                            }
                            .frame(minHeight: ThroSpacing.touchTargetMinimum)
                            .throRowTapTarget()
                        }
                        .buttonStyle(ThroPressStyle(radius: ThroSpacing.radiusCard, pressedFill: ThroColor.colorSurfaceSecondary, scales: false))
                        .accessibilityHint(line.leagueSeasonId != nil ? "Opens the team's fixtures in this season" : "")
                        .padding(.vertical, ThroSpacing.spacing3)
                        ThroDivider()
                    }
                }

                // Friendlies (PD-110): the team's own members read them and whoever runs it answers; somebody who runs
                // another team challenges from here.
                if let api {
                    if front.yourRole != nil {
                        FriendliesSection(api: api, teamId: front.teamId, runsIt: TeamFrontScreen.runsIt(front.yourRole))
                    } else {
                        ChallengeSection(api: api, target: front)
                    }
                }

                // What the team says of itself, under what the league published about it (PD-049).
                TeamLeagueSay(teams: teams, front: front, api: api)
                SectionHeader("Roster", meta: "\(front.roster.count)").padding(.top, ThroSpacing.spaceSectionGap)
                ThroDivider().padding(.top, ThroSpacing.spacing2)
                ForEach(Array(front.roster.enumerated()), id: \.offset) { _, member in
                    HStack(spacing: ThroSpacing.spacing3) {
                        PlayerIdentity(PlayerRef(name: member.name ?? "A player", unnamed: member.name == nil), size: .small)
                        Spacer()
                        // The admin names the captain and vice-captain here (PD-045); everyone else reads the role.
                        if front.yourRole == "admin", let handle = member.memberId, member.role != "admin" {
                            roleMenu(front, member: member, handle: handle)
                        } else {
                            Text(TeamFrontScreen.roleLabel(member.role)).thro(ThroTypography.metadata).foregroundStyle(ThroColor.colorTextSecondary)
                        }
                        // Blocking, where the person is read (PD-141), for the same reason reporting is:
                        // somebody who wants nothing more to do with a team-mate is looking at that
                        // team-mate, not hunting through a settings list for a screen they must already
                        // suspect exists. Not offered on yourself, and not on a roster entry with no player
                        // behind it — a walk-up has no account, and the server says so.
                        if let playerId = member.playerId, playerId != mePlayerId {
                            Menu {
                                Button("Block \(member.name ?? "this player")", role: .destructive) {
                                    blocking = (playerId, member.name ?? "this player")
                                }
                            } label: {
                                Icon(.ellipsis, size: 20)
                                    .frame(width: ThroSpacing.touchTargetMinimum, height: ThroSpacing.touchTargetMinimum)
                                    .foregroundStyle(ThroColor.colorTextTertiary)
                                    .contentShape(Rectangle())
                            }
                            .accessibilityLabel("More for \(member.name ?? "this player")")
                        }
                    }
                    .padding(.vertical, ThroSpacing.spacing2)
                    ThroDivider()
                }
                if front.yourRole == "admin" && front.roster.count > 1 {
                    Note("Tap a role to name the captain or the vice-captain. One of each: naming a new one makes the old one a player again, and the captain runs the team with you.")
                        .padding(.top, ThroSpacing.spacing3)
                }
                if front.roster.contains(where: { $0.name == nil }) {
                    Note(TeamFrontScreen.unnamedNote(front.roster.filter { $0.name == nil }.count))
                        .padding(.top, ThroSpacing.spacing3)
                }
                // PD-050: reportable from where it is read. A team's name is the whole of what a stranger
                // sees of it, so the way to say that name is wrong belongs on the page carrying the name,
                // not in a settings list somebody would have to already suspect exists.
                if let blocked { Snackbar(blocked, tone: .success).padding(.top, ThroSpacing.spacing3) }
                if let said = safety.note { Snackbar(said, tone: .error).padding(.top, ThroSpacing.spacing3) }
                ThroTextButton("Report this team", tone: .quiet) { reporting = true }
                    .padding(.top, ThroSpacing.spaceSectionGap)
            }
            .padding(.horizontal, ThroSpacing.spaceScreenGutter)
            .padding(.bottom, ThroSpacing.spacing6)
            .throReadable()
        }
        .task { mePlayerId = await api?.session?.playerId }
        .confirmationDialog("Block \(blocking?.name ?? "")?",
                            isPresented: Binding(get: { blocking != nil }, set: { if !$0 { blocking = nil } }),
                            titleVisibility: .visible) {
            Button("Block", role: .destructive) {
                if let who = blocking {
                    Task {
                        if await safety.block(player: who.playerId, api) { blocked = "Blocked. Neither of you can reach the other on THRØ." }
                        blocking = nil
                    }
                }
            }
            Button("Not now", role: .cancel) { blocking = nil }
        } message: {
            Text("Neither of you can invite, befriend, take a seat against or watch the other. No reason is asked for, and they are not told. You can lift it from You → Settings → Blocked.")
        }
        .sheet(isPresented: $reporting) {
            ReportSheet(safety: safety, kind: "team", subjectId: front.teamId, subjectName: front.name, api: api) {
                reporting = false
            }
        }
    }

    /// The role, as a control for the admin (PD-045): tapped, it lists the three with this one ticked.
    /// A picker rather than a row of buttons — the system draws a menu's items, and a picker says which
    /// role is held, where a list of "Make …" buttons only said which were not.
    private func roleMenu(_ front: TeamFront, member: TeamFront.Member, handle: UUID) -> some View {
        Menu {
            Picker("Role", selection: Binding(get: { member.role }, set: { role in
                guard role != member.role else { return }
                Task { await teams.assign(front.teamId, memberId: handle, role: role, api) }
            })) {
                ForEach(TeamFrontScreen.assignable, id: \.self) { role in
                    Text(TeamFrontScreen.roleLabel(role)).tag(role)
                }
            }
        } label: {
            HStack(spacing: ThroSpacing.spacing1) {
                Text(TeamFrontScreen.roleLabel(member.role))
                    .thro(ThroTypography.label.weight(.semibold))
                    .foregroundStyle(ThroColor.colorTextBrand)
                Icon(.chevronRight, size: 12)
                    .rotationEffect(.degrees(90))
                    .foregroundStyle(ThroColor.colorTextBrand)
            }
            .throTapTarget()
        }
        .accessibilityLabel("\(member.name ?? "A player"), \(TeamFrontScreen.roleLabel(member.role)). Change their role.")
    }

    /// Choosing a home: the public venues THRØ knows, by name, or a new one by name and town.
    private func homePicker(_ front: TeamFront) -> some View {
        VStack(alignment: .leading, spacing: ThroSpacing.spacing3) {
            ThroTextField("Find the pub or club", text: $venueQuery, placeholder: "Sun Inn")
                .autocorrectionDisabled()
                .onChange(of: venueQuery) { _, q in Task { await teams.searchVenues(q, api) } }
            if let said = teams.venueSearchSaid {
                Note(said, icon: .info).padding(.top, ThroSpacing.spacing2)
            }
            if !teams.venueMatches.isEmpty {
                ThroDivider()
                ForEach(teams.venueMatches, id: \.venueId) { v in
                    Button { Task { await teams.setHome(front.teamId, venueId: v.venueId, name: nil, locality: nil, api); choosingHome = false } } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(v.name).thro(ThroTypography.bodyLarge.weight(.semibold)).foregroundStyle(ThroColor.colorTextPrimary)
                                Text([v.locality, v.postcode].compactMap { $0 }.joined(separator: " · ")).thro(ThroTypography.metadata).foregroundStyle(ThroColor.colorTextSecondary)
                            }
                            Spacer()
                            Icon(.chevronRight, size: 16).foregroundStyle(ThroColor.colorTextSecondary)
                        }
                        .padding(.vertical, ThroSpacing.spacing2)
                        .throRowTapTarget()
                    }
                    .buttonStyle(ThroPressStyle(radius: ThroSpacing.radiusCard, pressedFill: ThroColor.colorSurfaceSecondary, scales: false))
                    ThroDivider()
                }
            } else if venueQuery.trimmingCharacters(in: .whitespaces).count >= 2 {
                Text("Nothing by that name yet. Add it below and it becomes a venue others can pick.")
                    .thro(ThroTypography.metadata).foregroundStyle(ThroColor.colorTextSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Eyebrow("Or add a new venue").padding(.top, ThroSpacing.spacing2)
            ThroTextField("Venue", text: $newVenueName, placeholder: "The Dolphin")
            ThroTextField("Town", text: $newVenueTown, placeholder: "Stockton-on-Tees")
            ThroButton("Set as home", variant: .secondary, size: .medium) {
                Task { await teams.setHome(front.teamId, venueId: nil, name: newVenueName, locality: newVenueTown.isEmpty ? nil : newVenueTown, api); choosingHome = false }
            }
            .disabled(newVenueName.trimmingCharacters(in: .whitespaces).count < 2)
        }
    }

    static func runsIt(_ role: String?) -> Bool { role == "admin" || role == "captain" }
    static func eyebrow(_ front: TeamFront) -> String {
        switch front.yourRole { case "admin": return "Your team · admin"; case "captain": return "Your team · captain"; case nil: return "Team"; default: return "Your team" }
    }
    static func placeLine(_ front: TeamFront) -> String {
        [front.venue.map { v in [v.name, v.postcode].compactMap { $0 }.joined(separator: " · ") }, front.locality].compactMap { $0 }.joined(separator: " · ").ifEmpty("No home venue set yet")
    }
    static func roleLabel(_ role: String) -> String {
        switch role { case "admin": return "Admin"; case "captain": return "Captain"; case "vice_captain": return "Vice-captain"; default: return "Player" }
    }
    /// The roles an admin names (PD-045). Admin is not one of them: the admin stays the admin.
    static let assignable = ["captain", "vice_captain", "player"]
    static func unnamedNote(_ n: Int) -> String {
        n == 1 ? "One member is counted and not named: THRØ names a person only when they are an adult who has said so, or a guardian has."
               : "\(n) members are counted and not named: THRØ names a person only when they are an adult who has said so, or a guardian has."
    }
}

private extension String {
    func ifEmpty(_ fallback: String) -> String { isEmpty ? fallback : self }
}

/// Starting a team on THRØ, or joining one by its code. One screen, two doors.
public struct JoinOrStartTeamScreen: View {
    @ObservedObject private var teams: TeamsModel
    private let api: ThroAPI?
    private let onBack: () -> Void
    private let onDone: (TeamSummary) -> Void
    @State private var name = ""
    @State private var locality = ""
    @State private var code = ""
    @State private var busy = false

    public init(teams: TeamsModel, api: ThroAPI?, onBack: @escaping () -> Void, onDone: @escaping (TeamSummary) -> Void) {
        self.teams = teams
        self.api = api
        self.onBack = onBack
        self.onDone = onDone
    }

    public var body: some View {
        VStack(spacing: 0) {
            TopBar("Your team on THRØ", eyebrow: "Discover", onBack: onBack)
            ScrollView {
                VStack(alignment: .leading, spacing: ThroSpacing.spacing3) {
                    SectionHeader("Join with a code")
                    Text("Your captain or admin has an eight-character team code. Enter it and you are on the roster.")
                        .thro(ThroTypography.body).foregroundStyle(ThroColor.colorTextSecondary).fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: ThroSpacing.spacing3) {
                        ThroTextField("Team code", text: $code, placeholder: "ABCD EFGH").autocorrectionDisabled()
                        ThroButton("Join", variant: .primary, size: .large) {
                            busy = true
                            Task { if let t = await teams.join(code: code, api) { onDone(t) }; busy = false }
                        }
                        .disabled(busy || TeamsModel.normalised(code).count != 8)
                        .padding(.top, 22)
                    }
                    SectionHeader("Or start one").padding(.top, ThroSpacing.spaceSectionGap)
                    Text("You become its admin. Then make its code and give it to the side.")
                        .thro(ThroTypography.body).foregroundStyle(ThroColor.colorTextSecondary).fixedSize(horizontal: false, vertical: true)
                    ThroTextField("Team name", text: $name, placeholder: "The Sun Inn")
                    ThroTextField("Town", text: $locality, placeholder: "Stockton-on-Tees")
                    ThroButton("Start the team", variant: .secondary, size: .large, fullWidth: true) {
                        busy = true
                        Task {
                            if let t = await teams.create(name: name, locality: locality.trimmingCharacters(in: .whitespaces).isEmpty ? nil : locality, api) { onDone(t) }
                            busy = false
                        }
                    }
                    .disabled(busy || name.trimmingCharacters(in: .whitespaces).count < 2)
                    if let note = teams.note {
                        Snackbar(note, tone: .error)
                    }
                    Note("A team on THRØ is public by its front — name, town, venue, competition. Who is in it is named only where THRØ may name them.")
                        .padding(.top, ThroSpacing.spaceSectionGap)
                }
                .padding(.horizontal, ThroSpacing.spaceScreenGutter)
                .padding(.vertical, ThroSpacing.spacing5)
                .throReadable()
            }
        }
        .background(ThroColor.colorBackgroundPrimary.ignoresSafeArea())
    }
}

// MARK: - Friendlies (PD-110)

/// A team's friendlies, sent and received. Whoever runs the team accepts or declines a received one and withdraws an
/// unanswered sent one; everybody on the team reads them. Every refusal is the server's words.
struct FriendliesSection: View {
    let api: ThroAPI
    let teamId: UUID
    let runsIt: Bool
    @State private var list: [Friendly]?
    @State private var declining: UUID?
    @State private var note = ""
    @State private var said: String?
    @State private var busy = false

    var body: some View {
        SectionHeader("Friendlies", meta: list.map { "\($0.count)" } ?? "").padding(.top, ThroSpacing.spaceSectionGap)
        if list == nil, let said {
            // Read and failed: say so, and offer the way to ask again. Never an empty state.
            ErrorState(title: "Friendlies could not be read", what: said,
                       safe: "Nothing about this team has changed.",
                       todo: "Try again with a connection.",
                       onAction: { Task { await load() } })
                .padding(.top, ThroSpacing.spacing2)
        }
        if let list {
            if list.isEmpty {
                Text("No friendlies yet. Open another team's page to challenge them.")
                    .thro(ThroTypography.body).foregroundStyle(ThroColor.colorTextSecondary).fixedSize(horizontal: false, vertical: true).padding(.top, ThroSpacing.spacing2)
            }
            ForEach(list) { f in
                DeskCard(icon: .users, title: f.direction == "sent" ? "v \(f.toTeam)" : "\(f.fromTeam) challenge you",
                         meta: f.playAt.formatted(date: .abbreviated, time: .shortened) + " · " + Self.standing(f)) {
                    if let m = f.message { Text("“\(m)”").thro(ThroTypography.body).foregroundStyle(ThroColor.colorTextSecondary).fixedSize(horizontal: false, vertical: true) }
                    if runsIt && f.state == "proposed" {
                        if f.direction == "received" {
                            if declining == f.friendlyId {
                                ThroTextField("Why not?", text: $note, placeholder: "cup night")
                                HStack(spacing: ThroSpacing.spacing2) {
                                    ThroButton("Decline", variant: .secondary, size: .medium) { Task { await answer(f, "declined") } }
                                        .disabled(note.trimmingCharacters(in: .whitespaces).count < 3 || busy)
                                    ThroTextButton("Not yet", tone: .quiet) { declining = nil }
                                }
                            } else {
                                HStack(spacing: ThroSpacing.spacing2) {
                                    ThroButton("Accept", variant: .secondary, size: .medium) { Task { await answer(f, "accepted") } }.disabled(busy)
                                    ThroTextButton("Decline", tone: .quiet) { declining = f.friendlyId; note = "" }.disabled(busy)
                                }
                            }
                        } else {
                            ThroButton("Withdraw", variant: .secondary, size: .medium) { Task { await withdraw(f) } }.disabled(busy)
                        }
                    }
                }
                .padding(.top, ThroSpacing.spacing2)
            }
        } else {
            Text("One moment…").thro(ThroTypography.body).foregroundStyle(ThroColor.colorTextSecondary).padding(.top, ThroSpacing.spacing2)
                .task { await load() }
        }
        if let said { Note(said).padding(.top, ThroSpacing.spacing2) }
    }

    static func standing(_ f: Friendly) -> String {
        switch f.state {
        case "proposed": return f.direction == "sent" ? "waiting for \(f.toTeam)" : "waiting for your answer"
        case "accepted": return f.matchId != nil ? "played, scored on THRØ" : "agreed" + (f.answerNote.map { " — \($0)" } ?? "")
        case "declined": return "declined" + (f.answerNote.map { " — \($0)" } ?? "")
        case "withdrawn": return "withdrawn"
        default: return f.state
        }
    }

    private func load() async {
        // `list` stays nil when the read fails (PD-137). Writing [] here said "no friendlies" to a captain
        // with a challenge waiting for their answer, any time the connection dropped — the loudest thing on
        // the screen being the one statement that was false.
        do { list = try await api.friendlies(team: teamId); said = nil }
        catch { said = (error as? APIError)?.message ?? error.localizedDescription }
    }

    private func answer(_ f: Friendly, _ answer: String) async {
        busy = true; defer { busy = false }
        do {
            _ = try await api.answerFriendly(f.friendlyId, answer: answer, note: declining == f.friendlyId ? note.trimmingCharacters(in: .whitespaces) : nil)
            declining = nil; said = answer == "accepted" ? "Agreed, in your name." : "Declined, with your reason kept."
            await load()
        } catch { said = (error as? APIError)?.message ?? error.localizedDescription }
    }

    private func withdraw(_ f: Friendly) async {
        busy = true; defer { busy = false }
        do { _ = try await api.withdrawFriendly(f.friendlyId); said = "Withdrawn."; await load() }
        catch { said = (error as? APIError)?.message ?? error.localizedDescription }
    }
}

/// On another team's page: somebody who runs a team challenges them to a friendly, from the team they run.
struct ChallengeSection: View {
    let api: ThroAPI
    let target: TeamFront
    @State private var mine: [TeamSummary]?
    @State private var from: UUID?
    @State private var when = Date().addingTimeInterval(7 * 24 * 3600)
    @State private var message = ""
    @State private var open = false
    @State private var said: String?
    @State private var busy = false

    private var runnable: [TeamSummary] { (mine ?? []).filter { $0.role == "admin" || $0.role == "captain" || $0.role == "vice_captain" } }

    var body: some View {
        if let mine, !runnable.isEmpty {
            SectionHeader("A friendly").padding(.top, ThroSpacing.spaceSectionGap)
            if open {
                if runnable.count > 1 {
                    ForEach(runnable) { t in
                        Button { from = t.teamId } label: {
                            HStack {
                                Icon(from == t.teamId ? .circleCheck : .circle, size: 20).foregroundStyle(from == t.teamId ? ThroColor.colorBackgroundBrand : ThroColor.colorTextSecondary)
                                Text("From \(t.name)").thro(ThroTypography.body).foregroundStyle(ThroColor.colorTextPrimary)
                                Spacer()
                            }
                            .frame(minHeight: ThroSpacing.touchTargetMinimum)
                            .throRowTapTarget()
                        }
                        .buttonStyle(ThroPressStyle(radius: ThroSpacing.radiusCard, pressedFill: ThroColor.colorSurfaceSecondary, scales: false))
                    }
                }
                DatePicker("When", selection: $when, in: Date()...)
                    .thro(ThroTypography.body).foregroundStyle(ThroColor.colorTextPrimary).padding(.top, ThroSpacing.spacing2)
                ThroTextField("A message", text: $message, placeholder: "Friday, our board, first to five?")
                HStack(spacing: ThroSpacing.spacing2) {
                    ThroButton("Challenge \(target.name)", variant: .primary, size: .medium) { Task { await send() } }.disabled(busy || from == nil)
                    ThroTextButton("Leave it", tone: .quiet) { open = false }
                }
                Note("They accept or decline from their team's page. A friendly reaches no league table.").padding(.top, ThroSpacing.spacing2)
            } else {
                ThroButton("Challenge them to a friendly", variant: .secondary, size: .medium) { open = true; if from == nil { from = runnable.first?.teamId } }
                    .padding(.top, ThroSpacing.spacing3)
            }
            if let said { Note(said).padding(.top, ThroSpacing.spacing2) }
            let _ = mine
        } else if mine == nil {
            // Left nil when the read fails (PD-137): "Challenge" was drawn disabled with nothing saying
            // why, because an unread list and a person who runs no team looked identical here.
            Color.clear.frame(height: 1).task {
                do { mine = try await api.myTeams() }
                catch { said = (error as? APIError)?.message ?? "Your teams could not be read just now." }
            }
        }
    }

    private func send() async {
        guard let from else { return }
        busy = true; defer { busy = false }
        do {
            _ = try await api.challenge(from: from, to: target.teamId, playAt: when, message: message.trimmingCharacters(in: .whitespaces))
            open = false; said = "Challenge sent. \(target.name) answer from their page; it shows under your team's Friendlies."
        } catch { said = (error as? APIError)?.message ?? error.localizedDescription }
    }
}
