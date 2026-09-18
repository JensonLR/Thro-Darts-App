import SwiftUI
import ThroDesign
import ThroJournal
import ThroNet
import ThroTokens

/// The account: who you are to THRØ, how you get in, and — once in — what is waiting for you.
///
/// The screen says what the store knows and nothing more: a person with one way in is told they
/// have one way in (PD-032), a failure says what happened and what is safe, and the two
/// server-backed lists behind it are reached from here so that "nothing is called eligible that
/// THRØ cannot check" and "no task is manufactured" arrive on the phone with their reasons intact.
public struct AccountScreen: View {
    @ObservedObject private var account: AccountStore
    private let onBack: () -> Void
    @State private var editingName = false
    @State private var name = ""
    @State private var showing: Sub?

    private enum Sub { case inbox, discovery, friends, profile }

    /// Where the account screen may be asked to open: on its own front, or straight on Friends.
    public enum Opening { case account, friends }

    /// The local picture store and the reader for it, so the profile page can carry a face. Both
    /// optional: a build with no image store shows initials, which is a mark rather than a fault.
    private let images: ImageStore?
    private let picture: (String?) -> Image?

    public init(account: AccountStore, opening: Opening = .account,
                images: ImageStore? = nil, picture: @escaping (String?) -> Image? = { _ in nil },
                onBack: @escaping () -> Void) {
        self.account = account
        self.images = images
        self.picture = picture
        self.onBack = onBack
        self._showing = State(initialValue: opening == .friends ? .friends : nil)
    }

    public var body: some View {
        if showing == .inbox {
            InboxScreen(account: account) { showing = nil }
        } else if showing == .discovery {
            DiscoveryScreen(account: account) { showing = nil }
        } else if showing == .friends {
            FriendsScreen(account: account) { showing = nil }
        } else if case .signedIn(let profile) = account.state, let id = profile.accountId {
            // **Signed in, this screen IS the profile.** It used to be a settings list whose first
            // row went to the profile, so every route to a person's own name passed through a page
            // that only pointed at another one. Both ways in — the You tab and Settings — land on
            // the same page now, and the lists that were on this one live there.
            YourProfileScreen(account: account, profile: profile, accountId: id,
                              images: images, picture: picture) { showing = nil; onBack() }
        } else {
            VStack(spacing: 0) {
                BoardHeader(title: "Account", eyebrow: "THRØ", onBack: onBack)
                ScrollView {
                    VStack(alignment: .leading, spacing: ThroSpacing.spacing4) {
                        switch account.state {
                        case .signedOut: signedOut
                        case .busy(let what): busy(what)
                        case .signedIn(let profile): signedIn(profile)
                        case .failed(let why, let was, _): failed(why, wasSignedIn: was)
                        }
                        server
                    }
                    .padding(.horizontal, ThroSpacing.spaceScreenGutter)
                    .padding(.top, ThroSpacing.spacing5)
                    .padding(.bottom, ThroSpacing.spacing6)
                    .throReadable()
                }
            }
            .background(ThroColor.colorBackgroundPrimary.ignoresSafeArea())
            .task { await account.start() }
        }
    }

    // MARK: states

    private var signedOut: some View {
        VStack(alignment: .leading, spacing: ThroSpacing.spacing3) {
            SectionHeader("Sign in")
            Note("**Your matches stay on this phone.** Signing in gives you a THRØ ID — the identity a "
                 + "league registers, a team names in a lineup, and a result is attributed to. Nothing "
                 + "on this phone is sent anywhere by signing in.")
            ThroButton("Continue with Apple", variant: .primary, size: .large, fullWidth: true) { Task { await account.signInWithApple() } }
            if account.configuration.googleClientID != nil {
                ThroButton("Continue with Google", variant: .secondary, size: .large, fullWidth: true) { Task { await account.signInWithGoogle() } }
            } else {
                SettingsRow(icon: .info, label: "Continue with Google", value: "Not set up in this build")
            }
            ThroButton("Sign in with a passkey", variant: .ghost, size: .large, icon: .lock, fullWidth: true) { Task { await account.usePasskey() } }
            ThroTextButton("Create an account with a passkey instead", tone: .quiet) { Task { await account.createAccountWithPasskey() } }
        }
    }

    private func busy(_ what: String) -> some View {
        VStack(alignment: .leading, spacing: ThroSpacing.spacing3) {
            SectionHeader(what)
            Note("Waiting on THRØ. If the server was asleep this can take up to a minute the first time.")
        }
    }

    private func signedIn(_ profile: Profile) -> some View {
        VStack(alignment: .leading, spacing: ThroSpacing.spacing3) {
            SectionHeader("You")
            // One row to the page where a name and a picture are typed and tapped, rather than the
            // name, the age and their two controls spread across this list. The founder had to go
            // through seven steps to type two words; this is one.
            LinkRow(icon: .circleUser, label: "Your profile",
                    value: profile.named ? (profile.displayName ?? "") : "Name yourself, add a picture") { showing = .profile }
            SettingsRow(icon: .shield, label: "Age band", value: ageBandCopy(profile.ageBand))
            SectionHeader("Friends")
            LinkRow(icon: .users, label: "Friends", value: account.friends.map { $0.isEmpty ? "None yet" : "\($0.count)" } ?? "Codes, given in person") { showing = .friends }
            SectionHeader("Ways in")
            let ways = WaysIn(profile: profile)
            waysIn(ways.count)
            // Each way held, by name (PD-102), so adding one visibly adds a row rather than changing one word.
            ForEach(ways.held, id: \.self) { way in
                SettingsRow(icon: .check, label: way.title, value: "Set up")
            }
            ForEach(ways.offers(googleConfigured: account.configuration.googleClientID != nil), id: \.self) { way in
                switch way {
                case .passkey:
                    ThroButton(ways.has(.passkey) ? "Add another passkey" : "Add a passkey", variant: .secondary, size: .medium, icon: .lock) { Task { await account.usePasskey() } }
                case .apple:
                    ThroTextButton("Add Sign in with Apple", tone: .quiet) { Task { await account.signInWithApple() } }
                case .google:
                    ThroTextButton("Add Sign in with Google", tone: .quiet) { Task { await account.signInWithGoogle() } }
                }
            }
            SectionHeader("From THRØ")
            LinkRow(icon: .bell, label: "Your inbox", value: "Tasks waiting on you") { showing = .inbox }
            LinkRow(icon: .compass, label: "Darts you can play", value: "Events, with why each is there") { showing = .discovery }
            SectionHeader("Leave")
            ThroButton("Sign out of this phone", variant: .destructive, size: .medium) { Task { await account.signOut() } }
        }
    }

    private func waysIn(_ n: Int) -> some View {
        Note(n <= 1
             ? "**One way into this account.** Lose it and the account is lost: THRØ has no email or "
               + "phone recovery, on purpose. Add a passkey or a second sign-in below."
             : "**\(n) ways into this account.** If one is lost, another still gets you in.")
    }

    private func failed(_ why: String, wasSignedIn: Bool) -> some View {
        ErrorState(title: "That did not go through", what: why,
                   safe: wasSignedIn ? "You are still signed in; nothing about your account changed." : "Nothing was created or changed.",
                   todo: "Try again, or come back when you are online.", actionLabel: "Back") { account.dismissFailure() }
    }

    private var server: some View {
        VStack(alignment: .leading, spacing: ThroSpacing.spacing2) {
            SectionHeader("Where this goes")
            SettingsRow(icon: .info, label: "Server", value: account.configuration.baseURL.host ?? "—")
            SettingsRow(icon: .info, label: "Matches", value: "Stay on this device")
        }
    }

    private func ageBandCopy(_ band: String) -> String {
        switch band { case "adult": return "Adult"; case "minor": return "Under 18"; default: return "Not known yet" }
    }
}

/// A row that goes somewhere. Stays still under the finger, as list rows do.
struct LinkRow: View {
    let icon: ThroIcon
    let label: String
    let value: String?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Icon(icon, size: 18).foregroundStyle(ThroColor.colorTextSecondary)
                VStack(alignment: .leading, spacing: 2) {
                    Text(label).thro(ThroTypography.body).foregroundStyle(ThroColor.colorTextPrimary)
                    if let value { Text(value).thro(ThroTypography.metadata).foregroundStyle(ThroColor.colorTextSecondary) }
                }
                Spacer(minLength: ThroSpacing.spacing3)
                Icon(.chevronRight, size: 16).foregroundStyle(ThroColor.colorTextSecondary)
            }
            .frame(minHeight: 52)
            .throRowTapTarget()
        }
        .buttonStyle(ThroPressStyle(radius: 0, pressedFill: ThroColor.colorBackgroundSecondary, scales: false))
        .overlay(alignment: .bottom) { Rectangle().fill(ThroColor.colorBorderDefault).frame(height: 1) }
        .accessibilityElement(children: .combine)
    }
}

/// A card on the desk: one task, one event, one friendly — the account screens' card shape (`CardGroup`'s), holding
/// its words and, beneath them, the acts a person may take on it. Plain rows with a hairline were rejected for these
/// screens: a thing waiting on you is a thing, not a line in a list.
struct DeskCard<Content: View>: View {
    let icon: ThroIcon
    let title: String
    let meta: String?
    let content: Content
    init(icon: ThroIcon, title: String, meta: String? = nil, @ViewBuilder content: () -> Content) {
        self.icon = icon; self.title = title; self.meta = meta; self.content = content()
    }
    var body: some View {
        VStack(alignment: .leading, spacing: ThroSpacing.spacing3) {
            HStack(alignment: .top, spacing: ThroSpacing.spacing3) {
                IconTile(icon: icon)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).thro(ThroTypography.bodyLarge.weight(.semibold)).foregroundStyle(ThroColor.colorTextPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                    if let meta {
                        Text(meta).thro(ThroTypography.metadata).foregroundStyle(ThroColor.colorTextSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            content
        }
        .padding(ThroSpacing.spacing4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(ThroColor.colorBackgroundRaised)
        .clipShape(RoundedRectangle(cornerRadius: ThroSpacing.radiusCard, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: ThroSpacing.radiusCard, style: .continuous).strokeBorder(ThroColor.colorBorderDefault, lineWidth: 1))
    }
}

/// What the Secretary is waiting on you for. Every task carries its reason; none is invented here.
public struct InboxScreen: View {
    @ObservedObject private var account: AccountStore
    private let onBack: () -> Void
    @State private var sections: [String: [InboxItem]]?
    @State private var problem: String?

    public init(account: AccountStore, onBack: @escaping () -> Void) {
        self.account = account
        self.onBack = onBack
    }

    public var body: some View {
        VStack(spacing: 0) {
            BoardHeader(title: "Your inbox", eyebrow: "Your profile", onBack: onBack)
            ScrollView {
                VStack(alignment: .leading, spacing: ThroSpacing.spacing4) {
                    if let problem {
                        ErrorState(title: "Could not load your inbox", what: problem, safe: "Nothing on this phone changed.", todo: "Try again when you are online.") { Task { await load() } }
                    } else if let sections {
                        if sections.values.allSatisfy(\.isEmpty) {
                            EmptyState(title: "Nothing waiting on you", message: "When a league or a team needs something from you, it appears here with the reason.")
                        }
                        ForEach(InboxOrder.sections.filter { !(sections[$0]?.isEmpty ?? true) }, id: \.self) { key in
                            SectionHeader(InboxOrder.title(key), meta: "\(sections[key]?.count ?? 0)")
                            ForEach(sections[key] ?? []) { item in
                                DeskCard(icon: InboxOrder.icon(item.kind), title: item.reason, meta: InboxOrder.detail(item)) {
                                    if item.kind == "registration_required" && item.state == "open" {
                                        RegistrationTaskActions(account: account, task: item.taskId) { Task { await load() } }
                                    }
                                    if item.kind == "rearrangement_answer_due" && item.state == "open", let proposal = item.proposal {
                                        RearrangementTaskActions(account: account, proposal: proposal) { Task { await load() } }
                                    }
                                }
                            }
                        }
                    } else {
                        Note("Asking THRØ what is waiting on you.")
                    }
                }
                .padding(.horizontal, ThroSpacing.spaceScreenGutter)
                .padding(.vertical, ThroSpacing.spacing5)
                .throReadable()
            }
        }
        .background(ThroColor.colorBackgroundPrimary.ignoresSafeArea())
        .task { await load() }
    }

    private func load() async {
        problem = nil
        do { sections = try await account.api.inbox() } catch let e as APIError { problem = e.message } catch { problem = error.localizedDescription }
    }
}

/// A registration task's three acts for whoever runs the team (PD-107): see what is missing, confirm by name a
/// requirement THRØ cannot check, and send the prepared submission. Sent is shown as sent — the league answers.
struct RegistrationTaskActions: View {
    @ObservedObject var account: AccountStore
    let task: UUID
    let reload: () -> Void
    @State private var assessed: RegistrationAssessment?
    @State private var confirming: String?
    @State private var note = ""
    @State private var said: String?
    @State private var busy = false

    var body: some View {
        VStack(alignment: .leading, spacing: ThroSpacing.spacing2) {
            if let a = assessed {
                if !a.missing.isEmpty {
                    Text("Still needs: " + a.missing.map { $0.replacingOccurrences(of: "_", with: " ") }.joined(separator: ", ") + ". The player sets these in their own profile.")
                        .thro(ThroTypography.metadata).foregroundStyle(ThroColor.colorTextSecondary)
                }
                ForEach(a.manualOutstanding, id: \.self) { requirement in
                    if confirming == requirement {
                        ThroTextField("How was the \(requirement) met?", text: $note, placeholder: "paid in cash, 14 Sep")
                        HStack(spacing: ThroSpacing.spacing2) {
                            ThroButton("Confirm \(requirement)", variant: .primary, size: .medium) { Task { await confirm(requirement) } }
                                .disabled(note.trimmingCharacters(in: .whitespaces).count < 3 || busy)
                            ThroTextButton("Not yet", tone: .quiet) { confirming = nil }
                        }
                    } else {
                        ThroButton("Confirm the \(requirement) by hand", variant: .secondary, size: .medium) { confirming = requirement; note = "" }
                            .disabled(busy)
                    }
                }
                if let submission = a.submissionId {
                    if a.state == "ready" {
                        ThroButton("Send it to the league", variant: .primary, size: .medium) { Task { await send(submission) } }.disabled(busy)
                    } else {
                        Text("Sent · \(a.state ?? "with the league") — the league answers, and only its answer registers the player.")
                            .thro(ThroTypography.metadata).foregroundStyle(ThroColor.colorTextSecondary)
                    }
                }
            } else {
                ThroButton("See what it needs", variant: .secondary, size: .medium) { Task { await assess() } }.disabled(busy)
            }
            if let said { Note(said) }
        }
        .padding(.top, ThroSpacing.spacing2)
    }

    private func assess() async {
        busy = true; defer { busy = false }
        do { assessed = try await account.api.assessRegistration(task: task); said = nil }
        catch { said = (error as? APIError)?.message ?? error.localizedDescription }
    }

    private func confirm(_ requirement: String) async {
        busy = true; defer { busy = false }
        do {
            try await account.api.confirmRequirement(task: task, requirement: requirement, note: note.trimmingCharacters(in: .whitespaces))
            confirming = nil; said = "\(requirement.capitalized) confirmed, in your name."
            assessed = try await account.api.assessRegistration(task: task)
        } catch { said = (error as? APIError)?.message ?? error.localizedDescription }
    }

    private func send(_ submission: UUID) async {
        busy = true; defer { busy = false }
        do {
            let state = try await account.api.submitRegistration(submission: submission)
            said = state == "delivered" ? "Sent. The league has it; its answer registers the player." : "Its state is now \(state)."
            assessed = try await account.api.assessRegistration(task: task)
            reload()
        } catch { said = (error as? APIError)?.message ?? error.localizedDescription }
    }
}

/// A proposed date the team owes an answer on (PD-108): both dates, from whom and why, and the answer — agree, or
/// decline with a reason. Agreeing moves nothing; the league applies what was agreed, and the fixture says so then.
struct RearrangementTaskActions: View {
    @ObservedObject var account: AccountStore
    let proposal: UUID
    let reload: () -> Void
    @State private var read: FixtureProposal?
    @State private var declining = false
    @State private var note = ""
    @State private var said: String?
    @State private var busy = false

    var body: some View {
        VStack(alignment: .leading, spacing: ThroSpacing.spacing2) {
            if let p = read {
                Text("\(p.byTeam) proposes \(ProposalWords.what(p)) instead of \(Self.when(p.scheduledAt))" + (p.reason.map { " — \($0)" } ?? ""))
                    .thro(ThroTypography.body).foregroundStyle(ThroColor.colorTextPrimary)
                if p.state == "proposed" {
                    if declining {
                        ThroTextField("Why not?", text: $note, placeholder: "we cannot raise a side that night")
                        HStack(spacing: ThroSpacing.spacing2) {
                            ThroButton("Decline", variant: .primary, size: .medium) { Task { await answer("rejected") } }
                                .disabled(note.trimmingCharacters(in: .whitespaces).count < 3 || busy)
                            ThroTextButton("Not yet", tone: .quiet) { declining = false }
                        }
                    } else {
                        HStack(spacing: ThroSpacing.spacing2) {
                            ThroButton("Agree to \(ProposalWords.what(p))", variant: .primary, size: .medium) { Task { await answer("accepted") } }.disabled(busy)
                            ThroButton("Decline", variant: .secondary, size: .medium) { declining = true; note = "" }.disabled(busy)
                        }
                    }
                } else {
                    Text(Self.standing(p.state)).thro(ThroTypography.metadata).foregroundStyle(ThroColor.colorTextSecondary)
                }
            } else {
                ThroButton("See the proposed date", variant: .secondary, size: .medium) { Task { await load() } }.disabled(busy)
            }
            if let said { Note(said) }
        }
        .padding(.top, ThroSpacing.spacing2)
    }

    static func when(_ date: Date) -> String { date.formatted(date: .abbreviated, time: .shortened) }

    static func standing(_ state: String) -> String {
        switch state {
        case "accepted": return "Agreed. The league applies it; the fixture moves when it does."
        case "applied": return "Applied by the league: the fixture has moved."
        case "declined": return "Declined."
        case "withdrawn": return "Withdrawn by the team that proposed it."
        default: return state
        }
    }

    private func load() async {
        busy = true; defer { busy = false }
        do { read = try await account.api.proposal(proposal); said = nil }
        catch { said = (error as? APIError)?.message ?? error.localizedDescription }
    }

    private func answer(_ answer: String) async {
        busy = true; defer { busy = false }
        do {
            read = try await account.api.answerProposal(proposal, answer: answer, note: declining ? note.trimmingCharacters(in: .whitespaces) : nil)
            declining = false
            said = answer == "accepted" ? "Agreed, in your name. The league applies it — until then the fixture stands where it was." : "Declined, with your reason kept."
            reload()
        } catch { said = (error as? APIError)?.message ?? error.localizedDescription }
    }
}

/// The inbox's five sections, in the order the Secretary's design puts them, with the words a person reads.
enum InboxOrder {
    static let sections = ["ACTION_REQUIRED", "DUE_TODAY", "UPCOMING", "WAITING_FOR_PLAYER", "WAITING_FOR_OPPONENT", "WAITING_FOR_LEAGUE", "COMPLETED"]
    static func title(_ key: String) -> String {
        switch key {
        case "ACTION_REQUIRED": return "Action required"
        case "DUE_TODAY": return "Due today"
        case "UPCOMING": return "Upcoming"
        case "WAITING_FOR_PLAYER": return "Waiting for a player"
        case "WAITING_FOR_OPPONENT": return "Waiting for the opponent"
        case "WAITING_FOR_LEAGUE": return "Waiting for the league"
        case "COMPLETED": return "Completed"
        default: return key.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }
    static func detail(_ item: InboxItem) -> String {
        let kind = words(item.kind)
        if let due = item.dueAt { return "\(kind) · due \(due.formatted(date: .abbreviated, time: .omitted))" }
        return "\(kind) · no deadline stated"
    }
    /// The task's kind in a person's words, not the server's identifier.
    static func words(_ kind: String) -> String {
        switch kind {
        case "registration_required": return "A registration"
        case "rearrangement_answer_due": return "A proposed date"
        case "result_submission_due": return "A result to send"
        case "consent_required": return "Consent needed"
        default: return kind.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }
    static func icon(_ kind: String) -> ThroIcon {
        switch kind {
        case "registration_required": return .shield
        case "rearrangement_answer_due": return .calendar
        case "result_submission_due": return .filePen
        case "consent_required": return .check
        default: return .bell
        }
    }
}

/// Darts the signed-in person can play, each card with the reasons the server gave.
public struct DiscoveryScreen: View {
    @ObservedObject private var account: AccountStore
    private let onBack: () -> Void
    @State private var sections: [String: [DiscoveryCard]]?
    @State private var problem: String?

    public init(account: AccountStore, onBack: @escaping () -> Void) {
        self.account = account
        self.onBack = onBack
    }

    public var body: some View {
        VStack(spacing: 0) {
            BoardHeader(title: "Darts you can play", eyebrow: "Your profile", onBack: onBack)
            ScrollView {
                VStack(alignment: .leading, spacing: ThroSpacing.spacing4) {
                    if let problem {
                        ErrorState(title: "Could not load events", what: problem, safe: "Nothing on this phone changed.", todo: "Try again when you are online.") { Task { await load() } }
                    } else if let sections {
                        if sections.values.allSatisfy(\.isEmpty) {
                            EmptyState(title: "Nothing coming up", message: "No open events in the next sixty days on THRØ yet. When an organiser opens one, it appears here with why it is offered to you.")
                        }
                        ForEach(DiscoveryOrder.sections.filter { !(sections[$0]?.isEmpty ?? true) }, id: \.self) { key in
                            SectionHeader(DiscoveryOrder.title(key), meta: "\(sections[key]?.count ?? 0)")
                            ForEach(sections[key] ?? []) { card in
                                DeskCard(icon: .trophy, title: card.name, meta: DiscoveryOrder.line(card)) {
                                    if !card.reasons.isEmpty {
                                        Text(card.reasons.joined(separator: " · ")).thro(ThroTypography.metadata).foregroundStyle(ThroColor.colorTextBrand)
                                            .fixedSize(horizontal: false, vertical: true)
                                    }
                                    EventActions(api: account.api, card: card) { Task { await load() } }
                                }
                            }
                        }
                    } else {
                        Note("Asking THRØ what you can play.")
                    }
                }
                .padding(.horizontal, ThroSpacing.spaceScreenGutter)
                .padding(.vertical, ThroSpacing.spacing5)
                .throReadable()
            }
        }
        .background(ThroColor.colorBackgroundPrimary.ignoresSafeArea())
        .task { await load() }
    }

    private func load() async {
        problem = nil
        do { sections = try await account.api.discovery() } catch let e as APIError { problem = e.message } catch { problem = error.localizedDescription }
    }
}

/// What a player does with an event from its card (PD-109): enter, withdraw, and on the day check in from this phone.
/// Every refusal is the server's words; nothing here decides eligibility.
struct EventActions: View {
    /// The server, signed in. Not the account: these acts need the wire and nothing else, so the event's own page
    /// under Discover (PD-126) uses them as they are.
    let api: ThroAPI
    let card: DiscoveryCard
    let reload: () -> Void
    @State private var page: EventPage?
    @State private var said: String?
    @State private var busy = false
    @State private var citing = false
    @State private var matches: [MatchOnRecord]?

    @State private var choosing = false
    @State private var choices: [(id: UUID, label: String)]?
    @State private var choicesSaid: String?

    private var entered: Bool { page?.you?.entered ?? card.entered }

    /// A partner from one of your teams' rosters, or a team you run — the people and sides the phone can already name.
    @ViewBuilder private var choicesList: some View {
        if let choices {
            if choices.isEmpty {
                Note(card.entrantKind == "pair" ? "No partner to pick yet: a partner is a player on a team you are in." : "You run no team on THRØ yet.")
            }
            ForEach(choices, id: \.id) { c in
                Button { Task { await enter(with: c.id) } } label: {
                    HStack { Text(c.label).thro(ThroTypography.body).foregroundStyle(ThroColor.colorTextPrimary); Spacer(); Icon(.chevronRight, size: 16).foregroundStyle(ThroColor.colorTextTertiary) }
                        .frame(minHeight: ThroSpacing.touchTargetMinimum).throRowTapTarget()
                }
                .buttonStyle(ThroPressStyle(radius: ThroSpacing.radiusCard, pressedFill: ThroColor.colorSurfaceSecondary, scales: false))
                .disabled(busy)
            }
            ThroTextButton("Leave it", tone: .quiet) { choosing = false }
        } else if let choicesSaid {
            ErrorState(title: "Your teams could not be read", what: choicesSaid,
                       safe: "You have not been entered.", todo: "Try again with a connection.",
                       onAction: { Task { await loadChoices() } })
        } else {
            Text("One moment…").thro(ThroTypography.metadata).foregroundStyle(ThroColor.colorTextSecondary)
        }
    }

    private func loadChoices() async {
        var found: [(id: UUID, label: String)] = []
        // Read and failed leaves `choices` nil (PD-137). Swallowed, it told somebody who runs three teams
        // that they run none — a false statement, louder than any spinner, on the screen that decides
        // whether they can enter at all.
        let mine: [TeamSummary]
        do { mine = try await api.myTeams(); choicesSaid = nil }
        catch {
            choicesSaid = (error as? APIError)?.message ?? "Your teams could not be read just now."
            choices = nil
            return
        }
        if card.entrantKind == "team" {
            found = mine.filter { $0.role == "admin" || $0.role == "captain" || $0.role == "vice_captain" }.map { ($0.teamId, $0.name) }
        } else {
            for t in mine {
                if let front = try? await api.teamFront(t.teamId) {
                    for m in front.roster where m.playerId != nil && m.playerId != me { found.append((m.playerId!, "\(m.name ?? "A player") · \(t.name)")) }
                }
            }
        }
        choices = found
    }

    private func enter(with choice: UUID) async {
        busy = true; defer { busy = false }
        do {
            page = card.entrantKind == "team" ? try await api.enter(event: card.eventId, team: choice) : try await api.enter(event: card.eventId, partner: choice)
            choosing = false; said = card.entrantKind == "team" ? "Entered. Any member checks the team in on the day." : "Entered as a pair. Either of you checks in on the day."
            reload()
        } catch { said = (error as? APIError)?.message ?? error.localizedDescription }
    }
    private var me: UUID? { api.session?.playerId }
    /// Your tie in the latest round, once the draw is made.
    private var myTie: EventPage.Tie? {
        guard let page, let me, let last = page.draw.map(\.round).max() else { return nil }
        return page.draw.first { $0.round == last && ($0.homeId == me || $0.awayId == me) }
    }
    private var inPlay: Bool { page.map { $0.state == "drawn" || $0.state == "in_progress" || $0.state == "complete" } ?? false }
    private var checkedIn: Bool { page?.you?.checkedIn ?? false }
    private var onTheDay: Bool { Date() >= card.startsAt.addingTimeInterval(-12 * 3600) }

    var body: some View {
        VStack(alignment: .leading, spacing: ThroSpacing.spacing2) {
            HStack(spacing: ThroSpacing.spacing2) {
                if entered {
                    if onTheDay && !checkedIn {
                        ThroButton("Check in on this phone", variant: .primary, size: .medium) { Task { await checkIn() } }.disabled(busy)
                    } else if checkedIn {
                        Text("Checked in · this phone scores it").thro(ThroTypography.metadata).foregroundStyle(ThroColor.colorTextSecondary)
                    }
                    // Before the draw only: once drawn, a player in the bracket is decided against, not withdrawn.
                    if !(page.map { $0.state != "open" && $0.state != "entries_closed" } ?? false) {
                        ThroButton("Withdraw", variant: .secondary, size: .medium) { Task { await withdraw() } }.disabled(busy || checkedIn)
                    }
                } else if card.access == "open" {
                    switch card.entrantKind {
                    case "pair":
                        ThroButton("Enter with a partner", variant: .primary, size: .medium) { choosing = true; Task { await loadChoices() } }.disabled(busy)
                    case "team":
                        ThroButton("Enter a team you run", variant: .primary, size: .medium) { choosing = true; Task { await loadChoices() } }.disabled(busy)
                    default:
                        ThroButton("Enter", variant: .primary, size: .medium) { Task { await enter() } }.disabled(busy)
                    }
                }
            }
            if choosing, !entered {
                choicesList
            }
            if entered && inPlay, let page {
                tieLine(page)
            }
            if let said { Note(said) }
        }
        .task { if card.entered && page == nil { page = try? await api.event(card.eventId) } }
    }

    /// Where you stand in the bracket (PD-111): your tie, its standing, and — once scored on THRØ — Name the match.
    @ViewBuilder private func tieLine(_ page: EventPage) -> some View {
        if page.state == "complete", let champion = page.winnerId {
            Text(champion == me ? "You won it." : "Over — \(page.draw.first { $0.winnerId == champion }.map { $0.homeId == champion ? ($0.home ?? "somebody") : ($0.away ?? "somebody") } ?? "somebody") won it.")
                .thro(ThroTypography.body).foregroundStyle(ThroColor.colorTextPrimary)
        } else if let t = myTie {
            let opponent = (t.homeId == me ? t.away : t.home) ?? "a player"
            if t.isBye {
                Text("Round \(t.round): a bye — you go through.").thro(ThroTypography.body).foregroundStyle(ThroColor.colorTextPrimary)
            } else if let w = t.winnerId {
                Text("Round \(t.round) v \(opponent): " + (w == me ? "you went through" : "you went out") + " · \(t.outcome ?? "")")
                    .thro(ThroTypography.body).foregroundStyle(ThroColor.colorTextPrimary)
            } else {
                Text("Round \(t.round): v \(opponent) · to be played").thro(ThroTypography.body).foregroundStyle(ThroColor.colorTextPrimary)
                if citing {
                    if let matches {
                        let ours = matches.filter { m in m.winner != nil && m.seats.contains { !$0.you && $0.name == opponent } }
                        if ours.isEmpty { Text("No finished match of yours against \(opponent) on THRØ yet.").thro(ThroTypography.metadata).foregroundStyle(ThroColor.colorTextSecondary) }
                        ForEach(ours.prefix(5)) { m in
                            Button { Task { await cite(t, m.matchId) } } label: {
                                HStack {
                                    Text(m.seats.map { $0.name ?? "A player" }.joined(separator: " v ")).thro(ThroTypography.body).foregroundStyle(ThroColor.colorTextPrimary)
                                    Spacer()
                                    Text(m.openedAt.formatted(date: .abbreviated, time: .shortened)).thro(ThroTypography.metadata).foregroundStyle(ThroColor.colorTextSecondary)
                                }
                                .frame(minHeight: ThroSpacing.touchTargetMinimum)
                                .throRowTapTarget()
                            }
                            .buttonStyle(ThroPressStyle(radius: ThroSpacing.radiusCard, pressedFill: ThroColor.colorSurfaceSecondary, scales: false))
                            .disabled(busy)
                        }
                        ThroTextButton("Leave it", tone: .quiet) { citing = false }
                    } else {
                        Text("One moment…").thro(ThroTypography.metadata).foregroundStyle(ThroColor.colorTextSecondary)
                    }
                } else {
                    ThroButton("Name the match", variant: .secondary, size: .medium) {
                            citing = true
                            // Left nil when the read fails (PD-137), so nothing claims this player has no
                            // finished match on THRØ when the truth is that THRØ could not be asked.
                            Task {
                                do { matches = try await api.myMatches() }
                                catch { said = (error as? APIError)?.message ?? "Your matches could not be read just now."; citing = false }
                            }
                        }.disabled(busy)
                }
            }
        } else {
            Text("You are not in the current round.").thro(ThroTypography.metadata).foregroundStyle(ThroColor.colorTextSecondary)
        }
    }

    private func cite(_ tie: EventPage.Tie, _ match: UUID) async {
        busy = true; defer { busy = false }
        do {
            page = try await api.citeTie(event: card.eventId, tie: tie.tieId, match: match)
            citing = false
            said = "Named. The winner is what the record says."
        } catch { said = (error as? APIError)?.message ?? error.localizedDescription }
    }

    private func enter() async {
        busy = true; defer { busy = false }
        do { page = try await api.enter(event: card.eventId); said = "Entered. Check in on this phone on the day."; reload() }
        catch { said = (error as? APIError)?.message ?? error.localizedDescription }
    }

    private func withdraw() async {
        busy = true; defer { busy = false }
        do { page = try await api.withdraw(event: card.eventId); said = "Withdrawn. Your place is open to somebody else."; reload() }
        catch { said = (error as? APIError)?.message ?? error.localizedDescription }
    }

    private func checkIn() async {
        busy = true; defer { busy = false }
        do {
            let grant = try await api.checkIn(event: card.eventId)
            page = try await api.event(card.eventId)
            said = "Checked in. This phone may score the event until \(grant.expiresAt.formatted(date: .abbreviated, time: .shortened)), signal or none."
        } catch { said = (error as? APIError)?.message ?? error.localizedDescription }
    }
}

enum DiscoveryOrder {
    static let sections = ["YOU_ARE_ELIGIBLE", "THIS_WEEKEND", "CLOSING_SOON", "NEAR_YOU", "YOUR_SERIES", "ALREADY_ENTERED", "ALL"]
    static func title(_ key: String) -> String {
        switch key {
        case "YOU_ARE_ELIGIBLE": return "You can enter"
        case "THIS_WEEKEND": return "This weekend"
        case "CLOSING_SOON": return "Entries closing soon"
        case "NEAR_YOU": return "Near your team"
        case "YOUR_SERIES": return "In a series you play"
        case "ALREADY_ENTERED": return "You are entered"
        case "ALL": return "Everything coming up"
        default: return key.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }
    static func line(_ card: DiscoveryCard) -> String {
        var parts = [card.startsAt.formatted(date: .abbreviated, time: .shortened)]
        if let venue = card.venue { parts.append(venue) } else if let locality = card.locality { parts.append(locality) }
        if let spots = card.spotsRemaining { parts.append(spots == 0 ? "full" : "\(spots) places left") } else { parts.append("places not stated") }
        return parts.joined(separator: " · ")
    }
}


// MARK: - Friends (V028)

/// Friends: a code given in person, entered by the other. No search, because a search is how a
/// stranger finds a child. The screen shows the code big enough to read across a table and lets it
/// be shared; a field takes one; the list is who you have. Every refusal is the server's own
/// sentence, shown as it came.
public struct FriendsScreen: View {
    @ObservedObject private var account: AccountStore
    private let onBack: () -> Void
    @State private var code = ""
    @State private var removing: Friend?

    public init(account: AccountStore, onBack: @escaping () -> Void) {
        self.account = account
        self.onBack = onBack
    }

    public var body: some View {
        VStack(spacing: 0) {
            BoardHeader(title: "Friends", eyebrow: "Your profile", onBack: onBack)
            ScrollView {
                VStack(alignment: .leading, spacing: ThroSpacing.spacing3) {
                    inviteSlate
                    SectionHeader("Enter a friend's code").padding(.top, ThroSpacing.spaceSectionGap)
                    HStack(spacing: ThroSpacing.spacing3) {
                        ThroTextField("Code", text: $code, placeholder: "ABCD EFGH")
                            .autocorrectionDisabled()
                        ThroButton("Add", variant: .primary, size: .large) {
                            let entered = code
                            Task { if await account.acceptCode(entered) { code = "" } }
                        }
                        .disabled(FriendsScreen.normalised(code).count != 8)
                        .padding(.top, 22)
                    }
                    if let note = account.friendsNote {
                        Snackbar(note, tone: .error)
                    }
                    SectionHeader("Your friends", meta: account.friends.map { "\($0.count)" }).padding(.top, ThroSpacing.spaceSectionGap)
                    if let friends = account.friends {
                        if friends.isEmpty {
                            Text("Nobody yet. Give your code to somebody, or enter theirs.")
                                .thro(ThroTypography.body).foregroundStyle(ThroColor.colorTextSecondary)
                        } else {
                            ThroDivider()
                            ForEach(friends) { friend in
                                HStack(spacing: ThroSpacing.spacing3) {
                                    PlayerIdentity(PlayerRef(name: friend.displayName), size: .small)
                                    Spacer(minLength: 0)
                                    Text("since \(friend.since.formatted(.dateTime.day().month(.abbreviated)))")
                                        .thro(ThroTypography.metadata).foregroundStyle(ThroColor.colorTextSecondary)
                                    Button { removing = friend } label: { Icon(.x, size: 16).foregroundStyle(ThroColor.colorTextSecondary).throTapTarget() }
                                        .buttonStyle(ThroPressStyle(radius: 22))
                                        .accessibilityLabel("Remove \(friend.displayName)")
                                }
                                .padding(.vertical, ThroSpacing.spacing2)
                                ThroDivider()
                            }
                        }
                    } else {
                        HStack { ProgressView(); Text("Reading").thro(ThroTypography.body).foregroundStyle(ThroColor.colorTextSecondary) }
                    }
                    Note("A friend sees your name and that you are friends. Nothing else is shared yet; what friends can do together comes next, and it will be said here when it does.")
                        .padding(.top, ThroSpacing.spaceSectionGap)
                }
                .padding(.horizontal, ThroSpacing.spaceScreenGutter)
                .padding(.vertical, ThroSpacing.spacing5)
                .throReadable()
            }
        }
        .background(ThroColor.colorBackgroundPrimary.ignoresSafeArea())
        .task { if account.friends == nil { await account.loadFriends() } }
        .confirmationDialog("Remove this friend?", isPresented: Binding(get: { removing != nil }, set: { if !$0 { removing = nil } }), titleVisibility: .visible) {
            if let friend = removing {
                Button("Remove \(friend.displayName)", role: .destructive) { Task { await account.removeFriend(friend) }; removing = nil }
            }
            Button("Keep", role: .cancel) { removing = nil }
        } message: { Text("They stop being your friend on THRØ, both ways. Either of you can start again with a new code.") }
    }

    private var inviteSlate: some View {
        ThroSlate(seed: 33) {
            VStack(alignment: .leading, spacing: ThroSpacing.spacing3) {
                Eyebrow("Your code", color: ThroColor.colorTextOnBoardSecondary)
                if let invite = account.invite {
                    Text(invite.spoken)
                        .thro(ThroTypography.display.family(.sport).weight(.bold).tracking(em: 0.08))
                        .foregroundStyle(ThroColor.colorTextOnBoard)
                        .minimumScaleFactor(0.6)
                        .lineLimit(1)
                        .accessibilityLabel("Your friend code, \(invite.code.map(String.init).joined(separator: " "))")
                    Text("Say it or show it to a friend. Good until \(invite.expiresAt.formatted(.dateTime.day().month(.abbreviated))), and for one friend.")
                        .thro(ThroTypography.metadata).foregroundStyle(ThroColor.colorTextOnBoardSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: ThroSpacing.spacing3) {
                        ShareLink(item: "My THRØ friend code is \(invite.spoken) — enter it in THRØ under You → Friends.") {
                            Text("SHARE").thro(ThroTypography.labelStrong.uppercase(true).tracking(em: 0.06))
                                .foregroundStyle(ThroColor.colorTextOnBoard).padding(.horizontal, ThroSpacing.spacing4)
                        }
                        .buttonStyle(ChalkKeyStyle(.lit, minHeight: ThroSpacing.touchTargetMinimum, seedAngle: 41))
                        .fixedSize()
                        Button { Task { await account.makeInvite() } } label: {
                            Text("NEW CODE").thro(ThroTypography.labelStrong.uppercase(true).tracking(em: 0.06))
                                .foregroundStyle(ThroColor.colorTextOnBoard).padding(.horizontal, ThroSpacing.spacing4)
                        }
                        .buttonStyle(ChalkKeyStyle(.field, minHeight: ThroSpacing.touchTargetMinimum, seedAngle: 97))
                        .fixedSize()
                    }
                } else {
                    Text("Make a code and give it to a friend in person. That is how friends start on THRØ: nobody is searched for.")
                        .thro(ThroTypography.body).foregroundStyle(ThroColor.colorTextOnBoardSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Button { Task { await account.makeInvite() } } label: {
                        Text("MAKE MY CODE").thro(ThroTypography.labelStrong.uppercase(true).tracking(em: 0.06))
                            .foregroundStyle(ThroColor.colorTextOnBoard).padding(.horizontal, ThroSpacing.spacing4)
                    }
                    .buttonStyle(ChalkKeyStyle(.lit, minHeight: ThroSpacing.touchTargetMinimum, seedAngle: 41))
                    .fixedSize()
                }
            }
            .padding(ThroSpacing.spacing5)
        }
    }

    /// Case, spaces and dashes are not part of a code.
    static func normalised(_ raw: String) -> String {
        raw.uppercased().filter { !$0.isWhitespace && $0 != "-" }
    }
}
