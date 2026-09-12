import Combine
import CoreSpotlight
import SwiftUI
import UniformTypeIdentifiers
import ThroTokens
import ThroDesign
import ThroJournal
import ThroLiveKit
import ThroNet
import ThroPlay

/// The app's state: the journal, what is in it, and which tab or flow is showing.
public final class AppStore: ObservableObject {
    public enum Flow: Equatable { case new, resume(MatchId) }

    public struct HomeMatch: Identifiable, Equatable {
        public let record: MatchRecord
        public let legsHome: Int
        public let legsAway: Int
        public let complete: Bool
        /// Why this match's own rows could not be replayed, when they could not. A match whose
        /// journal is unreadable is still a match that happened: it stays on the list and says so,
        /// rather than disappearing and leaving the player to wonder whether they imagined it.
        public let unreadable: String?
        /// How it ended short, if it did (PD-016). `complete` is true for both kinds, because the
        /// keypad is closed either way; this is what says which of the three it was.
        public let ending: Ending?
        public var id: MatchId { record.id }

        /// The status word on the row. Three states, not two: an abandoned match is finished and is
        /// not a result, and a row that showed it as either "In progress" or a win would be wrong.
        public var status: String {
            if unreadable != nil { return "Unreadable" }
            switch ending {
            case .retired: return "Retired"
            case .abandoned: return "No result"
            case nil: return complete ? "Finished" : "In progress"
            }
        }

        public init(record: MatchRecord, legsHome: Int, legsAway: Int, complete: Bool,
                    unreadable: String?, ending: Ending? = nil) {
            self.record = record
            self.legsHome = legsHome
            self.legsAway = legsAway
            self.complete = complete
            self.unreadable = unreadable
            self.ending = ending
        }
    }

    public let journal: Journal?
    /// Why the journal could not be opened, when it could not. Shown, never swallowed.
    public let openProblem: String?

    @Published public var tab: BottomBar.Tab = .home
    @Published public var flow: Flow?
    @Published public private(set) var matches: [HomeMatch] = []
    /// Why the list of matches could not be read, when it could not. An empty list and an unreadable
    /// one are different facts and the screen must not show the second as the first.
    @Published public private(set) var listProblem: String?
    /// The matches that have been put away (PD-026). Their own list, read at the same time as
    /// Home's, so opening the shelf is not a second trip to the database.
    @Published public private(set) var archived: [HomeMatch] = []
    /// What went wrong the last time somebody tried to archive or delete something, if anything.
    /// Shown on the screen that asked, then cleared — a failure that only appears in a log is a
    /// failure the person is left to guess at.
    @Published public var actionProblem: String?

    /// Which fixtures cite a match, so a delete that would strip a league table of its evidence can
    /// be refused (PD-026). A closure because the fixtures live in `ClubBook` — a different
    /// database, deliberately — and this store must not learn to open it.
    public var fixturesCiting: (MatchId) -> [String] = { _ in [] }
    /// What this phone has done in the last seven days (PD-027). Nil while the journal cannot be
    /// read; the screen shows the reason it already has rather than an empty strip.
    @Published public private(set) var week: DeviceSummary.Week?

    public init() {
        do {
            journal = try AppStore.openJournal()
            openProblem = nil
        } catch {
            journal = nil
            openProblem = "\(error)"
        }
        refresh()
    }

    /// For previews and tests: a store over a journal the caller made.
    public init(journal: Journal) {
        self.journal = journal
        self.openProblem = nil
        refresh()
    }

    /// Where the journal and the club book live. One directory, so one backup decision covers both.
    static func container() throws -> URL {
        let support = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                                  appropriateFor: nil, create: true)
        let dir = support.appendingPathComponent("THRO", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static func openJournal() throws -> Journal {
        let dir = try container()
        // PD-017. A journal is the only copy of what was thrown, so it belongs in the device backup.
        // Stated and read back rather than left to a default, for the same reason the durability
        // pragmas are: a default that nothing checks is a default that changes.
        BackupPolicy.include(dir)
        let opened = try Journal(path: dir.appendingPathComponent("journal.sqlite").path,
                                 deviceId: DeviceId(deviceId()))
        reconcileDeviceId(opened)
        return opened
    }

    /// Whether this device's darts would survive a new phone (PD-017). Read on demand rather than
    /// cached, because the answer is a fact about the file system now and not when the app started.
    public var backupState: BackupPolicy.State {
        (try? AppStore.container()).map(BackupPolicy.read) ?? .unknown("the data folder could not be found")
    }

    /// What the diagnostics folder holds, read on demand for the same reason `backupState` is: it
    /// is a fact about the file system now.
    public var diagnosticsHeld: ThroDiagnostics.Held {
        guard let dir = try? AppStore.container(), let folder = try? ThroDiagnostics.folder(in: dir) else {
            return ThroDiagnostics.Held(count: 0, bytes: 0, newest: nil)
        }
        return ThroDiagnostics.held(in: folder)
    }

    /// Deletes every collected report. The switch going off removes what was collected rather than
    /// only stopping new arrivals — the rule Spotlight's switch follows, for the same reason.
    public func forgetDiagnostics() {
        guard let dir = try? AppStore.container(), let folder = try? ThroDiagnostics.folder(in: dir) else { return }
        ThroDiagnostics.forget(in: folder)
    }

    /// Everything this device holds, as one file the player can keep (PD-017).
    ///
    /// Written to a temporary file so it can be shared. Nothing is sent anywhere by this: the
    /// player chooses where it goes, which is the whole point of it existing alongside the backup.
    public func exportEverything(clubs book: ClubBook?, at now: Date = Date()) throws -> URL {
        guard let journal else { throw ExportError.notAnExport("this device has no journal open") }
        let document = try Export.make(journal,
                                       clubs: (try? book?.exportRows()) ?? [],
                                       people: (try? book?.people()) ?? [],
                                       assetsNotIncluded: Array((try? book?.referencedAssetIds()) ?? []).sorted(),
                                       at: now)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(Export.filename(at: now))
        try Export.data(document).write(to: url, options: .atomic)
        return url
    }

    static let deviceIdKey = "thro.journal.deviceId"

    /// A random identifier for this install. It names the device in the journal's sequence and is
    /// not a secret and not a hardware identifier.
    static func deviceId(in defaults: UserDefaults = .standard) -> String {
        if let existing = defaults.string(forKey: deviceIdKey) { return existing }
        let fresh = UUID().uuidString
        defaults.set(fresh, forKey: deviceIdKey)
        return fresh
    }

    /// The journal's identity is this device's identity, and the caller's copy is corrected to it.
    ///
    /// The journal already refuses to take a new identity once it has one, so a cleared
    /// `UserDefaults` cannot restart `device_seq`. But refusing is only half of it: without this the
    /// journal would be right about itself while every other reader of `deviceId()` — a sync client
    /// naming this device to a server, say — held the identity the journal had just rejected, which
    /// is the same one-device-arriving-as-two that the refusal exists to prevent, only quieter.
    /// Returns whether anything was corrected.
    @discardableResult
    static func reconcileDeviceId(_ journal: Journal, in defaults: UserDefaults = .standard) -> Bool {
        guard journal.deviceIdSupersededCallers != nil else { return false }
        defaults.set(journal.deviceId.value, forKey: deviceIdKey)
        return true
    }

    /// Reads the journal, and says so when it cannot.
    ///
    /// Both of the failures here used to be swallowed. `matches()` throwing produced an empty list,
    /// so a journal that could not be read showed the same screen as a journal with nothing in it —
    /// "No matches yet" over a database full of them. And a record whose replay threw was dropped
    /// from the list entirely, which is worse: the journal refuses to replay a corrupt row **on
    /// purpose**, and the app answered by hiding the match. Evidence that exists must never be
    /// shown as evidence that does not.
    public func refresh() {
        guard let journal else { matches = []; archived = []; listProblem = nil; return }
        let records: [MatchRecord]
        do {
            records = try journal.matches()
            listProblem = nil
        } catch {
            matches = []
            archived = []
            listProblem = "\(error)"
            return
        }
        let all = records.map { home($0, in: journal) }
        matches = all.filter { !$0.record.isArchived }
        archived = all.filter { $0.record.isArchived }
        // Only the last seven days are replayed for this, so the cost is bounded by how much darts
        // somebody has thrown this week rather than by how long they have had the app.
        week = try? DeviceSummary.week(in: journal)
    }

    /// One row, replayed. Split out of `refresh` when the shelf arrived (PD-026) so that Home and
    /// the shelf are built by the same code rather than by two that must be kept alike.
    private func home(_ record: MatchRecord, in journal: Journal) -> HomeMatch {
        do {
            let state = try journal.replay(record.id)
            let ending = try journal.ending(for: record.id)
            return HomeMatch(record: record,
                             legsHome: state.legsWonTotal[Seat.home.playerId] ?? 0,
                             legsAway: state.legsWonTotal[Seat.away.playerId] ?? 0,
                             // Ended short counts as complete here: the keypad is closed and the
                             // row must not offer to resume a match nothing more can be added to.
                             complete: state.isComplete || ending != nil, unreadable: nil,
                             ending: ending)
        } catch {
            return HomeMatch(record: record, legsHome: 0, legsAway: 0,
                             complete: false, unreadable: "\(error)")
        }
    }

    // MARK: - putting a match away, and taking it off the phone (PD-026)

    /// Moves a match to the shelf, or brings it back. Nothing is lost either way.
    public func setArchived(_ id: MatchId, _ archived: Bool) {
        guard let journal else { return }
        do {
            try journal.setArchived(id, archived)
            actionProblem = nil
            refresh()
        } catch {
            actionProblem = "\(error)"
        }
    }

    /// Why this match may not be deleted, or nil when it may.
    ///
    /// **The refusal is about somebody else's record, not about this phone's tidiness.** A result a
    /// league has taken from this match cites it by id; that citation is what makes the result
    /// *scored* rather than *typed in*, and deleting the match would leave a table resting on
    /// evidence nobody could produce. Archiving does everything the person wanted and keeps it.
    public func deletionRefusal(_ id: MatchId) -> String? {
        let citing = fixturesCiting(id)
        guard !citing.isEmpty else { return nil }
        let fixtures = citing.count == 1 ? "a fixture" : "\(citing.count) fixtures"
        return "This match cannot be deleted: \(fixtures) took a result from it, and that result "
             + "would be left claiming evidence that no longer exists. Archive it instead — it "
             + "leaves Home and everything it proves stays."
    }

    /// Takes a match off this phone for good.
    ///
    /// Returns how many visits went with it, so the screen can say what was actually lost rather
    /// than "deleted". Refuses when `deletionRefusal` has something to say.
    @discardableResult
    public func delete(_ id: MatchId) -> Int? {
        guard let journal else { return nil }
        if let refusal = deletionRefusal(id) {
            actionProblem = refusal
            return nil
        }
        do {
            let rows = try journal.deleteMatch(id)
            actionProblem = nil
            refresh()
            return rows
        } catch {
            actionProblem = "\(error)"
            return nil
        }
    }
}

/// The root of the app. Mount this from the Xcode app target's `App`:
///
///     @main struct ThroDartsApp: App { var body: some Scene { WindowGroup { ThroRootView() } } }
public struct ThroRootView: View {
    @StateObject private var store: AppStore
    /// The clubs this device holds. Its own store because it is its own database, for the reason
    /// `ClubBook` gives: a roster is edited and a journal never is.
    @StateObject private var clubs = ClubStore()
    @AppStorage(Appearance.storageKey) private var appearanceRaw: String = Appearance.system.rawValue
    @State private var showingSettings = false
    @State private var showingAccount = false
    /// Your profile, when it is open: the profile it was opened on, and which part of it. Held here
    /// rather than re-read from the account on every pass, so the page stays on screen through what
    /// happens on it — a name saving, a way in being added, an erasure finishing — instead of
    /// vanishing the moment the account stops saying `signedIn`.
    @State private var profileOpen: ProfileOpening?
    /// The You tab's Friends button opens the account screen on Friends rather than on its front.
    @State private var openingFriends = false
    @StateObject private var accountHolder = AccountHolder()
    /// The matches this person has on THRØ (PD-043), for the Live tab.
    @StateObject private var throMatches = ThroMatchesModel()
    /// The matches this phone is sharing live as they are scored (PD-044).
    @StateObject private var liveShare = LiveShare()
    /// The person whose page is open, if any. Their figures come from the journal, so this is the
    /// one screen in the app where a statistic is about a person rather than about a match.
    @State private var viewing: LocalPerson?
    /// Where an incoming link asked to go, until a screen can take it there. The shared one, because
    /// an App Intent and a Spotlight result both arrive from outside any view.
    @ObservedObject private var router = ThroRouter.shared
    /// For the one URL this app opens that is not its own: its page in iPhone Settings.
    @Environment(\.openURL) private var openURL
    /// The leg in play, as the app's one holder of it. The scoring session pushes here for the wall
    /// screen (club TV mode); reading it for the widgets' file means there is one live state rather
    /// than two that can disagree about what is on the board.
    @ObservedObject private var venue = ThroVenue.shared
    /// The club a link named, handed to the Discover tab and cleared as it lands.
    /// Where the Clubs tab has been asked to land — a club, or a club and one of its fixtures.
    @State private var openClub: ClubLanding?
    /// Whether this phone's own search field finds matches, people and clubs (on by default).
    @AppStorage(ThroSpotlight.enabledKey) private var spotlight: Bool = true
    /// Whether iOS may tell this app how it performed. Off by default; Settings explains it.
    @AppStorage(ThroDiagnostics.enabledKey) private var diagnostics: Bool = false
    /// PD-007: the opening plays once, at cold launch, over whatever the app shows first.
    @State private var opening = true
    /// Answered for THIS run: the welcome after the opening. `@State` rather than `@AppStorage`
    /// on purpose — a cold launch while signed out asks again, because signing in is the thing the
    /// app needs and a person with no account has not done it. One tap is past it.
    @State private var welcomeAnswered = false
    /// What the last attempt to send a match said (PD-040): a count, or the reason it could not go.
    @State private var sendNote: String?
    /// The opening withdraws its own motion under this setting; the handover has to withdraw too,
    /// or a person who asked for none would still be shown the app growing towards them.
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init() { _store = StateObject(wrappedValue: AppStore()) }
    public init(store: AppStore) { _store = StateObject(wrappedValue: store) }

    public var body: some View {
        ZStack {
            content
                // The app does not sit waiting behind the opening and then get uncovered: it comes
                // *towards* the viewer as the opening leaves, by the same 2% the design's impact
                // magnitude defines. One movement, in one direction, rather than a cut.
                .scaleEffect(opening && !reduceMotion ? 2 - ThroMotion.motionScaleImpact : 1)
                .opacity(opening && !reduceMotion ? 0 : 1)
            // Between the opening and the product, once: the welcome, on the board the dart landed
            // in. It sits UNDER the opening and OVER the app, so the opening resolves into it
            // rather than cutting to it, and the tabs are never briefly visible behind it.
            // `holdsSession`, not `isSignedIn`: a phone that is offline at launch holds a session it
            // cannot confirm yet, and asking that person to sign in would be the wrong question. Not
            // while the profile is open, either — an erasure ends there, and the screen that says
            // what was destroyed is the one to read, not a sign-in board laid over it.
            if let account, Welcome.shows(configured: true, settled: account.settled,
                                          signedIn: account.holdsSession,
                                          answeredThisLaunch: welcomeAnswered || profileOpen != nil) {
                WelcomeScreen(account: account) {
                    withAnimation(.throExit(ThroMotion.motionDurationStandard)) { welcomeAnswered = true }
                }
                .transition(.opacity)
                .zIndex(0.5)
            }
            if opening {
                // Held on its last frame until the account has answered (`OpeningHold`).
                LaunchSequenceView(holding: account.map { !$0.settled } ?? false) { fade in
                    // `.easeInOut` was Apple's curve on the single most important transition in the
                    // app — the handover from the opening to the product. `throExit` is the
                    // design's own (PD-027).
                    withAnimation(.throExit(fade)) { opening = false }
                }
                .transition(.opacity)
                .zIndex(1)
            }
        }
        // A link may arrive at any moment — during the opening, mid-match, on a cold launch before
        // the journal has opened. None of those is a moment to move the screen, so the router holds
        // it and this takes it when SwiftUI is next evaluating.
        .onOpenURL { router.open($0) }
        // Debug builds only: `-ThroScreen tab/discover` opens on a named screen, through the same
        // router a link uses, so a script can look at a surface nobody can tap its way to.
        .task {
            #if DEBUG
            ScreenshotScreen.goIfAsked()
            #endif
        }
        // Look for a stored sign-in as the app starts, rather than waiting for somebody to open the
        // account screen: the welcome cannot decide whether to appear until this has answered.
        .task { await account?.start() }
        // Matches shared live go up as they are scored (PD-044); idle while nothing is shared.
        .task { await shareLoop() }
        // A tapped Spotlight result arrives as a user activity rather than a URL, and is the one
        // place `onContinueUserActivity` is right — a universal link would arrive at `onOpenURL`,
        // which is the mistake a 2024-era mental model makes in SwiftUI.
        .onContinueUserActivity(CSSearchableItemActionType) { activity in
            if let route = ThroSpotlight.route(for: activity) { router.go(route) }
        }
        .onChange(of: router.pending) { _, _ in follow() }
        .task {
            follow()
            reindex()
            // A scoreboard that outlived the app that started it is a score nobody is keeping. On a
            // cold launch the in-memory handle is gone, so anything still running is orphaned.
            LiveBoard.clearStale()
            project()
            collect()
        }
        .onChange(of: diagnostics) { _, _ in collect() }
        // Keyed on what is actually indexable rather than on a count: a club being renamed changes
        // no count, and an index that only noticed additions would keep showing the old name.
        .onChange(of: searchable) { _, _ in reindex(); project() }
        // The widgets' file is rewritten whenever what it would say changes. The leg is keyed
        // separately from the rest, because a visit changes the leg and nothing else — and a widget
        // still showing 141 after three darts is the failure the projection exists to avoid.
        .onChange(of: venue.state) { _, _ in project() }
        .onChange(of: store.week) { _, _ in project() }
    }

    /// A fingerprint of everything Spotlight would hold, so a rename reindexes as surely as an add.
    private var searchable: String {
        let matches = (store.matches + store.archived)
            .map { "\($0.record.id.value)|\($0.record.homeName)|\($0.record.awayName)|\($0.complete)" }
        let people = clubs.people.map { "\($0.id)|\($0.name)" }
        let orgs = clubs.clubs.map { "\($0.id)|\($0.name)|\($0.kind.rawValue)" }
        return (matches + people + orgs).joined(separator: "\n") + "|\(spotlight)"
    }

    private func reindex() {
        ThroSpotlight.index(matches: store.matches + store.archived,
                            people: clubs.people, clubs: clubs.clubs, enabled: spotlight)
    }

    /// Subscribes to MetricKit, or stops. Off by default and stopped the moment the switch goes
    /// off — the reports themselves are deleted by Settings at the same time.
    private func collect() {
        #if os(iOS)
        guard diagnostics, let dir = try? AppStore.container() else {
            return ThroMetricSubscriber.shared.stop()
        }
        ThroMetricSubscriber.shared.start(in: dir)
        #endif
    }

    /// The half of the readiness facts that comes from this phone's own data rather than from a
    /// system framework.
    ///
    /// Read here, in the one place that already holds all of it, and passed down — so the screen
    /// cannot disagree with Home about how many matches are finished.
    @MainActor
    private func readiness() -> ThroReadiness.Facts {
        let everything = store.matches + store.archived
        return ThroReadiness.Facts(
            matchInProgress: ThroReadiness.beingScored(everything),
            finishedMatches: ThroReadiness.shareable(everything),
            datedFixtures: clubs.clubs.flatMap(\.fixtures).filter { $0.at != nil }.count,
            spotlightOn: spotlight,
            diagnosticsOn: diagnostics,
            diagnosticsHeld: store.diagnosticsHeld.count)
    }

    /// Takes somebody where a readiness row says to go.
    ///
    /// Two kinds of destination and no third: somewhere in THRØ, through the same router a link
    /// goes through — so a row cannot reach a screen a universal link could not — or this app's own
    /// page in iPhone Settings, which is the only page iOS lets any app open. `follow()` already
    /// closes Settings for a tab or a new match, so there is nothing to close here.
    private func goReadiness(_ go: ThroReadiness.Go) {
        switch go {
        case let .place(_, route):
            router.go(route)
        case .phoneSettings:
            #if os(iOS)
            if let url = ThroReadiness.phoneSettings { openURL(url) }
            #endif
        }
    }

    /// Rewrites the small file the widgets read. A no-op on a build with no App Group.
    private func project() {
        ThroProjectionWriter.write(matches: store.matches, week: store.week, clubs: clubs.clubs,
                                   live: venue.state, liveFormat: venue.format)
    }

    /// Goes where a link asked, once, if the place still exists.
    ///
    /// **A route names a place; it does not assert that the place is there.** A match id in a
    /// widget tapped a week after the match was deleted, a person removed from this phone, a club
    /// that was on another device — all of them arrive here looking exactly like a good link. Each
    /// is checked against what this device actually holds, and an address that resolves to nothing
    /// leaves the screen alone rather than opening an empty one.
    private func follow() {
        guard let route = router.take() else { return }
        switch route {
        case let .tab(tab):
            viewing = nil; showingSettings = false; store.flow = nil
            store.tab = tab
        case .settings:
            viewing = nil; store.flow = nil
            showingSettings = true
        case let .match(id):
            guard store.matches.contains(where: { $0.record.id == id })
                    || store.archived.contains(where: { $0.record.id == id }) else { return }
            viewing = nil; showingSettings = false
            store.flow = .resume(id)
        case let .person(id):
            guard let person = clubs.people.first(where: { $0.id == id }) else { return }
            showingSettings = false; store.flow = nil
            viewing = person
        case let .club(id):
            guard clubs.clubs.contains(where: { $0.id == id }) else { return }
            viewing = nil; showingSettings = false; store.flow = nil
            store.tab = .discover
            openClub = ClubLanding(club: id)
        case .newMatch:
            viewing = nil; showingSettings = false
            store.flow = .new
        case .continueLatest:
            viewing = nil; showingSettings = false
            // `matches` is newest first, so the first unfinished one is the one they walked away
            // from. With none, Play — not a guess about which match, but the right place when there
            // is no match to continue, and the screen there says so rather than opening an empty one.
            if let open = store.matches.first(where: { !$0.complete }) {
                store.flow = .resume(open.record.id)
            } else {
                store.flow = nil
                store.tab = .play
            }
        }
    }

    @ViewBuilder private var content: some View {
        if let flow = store.flow, let journal = store.journal {
            PlayFlow(journal: journal, resume: resumeId(flow),
                     people: clubs.people,
                     resolvePerson: { clubs.person(named: $0)?.id }) {
                store.flow = nil
                store.refresh()
            }
        } else if let person = viewing {
            PersonScreen(person: person, journal: store.journal, clubs: clubs.clubs,
                         onBack: { viewing = nil },
                         onRemove: { if clubs.deletePerson(person.id) { viewing = nil } })
                .throAppearance(Appearance(stored: appearanceRaw))
        } else if let opened = profileOpen, let account, let id = opened.profile.accountId {
            YourProfileScreen(account: account, profile: opened.profile, accountId: id, opening: opened.part,
                              images: clubs.images, picture: { clubs.image($0) }) { profileOpen = nil }
        } else if showingAccount, let account {
            // **One way in, and it is the good one.** SIGN IN on the You tab used to open a settings
            // list of buttons under a paragraph; it opens the same board the welcome does. The
            // welcome is asked once at launch, so without this a player who tapped "Not now" could
            // never see it again — which is exactly what happened. The full account list is still
            // there for somebody signed in, and under Settings for the passkey-only path.
            Group {
                if !account.holdsSession && !openingFriends {
                    // The welcome sets its own appearance and draws its own board edge to edge.
                    WelcomeScreen(account: account, ask: .fromYou) { showingAccount = false }
                } else {
                    AccountScreen(account: account, opening: openingFriends ? .friends : .account,
                                  images: clubs.images, picture: { clubs.image($0) }) { showingAccount = false; openingFriends = false }
                        .throAppearance(Appearance(stored: appearanceRaw))
                }
            }
        } else if showingSettings {
            SettingsScreen(onBack: { showingSettings = false },
                           onReplayOpening: { showingSettings = false; opening = true },
                           onAccount: account == nil ? nil : { openAccount(nil) },
                           account: youAccount, picture: accountPicture,
                           organisationCount: { clubs.clubs.count },
                           onClearOrganisations: { clubs.deleteAllOrganisations() },
                           backupState: { store.backupState },
                           makeExport: { try store.exportEverything(clubs: clubs.book) },
                           diagnosticsHeld: { store.diagnosticsHeld },
                           onForgetDiagnostics: store.forgetDiagnostics,
                           readinessFacts: { await ThroReadiness.probe(app: readiness()) },
                           onGoReadiness: goReadiness)
                .throAppearance(Appearance(stored: appearanceRaw))
        } else {
            VStack(spacing: 0) {
                tabContent
                BottomBar(selection: store.tab) { store.tab = $0 }
            }
            .background(ThroColor.colorBackgroundPrimary.ignoresSafeArea())
            // PD-003: the player chooses System / Light / Dark in Settings; every screen follows it.
            .throAppearance(Appearance(stored: appearanceRaw))
        }
    }

    private func resumeId(_ flow: AppStore.Flow) -> MatchId? {
        if case .resume(let id) = flow { return id }
        return nil
    }

    @ViewBuilder private var tabContent: some View {
        switch store.tab {
        case .home: HomeScreen(store: store)
        case .play: PlayLandingScreen(store: store)
        case .live:
            LiveScreen(store: store, clubs: clubs.clubs,
                       onClubs: { store.tab = .discover },
                       // The one row on that screen a league keeper owes something on, sent to the
                       // control that discharges it rather than to the list of clubs.
                       onRecord: { club, fixture in
                           store.tab = .discover
                           openClub = ClubLanding(club: club.id, wanted: .result(fixture: fixture.id))
                       },
                       // A fixture still to play has nothing to record. Its list is where a
                       // player's own controls are — the reminder, the calendar entry, the search
                       // for the venue — so that is where it goes.
                       onFixtures: { club in
                           store.tab = .discover
                           openClub = ClubLanding(club: club.id, wanted: .fixtures)
                       },
                       onSend: account == nil ? nil : { match in sendToThro(match) },
                       sendNote: sendNote,
                       // What THRØ holds of this person's matches (PD-043): read again whenever the
                       // tab is, and after every send.
                       records: account == nil ? nil : throMatches, api: account?.api,
                       signedIn: account?.isSignedIn ?? false,
                       liveShare: account == nil ? nil : liveShare)
        case .discover: ClubsFlow(store: clubs, open: $openClub, api: account?.api, signedIn: account?.isSignedIn ?? false)
        case .you: YouScreen(account: youAccount, picture: accountPicture, clubs: clubs.clubs, people: clubs.people,
                             badge: { clubs.image($0.badgeAssetId) },
                             onSettings: { showingSettings = true },
                             onAccount: { openAccount(nil) },
                             onFriends: { openAccount(.friends) },
                             onProfile: { openAccount(nil) },
                             onRetry: { Task { await account?.start() } },
                             onClubs: { store.tab = .discover },
                             onPerson: { viewing = $0 })
            .task { if let account, account.isSignedIn, account.friends == nil { await account.loadFriends() } }
        }
    }
}

/// Home, honestly. The export's `home-new` shows a rating hero, a confidence meter and events near
/// you; none of those exist for this build (OD-001, no servers), so Home shows what is true: the
/// matches on this device, or an empty state with the one action that is real.
/// The first screen of the app.
///
/// **It was a title, a list and a button.** The founder: *"home page feels very bare & basic, all
/// screens feel bare & basic."* Correct, and the fix is not decoration. A darts app's first screen
/// should answer three things before a finger moves: *is there a match I walked away from*, *what
/// have I been throwing*, and *what happened lately* — in that order, because that is the order
/// they matter in.
///
/// So, top to bottom: the masthead, on the board's own dark surface rather than a system title bar;
/// the match in progress, if there is one, as the largest object on the screen; the last seven days
/// as figures from the audited honesty layer; then the record, then the shelf. Each block lands a
/// beat after the one above it (`throEntrance`).
///
/// **Nothing here is filler.** Every number comes from `DeviceSummary`, which comes from
/// `Statistics`, which returns *unavailable* rather than a flattering zero — so a new phone shows
/// dashes and says why, and a screen that is honestly empty stays honestly empty.
public struct HomeScreen: View {
    @ObservedObject var store: AppStore
    /// Whether the rows are showing their archive and delete controls (PD-026). Off by default:
    /// the common thing a person does with a match is open it.
    @State private var editing = false
    /// The match a delete has been asked for and not yet confirmed.
    @State private var confirmingDelete: AppStore.HomeMatch?
    @State private var showingArchive = false

    public init(store: AppStore) { self.store = store }

    /// The match to offer to continue: the newest one still open. A match that ended short is not
    /// one of these — `complete` is true for it — so the card never offers to resume something the
    /// journal would refuse to take another dart for (PD-016).
    private var inProgress: AppStore.HomeMatch? {
        store.matches.first { !$0.complete && $0.unreadable == nil }
    }

    public var body: some View {
        Group {
            if showingArchive {
                ArchiveScreen(store: store, onBack: { showingArchive = false })
            } else {
                home
            }
        }
        .background(ThroColor.colorBackgroundPrimary.ignoresSafeArea())
    }

    /// Nothing scored, nothing archived, and nothing wrong — the one state where Home has no content at
    /// all, and the state PD-068 makes the field rather than a card on a sheet of cream.
    private var nothingAtAll: Bool {
        store.openProblem == nil && store.listProblem == nil && store.actionProblem == nil
            && store.matches.isEmpty && store.archived.isEmpty
    }

    @ViewBuilder private var home: some View {
        if nothingAtAll {
            // The masthead stays: it is already the field, so the wordmark and the board below it read as
            // one surface with a lamp in it rather than as a green strip above a green page. No scroll
            // view, because there is nothing to scroll — and a page that scrolls past its own emptiness is
            // how the card version came to look like a notice pinned to the top of a tablet.
            VStack(spacing: 0) {
                Masthead(line: mastheadLine).throEntrance(0)
                ThroNothingYet(title: "No matches yet",
                               message: "Score a match on this device and it will appear here. Nothing is "
                                      + "sent anywhere unless you send it.",
                               actionLabel: "Start match") { store.flow = .new }
                    .throEntrance(1)
            }
        } else {
            scrollingHome
        }
    }

    private var scrollingHome: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Masthead(line: mastheadLine).throEntrance(0)
                FontSubstitutionNotice()
                    .padding(.horizontal, ThroSpacing.spaceScreenGutter)
                    .padding(.top, ThroSpacing.spacing4)
                if let problem = store.actionProblem {
                    block {
                        Snackbar(problem, tone: .error, actionLabel: "OK") { store.actionProblem = nil }
                    }
                }
                if let problem = store.openProblem {
                    block {
                        ErrorState(title: "The journal could not be opened",
                                   what: problem,
                                   safe: "Nothing has been lost. The journal is a file on this device and it has not been written to.",
                                   todo: "Close the app and open it again. If it keeps happening, say so — this is the file every match on this phone lives in.")
                    }
                } else if let problem = store.listProblem {
                    block {
                        ErrorState(title: "Your matches could not be read",
                                   what: problem,
                                   safe: "Every match is still on this device. This screen could not read the list; it did not delete anything.",
                                   todo: "Close the app and open it again.",
                                   actionLabel: "Try again") { store.refresh() }
                    }
                } else if store.matches.isEmpty && store.archived.isEmpty {
                    block {
                        EmptyState(title: "No matches yet",
                                   message: "Score a match on this device and it will appear here.",
                                   actionLabel: "Start match") { store.flow = .new }
                    }
                    .throEntrance(1)
                } else {
                    sections(after: store.openProblem == nil ? 1 : 2)
                }
            }
            .padding(.bottom, ThroSpacing.spacing6)
            // Paper under everything below the masthead; the field behind the top shows above it.
            .background(ThroColor.colorBackgroundPrimary)
        }
        // The field under the clock, so Home opens on green edge to edge as the opening ends on it,
        // rather than on a paper strip with the green starting below it.
        .throBrandFieldBehind()
        .confirmationDialog("Delete this match?",
                            isPresented: Binding(get: { confirmingDelete != nil },
                                                 set: { if !$0 { confirmingDelete = nil } }),
                            titleVisibility: .visible) {
            Button("Delete for good", role: .destructive) {
                if let match = confirmingDelete { store.delete(match.id) }
                confirmingDelete = nil
            }
            Button("Archive instead") {
                if let match = confirmingDelete { store.setArchived(match.id, true) }
                confirmingDelete = nil
            }
            Button("Cancel", role: .cancel) { confirmingDelete = nil }
        } message: {
            if let match = confirmingDelete { Text(HomeScreen.deleteWarning(match)) }
        }
    }

    /// What a delete actually costs, said in full before it happens.
    ///
    /// Not "this cannot be undone", which every app says and nobody reads. The names, the darts and
    /// where the record will and will not survive — because the one thing a person cannot know from
    /// the row is whether they already sent this match somewhere.
    static func deleteWarning(_ match: AppStore.HomeMatch) -> String {
        let who = "\(match.record.homeName) v \(match.record.awayName)"
        let when = match.record.startedAt.formatted(date: .abbreviated, time: .shortened)
        return "\(who), \(when). Every visit in it leaves this phone and its figures leave your "
             + "history. An export or a backup written before now still has it; nothing this app "
             + "can do reaches those. Archiving takes it off Home and keeps all of it."
    }

    @ViewBuilder private func sections(after first: Int) -> some View {
        if let match = inProgress {
            block {
                ContinueCard(match: match) { store.flow = .resume(match.id) }
            }
            .throEntrance(first)
        }
        if let week = store.week, !store.matches.isEmpty || !store.archived.isEmpty {
            block {
                WeekStrip(week: week)
            }
            .throEntrance(first + 1)
        }
        if !store.matches.isEmpty {
            block {
                SectionHeader("On this device",
                              meta: "\(store.matches.count) \(store.matches.count == 1 ? "match" : "matches")",
                              action: editing ? "Done" : "Edit") {
                    withAnimation(.throEnter()) { editing.toggle() }
                }
                ForEach(store.matches) { match in
                    MatchRow(match: match,
                             editing: editing,
                             onOpen: { store.flow = .resume(match.id) },
                             onArchive: { withAnimation(.throEnter()) { store.setArchived(match.id, true) } },
                             onDelete: { confirmingDelete = match })
                    ThroDivider()
                }
            }
            .throEntrance(first + 2)
        }
        if !store.archived.isEmpty {
            block {
                ShelfRow(count: store.archived.count) { showingArchive = true }
            }
            .throEntrance(first + 3)
        }
        block {
            ThroButton("Start match", variant: .primary, size: .large, fullWidth: true) { store.flow = .new }
        }
        .throEntrance(first + 4)
    }

    /// One line under the wordmark, and it is a fact rather than a greeting. "Good evening" tells a
    /// player nothing; the number of matches this phone has watched this week tells them where they
    /// are.
    private var mastheadLine: String {
        if store.openProblem != nil { return "The journal could not be opened" }
        guard let week = store.week else { return "Nothing has left this phone" }
        if week.matches == 0 {
            return store.matches.isEmpty && store.archived.isEmpty
                ? "Nothing on this phone yet"
                : "Nothing in the last seven days"
        }
        let matches = "\(week.matches) match\(week.matches == 1 ? "" : "es")"
        let legs = week.legs == 0 ? "" : " · \(week.legs) leg\(week.legs == 1 ? "" : "s")"
        return "\(matches)\(legs) this week"
    }

    private func block<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: ThroSpacing.spacing3) { content() }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, ThroSpacing.spacing6)
            .padding(.horizontal, ThroSpacing.spaceScreenGutter)
            // The board above runs edge to edge; what is read under it sits in a column (PD-052).
            .throReadable()
    }
}

/// The top of Home: the mark, on the board's own surface.
///
/// **Not a `TopBar`.** A large title in a system bar is what every app on the phone opens with, and
/// the founder's word for that was *generic*. THRØ has a dark board surface of its own and a mark
/// that was drawn for it; this is the one place on Home where the app says its own name, so it says
/// it in its own colours and lets the rest of the screen be plain.
struct Masthead: View {
    let line: String

    /// A phone on its side gets the mark and its line on one row (PD-061). iOS's own signal for a short
    /// screen, held to `ThroMasthead`'s height rule by a test rather than by hope.
    @Environment(\.verticalSizeClass) private var verticalSizeClass

    private var shape: ThroMasthead.Shape {
        ThroMasthead.shape(verticalSizeClassIsCompact: verticalSizeClass == .compact)
    }

    var body: some View {
        Group {
            switch shape {
            case .stacked:
                VStack(alignment: .leading, spacing: ThroSpacing.spacing2) {
                    // The logo, not a font's Ø: THR in the face and the mark as the Ø, drawn live at the
                    // display role's cap height.
                    ThroWordmark(capHeight: ThroTypography.display.capHeight, color: ThroColor.throChalk)
                        .accessibilityAddTraits(.isHeader)
                    line(ThroTypography.label, lines: 2)
                }
            case .oneLine:
                // The mark keeps the baseline and the sentence sits beside it, so a landscape phone opens
                // on its content rather than on a third of a screen of green. One line, not two: a
                // masthead that wraps on a short screen is the thing this exists to stop.
                HStack(alignment: .firstTextBaseline, spacing: ThroSpacing.spacing3) {
                    ThroWordmark(capHeight: ThroTypography.heading2.capHeight, color: ThroColor.throChalk)
                        .accessibilityAddTraits(.isHeader)
                    line(ThroTypography.label, lines: 1)
                    Spacer(minLength: 0)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, ThroSpacing.spaceScreenGutter)
        .padding(.vertical, shape == .oneLine ? ThroSpacing.spacing3 : ThroSpacing.spacing6)
        // **The brand field, and chalk on it.** The first draft of this used `throChalkSunken` for
        // the band — a *light* neutral — under `throChalk` text: 1.08:1, which is invisible. The
        // `thro*` primitives are the raw palette and are not appearance-aware; `chalk` is the
        // near-white and `ink` is the dark, and I had them the wrong way round.
        //
        // What it is now is the field the app launches on, so Home opens on the same green the
        // opening's first frame is: `colorBackgroundBrand` — throGreen in light, throGreenDeep in
        // dark — with **`throChalk` rather than `colorTextInverse`**, because `colorTextInverse` is
        // *ink* in dark mode and lands at 1.99:1 on the brand surface, which is one of the design's
        // 21 recorded exceptions. Chalk measures 11.24:1 light and 8.75:1 dark at full strength,
        // and 6.61 / 5.39 for the line beneath it. `build.py` now checks that pair on every push.
        .background {
            ThroColor.colorBackgroundBrand.ignoresSafeArea(edges: .top)
        }
    }

    /// The line under the mark, or beside it. One definition, so the two shapes cannot drift apart.
    private func line(_ role: ThroTypeRole, lines: Int) -> some View {
        Text(self.line)
            .thro(role)
            .foregroundStyle(ThroColor.throChalk.opacity(0.78))
            .lineLimit(lines)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// The match you walked away from, offered back.
///
/// **The largest object on Home when it exists**, because it is the only thing on the screen that
/// is unfinished. It was a row in a list, indistinguishable from thirty finished matches, marked
/// only by a small blue tag.
struct ContinueCard: View {
    let match: AppStore.HomeMatch
    let onContinue: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: ThroSpacing.spacing4) {
            HStack(alignment: .firstTextBaseline) {
                Eyebrow("Still going", color: ThroColor.colorTextBrand)
                Spacer(minLength: ThroSpacing.spacing2)
                Text(match.record.startedAt.formatted(date: .abbreviated, time: .shortened))
                    .thro(ThroTypography.metadata)
                    .foregroundStyle(ThroColor.colorTextSecondary)
                    .lineLimit(1)
            }
            HStack(alignment: .firstTextBaseline, spacing: ThroSpacing.spacing3) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(match.record.homeName)
                        .thro(ThroTypography.heading2.weight(.bold))
                        .foregroundStyle(ThroColor.colorTextPrimary)
                        .lineLimit(1)
                    Text(match.record.awayName)
                        .thro(ThroTypography.heading2.weight(.bold))
                        .foregroundStyle(ThroColor.colorTextPrimary)
                        .lineLimit(1)
                }
                Spacer(minLength: ThroSpacing.spacing2)
                VStack(alignment: .trailing, spacing: 2) {
                    Text("\(match.legsHome)")
                        .thro(ThroTypography.heading2.family(.sport).weight(.bold))
                    Text("\(match.legsAway)")
                        .thro(ThroTypography.heading2.family(.sport).weight(.bold))
                }
                .foregroundStyle(ThroColor.colorTextPrimary)
            }
            Text("\(match.record.startingScore) · \(match.record.legsMode == .bestOf ? "Best of" : "First to") \(match.record.legsTarget)")
                .thro(ThroTypography.metadata)
                .foregroundStyle(ThroColor.colorTextSecondary)
                .lineLimit(1)
            ThroButton("Continue", variant: .primary, size: .large, fullWidth: true, action: onContinue)
        }
        .padding(ThroSpacing.spacing5)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: ThroSpacing.radiusCard, style: .continuous)
            .fill(ThroColor.colorBackgroundRaised))
        .overlay(RoundedRectangle(cornerRadius: ThroSpacing.radiusCard, style: .continuous)
            .strokeBorder(ThroColor.colorBorderDefault, lineWidth: 1))
    }
}

/// What this phone has seen in a week.
///
/// **The figures are the audited ones**, drawn by `StatGrid` in the three forms PD-015 defines: a
/// number, a range, or a dash that says why. A new phone shows three dashes and a sentence, which
/// is the correct thing for it to show and is why filling this strip with zeroes was never an
/// option.
struct WeekStrip: View {
    let week: DeviceSummary.Week

    var body: some View {
        VStack(alignment: .leading, spacing: ThroSpacing.spacing4) {
            SectionHeader("Last 7 days", meta: meta)
            StatGrid(week.figures.map(WeekStrip.item))
            if week.unreadable > 0 {
                Text("\(week.unreadable) match\(week.unreadable == 1 ? "" : "es") this week could not be replayed, so no dart in \(week.unreadable == 1 ? "it is" : "them is") counted above.")
                    .thro(ThroTypography.metadata)
                    .foregroundStyle(ThroColor.colorStatusError)
                    .fixedSize(horizontal: false, vertical: true)
            }
            // Both players' darts are on this phone and both are in these figures. Saying so is the
            // difference between a description and a claim about one person.
            Text("Every dart thrown on this phone, both players. Your own figures are on your page.")
                .thro(ThroTypography.metadata)
                .foregroundStyle(ThroColor.colorTextTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var meta: String {
        week.matches == 0
            ? "nothing yet"
            : "\(week.matches) match\(week.matches == 1 ? "" : "es") · \(week.legs) leg\(week.legs == 1 ? "" : "s")"
    }

    /// `StatLine` carries the basis; `StatItem` draws it. The mapping is total on purpose — a new
    /// confidence would fail to compile here rather than silently drawing as a confident number.
    static func item(_ line: StatLine) -> StatItem {
        switch line.confidence {
        case .exact: return .exact(line.label, line.value, note: line.note)
        case .range: return .range(line.label, line.value, why: line.note ?? "")
        case .unavailable: return .unavailable(line.label, why: line.note ?? "")
        }
    }
}

/// The way to the shelf (PD-026).
struct ShelfRow: View {
    let count: Int
    let onOpen: () -> Void

    var body: some View {
        Button(action: onOpen) {
            HStack(spacing: ThroSpacing.spacing3) {
                Icon(.eyeOff, size: 20).foregroundStyle(ThroColor.colorTextSecondary)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Archived")
                        .thro(ThroTypography.label.weight(.semibold))
                        .foregroundStyle(ThroColor.colorTextPrimary)
                    Text("\(count) match\(count == 1 ? "" : "es") off Home. Still in your history and your export.")
                        .thro(ThroTypography.metadata)
                        .foregroundStyle(ThroColor.colorTextSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: ThroSpacing.spacing2)
                Icon(.chevronRight, size: 16).foregroundStyle(ThroColor.colorTextTertiary)
            }
            .padding(.vertical, ThroSpacing.spacing3)
            .frame(minHeight: ThroSpacing.touchTargetMinimum)
            .throRowTapTarget()
        }
        .buttonStyle(ThroPressStyle(radius: ThroSpacing.radiusCard,
                                    pressedFill: ThroColor.colorSurfaceSecondary, scales: false))
    }
}

/// The shelf: matches put away, and the way to bring one back (PD-026).
///
/// **A separate screen rather than a collapsed section**, because a shelf that lives inside Home is
/// still on Home. The point of archiving is that the match is somewhere else.
public struct ArchiveScreen: View {
    @ObservedObject var store: AppStore
    let onBack: () -> Void
    @State private var confirmingDelete: AppStore.HomeMatch?

    public init(store: AppStore, onBack: @escaping () -> Void) {
        self.store = store
        self.onBack = onBack
    }

    public var body: some View {
        VStack(spacing: 0) {
            TopBar("Archived", eyebrow: "Off Home, still yours", onBack: onBack)
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    if let problem = store.actionProblem {
                        block {
                            Snackbar(problem, tone: .error, actionLabel: "OK") { store.actionProblem = nil }
                        }
                    }
                    if store.archived.isEmpty {
                        block {
                            EmptyState(title: "Nothing archived",
                                       message: "Matches you put away from Home appear here. They stay in your history and in every export.")
                        }
                        .throEntrance(0)
                    } else {
                        block {
                            Text("These are off Home and nowhere else. Every figure on your page still counts them, and every export still carries them.")
                                .thro(ThroTypography.metadata)
                                .foregroundStyle(ThroColor.colorTextSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                            ForEach(store.archived) { match in
                                MatchRow(match: match,
                                         editing: true,
                                         archived: true,
                                         onOpen: { store.flow = .resume(match.id) },
                                         onArchive: { withAnimation(.throEnter()) { store.setArchived(match.id, false) } },
                                         onDelete: { confirmingDelete = match })
                                ThroDivider()
                            }
                        }
                        .throEntrance(0)
                    }
                }
                .padding(.bottom, ThroSpacing.spacing6)
            }
        }
        .background(ThroColor.colorBackgroundPrimary.ignoresSafeArea())
        .confirmationDialog("Delete this match?",
                            isPresented: Binding(get: { confirmingDelete != nil },
                                                 set: { if !$0 { confirmingDelete = nil } }),
                            titleVisibility: .visible) {
            Button("Delete for good", role: .destructive) {
                if let match = confirmingDelete { store.delete(match.id) }
                confirmingDelete = nil
            }
            Button("Cancel", role: .cancel) { confirmingDelete = nil }
        } message: {
            if let match = confirmingDelete { Text(HomeScreen.deleteWarning(match)) }
        }
    }

    private func block<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: ThroSpacing.spacing3) { content() }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, ThroSpacing.spacing6)
            .padding(.horizontal, ThroSpacing.spaceScreenGutter)
            // The board above runs edge to edge; what is read under it sits in a column (PD-052).
            .throReadable()
    }
}

/// One match on this device: the players, the legs, when, and what it is worth as evidence.
///
/// In edit mode (PD-026) it also carries the two things a person can do with a match they no longer
/// want on Home. **Only in edit mode**: a row that always showed a delete button would put a
/// destructive control under the thumb of somebody reaching to open a match, and a row that hid
/// both behind a long press would hide them from everybody who has never discovered a long press.
public struct MatchRow: View {
    let match: AppStore.HomeMatch
    /// Whether the archive and delete controls are showing.
    var editing: Bool = false
    /// True on the shelf, where the archive control means *bring it back* rather than *put it away*.
    var archived: Bool = false
    let onOpen: () -> Void
    var onArchive: (() -> Void)?
    var onDelete: (() -> Void)?

    public init(match: AppStore.HomeMatch, editing: Bool = false, archived: Bool = false,
                onOpen: @escaping () -> Void, onArchive: (() -> Void)? = nil,
                onDelete: (() -> Void)? = nil) {
        self.match = match
        self.editing = editing
        self.archived = archived
        self.onOpen = onOpen
        self.onArchive = onArchive
        self.onDelete = onDelete
    }

    public var body: some View {
        HStack(spacing: 0) {
            Button(action: { if match.unreadable == nil { onOpen() } }) {
                details.throRowTapTarget()
            }
            .buttonStyle(ThroPressStyle(radius: ThroSpacing.radiusCard,
                                        pressedFill: ThroColor.colorSurfaceSecondary, scales: false))
            .disabled(match.unreadable != nil)
            if editing {
                if let onArchive {
                    Button(action: onArchive) {
                        Icon(archived ? .eye : .eyeOff, size: 20)
                            .foregroundStyle(ThroColor.colorTextSecondary)
                            .throTapTarget()
                    }
                    .buttonStyle(ThroPressStyle(radius: ThroSpacing.radiusStatus))
                    .accessibilityLabel(archived ? "Put \(match.record.homeName) v \(match.record.awayName) back on Home"
                                                 : "Archive \(match.record.homeName) v \(match.record.awayName)")
                }
                if let onDelete {
                    Button(action: onDelete) {
                        Icon(.circleX, size: 20)
                            .foregroundStyle(ThroColor.colorStatusError)
                            .throTapTarget()
                    }
                    .buttonStyle(ThroPressStyle(radius: ThroSpacing.radiusStatus))
                    .accessibilityLabel("Delete \(match.record.homeName) v \(match.record.awayName)")
                }
            }
        }
        // The controls slide in from the trailing edge rather than appearing, so a row that grows a
        // delete button under a finger is something the eye can follow.
        .animation(.throEnter(), value: editing)
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: ThroSpacing.spacing1) {
            HStack(alignment: .firstTextBaseline) {
                Text("\(match.record.homeName) v \(match.record.awayName)")
                    .thro(ThroTypography.heading3.weight(.bold))
                    .foregroundStyle(ThroColor.colorTextPrimary)
                    .lineLimit(1)
                Spacer()
                if match.unreadable == nil {
                    Text("\(match.legsHome)–\(match.legsAway)")
                        .thro(ThroTypography.heading3.family(.sport).weight(.bold))
                        .foregroundStyle(ThroColor.colorTextPrimary)
                }
            }
            HStack(spacing: ThroSpacing.spacing2) {
                Text("\(match.record.startingScore) · Bo\(match.record.legsTarget) · \(match.record.startedAt.formatted(date: .abbreviated, time: .shortened))")
                    .thro(ThroTypography.metadata)
                    .foregroundStyle(ThroColor.colorTextSecondary)
                    .lineLimit(1)
                Spacer(minLength: ThroSpacing.spacing2)
                if match.unreadable != nil {
                    // The score is not shown because it is not known. A match whose rows will not
                    // replay must not be opened into a scoring screen built on a state that could
                    // not be rebuilt, and must not be quietly dropped from the list either.
                    Tag("Cannot be read", tone: .error)
                } else if match.ending == .abandoned {
                    // NOT a verification state. There is no result here, and a "self-reported"
                    // badge would be attesting to a claim nobody made (PD-016).
                    Tag("No result", tone: .neutral)
                } else if match.ending != nil {
                    // A retirement IS a result, and it is the kind people later disagree about,
                    // so the row carries both what it was and who stands behind it.
                    Tag("Retired", tone: .warning)
                    VerificationState(.selfReported, compact: true)
                } else if match.complete {
                    VerificationState(.selfReported, compact: true)
                } else {
                    Tag("In progress", tone: .info)
                }
            }
            if let problem = match.unreadable {
                Text(problem)
                    .thro(ThroTypography.metadata)
                    .foregroundStyle(ThroColor.colorStatusError)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, ThroSpacing.spacing3)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// The Play tab: the way in to a match.
///
/// **It was one empty state and a button** — the founder's *bare and basic* in its purest form, on
/// the tab whose whole job is to start a game. What it lacked was not decoration but the two facts a
/// person opening it actually has: the match they walked away from, and what they last played.
///
/// Both come from the journal. Nothing here is remembered separately from the record, so nothing
/// here can be out of step with it.
public struct PlayLandingScreen: View {
    @ObservedObject var store: AppStore

    public init(store: AppStore) { self.store = store }

    private var inProgress: AppStore.HomeMatch? {
        store.matches.first { !$0.complete && $0.unreadable == nil }
    }

    /// The format of the last match started on this phone, described. Not a setting and not a
    /// preference — the record, read back, which is why it cannot drift from what was played.
    private var lastFormat: String? {
        guard let last = store.matches.first?.record else { return nil }
        let legs = last.legsMode == .bestOf ? "Best of \(last.legsTarget)" : "First to \(last.legsTarget)"
        let out = last.outRule == .double ? "double out" : "straight out"
        let inRule = last.inRule == .double ? ", double in" : ""
        return "\(last.startingScore) · \(legs) · \(out)\(inRule)"
    }

    public var body: some View {
        VStack(spacing: 0) {
            TopBar("Play", large: true)
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    if let match = inProgress {
                        block { ContinueCard(match: match) { store.flow = .resume(match.id) } }
                            .throEntrance(0)
                    }
                    block {
                        if inProgress == nil {
                            Text("Two players, one phone.")
                                .thro(ThroTypography.heading2.weight(.bold))
                                .foregroundStyle(ThroColor.colorTextPrimary)
                        }
                        ThroButton(inProgress == nil ? "Start match" : "Start another",
                                   variant: inProgress == nil ? .primary : .secondary,
                                   size: .large, fullWidth: true) { store.flow = .new }
                        if let lastFormat {
                            Text("Last time: \(lastFormat).")
                                .thro(ThroTypography.metadata)
                                .foregroundStyle(ThroColor.colorTextSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .throEntrance(1)
                    // A card rather than two loose sentences on bare paper. Settings is the screen in
                    // this app that reads as designed on a tablet, and the reason is that its content
                    // has body: rows in a card that fill the measure. Two paragraphs floating on a grey
                    // field are the same words with nothing holding them (PD-052).
                    block {
                        CardGroup("How this works") {
                            CardLine(icon: .filePen,
                                     text: "**Every visit is committed to this device before the screen "
                                         + "changes.** A crash between two darts loses nothing, because the "
                                         + "score you can see has already been written down.")
                            CardDivider()
                            CardLine(icon: .lock,
                                     text: "**Your matches stay on this phone.** Nothing here is uploaded. "
                                         + "The only thing this build sends anywhere is a sign-in, if you "
                                         + "choose to make one under Settings, and your matches are yours "
                                         + "until you export them.")
                        }
                    }
                    .throEntrance(2)
                    if !store.matches.isEmpty {
                        block {
                            SectionHeader("Lately", meta: "\(store.matches.count) on this device")
                            ForEach(store.matches.prefix(3)) { match in
                                MatchRow(match: match) { store.flow = .resume(match.id) }
                                ThroDivider()
                            }
                        }
                        .throEntrance(3)
                    }
                }
                .padding(.bottom, ThroSpacing.spacing6)
            }
        }
        .background(ThroColor.colorBackgroundPrimary.ignoresSafeArea())
    }

    private func block<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: ThroSpacing.spacing3) { content() }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, ThroSpacing.spacing6)
            .padding(.horizontal, ThroSpacing.spaceScreenGutter)
            // The board above runs edge to edge; what is read under it sits in a column (PD-052).
            .throReadable()
    }
}

/// The You tab. The export's You is a profile with a settings action in its TopBar; this build has
/// no profile to show and says so, and keeps the action.
///
/// It does have one true thing to put there: **the clubs kept on this phone**. Somebody who starts a
/// club under Discover and then looks for it under You has not made a mistake — that is where a
/// person expects their own things to be — so it is listed here and one tap goes to it. The tab
/// itself is not renamed: the tab set is the export's.
public struct YouScreen: View {
    /// What the You tab knows about the account, flattened so the screen needs no store.
    public enum Account: Equatable {
        /// The build names no server.
        case none
        case signedOut
        case busy(String)
        case signedIn(name: String?, ageBand: String, friends: Int?)
        /// Holding a session THRØ could not confirm — offline, or the server did not answer.
        case unverified
    }

    private let account: Account
    private let clubs: [Club]
    private let people: [LocalPerson]
    private let onSettings: () -> Void
    private let onAccount: () -> Void
    private let onFriends: () -> Void
    /// Straight to the page about the person, rather than to a list with it on.
    private let onProfile: () -> Void
    private let onClubs: () -> Void
    private let onPerson: (LocalPerson) -> Void
    private let badge: (Club) -> Image?

    /// Another go at confirming a session THRØ could not reach (`Account.unverified`).
    private let onRetry: () -> Void
    /// The signed-in person's picture, where this phone holds one.
    private let picture: Image?

    public init(account: Account = .none, picture: Image? = nil, clubs: [Club] = [], people: [LocalPerson] = [],
                badge: @escaping (Club) -> Image? = { _ in nil },
                onSettings: @escaping () -> Void,
                onAccount: @escaping () -> Void = {}, onFriends: @escaping () -> Void = {},
                onProfile: @escaping () -> Void = {}, onRetry: @escaping () -> Void = {},
                onClubs: @escaping () -> Void = {}, onPerson: @escaping (LocalPerson) -> Void = { _ in }) {
        self.onRetry = onRetry
        self.picture = picture
        self.account = account
        self.badge = badge
        self.clubs = clubs
        self.people = people
        self.onSettings = onSettings
        self.onAccount = onAccount
        self.onFriends = onFriends
        self.onProfile = onProfile
        self.onClubs = onClubs
        self.onPerson = onPerson
    }

    /// The slate's words for each state of the account.
    static func words(_ account: Account) -> (eyebrow: String, title: String, detail: String) {
        switch account {
        case .none: return ("You", "This phone", "This build names no server, so what you score stays here.")
        case .signedOut: return ("You", "Sign in to carry your darts with you", "Your name, your friends and the leagues you join live on your account. Matches scored here stay here either way.")
        case .busy(let what): return ("You", what, "One moment.")
        case .unverified:
            return ("You", "Signed in on this phone",
                    "THRØ could not be reached to confirm it just now. Nothing you score here depends on it.")
        case .signedIn(let name, let band, let friends):
            let who = name ?? "No name yet"
            let age = band == "adult" ? "18 or over" : band == "minor" ? "Under 18" : "Age not said yet"
            let mates = friends.map { $0 == 1 ? "1 friend" : "\($0) friends" } ?? "Friends"
            return ("You", who, "\(age) · \(mates)")
        }
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                header
                VStack(alignment: .leading, spacing: 0) {
                    if !people.isEmpty {
                        Eyebrow("Who plays on this phone").padding(.top, ThroSpacing.spacing6)
                        ThroDivider().padding(.top, ThroSpacing.spacing2)
                        ForEach(people) { person in
                            Button { onPerson(person) } label: {
                                HStack(spacing: ThroSpacing.spacing3) {
                                    PlayerIdentity(PlayerRef(name: person.name), size: .small)
                                    Spacer(minLength: 0)
                                    Icon(.chevronRight, size: 16).foregroundStyle(ThroColor.colorTextSecondary)
                                }
                                .padding(.vertical, ThroSpacing.spacing2)
                                .frame(minHeight: ThroSpacing.touchTargetMinimum)
                                .throRowTapTarget()
                            }
                            .buttonStyle(ThroPressStyle(radius: ThroSpacing.radiusCard,
                                                        pressedFill: ThroColor.colorSurfaceSecondary,
                                                        scales: false))
                            ThroDivider()
                        }
                    }
                    // Nothing here yet is still something to look at: a card holds the sentence and the
                    // way out of it, where a line of grey text and a loose button left two thirds of a
                    // tablet with nothing on it (PD-052).
                    if clubs.isEmpty {
                        CardGroup("Teams you keep") {
                            CardLine(icon: .users,
                                     text: "**None on this phone yet.** Start one under Discover and its "
                                         + "roster and fixtures are kept here.")
                            CardDivider()
                            CardPad {
                                ThroButton("Start a team", variant: .secondary, size: .large,
                                           fullWidth: true, action: onClubs)
                            }
                        }
                        .padding(.top, ThroSpacing.spaceSectionGap)
                    } else {
                        Eyebrow("Teams you keep").padding(.top, ThroSpacing.spaceSectionGap)
                        ThroDivider().padding(.top, ThroSpacing.spacing2)
                        ForEach(clubs) { club in
                            Button(action: onClubs) {
                                OrganisationRow(initials: club.initials, name: club.name,
                                                meta: "\(club.kind.label) · \(club.meta)",
                                                accent: club.accentHex.flatMap { Color.thro(hex: $0) },
                                                trailing: club.yourRole?.label,
                                                image: badge(club))
                                    .throRowTapTarget()
                            }
                            .buttonStyle(ThroPressStyle(radius: ThroSpacing.radiusCard,
                                                        pressedFill: ThroColor.colorSurfaceSecondary,
                                                        scales: false))
                            ThroDivider()
                        }
                    }
                    Note("Matches scored on this phone stay on it, whoever is signed in. A rating is not in this build: what you see are the figures the darts produced (PD-018).")
                        .padding(.top, ThroSpacing.spaceSectionGap)
                }
                .padding(.horizontal, ThroSpacing.spaceScreenGutter)
                .padding(.bottom, ThroSpacing.spacing6)
                // The last of the five tabs without the measure (PD-052). Home, Archive, Play and Live all
                // had it, so You was the one screen in the tab set that stretched across a tablet.
                .throReadable()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            // Paper under the lists; the field behind the top shows only above the header.
            .background(ThroColor.colorBackgroundPrimary)
            .throEntrance(0)
        }
        .throBrandFieldBehind()
    }

    /// The top of the tab: the brand field, and on it whoever this phone is signed in as — or the
    /// door in. It was a slate card under a system title bar, which made the You tab the one screen
    /// of the account area that started on paper; now it opens on the same field Home, Settings and
    /// your profile do, with you on it.
    private var header: some View {
        let w = YouScreen.words(account)
        return VStack(alignment: .leading, spacing: ThroSpacing.spacing4) {
            HStack(alignment: .center) {
                Eyebrow(w.eyebrow, color: ThroColor.throChalk.opacity(0.78))
                Spacer()
                Button(action: onSettings) {
                    Icon(.settings, size: 22)
                        .foregroundStyle(ThroColor.throChalk)
                        .throTapTarget(.trailing)
                }
                .buttonStyle(ThroPressStyle(radius: ThroSpacing.radiusStatus))
                .accessibilityLabel("Settings")
            }
            HStack(alignment: .center, spacing: ThroSpacing.spacing4) {
                if case .signedIn(let name, _, _) = account {
                    PersonMark(initials: AccountSlate.initials(name), size: 64, picture: picture)
                }
                VStack(alignment: .leading, spacing: ThroSpacing.spacing1) {
                    Text(w.title)
                        .thro(ThroTypography.heading1.family(.sport).weight(.bold).tracking(em: 0))
                        .foregroundStyle(ThroColor.throChalk)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(w.detail)
                        .thro(ThroTypography.body)
                        .foregroundStyle(ThroColor.throChalk.opacity(0.78))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            switch account {
            case .signedOut:
                slateButton("SIGN IN", lit: true, seed: 11, action: onAccount)
            case .signedIn:
                HStack(spacing: ThroSpacing.spacing3) {
                    slateButton("FRIENDS", lit: true, seed: 13, action: onFriends)
                    // **PROFILE, and it goes to the profile.** It used to say ACCOUNT and open a
                    // settings list, from which the profile was another row — five steps to the
                    // page that is about you, on the tab called You.
                    slateButton("PROFILE", lit: false, seed: 17, action: onProfile)
                }
            case .unverified:
                slateButton("TRY AGAIN", lit: true, seed: 19, action: onRetry)
            case .none, .busy:
                EmptyView()
            }
        }
        .padding(.horizontal, ThroSpacing.spaceScreenGutter)
        .padding(.top, ThroSpacing.spacing2)
        .padding(.bottom, ThroSpacing.spacing6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(ThroColor.colorBackgroundBrand)
    }

    private func slateButton(_ label: String, lit: Bool, seed: Double, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label).thro(ThroTypography.labelStrong.uppercase(true).tracking(em: 0.06))
                .foregroundStyle(ThroColor.colorTextOnBoard).padding(.horizontal, ThroSpacing.spacing4)
        }
        .buttonStyle(ChalkKeyStyle(lit ? .lit : .field, minHeight: ThroSpacing.touchTargetMinimum, seedAngle: seed))
        .fixedSize()
        .padding(.top, ThroSpacing.spacing1)
    }
}

/// What the running app was built from. The Xcode target stamps the short commit into Info.plist in a
/// script phase — a "+" after it means the checkout had uncommitted changes — so a phone can always
/// say which build it runs and the runbook can ask. A build without the stamp says so.
public enum BuildInfo {
    public static var commit: String {
        Bundle.main.object(forInfoDictionaryKey: "ThroBuildCommit") as? String ?? "unstamped"
    }
    public static var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
    }
    /// "1.0 · ea67fe6", or just the commit when there is no version.
    public static var label: String { version.isEmpty ? commit : "\(version) · \(commit)" }
}

/// One row of the export's Settings: an 18-point icon, the label, the value, a hairline beneath. The
/// export ends each row with a chevron; a row that goes nowhere does not pretend to.
public struct SettingsRow: View {
    private let icon: ThroIcon
    private let label: String
    private let value: String?

    public init(icon: ThroIcon, label: String, value: String? = nil) {
        self.icon = icon
        self.label = label
        self.value = value
    }

    public var body: some View {
        HStack(spacing: 12) {
            Icon(icon, size: 18).foregroundStyle(ThroColor.colorTextSecondary)
            Text(label).thro(ThroTypography.body).foregroundStyle(ThroColor.colorTextPrimary)
            Spacer(minLength: ThroSpacing.spacing3)
            if let value {
                Text(value).thro(ThroTypography.label).foregroundStyle(ThroColor.colorTextSecondary)
                    .multilineTextAlignment(.trailing)
            }
        }
        .frame(minHeight: 52)
        .overlay(alignment: .bottom) { Rectangle().fill(ThroColor.colorBorderDefault).frame(height: 1) }
        .accessibilityElement(children: .combine)
    }
}

/// The Live tab: what is happening now, on this phone.
///
/// **It was a screen that said "not built".** In an app with no network that is nearly true — you
/// cannot watch somebody else's match, and this build says so, at the bottom, where an absence
/// belongs. But *nothing live* was never true: a match in progress on this device is the most live
/// thing THRØ has, and a fixture somebody played and nobody has entered a result for is the one row
/// an official actually has to act on.
///
/// Everything here is read from the journal and the club book. **Nothing is scheduled, predicted or
/// invented** — including the ordering, which is the order an official typed the fixtures in,
/// because `Fixture.when` is a line of text an official wrote and not a date this app can sort by.
/// Saying that is better than sorting text and calling it a diary.
public struct LiveScreen: View {
    @ObservedObject var store: AppStore
    private let clubs: [Club]
    private let onClubs: () -> Void
    /// Where a fixture that has been played and not entered sends somebody: the screen that records
    /// it. Optional so the screen still stands up on its own with nowhere to send them.
    private let onRecord: ((Club, Fixture) -> Void)?
    /// Sending a finished match to THRØ (PD-040). Nil when this build has no server to send to.
    private let onSend: ((AppStore.HomeMatch) -> Void)?
    /// What the last send said — a count, or the reason it could not go.
    private let sendNote: String?
    /// Where a fixture still to play sends somebody: its club's list of fixtures, which is where
    /// the reminder, the calendar entry and the venue search live.
    private let onFixtures: ((Club) -> Void)?
    /// What THRØ holds of the matches this person played (PD-043). Nil when this build names no server.
    private let records: ThroMatchesModel?
    private let api: ThroAPI?
    private let signedIn: Bool
    /// Sharing a match live as it is scored (PD-044). Nil when this build names no server.
    private let liveShare: LiveShare?
    /// Which page of a sent match is open over this tab.
    @State private var sheet: ThroMatchSheet?

    public init(store: AppStore, clubs: [Club] = [], onClubs: @escaping () -> Void = {},
                onRecord: ((Club, Fixture) -> Void)? = nil,
                onFixtures: ((Club) -> Void)? = nil,
                onSend: ((AppStore.HomeMatch) -> Void)? = nil, sendNote: String? = nil,
                records: ThroMatchesModel? = nil, api: ThroAPI? = nil, signedIn: Bool = false,
                liveShare: LiveShare? = nil) {
        self.store = store
        self.clubs = clubs
        self.onClubs = onClubs
        self.onRecord = onRecord
        self.onFixtures = onFixtures
        self.onSend = onSend
        self.sendNote = sendNote
        self.records = records
        self.api = api
        self.signedIn = signedIn
        self.liveShare = liveShare
    }

    /// The name typed on this phone for the other seat, when this phone scored the match — this
    /// phone's own record, shown back to the person who typed it.
    private func typedOpponent(_ r: MatchOnRecord) -> String? {
        guard r.youSent, let other = r.theirs?.seat,
              let local = store.matches.first(where: { UUID(uuidString: $0.record.id.value) == r.matchId }) else { return nil }
        return other == "home" ? local.record.homeName : local.record.awayName
    }

    private var inProgress: [AppStore.HomeMatch] {
        store.matches.filter { !$0.complete && $0.unreadable == nil }
    }

    /// Played, and nobody has said what happened — across every club on this phone. A league's own
    /// screen leads with these for one league; this is all of them at once, which is the only place
    /// somebody keeping three clubs can see the whole of what they owe.
    private var awaiting: [(club: Club, fixture: Fixture)] {
        clubs.flatMap { club in club.fixturesAwaitingResults.map { (club, $0) } }
    }

    private var upcoming: [(club: Club, fixture: Fixture)] {
        clubs.flatMap { club in club.upcomingFixtures.map { (club, $0) } }
    }

    public var body: some View {
        VStack(spacing: 0) {
            TopBar("Live", large: true)
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    if inProgress.isEmpty && awaiting.isEmpty && upcoming.isEmpty {
                        block {
                            EmptyState(title: "Nothing on right now",
                                       message: "A match you are scoring shows here while it is going, and so do fixtures your teams have not finished with.",
                                       actionLabel: "Start match") { store.flow = .new }
                        }
                        .throEntrance(0)
                    }
                    if !inProgress.isEmpty {
                        block {
                            SectionHeader("On this phone", meta: inProgress.count == 1 ? "1 match" : "\(inProgress.count) matches")
                            ForEach(inProgress) { match in
                                ContinueCard(match: match) { store.flow = .resume(match.id) }
                                // Shared live (PD-044): the other player follows it on their own phone.
                                if let liveShare, signedIn {
                                    LiveShareRow(share: liveShare, match: match)
                                }
                            }
                        }
                        .throEntrance(0)
                    }
                    if !awaiting.isEmpty {
                        block {
                            SectionHeader("Waiting on a result", meta: "\(awaiting.count)")
                            Note("**Played, and nobody has said what happened.** Until somebody "
                                 + "does, these count for nothing in a table — not as a nil-nil, "
                                 + "and not as a win for anybody.")
                            ForEach(awaiting, id: \.fixture.id) { row in
                                // **Four screens became one tap.** This row used to open the list
                                // of clubs, from which the way to the control is the club, its
                                // fixtures, the fixture, and then Record — for the one row on this
                                // screen that exists because somebody has to act on it.
                                LiveFixtureRow(club: row.club, fixture: row.fixture) {
                                    guard let onRecord else { return onClubs() }
                                    onRecord(row.club, row.fixture)
                                }
                                ThroDivider()
                            }
                        }
                        .throEntrance(1)
                    }
                    if !upcoming.isEmpty {
                        block {
                            SectionHeader("Still to play", meta: "\(upcoming.count)")
                            ForEach(upcoming, id: \.fixture.id) { row in
                                LiveFixtureRow(club: row.club, fixture: row.fixture) {
                                    guard let onFixtures else { return onClubs() }
                                    onFixtures(row.club)
                                }
                                ThroDivider()
                            }
                            Note("**In the order they were entered.** A fixture's date is a line an "
                                 + "official typed, not something this app reads, so it is not "
                                 + "sorted into a diary it cannot honestly build.")
                        }
                        .throEntrance(2)
                    }
                    // Sending a match to THRØ (PD-040). Here rather than on the result screen
                    // because ThroPlay has no network target — that is the rule that keeps scoring
                    // working with no signal — so the one place that has both the journal and the
                    // account is this one.
                    if let onSend {
                        let done = store.matches.filter { $0.complete && $0.unreadable == nil }
                        block {
                            SectionHeader("Send to THRØ", meta: done.isEmpty ? nil : "\(done.count)")
                            if done.isEmpty {
                                Note("**A finished match can be sent to your account.** There is nothing "
                                     + "finished on this phone yet.")
                            } else {
                                Note("**THRØ takes the record, not a summary** — every visit and every undo, "
                                     + "as this phone wrote them. It is your word for the match until the "
                                     + "other player confirms it, and sending it again is safe.")
                                ForEach(done) { match in
                                    HStack(spacing: ThroSpacing.spacing3) {
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text("\(match.record.homeName) v \(match.record.awayName)")
                                                .thro(ThroTypography.body).foregroundStyle(ThroColor.colorTextPrimary)
                                            Text("\(match.legsHome)–\(match.legsAway)")
                                                .thro(ThroTypography.metadata).foregroundStyle(ThroColor.colorTextSecondary)
                                        }
                                        Spacer()
                                        ThroButton("Send", variant: .secondary, size: .small) { onSend(match) }
                                    }
                                    .frame(minHeight: ThroSpacing.touchTargetMinimum)
                                    ThroDivider()
                                }
                            }
                            if let sendNote {
                                Note(sendNote, icon: .info)
                            }
                        }
                        .throEntrance(3)
                    }
                    // What THRØ holds of the matches this person played (PD-043): where each one
                    // stands, the code for the other player, and the way in for somebody given one.
                    if let records, signedIn {
                        block {
                            ThroMatchesBlock(model: records, typedOpponent: typedOpponent,
                                             onOpen: { sheet = .match($0.matchId) },
                                             onEnterCode: { sheet = .enterCode })
                        }
                        .throEntrance(4)
                    }
                    // It said "watching is next" until PD-044 built it; now it says how, and to whom.
                    block {
                        if liveShare != nil && signedIn {
                            Note("**The other player can follow a match as you score it.** Switch on *Share it "
                                 + "live* under its card and give them the code from On THRØ; they open it there. "
                                 + "Nobody else can watch it: there are no spectators yet.")
                        } else {
                            Note("**A match can be followed from the other player's phone** once you are signed "
                                 + "in: it is shared live from its card here, and only with them.")
                        }
                    }
                    .throEntrance(5)
                }
                .padding(.bottom, ThroSpacing.spacing6)
            }
        }
        .background(ThroColor.colorBackgroundPrimary.ignoresSafeArea())
        .task(id: signedIn) { await records?.load(api, signedIn: signedIn) }
        .sheet(item: $sheet) { which in
            if let records {
                switch which {
                case .match(let id):
                    ThroMatchScreen(model: records, matchId: id, api: api,
                                    typed: records.record(id).flatMap(typedOpponent), onClose: { sheet = nil })
                case .enterCode:
                    // A seat taken opens its match, on the answer the other player is waiting for.
                    MatchCodeEntryScreen(model: records, api: api,
                                         onClaimed: { sheet = .match($0.matchId) }, onClose: { sheet = nil })
                }
            }
        }
    }

    private func block<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: ThroSpacing.spacing3) { content() }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, ThroSpacing.spacing6)
            .padding(.horizontal, ThroSpacing.spaceScreenGutter)
            // The board above runs edge to edge; what is read under it sits in a column (PD-052).
            .throReadable()
    }
}

/// One fixture on the Live tab, said with the club it belongs to — which the club's own fixture list
/// does not need to say and this one does, because here they are mixed together.
struct LiveFixtureRow: View {
    let club: Club
    let fixture: Fixture
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: ThroSpacing.spacing3) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(fixture.title)
                        .thro(ThroTypography.label.weight(.semibold))
                        .foregroundStyle(ThroColor.colorTextPrimary)
                        .lineLimit(1)
                    Text([club.name, fixture.when, fixture.venue].filter { !$0.isEmpty }.joined(separator: " · "))
                        .thro(ThroTypography.metadata)
                        .foregroundStyle(ThroColor.colorTextSecondary)
                        .lineLimit(1)
                }
                Spacer(minLength: ThroSpacing.spacing2)
                Tag(fixture.state.label, tone: fixture.awaitsResult ? .warning : .info)
                Icon(.chevronRight, size: 16).foregroundStyle(ThroColor.colorTextTertiary)
            }
            .padding(.vertical, ThroSpacing.spacing3)
            .frame(minHeight: ThroSpacing.touchTargetMinimum)
            .throRowTapTarget()
        }
        .buttonStyle(ThroPressStyle(radius: ThroSpacing.radiusCard,
                                    pressedFill: ThroColor.colorSurfaceSecondary, scales: false))
    }
}

/// The one account store for the app, made once the journal's device id is known; nil when the
/// build names no server, and the Settings row says so.
@MainActor
final class AccountHolder: ObservableObject {
    private(set) var store: AccountStore?
    /// The store's own changes, passed on. The root decides three things from the account — whether
    /// the welcome shows, whether the opening holds, where the profile goes — and before this it
    /// only re-read the account when something else happened to redraw it, which is how the opening
    /// could hand over to an app that did not yet know who was signed in.
    private var relay: AnyCancellable?

    func resolve(journalDeviceId: String?) -> AccountStore? {
        if store == nil {
            store = ThroServer.account(journalDeviceId: journalDeviceId)
            relay = store?.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }
        }
        return store
    }
}

/// The profile as it was when it was opened, and which part of it to open on.
struct ProfileOpening: Equatable {
    let profile: Profile
    let part: YourProfileScreen.Sub?
}

extension ThroRootView {
    var account: AccountStore? { accountHolder.resolve(journalDeviceId: AppStore.deviceId()) }

    /// Your profile if you are signed in; the welcome board if you are not; and, for a phone holding a
    /// session THRØ has not confirmed yet, the account screen that says so and tries again.
    func openAccount(_ part: YourProfileScreen.Sub?) {
        if let profile = account?.profile, profile.accountId != nil {
            profileOpen = ProfileOpening(profile: profile, part: part)
        } else {
            openingFriends = false
            showingAccount = true
        }
    }

    /// Send a finished match to THRØ (PD-040).
    ///
    /// **Which seat was yours is a question only you can answer**, and this build answers it the one
    /// honest way it can without asking: by your own name. A local match is two names typed at an
    /// oche, so if neither is yours THRØ says so rather than guessing — a match filed under the
    /// wrong player is worse than a match not filed at all.
    private func sendToThro(_ match: AppStore.HomeMatch) {
        guard let account, let journal = store.journal else { return }
        guard case .signedIn(let profile) = account.state, let mine = profile.displayName, profile.named else {
            sendNote = "Name yourself on your profile first, so THRØ knows which player you were."
            return
        }
        let record = match.record
        guard let seat = MatchUpload.seat(of: mine, home: record.homeName, away: record.awayName) else {
            sendNote = "THRØ cannot tell which player you were in \(record.homeName) v \(record.awayName). "
                + "Your profile says \(mine). Score under the name on your profile and it will know."
            return
        }

        let entries: [JournalEntry]
        do { entries = try journal.entries(for: record.id) } catch {
            sendNote = "This phone could not read that match back: \(error.localizedDescription)"
            return
        }
        guard case .ready(let rows) = MatchUpload.rows(from: entries) else {
            if case .notYet(let reason) = MatchUpload.rows(from: entries) { sendNote = reason }
            return
        }
        // The server's words for the format, spelled out (see `MatchUpload.format`): described, the legs
        // mode came out `bestof`, and no match a phone sent was ever taken.
        let format = MatchUpload.format(for: record)
        sendNote = "Sending…"
        Task {
            do {
                let sent = try await account.api.sendMatch(
                    matchId: UUID(uuidString: record.id.value) ?? UUID(),
                    deviceId: UUID(uuidString: AppStore.deviceId()) ?? UUID(), seat: seat, format: format, rows: rows)
                sendNote = MatchUpload.done(sent)
                // It is on THRØ now, with a seat for the other player to take: show it there.
                await throMatches.load(account.api, signedIn: true)
            } catch {
                sendNote = SignInProblem.words(error)
            }
        }
    }
    /// Sharing matches live (PD-044): every three seconds, the new rows of the shared matches go up.
    /// Runs for the life of the root view, and does nothing while nothing is shared.
    func shareLoop() async {
        while !Task.isCancelled {
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            guard let account, account.isSignedIn, !liveShare.sharing.isEmpty else { continue }
            let name = account.profile.flatMap { $0.named ? $0.displayName : nil }
            // A match on THRØ for the first time has a seat for the other player to take: show it there.
            if await liveShare.tick(store: store, api: account.api, profileName: name) {
                await throMatches.load(account.api, signedIn: true)
            }
        }
    }

    /// What the You tab shows on its slate.
    var youAccount: YouScreen.Account {
        guard let account else { return .none }
        switch account.state {
        case .signedIn(let p): return .signedIn(name: p.named ? p.displayName : nil, ageBand: p.ageBand, friends: account.friends?.count)
        case .busy(let what): return .busy(what)
        // Still holding a session THRØ could not confirm: signed in, and said so honestly.
        case .failed(_, wasSignedIn: true): return .unverified
        case .failed, .signedOut: return .signedOut
        }
    }
    /// The signed-in person's picture, where this phone holds one (`AccountPicture`).
    var accountPicture: Image? {
        guard let id = account?.profile?.accountId else { return nil }
        return clubs.image(AccountPicture.assetId(id))
    }
}

