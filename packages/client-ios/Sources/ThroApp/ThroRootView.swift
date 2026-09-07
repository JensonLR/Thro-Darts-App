import SwiftUI
import ThroTokens
import ThroDesign
import ThroJournal
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
        guard let journal else { matches = []; listProblem = nil; return }
        let records: [MatchRecord]
        do {
            records = try journal.matches()
            listProblem = nil
        } catch {
            matches = []
            listProblem = "\(error)"
            return
        }
        matches = records.map { record in
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
    /// The person whose page is open, if any. Their figures come from the journal, so this is the
    /// one screen in the app where a statistic is about a person rather than about a match.
    @State private var viewing: LocalPerson?
    /// PD-007: the opening plays once, at cold launch, over whatever the app shows first.
    @State private var opening = true

    public init() { _store = StateObject(wrappedValue: AppStore()) }
    public init(store: AppStore) { _store = StateObject(wrappedValue: store) }

    public var body: some View {
        ZStack {
            content
            if opening {
                LaunchSequenceView { fade in
                    withAnimation(.easeInOut(duration: fade)) { opening = false }
                }
                .transition(.opacity)
                .zIndex(1)
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
            PersonScreen(person: person, journal: store.journal, clubs: clubs.clubs) { viewing = nil }
                .throAppearance(Appearance(stored: appearanceRaw))
        } else if showingSettings {
            SettingsScreen(onBack: { showingSettings = false },
                           onReplayOpening: { showingSettings = false; opening = true },
                           backupState: { store.backupState },
                           makeExport: { try store.exportEverything(clubs: clubs.book) })
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
        case .live: NotBuiltScreen(title: "Live")
        case .discover: ClubsFlow(store: clubs)
        case .you: YouScreen(clubs: clubs.clubs, people: clubs.people,
                             badge: { clubs.image($0.badgeAssetId) },
                             onSettings: { showingSettings = true },
                             onClubs: { store.tab = .discover },
                             onPerson: { viewing = $0 })
        }
    }
}

/// Home, honestly. The export's `home-new` shows a rating hero, a confidence meter and events near
/// you; none of those exist for this build (OD-001, no servers), so Home shows what is true: the
/// matches on this device, or an empty state with the one action that is real.
public struct HomeScreen: View {
    @ObservedObject var store: AppStore

    public init(store: AppStore) { self.store = store }

    public var body: some View {
        VStack(spacing: 0) {
            TopBar("Home", large: true)
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    FontSubstitutionNotice()
                        .padding(.horizontal, ThroSpacing.spaceScreenGutter)
                        .padding(.top, ThroSpacing.spacing4)
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
                    } else if store.matches.isEmpty {
                        block {
                            EmptyState(title: "No matches yet",
                                       message: "Score a match on this device and it will appear here.",
                                       actionLabel: "Start match") { store.flow = .new }
                        }
                    } else {
                        block {
                            SectionHeader("On this device", meta: "\(store.matches.count) \(store.matches.count == 1 ? "match" : "matches")")
                            ForEach(store.matches) { match in
                                MatchRow(match: match) { store.flow = .resume(match.id) }
                                ThroDivider()
                            }
                        }
                        block {
                            ThroButton("Start match", variant: .primary, size: .large, fullWidth: true) { store.flow = .new }
                        }
                    }
                }
            }
        }
        .background(ThroColor.colorBackgroundPrimary.ignoresSafeArea())
    }

    private func block<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: ThroSpacing.spacing3) { content() }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, ThroSpacing.spacing6)
            .padding(.horizontal, ThroSpacing.spaceScreenGutter)
    }
}

/// One match on this device: the players, the legs, when, and what it is worth as evidence.
public struct MatchRow: View {
    let match: AppStore.HomeMatch
    let onOpen: () -> Void

    public init(match: AppStore.HomeMatch, onOpen: @escaping () -> Void) {
        self.match = match
        self.onOpen = onOpen
    }

    public var body: some View {
        Button(action: { if match.unreadable == nil { onOpen() } }) {
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
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(match.unreadable != nil)
    }
}

/// The Play tab: the way in to a new match.
public struct PlayLandingScreen: View {
    @ObservedObject var store: AppStore

    public init(store: AppStore) { self.store = store }

    public var body: some View {
        VStack(spacing: 0) {
            TopBar("Play", large: true)
            ScrollView {
                VStack(alignment: .leading, spacing: ThroSpacing.spacing4) {
                    EmptyState(title: "Score a match",
                               message: "Two players, one phone. Every visit is saved to this device before it is shown, so a crash loses nothing.",
                               actionLabel: "Start match") { store.flow = .new }
                }
                .padding(.vertical, ThroSpacing.spacing6)
                .padding(.horizontal, ThroSpacing.spaceScreenGutter)
            }
        }
        .background(ThroColor.colorBackgroundPrimary.ignoresSafeArea())
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
    private let clubs: [Club]
    private let people: [LocalPerson]
    private let onSettings: () -> Void
    private let onClubs: () -> Void
    private let onPerson: (LocalPerson) -> Void
    private let badge: (Club) -> Image?

    public init(clubs: [Club] = [], people: [LocalPerson] = [],
                badge: @escaping (Club) -> Image? = { _ in nil },
                onSettings: @escaping () -> Void,
                onClubs: @escaping () -> Void = {}, onPerson: @escaping (LocalPerson) -> Void = { _ in }) {
        self.badge = badge
        self.clubs = clubs
        self.people = people
        self.onSettings = onSettings
        self.onClubs = onClubs
        self.onPerson = onPerson
    }

    public var body: some View {
        VStack(spacing: 0) {
            TopBar("You", actions: [TopBar.Action(icon: .settings, label: "Settings", action: onSettings)], large: true)
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    EmptyState(title: "Profile not in this build",
                               message: "Your profile, rating and passport need THRØ's servers. This build scores matches and keeps them on the device; nothing else is connected yet. Settings are behind the gear above.")
                        .padding(.top, ThroSpacing.spacing6)
                    if !people.isEmpty {
                        Eyebrow("Who plays on this phone").padding(.top, ThroSpacing.spaceSectionGap)
                        ThroDivider().padding(.top, ThroSpacing.spacing2)
                        ForEach(people) { person in
                            Button { onPerson(person) } label: {
                                HStack(spacing: ThroSpacing.spacing3) {
                                    PlayerIdentity(PlayerRef(name: person.name), size: .small)
                                    Spacer(minLength: 0)
                                    Icon(.chevronRight, size: 16).foregroundStyle(ThroColor.colorTextSecondary)
                                }
                                .padding(.vertical, ThroSpacing.spacing2)
                            }
                            .buttonStyle(.plain)
                            ThroDivider()
                        }
                    }
                    Eyebrow("Clubs you keep").padding(.top, ThroSpacing.spaceSectionGap)
                    if clubs.isEmpty {
                        Text("None on this phone. Start one under Discover and its roster and fixtures are kept here.")
                            .thro(ThroTypography.body)
                            .foregroundStyle(ThroColor.colorTextSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.top, ThroSpacing.spacing2)
                        ThroButton("Start a club", variant: .secondary, size: .large,
                                   fullWidth: true, action: onClubs)
                            .padding(.top, ThroSpacing.spacing4)
                    } else {
                        ThroDivider().padding(.top, ThroSpacing.spacing2)
                        ForEach(clubs) { club in
                            Button(action: onClubs) {
                                OrganisationRow(initials: club.initials, name: club.name,
                                                meta: "\(club.kind.label) · \(club.meta)",
                                                accent: club.accentHex.flatMap { Color.thro(hex: $0) },
                                                trailing: club.yourRole?.label,
                                                image: badge(club))
                            }
                            .buttonStyle(.plain)
                            ThroDivider()
                        }
                    }
                }
                .padding(.horizontal, ThroSpacing.spaceScreenGutter)
                .padding(.bottom, ThroSpacing.spacing6)
            }
        }
        .background(ThroColor.colorBackgroundPrimary.ignoresSafeArea())
    }
}

/// After the export's Settings screen: grouped rows of icon, label and value under section headers.
/// Only what is true of this build appears — one setting, and the facts of the build. PD-003 puts the
/// appearance choice here.
public struct SettingsScreen: View {
    @AppStorage(Appearance.storageKey) private var appearanceRaw: String = Appearance.system.rawValue
    @AppStorage(ScoringPreferences.keepScreenAwakeKey) private var keepScreenAwake: Bool = true
    @AppStorage(ThroHaptics.enabledKey) private var haptics: Bool = true
    @AppStorage(OpeningPreferences.soundKey) private var openingSound: Bool = true
    @AppStorage(OpeningPreferences.hapticsKey) private var openingHaptics: Bool = true
    private let onBack: () -> Void
    private let onReplayOpening: (() -> Void)?
    /// PD-017. Where the file comes from and what the file system says about backups. Closures
    /// rather than the stores themselves, so Settings stays a screen and not a second owner of the
    /// device's data — and so a test can drive both without a journal on disk.
    private let backupState: () -> BackupPolicy.State
    private let makeExport: (() throws -> URL)?
    @State private var exported: URL?
    @State private var exportProblem: String?

    public init(onBack: @escaping () -> Void, onReplayOpening: (() -> Void)? = nil,
                backupState: @escaping () -> BackupPolicy.State = { .unknown("no data folder in this build") },
                makeExport: (() throws -> URL)? = nil) {
        self.onBack = onBack
        self.onReplayOpening = onReplayOpening
        self.backupState = backupState
        self.makeExport = makeExport
    }

    private var appearance: Binding<Appearance> {
        Binding(get: { Appearance(stored: appearanceRaw) }, set: { appearanceRaw = $0.rawValue })
    }

    public var body: some View {
        VStack(spacing: 0) {
            TopBar("Settings", onBack: onBack, large: true)
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    group("Appearance") {
                        SegmentedControl(Appearance.allCases.map { ($0, $0.label) }, selection: appearance)
                        Text("Every screen follows this, scoring included. System follows the phone.")
                            .thro(ThroTypography.metadata)
                            .foregroundStyle(ThroColor.colorTextSecondary)
                    }
                    group("Scoring") {
                        // The export's Settings lists this row under Scoring, default On. The switch
                        // is the platform's; the export draws no toggle.
                        HStack(spacing: 12) {
                            Icon(.smartphone, size: 18).foregroundStyle(ThroColor.colorTextSecondary)
                            Toggle(isOn: $keepScreenAwake) {
                                Text("Keep screen awake").thro(ThroTypography.body).foregroundStyle(ThroColor.colorTextPrimary)
                            }
                            .tint(ThroColor.colorSurfaceBrand)
                        }
                        .frame(minHeight: 52)
                        .overlay(alignment: .bottom) { Rectangle().fill(ThroColor.colorBorderDefault).frame(height: 1) }
                        Text("While scoring, the phone does not sleep between visits.")
                            .thro(ThroTypography.metadata)
                            .foregroundStyle(ThroColor.colorTextSecondary)
                        // PD-015. Default on: the point of a haptic at a dartboard is that it is
                        // felt while the player is looking at the board. Off is offered because a
                        // phone buzzing in a pocket through a match is somebody else's idea of help.
                        HStack(spacing: 12) {
                            Icon(.target, size: 18).foregroundStyle(ThroColor.colorTextSecondary)
                            Toggle(isOn: $haptics) {
                                Text("Haptics").thro(ThroTypography.body).foregroundStyle(ThroColor.colorTextPrimary)
                            }
                            .tint(ThroColor.colorSurfaceBrand)
                        }
                        .frame(minHeight: 52)
                        .overlay(alignment: .bottom) { Rectangle().fill(ThroColor.colorBorderDefault).frame(height: 1) }
                        Text("A light tap on every key, a firmer one when a visit is saved, and a distinct one for a bust and for a leg won — so those two are felt without looking at the phone.")
                            .thro(ThroTypography.metadata)
                            .foregroundStyle(ThroColor.colorTextSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    group("Opening") {
                        // PD-007 v2: the throw that opens the app, its sound and its haptic. Sound goes
                        // through the ambient session, so the silent switch always wins.
                        toggleRow(icon: .info, label: "Sound", isOn: $openingSound)
                        toggleRow(icon: .smartphone, label: "Haptic on the strike", isOn: $openingHaptics)
                        if let onReplayOpening {
                            ThroButton("Play the opening again", variant: .secondary, size: .medium, action: onReplayOpening)
                                .padding(.top, ThroSpacing.spacing2)
                        }
                        Text("The silent switch silences the sound whatever this says. Reduce Motion shows the finished mark instead of the throw.")
                            .thro(ThroTypography.metadata)
                            .foregroundStyle(ThroColor.colorTextSecondary)
                    }
                    group("Your darts") {
                        // PD-017. Both halves are told. A player who learns their darts are in
                        // iCloud from a support article rather than from the app has been failed
                        // twice — and one who assumes they are, and is wrong, has been failed worse.
                        let state = backupState()
                        SettingsRow(icon: state.isIncluded ? .cloudCheck : .cloudOff,
                                    label: "In the phone's backup",
                                    value: state.isIncluded ? "Yes" : "No")
                        Text(BackupPolicy.sentence(state))
                            .thro(ThroTypography.metadata)
                            .foregroundStyle(state.isIncluded ? ThroColor.colorTextSecondary : ThroColor.colorStatusError)
                            .fixedSize(horizontal: false, vertical: true)
                        if let makeExport {
                            ThroButton("Export everything", variant: .secondary, size: .medium) {
                                do {
                                    exported = try makeExport()
                                    exportProblem = nil
                                } catch {
                                    exported = nil
                                    exportProblem = "\(error)"
                                }
                            }
                            .padding(.top, ThroSpacing.spacing2)
                            if let exported {
                                ShareLink(item: exported) {
                                    Text("Save or send \(exported.lastPathComponent)")
                                        .thro(ThroTypography.body.weight(.semibold))
                                        .foregroundStyle(ThroColor.colorTextBrand)
                                }
                            }
                            if let exportProblem {
                                Snackbar(exportProblem, tone: .error)
                            }
                            Text("One file with every match, every visit as written — corrections and all — and every club this phone keeps. Nothing is sent anywhere: you choose where it goes. Pictures are not in it; the file names the ones this phone holds.")
                                .thro(ThroTypography.metadata)
                                .foregroundStyle(ThroColor.colorTextSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    group("This build") {
                        SettingsRow(icon: .info, label: "Build", value: BuildInfo.label)
                        SettingsRow(icon: .info, label: "Matches", value: "Stay on this device")
                        SettingsRow(icon: .cloudOff, label: "Sending results to THRØ", value: "Not built")
                        SettingsRow(icon: .info, label: "Fonts", value: ThroFont.customFacesRegistered ? "Embedded" : "System face")
                        SettingsRow(icon: .circleUser, label: "Account and profile", value: "Not built")
                    }
                }
            }
        }
        .background(ThroColor.colorBackgroundPrimary.ignoresSafeArea())
    }

    private func toggleRow(icon: ThroIcon, label: String, isOn: Binding<Bool>) -> some View {
        HStack(spacing: 12) {
            Icon(icon, size: 18).foregroundStyle(ThroColor.colorTextSecondary)
            Toggle(isOn: isOn) {
                Text(label).thro(ThroTypography.body).foregroundStyle(ThroColor.colorTextPrimary)
            }
            .tint(ThroColor.colorSurfaceBrand)
        }
        .frame(minHeight: 52)
        .overlay(alignment: .bottom) { Rectangle().fill(ThroColor.colorBorderDefault).frame(height: 1) }
    }

    private func group<Content: View>(_ title: String, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: ThroSpacing.spacing3) {
            SectionHeader(title)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, ThroSpacing.spacing2)
        .padding(.bottom, ThroSpacing.spacing4)
        .padding(.horizontal, ThroSpacing.spaceScreenGutter)
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

/// The tabs the export draws and this build cannot honestly fill. They say so.
public struct NotBuiltScreen: View {
    let title: String

    public init(title: String) { self.title = title }

    public var body: some View {
        VStack(spacing: 0) {
            TopBar(title, large: true)
            ScrollView {
                EmptyState(title: "Not in this build",
                           message: "\(title) needs THRØ's servers. This build scores matches and keeps them on the device; nothing else is connected yet.")
                    .padding(.vertical, ThroSpacing.spacing6)
                    .padding(.horizontal, ThroSpacing.spaceScreenGutter)
            }
        }
        .background(ThroColor.colorBackgroundPrimary.ignoresSafeArea())
    }
}
