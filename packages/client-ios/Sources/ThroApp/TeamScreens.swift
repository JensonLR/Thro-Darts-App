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

    public func searchVenues(_ query: String, _ api: ThroAPI?) async {
        guard let api, query.trimmingCharacters(in: .whitespaces).count >= 2 else { venueMatches = []; return }
        do { venueMatches = try await api.venues(matching: query) } catch { venueMatches = [] }
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

    public init(teams: TeamsModel, teamId: UUID, api: ThroAPI?, onBack: @escaping () -> Void) {
        self.teams = teams
        self.teamId = teamId
        self.api = api
        self.onBack = onBack
    }

    public var body: some View {
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
                            ShareLink(item: "Join \(front.name) on THRØ: the team code is \(invite.spoken). Enter it in THRØ under Discover → Join or start.") {
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
                        HStack {
                            Text(line.league).thro(ThroTypography.bodyLarge.weight(.semibold)).foregroundStyle(ThroColor.colorTextPrimary)
                            Spacer()
                            Text([line.label, line.division].compactMap { $0 }.joined(separator: " · ")).thro(ThroTypography.body).foregroundStyle(ThroColor.colorTextSecondary)
                        }
                        .padding(.vertical, ThroSpacing.spacing3)
                        ThroDivider()
                    }
                }

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
            }
            .padding(.horizontal, ThroSpacing.spaceScreenGutter)
            .padding(.bottom, ThroSpacing.spacing6)
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
            }
        }
        .background(ThroColor.colorBackgroundPrimary.ignoresSafeArea())
    }
}
