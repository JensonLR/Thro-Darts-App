import SwiftUI
import ThroDesign
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

    private enum Sub { case inbox, discovery, friends }

    public init(account: AccountStore, onBack: @escaping () -> Void) {
        self.account = account
        self.onBack = onBack
    }

    public var body: some View {
        if showing == .inbox {
            InboxScreen(account: account) { showing = nil }
        } else if showing == .discovery {
            DiscoveryScreen(account: account) { showing = nil }
        } else if showing == .friends {
            FriendsScreen(account: account) { showing = nil }
        } else {
            VStack(spacing: 0) {
                TopBar("Account", onBack: onBack, large: true)
                ScrollView {
                    VStack(alignment: .leading, spacing: ThroSpacing.spacing4) {
                        switch account.state {
                        case .signedOut: signedOut
                        case .busy(let what): busy(what)
                        case .signedIn(let profile): signedIn(profile)
                        case .failed(let why, let was): failed(why, wasSignedIn: was)
                        }
                        server
                    }
                    .padding(.horizontal, ThroSpacing.spaceScreenGutter)
                    .padding(.bottom, ThroSpacing.spacing6)
                }
            }
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
            if editingName {
                ThroTextField("Your name", text: $name, placeholder: "How your league knows you",
                              helper: "Shown to the teams and leagues you are part of. Change it any time.")
                HStack(spacing: ThroSpacing.spacing3) {
                    ThroButton("Save", variant: .primary, size: .medium) { editingName = false; Task { await account.setDisplayName(name) } }
                    ThroButton("Cancel", variant: .ghost, size: .medium) { editingName = false }
                }
            } else {
                SettingsRow(icon: .circleUser, label: "Name", value: profile.named ? (profile.displayName ?? "") : "Not set yet")
                ThroTextButton(profile.named ? "Change your name" : "Set your name") { name = profile.named ? (profile.displayName ?? "") : ""; editingName = true }
            }
            SettingsRow(icon: .shield, label: "Age band", value: ageBandCopy(profile.ageBand))
            if profile.ageBand == "unknown" {
                Note("THRØ does not guess ages. Say you are 18 or over and friends unlock; under 18 is welcome to play, and a guardian's confirmation for the rest is coming.")
                ThroButton("I am 18 or over", variant: .secondary, size: .medium, icon: .check) { Task { await account.declareAdult() } }
            }
            SectionHeader("Friends")
            LinkRow(icon: .users, label: "Friends", value: account.friends.map { $0.isEmpty ? "None yet" : "\($0.count)" } ?? "Codes, given in person") { showing = .friends }
            SectionHeader("Ways in")
            waysIn(profile.credentials ?? 1)
            ThroButton("Add a passkey", variant: .secondary, size: .medium, icon: .lock) { Task { await account.usePasskey() } }
            ThroTextButton("Add Sign in with Apple", tone: .quiet) { Task { await account.signInWithApple() } }
            if account.configuration.googleClientID != nil {
                ThroTextButton("Add Sign in with Google", tone: .quiet) { Task { await account.signInWithGoogle() } }
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
            TopBar("Your inbox", onBack: onBack, large: true)
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
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(item.reason).thro(ThroTypography.body).foregroundStyle(ThroColor.colorTextPrimary)
                                    Text(InboxOrder.detail(item)).thro(ThroTypography.metadata).foregroundStyle(ThroColor.colorTextSecondary)
                                }
                                .frame(minHeight: 52, alignment: .leading)
                                .overlay(alignment: .bottom) { Rectangle().fill(ThroColor.colorBorderDefault).frame(height: 1) }
                            }
                        }
                    } else {
                        Note("Asking THRØ what is waiting on you.")
                    }
                }
                .padding(.horizontal, ThroSpacing.spaceScreenGutter)
            }
        }
        .task { await load() }
    }

    private func load() async {
        problem = nil
        do { sections = try await account.api.inbox() } catch let e as APIError { problem = e.message } catch { problem = error.localizedDescription }
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
        let kind = item.kind.replacingOccurrences(of: "_", with: " ")
        if let due = item.dueAt { return "\(kind) · due \(due.formatted(date: .abbreviated, time: .omitted))" }
        return "\(kind) · no deadline stated"
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
            TopBar("Darts you can play", onBack: onBack, large: true)
            ScrollView {
                VStack(alignment: .leading, spacing: ThroSpacing.spacing4) {
                    if let problem {
                        ErrorState(title: "Could not load events", what: problem, safe: "Nothing on this phone changed.", todo: "Try again when you are online.") { Task { await load() } }
                    } else if let sections {
                        let all = sections["ALL"] ?? []
                        if all.isEmpty {
                            EmptyState(title: "Nothing coming up", message: "No open events in the next sixty days on THRØ yet. When an organiser opens one, it appears here with why it is offered to you.")
                        }
                        ForEach(DiscoveryOrder.sections.filter { !(sections[$0]?.isEmpty ?? true) }, id: \.self) { key in
                            SectionHeader(DiscoveryOrder.title(key), meta: "\(sections[key]?.count ?? 0)")
                            ForEach(sections[key] ?? []) { card in
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(card.name).thro(ThroTypography.heading3).foregroundStyle(ThroColor.colorTextPrimary)
                                    Text(DiscoveryOrder.line(card)).thro(ThroTypography.label).foregroundStyle(ThroColor.colorTextSecondary)
                                    ForEach(card.reasons, id: \.self) { reason in
                                        Text("· \(reason)").thro(ThroTypography.metadata).foregroundStyle(ThroColor.colorTextSecondary)
                                    }
                                }
                                .padding(.vertical, ThroSpacing.spacing2)
                                .overlay(alignment: .bottom) { Rectangle().fill(ThroColor.colorBorderDefault).frame(height: 1) }
                            }
                        }
                    } else {
                        Note("Asking THRØ what you can play.")
                    }
                }
                .padding(.horizontal, ThroSpacing.spaceScreenGutter)
            }
        }
        .task { await load() }
    }

    private func load() async {
        problem = nil
        do { sections = try await account.api.discovery() } catch let e as APIError { problem = e.message } catch { problem = error.localizedDescription }
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
            TopBar("Friends", eyebrow: "Account", onBack: onBack)
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
                        ShareLink(item: "My THRØ friend code is \(invite.spoken) — enter it under Account → Friends.") {
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
