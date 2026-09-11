import SwiftUI
import ThroDesign
import ThroJournal
import ThroNet
import ThroTokens

// Your profile, and the way out of THRØ.
//
// **What was wrong.** Setting a name meant: You, SIGN IN, scroll a settings list, find a row called
// Name, tap a text link called *Set your name*, get a field, type, tap Save. Seven steps to type two
// words, and no picture at any point. The founder: *"Hard & painful experience to customise your
// account, name etc. during this experience too. no profile pic option."* Correct on both counts.
//
// **What it is now.** One screen that looks like the person it is about: the mark at 96 pt, their
// name under it in the sport face, and both editable where they sit. No sub-screen, no Save button
// hunting — the name commits when the field is left, which is how every field in iOS behaves.

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

/// Your profile: the mark, the name, the age band, and the way out.
public struct YourProfileScreen: View {
    @ObservedObject private var account: AccountStore
    private let profile: Profile
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

    /// The three lists that used to live behind a separate Account screen. They are about the
    /// person, so they are reached from the page about the person.
    enum Sub { case friends, inbox, discovery }

    /// The account this page is about. `Profile.accountId` is optional because a development
    /// principal has none; a page about nobody is not a page, so the caller passes one that has one.
    private let accountId: UUID

    public init(account: AccountStore, profile: Profile, accountId: UUID, images: ImageStore?,
                picture: @escaping (String?) -> Image?, onBack: @escaping () -> Void) {
        self.account = account
        self.profile = profile
        self.accountId = accountId
        self.images = images
        self.picture = picture
        self.onBack = onBack
        _name = State(initialValue: profile.named ? (profile.displayName ?? "") : "")
    }

    private var assetId: String? { AccountPicture.assetId(accountId) }

    /// The initials the mark falls back to. The same two-letter rule the rosters use, so a person is
    /// the same object on their own page as in a list.
    var initials: String {
        let words = name.split(separator: " ").filter { !$0.isEmpty }
        let letters = words.prefix(2).compactMap { $0.first }
        return letters.isEmpty ? "?" : String(letters).uppercased()
    }

    public var body: some View {
        if let showing {
            switch showing {
            case .friends: FriendsScreen(account: account) { self.showing = nil }
            case .inbox: InboxScreen(account: account) { self.showing = nil }
            case .discovery: DiscoveryScreen(account: account) { self.showing = nil }
            }
        } else if deleting {
            DeleteAccountScreen(account: account) {
                AccountPicture.forget(accountId, in: images)
                onBack()
            } onCancel: { deleting = false }
        } else {
            VStack(spacing: 0) {
                TopBar("Your profile", onBack: { commitName(); onBack() }, large: true)
                ScrollView {
                    VStack(alignment: .leading, spacing: ThroSpacing.spacing5) {
                        head
                        band
                        // **Everything about the person, on the page about the person.** These
                        // were behind a second screen called Account, which is why reaching any of
                        // them took four taps and a scroll.
                        SectionHeader("Friends")
                        LinkRow(icon: .users, label: "Friends",
                                value: account.friends.map { $0.isEmpty ? "None yet" : "\($0.count)" } ?? "Codes, given in person") { showing = .friends }
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
                        SectionHeader("Leaving")
                        ThroButton("Sign out of this phone", variant: .secondary, size: .medium) {
                            Task { await account.signOut(); onBack() }
                        }
                        // Apple requires an account that can be made in an app to be deletable in
                        // it, and so does the law. It is a plain row rather than something hidden
                        // behind support: a person who wants out should not have to ask anybody.
                        ThroButton("Delete your account", variant: .destructive, size: .medium, icon: .circleX) {
                            commitName(); deleting = true
                        }
                        Text("Deleting takes your name, your sign-ins and your friends out of THRØ for good. "
                             + "The next screen says exactly what goes and what stays.")
                            .thro(ThroTypography.metadata)
                            .foregroundStyle(ThroColor.colorTextSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.horizontal, ThroSpacing.spaceScreenGutter)
                    .padding(.bottom, ThroSpacing.spacing7)
                }
            }
            .background(ThroColor.colorBackgroundPrimary.ignoresSafeArea())
            .throAppearance(Appearance(stored: appearanceRaw))
        }
    }

    // MARK: - the head: a face and a name, both editable where they sit

    @ViewBuilder private var head: some View {
        VStack(spacing: ThroSpacing.spacing4) {
            PicturePicker(subject: .person(initials: initials), size: 96,
                          current: picture(assetId),
                          refusedBecause: AccountPicture.refusal(ageBand: profile.ageBand),
                          picked: $picked, removed: $removed)
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
            // The name IS the field. No row, no "Set your name" link, no Save: it is typed where it
            // is read, and it commits when the field is left, which is what every other field on
            // the phone does.
            TextField("Your name", text: $name)
                .thro(ThroTypography.heading1.family(.sport).weight(.bold).tracking(em: 0))
                .foregroundStyle(ThroColor.colorTextPrimary)
                .multilineTextAlignment(.center)
                .textContentType(.name)
                .autocorrectionDisabled()
                .submitLabel(.done)
                .focused($editingName)
                .onSubmit(commitName)
                .frame(maxWidth: .infinity)
                .padding(.vertical, ThroSpacing.spacing2)
                .overlay(alignment: .bottom) {
                    // A chalk rule under it, so it reads as something written rather than a box.
                    ChalkRule(weight: 2, seedAngle: 17).fill(ThroColor.colorBorderDefault)
                        .frame(height: 3)
                }
                .accessibilityLabel("Your name")
                .accessibilityHint("Shown to the teams and leagues you are part of")
            Text(YourProfileScreen.nameNote(named: profile.named))
                .thro(ThroTypography.metadata)
                .foregroundStyle(ThroColor.colorTextSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, ThroSpacing.spacing5)
        .onChange(of: editingName) { was, now in if was && !now { commitName() } }
    }

    /// How many ways into this account there are, and why one is not enough (PD-032).
    private func waysIn(_ n: Int) -> some View {
        Note(n <= 1
             ? "**One way into this account.** Lose it and the account is lost: THRØ has no email or "
               + "phone recovery, on purpose. Add a passkey or a second sign-in below."
             : "**\(n) ways into this account.** If one is lost, another still gets you in.")
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

    // MARK: - the age band

    @ViewBuilder private var band: some View {
        SectionHeader("Your age band")
        if profile.ageBand == "unknown" {
            Note("THRØ does not guess ages. Saying you are 18 or over unlocks friends and a picture; "
                 + "under 18 is welcome to play, and a guardian's confirmation for the rest is coming.")
            ThroButton("I am 18 or over", variant: .secondary, size: .medium, icon: .check) {
                Task { await account.declareAdult() }
            }
        } else {
            SettingsRow(icon: .shield, label: "Age band",
                        value: profile.ageBand == "adult" ? "18 or over" : "Under 18")
        }
    }
}

/// Erasure (V031), said in words before it is done.
///
/// **Why it lists what stays.** A match is two people's record. Telling somebody "everything will be
/// deleted" and then keeping the leg they played against their mate would be a lie; telling them
/// nothing and keeping it would be worse. So the screen says both halves, and the half that stays
/// is the half that names nobody once this has run.
public struct DeleteAccountScreen: View {
    @ObservedObject private var account: AccountStore
    private let onErased: () -> Void
    private let onCancel: () -> Void

    @AppStorage(Appearance.storageKey) private var appearanceRaw: String = Appearance.system.rawValue
    @State private var confirming = false
    @State private var problem: String?
    @State private var working = false

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
        "Matches scored on this phone. They were never sent anywhere; clear them under Settings if "
            + "you want them gone as well.",
    ]

    public static let finality =
        "This cannot be undone. Signing in again with the same Apple ID makes a brand new account "
        + "with nothing in it."

    public var body: some View {
        VStack(spacing: 0) {
            TopBar("Delete your account", onBack: onCancel, large: true)
            ScrollView {
                VStack(alignment: .leading, spacing: ThroSpacing.spacing4) {
                    if let problem {
                        Snackbar(problem, tone: .error)
                    }
                    SectionHeader("What goes")
                    ForEach(DeleteAccountScreen.goes, id: \.self) { line in
                        bullet(line, icon: .circleX, tone: ThroColor.colorTextPrimary)
                    }
                    SectionHeader("What stays, and why")
                    ForEach(DeleteAccountScreen.stays, id: \.self) { line in
                        bullet(line, icon: .info, tone: ThroColor.colorTextSecondary)
                    }
                    Note(DeleteAccountScreen.finality, icon: .info)
                        .padding(.top, ThroSpacing.spacing2)
                    ThroButton(working ? "Deleting" : "Delete my account", variant: .destructive,
                               size: .large, fullWidth: true, disabled: working, loading: working) {
                        confirming = true
                    }
                    .padding(.top, ThroSpacing.spacing3)
                    ThroButton("Keep my account", variant: .ghost, size: .large, fullWidth: true, action: onCancel)
                }
                .padding(.horizontal, ThroSpacing.spaceScreenGutter)
                .padding(.bottom, ThroSpacing.spacing7)
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

    private func bullet(_ line: String, icon: ThroIcon, tone: Color) -> some View {
        HStack(alignment: .top, spacing: ThroSpacing.spacing3) {
            Icon(icon, size: 18).foregroundStyle(ThroColor.colorTextSecondary)
            Text(line)
                .thro(ThroTypography.body)
                .foregroundStyle(tone)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }

    private func erase() {
        working = true
        Task {
            let why = await account.eraseAccount()
            working = false
            // Signed out either way — `AccountStore.eraseAccount` says why — so the screen leaves
            // either way, and a failure is reported rather than swallowed.
            problem = why
            if why == nil { onErased() }
        }
    }
}
