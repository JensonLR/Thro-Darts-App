import SwiftUI
import ThroDesign
import ThroJournal
import ThroNet
import ThroTokens

// Your profile, and the way out of THRØ.
//
// **What was wrong, the first time.** Setting a name meant: You, SIGN IN, scroll a settings list,
// find a row called Name, tap a text link called *Set your name*, get a field, type, tap Save. Seven
// steps to type two words, and no picture at any point.
//
// **What was wrong, the second time.** The founder: *"poor journey for profile experience overall
// too just very clunky & poorly designed"*, and then *"still won't let me delete full account."*
// Two causes, one of them invisible. The page was grey rows on a system list. And every change to
// the account set it to busy, which took this page off the screen while a name saved and took the
// delete screen off the screen while an erasure ran — so an erasure that failed reported its failure
// to a screen that no longer existed, and the person landed back here with the account still there
// and no word about why. (The failure itself was V031 refusing anybody who held a friend code they
// had not given out yet; V033 is that fix. `AccountStore.working` is this one.)
//
// **What it is now.** The person on the brand field — their mark, their name in chalk where it is
// changed, and who sees it — and under it the cards the rest of the account area is made of.
// Changes happen where they are asked for, and the page stays put while they do.

/// Where an account's own picture is kept, and the rule about who may have one.
///
/// **It is kept on this phone.** THRØ's server stores no images of anybody — there is no bucket, no
/// URL and nothing to leak — so an account's picture lives in the same local store the club badges
/// use, and the screen says so rather than implying it follows the person to a new phone. When that
/// changes, this is the one place that has to.
public enum AccountPicture {
    /// Keyed by account, so signing in as somebody else on a shared phone never inherits a face.
    public static func key(_ accountId: UUID) -> String { "thro.account.picture.\(accountId.uuidString)" }

    public static func assetId(_ accountId: UUID) -> String? {
        UserDefaults.standard.string(forKey: key(accountId))
    }

    /// The same rule as everywhere else in THRØ: a picture is an adult's (PD-014). Somebody whose
    /// age is not recorded is treated as a child, because what is unknown is whether they are one.
    public static func refusal(ageBand: String) -> String? {
        guard !ImagePolicy.mayHavePicture(ageBand: ageBand) else { return nil }
        return ageBand == "minor"
            ? "THRØ holds no pictures of under-18s. Your mark is your initials."
            : "Say you are 18 or over and you can add a picture. Until then your mark is your initials."
    }

    /// Stores the bytes and remembers the id; passing nil takes the picture off and deletes it.
    @discardableResult
    public static func set(_ data: Data?, for accountId: UUID, in store: ImageStore?) -> String? {
        let old = assetId(accountId)
        if let data, let store, let id = try? store.put(data) {
            UserDefaults.standard.set(id, forKey: key(accountId))
            if let old, old != id { try? store.delete(old) }
            return id
        }
        if data == nil {
            UserDefaults.standard.removeObject(forKey: key(accountId))
            if let old, let store { try? store.delete(old) }
        }
        return nil
    }

    /// Everything this phone kept about that account's face. Called when the account is erased.
    public static func forget(_ accountId: UUID, in store: ImageStore?) {
        set(nil, for: accountId, in: store)
    }
}

/// Your profile: the mark, the name, the age band, the people and ways in around them, the way out.
public struct YourProfileScreen: View {
    @ObservedObject private var account: AccountStore
    /// The profile the page was opened on. What it shows is the account's own profile while there
    /// is one (`profile`), so a saved name or a declared age appears as soon as it lands.
    private let opened: Profile
    /// Which list the page was opened on, if any — the You tab's FRIENDS opens straight on Friends.
    private let openedOn: Sub?
    private let images: ImageStore?
    private let picture: (String?) -> Image?
    private let onBack: () -> Void

    @AppStorage(Appearance.storageKey) private var appearanceRaw: String = Appearance.system.rawValue
    @State private var name: String
    @State private var picked: Data?
    @State private var removed = false
    @State private var deleting = false
    @State private var showing: Sub?
    @FocusState private var editingName: Bool
    /// PD-050: who this person has asked not to hear from. Owned by this page rather than passed into it,
    /// because the list is read when the page behind the row is opened and is of no use to anything else.
    @StateObject private var safety = SafetyModel()

    /// The lists that used to live behind a separate Account screen, and the blocked list that has joined
    /// them (PD-050). They are about the person, so they are reached from the page about the person.
    public enum Sub: Sendable { case friends, inbox, discovery, blocked }

    /// The account this page is about. `Profile.accountId` is optional because a development
    /// principal has none; a page about nobody is not a page, so the caller passes one that has one.
    private let accountId: UUID

    public init(account: AccountStore, profile: Profile, accountId: UUID, opening: Sub? = nil,
                images: ImageStore?, picture: @escaping (String?) -> Image?, onBack: @escaping () -> Void) {
        self.account = account
        self.opened = profile
        self.openedOn = opening
        self.accountId = accountId
        self.images = images
        self.picture = picture
        self.onBack = onBack
        _name = State(initialValue: profile.named ? (profile.displayName ?? "") : "")
        _showing = State(initialValue: opening)
    }

    /// The account's own profile while there is one; the one the page opened on once there is not,
    /// because an erasure finishes on this page and the page should not blank itself first.
    private var profile: Profile { account.profile ?? opened }

    private var assetId: String? { AccountPicture.assetId(accountId) }

    /// The initials the mark falls back to. The same two-letter rule the rosters use, so a person is
    /// the same object on their own page as in a list.
    var initials: String {
        let words = name.split(separator: " ").filter { !$0.isEmpty }
        let letters = words.prefix(2).compactMap { $0.first }
        return letters.isEmpty ? "?" : String(letters).uppercased()
    }

    public var body: some View {
        Group {
            if let showing {
                list(showing)
            } else if deleting {
                DeleteAccountScreen(account: account) {
                    AccountPicture.forget(accountId, in: images)
                    onBack()
                } onCancel: { deleting = false }
            } else {
                page
            }
        }
        .throAppearance(Appearance(stored: appearanceRaw))
    }

    /// One of the lists about the person. Back from the list the page was opened on goes back to
    /// where the person came from — FRIENDS on the You tab lands on Friends, and its back button
    /// should not take a detour through a page they never asked for.
    @ViewBuilder private func list(_ part: Sub) -> some View {
        let back = { if openedOn == part { onBack() } else { showing = nil } }
        switch part {
        case .friends: FriendsScreen(account: account, onBack: back)
        case .inbox: InboxScreen(account: account, onBack: back)
        case .discovery: DiscoveryScreen(account: account, onBack: back)
        case .blocked: BlockedAccountsScreen(safety: safety, api: account.api, onBack: back)
        }
    }

    private var page: some View {
        ScrollView {
            VStack(spacing: 0) {
                hero
                VStack(alignment: .leading, spacing: ThroSpacing.spaceSectionGap) {
                    if let problem = account.problem {
                        Snackbar(problem, tone: .error, actionLabel: "OK") { account.dismissProblem() }
                    }
                    band
                    CardGroup("Friends") {
                        CardRow(icon: .users, label: "Friends", value: friendsLine) { showing = .friends }
                        CardDivider()
                        // PD-050: blocking is the other half of who may reach you, so it sits beside the
                        // people who can — not in a settings list somebody would have to suspect exists.
                        CardRow(icon: .shield, label: "Blocked", value: blockedLine) { showing = .blocked }
                    }
                    waysIn
                    CardGroup("From THRØ") {
                        CardRow(icon: .bell, label: "Your inbox", value: "Tasks waiting on you") { showing = .inbox }
                        CardDivider()
                        CardRow(icon: .compass, label: "Darts you can play", value: "Events, with why each is there") {
                            showing = .discovery
                        }
                    }
                    leaving
                }
                .padding(.horizontal, ThroSpacing.spaceScreenGutter)
                .padding(.top, ThroSpacing.spacing5)
                .padding(.bottom, ThroSpacing.spacing7)
                .throReadable()
                .frame(maxWidth: .infinity)
                .background(ThroColor.colorBackgroundPrimary)
            }
        }
        // The field runs up under the clock, as it does on Settings.
        .throBrandFieldBehind()
        .task { if account.friends == nil { await account.loadFriends() } }
    }

    // MARK: - the head: a face and a name, both changed where they sit

    /// The top of the page: the brand field, and on it the person.
    private var hero: some View {
        VStack(alignment: .leading, spacing: 0) {
            PageBar(onBack: { commitName(); onBack() }, ink: ThroColor.throChalk)
            VStack(alignment: .leading, spacing: ThroSpacing.spacing4) {
                Eyebrow("Your profile", color: ThroColor.throChalk.opacity(0.78))
                PicturePicker(subject: .person(initials: initials), size: 88,
                              current: picture(assetId),
                              refusedBecause: AccountPicture.refusal(ageBand: profile.ageBand),
                              picked: $picked, removed: $removed, onBoard: true)
                    .onChange(of: picked) { _, data in
                        guard let data else { return }
                        AccountPicture.set(data, for: accountId, in: images)
                        picked = nil
                    }
                    .onChange(of: removed) { _, gone in
                        guard gone else { return }
                        AccountPicture.set(nil, for: accountId, in: images)
                        removed = false
                    }
                VStack(alignment: .leading, spacing: ThroSpacing.spacing2) {
                    nameField
                    status
                }
            }
            .padding(.horizontal, ThroSpacing.spaceScreenGutter)
            .padding(.top, ThroSpacing.spacing1)
            .padding(.bottom, ThroSpacing.spacing6)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(ThroColor.colorBackgroundBrand)
        .onChange(of: editingName) { was, now in if was && !now { commitName() } }
    }

    /// The name IS the field: typed where it is read, in chalk on the board, and committed when the
    /// field is left — which is what every other field on the phone does. No row, no Save button.
    private var nameField: some View {
        HStack(spacing: ThroSpacing.spacing3) {
            TextField("", text: $name, prompt: Text("Your name").foregroundStyle(ThroColor.throChalk.opacity(0.55)))
                .thro(ThroTypography.heading1.family(.sport).weight(.bold).tracking(em: 0))
                .foregroundStyle(ThroColor.throChalk)
                .tint(ThroColor.throChalk)
                .textContentType(.name)
                .autocorrectionDisabled()
                .submitLabel(.done)
                .focused($editingName)
                .onSubmit(commitName)
                .accessibilityLabel("Your name")
                .accessibilityHint("Shown to the teams and leagues you are part of")
            if !editingName {
                // Says the name can be changed where it sits, which a heading otherwise would not.
                Icon(.pencilLine, size: 18)
                    .foregroundStyle(ThroColor.throChalk.opacity(0.78))
                    .accessibilityHidden(true)
            }
        }
        .padding(.vertical, ThroSpacing.spacing2)
        .overlay(alignment: .bottom) {
            // A chalk rule under it, so it reads as something written on the board, not a box.
            ChalkRule(weight: 2, seedAngle: 17).fill(ThroColor.colorMarkOnBoard)
                .frame(height: 3)
        }
    }

    /// Under the name: who sees it — or, while something is being done to the account, what.
    @ViewBuilder private var status: some View {
        if let working = account.working {
            HStack(spacing: ThroSpacing.spacing2) {
                ProgressView().controlSize(.small).tint(ThroColor.throChalk)
                Text(working)
                    .thro(ThroTypography.metadata)
                    .foregroundStyle(ThroColor.throChalk.opacity(0.78))
            }
            .accessibilityElement(children: .combine)
        } else {
            Text(YourProfileScreen.nameNote(named: profile.named))
                .thro(ThroTypography.metadata)
                .foregroundStyle(ThroColor.throChalk.opacity(0.78))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    static func nameNote(named: Bool) -> String {
        named ? "Shown to the teams and leagues you are part of. Change it any time."
              : "Tap to type it. This is how a team names you in a lineup."
    }

    private func commitName() {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != (profile.displayName ?? "") else { return }
        Task { await account.setDisplayName(trimmed) }
    }

    // MARK: - the cards

    @ViewBuilder private var band: some View {
        if profile.ageBand == "unknown" {
            CardGroup("Your age band",
                      footnote: "THRØ does not guess ages. Saying you are 18 or over unlocks friends and a picture; "
                          + "under 18 is welcome to play, and a guardian's confirmation for the rest is coming.") {
                CardRow(icon: .check, label: "I am 18 or over", value: "Said once, by you", leads: false) {
                    Task { await account.declareAdult() }
                }
            }
            .disabled(account.working != nil)
        } else {
            CardGroup("Your age band") {
                CardInfoRow(icon: .shield, label: "Age band", value: profile.ageBand == "adult" ? "18 or over" : "Under 18")
            }
        }
    }

    /// What the Blocked row says before it is opened. Nothing is fetched to fill it in: asking THRØ who
    /// somebody blocked, to put a number on a row they may never tap, is a request spent on nothing. Once
    /// the list has been opened the count is known, and then the count is the truer thing to say.
    private var blockedLine: String {
        safety.blocked.isEmpty ? "Anyone you never want to hear from" : "\(safety.blocked.count)"
    }

    private var friendsLine: String {
        guard let friends = account.friends else { return "Codes, given in person" }
        if friends.isEmpty { return "None yet. Codes are given in person" }
        return friends.count == 1 ? "1 friend" : "\(friends.count) friends"
    }

    /// How many ways into this account there are, and why one is not enough (PD-032).
    static func waysInNote(_ n: Int) -> String {
        n <= 1
            ? "One way into this account. Lose it and the account is lost: THRØ has no email or phone "
              + "recovery, on purpose. Add a passkey or a second sign-in above."
            : "\(n) ways into this account. If one is lost, another still gets you in."
    }

    private var waysIn: some View {
        CardGroup("Ways in", footnote: YourProfileScreen.waysInNote(profile.credentials ?? 1)) {
            CardRow(icon: .lock, label: "Add a passkey", leads: false) { Task { await account.usePasskey() } }
            CardDivider()
            // Apple's own mark, as Sign in with Apple requires of a control that starts it.
            CardRow(icon: nil, symbol: "apple.logo", label: "Add Sign in with Apple", leads: false) {
                Task { await account.signInWithApple() }
            }
            if account.configuration.googleClientID != nil {
                CardDivider()
                CardRow(icon: .user, label: "Add Sign in with Google", leads: false) {
                    Task { await account.signInWithGoogle() }
                }
            }
        }
        .disabled(account.working != nil)
    }

    private var leaving: some View {
        CardGroup("Leaving",
                  footnote: "Deleting takes your name, your sign-ins and your friends out of THRØ for good. "
                      + "The next screen says exactly what goes and what stays.") {
            CardRow(icon: .smartphone, label: "Sign out of this phone", leads: false) {
                Task { await account.signOut(); onBack() }
            }
            CardDivider()
            // Apple requires an account that can be made in an app to be deletable in it, and so
            // does the law. It is a row rather than something hidden behind support: a person who
            // wants out should not have to ask anybody.
            CardRow(icon: .circleX, label: "Delete your account", tone: .destructive) {
                commitName(); deleting = true
            }
        }
        .disabled(account.working != nil)
    }
}

/// Erasure (V031, V033), said in words before it is done — and after.
///
/// **Why it lists what stays.** A match is two people's record. Telling somebody "everything will be
/// deleted" and then keeping the leg they played against their mate would be a lie; telling them
/// nothing and keeping it would be worse. So the screen says both halves, and the half that stays
/// is the half that names nobody once this has run.
///
/// **Why it says what was done.** A person who exercises a right is owed an account of what was
/// done with it (UK GDPR Art 12(3)). So when the server answers, this screen reads its counts back —
/// the ways in destroyed, the sessions ended — before the person leaves it.
public struct DeleteAccountScreen: View {
    @ObservedObject private var account: AccountStore
    private let onErased: () -> Void
    private let onCancel: () -> Void

    @AppStorage(Appearance.storageKey) private var appearanceRaw: String = Appearance.system.rawValue
    @State private var confirming = false
    @State private var problem: String?
    @State private var working = false
    /// What the server destroyed, once it has.
    @State private var erased: ThroAPI.Erasure?

    public init(account: AccountStore, onErased: @escaping () -> Void, onCancel: @escaping () -> Void) {
        self.account = account
        self.onErased = onErased
        self.onCancel = onCancel
    }

    /// What is destroyed. Every line is something the server actually blanks or revokes in V031.
    public static let goes = [
        "Your name, and your age band.",
        "Every way you sign in: Apple, Google and any passkey.",
        "Every session, on this phone and any other, at once.",
        "Your friends, and any friend code you have given out.",
        "Your claim on your player record, so nothing about you can be shown again.",
    ]

    /// What stays, and why. Honest about the part that is not the person's alone to erase.
    public static let stays = [
        "Matches you have played. A leg is the other player's record too, and a league's table "
            + "stands on it — so the result stays, with no name on it and nothing pointing back to you.",
        "Matches scored on this phone. They were never sent anywhere unless you sent them; delete "
            + "them from Home if you want them gone as well.",
    ]

    public static let finality =
        "This cannot be undone. Signing in again with the same Apple ID makes a brand new account "
        + "with nothing in it."

    /// Said once it is done.
    public static let afterwards =
        "Matches you played stay, with no name on them. Matches scored on this phone are still here. "
        + "You can sign in again at any time; it will be a new account with nothing in it."

    public var body: some View {
        VStack(spacing: 0) {
            BoardHeader(title: erased == nil ? "Delete your account" : "Your account is deleted",
                        eyebrow: "Your profile", onBack: erased == nil ? onCancel : nil)
            ScrollView {
                VStack(alignment: .leading, spacing: ThroSpacing.spaceSectionGap) {
                    if let erased {
                        done(erased)
                    } else {
                        ask
                    }
                }
                .padding(.horizontal, ThroSpacing.spaceScreenGutter)
                .padding(.top, ThroSpacing.spacing5)
                .padding(.bottom, ThroSpacing.spacing7)
                .throReadable()
            }
        }
        .background(ThroColor.colorBackgroundPrimary.ignoresSafeArea())
        .throAppearance(Appearance(stored: appearanceRaw))
        // The second ask names what is about to happen rather than saying "Are you sure?", which is
        // a question with no information in it.
        .confirmationDialog("Delete your THRØ account?", isPresented: $confirming, titleVisibility: .visible) {
            Button("Delete it for good", role: .destructive) { erase() }
            Button("Keep it", role: .cancel) {}
        } message: {
            Text(DeleteAccountScreen.finality)
        }
    }

    @ViewBuilder private var ask: some View {
        if let problem {
            Snackbar(problem, tone: .error)
        }
        CardGroup("What goes") {
            ForEach(Array(DeleteAccountScreen.goes.enumerated()), id: \.offset) { index, line in
                if index > 0 { CardDivider() }
                CardLine(icon: .circleX, tone: .destructive, text: line)
            }
        }
        CardGroup("What stays, and why") {
            ForEach(Array(DeleteAccountScreen.stays.enumerated()), id: \.offset) { index, line in
                if index > 0 { CardDivider() }
                CardLine(icon: .info, text: line)
            }
        }
        Note(DeleteAccountScreen.finality, icon: .info)
        VStack(spacing: ThroSpacing.spacing3) {
            ThroButton(working ? "Deleting" : "Delete my account", variant: .destructive,
                       size: .large, fullWidth: true, disabled: working, loading: working) {
                confirming = true
            }
            ThroButton("Keep my account", variant: .ghost, size: .large, fullWidth: true, action: onCancel)
                .disabled(working)
        }
    }

    @ViewBuilder private func done(_ gone: ThroAPI.Erasure) -> some View {
        Note("THRØ has taken your name, your sign-ins and your friends out for good. This is what it "
             + "destroyed, as the server reported it.", icon: .circleCheck)
        CardGroup("What was destroyed") {
            CardInfoRow(icon: .lock, label: "Ways in", value: "\(gone.credentials)")
            CardDivider()
            CardInfoRow(icon: .smartphone, label: "Sessions ended", value: "\(gone.sessions)")
            CardDivider()
            CardInfoRow(icon: .users, label: "Friendships ended", value: "\(gone.friendships)")
            CardDivider()
            CardInfoRow(icon: .circleUser, label: "Claim on your player record", value: gone.claims == 0 ? "None held" : "Revoked")
            CardDivider()
            CardInfoRow(icon: .shield, label: "Consents withdrawn", value: "\(gone.consents)")
        }
        Note(DeleteAccountScreen.afterwards, icon: .info)
        ThroButton("Done", variant: .primary, size: .large, fullWidth: true, action: onErased)
    }

    private func erase() {
        working = true
        problem = nil
        Task {
            let outcome = await account.eraseAccount()
            working = false
            switch outcome {
            case .erased(let gone):
                withAnimation(.throEnter(ThroMotion.motionDurationStandard)) { erased = gone }
            case .failed(let why):
                // The account is still there, and this is the screen that asked: it says why here.
                problem = why
            }
        }
    }
}
