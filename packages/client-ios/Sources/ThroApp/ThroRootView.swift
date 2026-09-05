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
        public var id: MatchId { record.id }
    }

    public let journal: Journal?
    /// Why the journal could not be opened, when it could not. Shown, never swallowed.
    public let openProblem: String?

    @Published public var tab: BottomBar.Tab = .home
    @Published public var flow: Flow?
    @Published public private(set) var matches: [HomeMatch] = []

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

    static func openJournal() throws -> Journal {
        let support = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                                  appropriateFor: nil, create: true)
        let dir = support.appendingPathComponent("THRO", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return try Journal(path: dir.appendingPathComponent("journal.sqlite").path, deviceId: DeviceId(deviceId()))
    }

    /// A random identifier for this install. It names the device in the journal's sequence and is
    /// not a secret and not a hardware identifier.
    static func deviceId() -> String {
        let key = "thro.journal.deviceId"
        if let existing = UserDefaults.standard.string(forKey: key) { return existing }
        let fresh = UUID().uuidString
        UserDefaults.standard.set(fresh, forKey: key)
        return fresh
    }

    public func refresh() {
        guard let journal else { matches = []; return }
        let records = (try? journal.matches()) ?? []
        matches = records.compactMap { record in
            guard let state = try? journal.replay(record.id) else { return nil }
            return HomeMatch(record: record,
                             legsHome: state.legsWonTotal[Seat.home.playerId] ?? 0,
                             legsAway: state.legsWonTotal[Seat.away.playerId] ?? 0,
                             complete: state.isComplete)
        }
    }
}

/// The root of the app. Mount this from the Xcode app target's `App`:
///
///     @main struct ThroDartsApp: App { var body: some Scene { WindowGroup { ThroRootView() } } }
public struct ThroRootView: View {
    @StateObject private var store: AppStore

    public init() { _store = StateObject(wrappedValue: AppStore()) }
    public init(store: AppStore) { _store = StateObject(wrappedValue: store) }

    public var body: some View {
        if let flow = store.flow, let journal = store.journal {
            PlayFlow(journal: journal, resume: resumeId(flow)) {
                store.flow = nil
                store.refresh()
            }
        } else {
            VStack(spacing: 0) {
                tabContent
                BottomBar(selection: store.tab) { store.tab = $0 }
            }
            .background(ThroColor.colorBackgroundPrimary.ignoresSafeArea())
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
        case .discover: NotBuiltScreen(title: "Discover")
        case .you: NotBuiltScreen(title: "You")
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
                            EmptyState(title: "The journal could not be opened", message: problem)
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
        Button(action: onOpen) {
            VStack(alignment: .leading, spacing: ThroSpacing.spacing1) {
                HStack(alignment: .firstTextBaseline) {
                    Text("\(match.record.homeName) v \(match.record.awayName)")
                        .thro(ThroTypography.heading3.weight(.bold))
                        .foregroundStyle(ThroColor.colorTextPrimary)
                        .lineLimit(1)
                    Spacer()
                    Text("\(match.legsHome)–\(match.legsAway)")
                        .thro(ThroTypography.heading3.family(.sport).weight(.bold))
                        .foregroundStyle(ThroColor.colorTextPrimary)
                }
                HStack(spacing: ThroSpacing.spacing2) {
                    Text("\(match.record.startingScore) · Bo\(match.record.legsTarget) · \(match.record.startedAt.formatted(date: .abbreviated, time: .shortened))")
                        .thro(ThroTypography.metadata)
                        .foregroundStyle(ThroColor.colorTextSecondary)
                    Spacer()
                    if match.complete {
                        VerificationState(.selfReported, compact: true)
                    } else {
                        Tag("In progress", tone: .info)
                    }
                }
            }
            .padding(.vertical, ThroSpacing.spacing3)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
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
