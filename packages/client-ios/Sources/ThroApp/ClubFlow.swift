import Foundation
import SwiftUI
import ThroTokens
import ThroDesign
import ThroJournal
import ThroPlay

// Clubs on the phone, wired to the book that holds them (PD-009, PD-010).
//
// What is real in this build and what is not, stated once here so no screen has to imply it:
//
//  - **Real**: a club you start, its roster, its fixture list. It is yours, it is on this phone, and
//    it survives being closed because `ClubBook` writes under the measured configuration.
//  - **Not real**: joining somebody else's club, and sending an announcement. Both need a server and
//    an identity (Gate 6, B4). The announcement composer exists and is reachable, because what it
//    says about who would be reached is true and worth showing; the send is refused with the reason
//    rather than pretended.

/// The clubs this device holds, as the screens want them.
public final class ClubStore: ObservableObject {
    /// The book, or nil when it could not be opened.
    public let book: ClubBook?
    /// Why it could not be opened, when it could not. Shown, never swallowed.
    public let openProblem: String?

    @Published public private(set) var clubs: [Club] = []
    /// Why the last write did not happen. Cleared when the next one succeeds.
    @Published public var writeProblem: String?

    public init() {
        do {
            book = try ClubStore.open()
            openProblem = nil
        } catch {
            book = nil
            openProblem = "\(error)"
        }
        refresh()
    }

    /// For previews and tests: a store over a book the caller made.
    public init(book: ClubBook) {
        self.book = book
        self.openProblem = nil
        refresh()
    }

    static func open() throws -> ClubBook {
        let support = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                                  appropriateFor: nil, create: true)
        let dir = support.appendingPathComponent("THRO", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        // Its own file, beside the journal and not inside it: see the note at the top of ClubBook.
        return try ClubBook(path: dir.appendingPathComponent("clubs.sqlite").path)
    }

    public func refresh() {
        guard let book else { clubs = []; people = []; return }
        do {
            clubs = try book.clubs().map { try ClubStore.assemble($0, from: book) }
            people = try book.people()
        } catch {
            clubs = []
            people = []
            writeProblem = "\(error)"
        }
    }

    public func club(_ id: String) -> Club? { clubs.first { $0.id == id } }

    // MARK: - writes

    /// Runs a write and keeps its failure, rather than dropping it on the floor. Returns whether it
    /// happened, so a screen can stay open on a refusal instead of dismissing over the top of it.
    @discardableResult
    private func write(_ body: (ClubBook) throws -> Void) -> Bool {
        guard let book else { writeProblem = openProblem ?? "no club book on this device"; return false }
        do {
            try body(book)
            writeProblem = nil
            refresh()
            return true
        } catch {
            writeProblem = "\(error)"
            return false
        }
    }

    @discardableResult
    public func createClub(name: String, kind: OrgKind, accentHex: String?) -> Bool {
        write { try $0.createClub(name: name, kind: kind.rawValue, accentHex: accentHex) }
    }

    @discardableResult
    public func rename(_ clubId: String, to name: String, accentHex: String?) -> Bool {
        write { try $0.updateClub(id: clubId, name: name, accentHex: accentHex) }
    }

    @discardableResult
    public func delete(_ clubId: String) -> Bool {
        write { try $0.deleteClub(id: clubId) }
    }

    @discardableResult
    public func addMember(to clubId: String, name: String, role: OrgRole, ageBand: AgeBand) -> Bool {
        write { try $0.addMember(to: clubId, name: name, role: role.rawValue, ageBand: ageBand.rawValue) }
    }

    @discardableResult
    public func removeMember(_ memberId: String, from clubId: String) -> Bool {
        write { try $0.removeMember(memberId, from: clubId) }
    }

    @discardableResult
    public func addFixture(to clubId: String, title: String, when: Date, venue: String) -> Bool {
        write { try $0.addFixture(to: clubId, title: title, when: when, venue: venue) }
    }

    @discardableResult
    public func move(_ fixtureId: String, in clubId: String, to state: FixtureState) -> Bool {
        write { try $0.moveFixture(fixtureId, in: clubId, to: state.rawValue) }
    }

    // MARK: - people (ADR-016)

    /// Everybody who has played on this device.
    @Published public private(set) var people: [LocalPerson] = []

    /// The person a typed name refers to, adding them to the book if they are new.
    ///
    /// Returns nil only when the book could not be written, in which case the match is still played
    /// and still saved — it simply carries no player id, which is the same state every match written
    /// before ADR-016 is in, and is recoverable later.
    public func person(named name: String) -> LocalPerson? {
        guard let book else { return nil }
        do {
            let found = try book.person(named: name)
            people = try book.people()
            return found
        } catch {
            writeProblem = "\(error)"
            return nil
        }
    }

    public func rename(person id: String, to name: String) -> Bool {
        write { try $0.renamePerson(id, to: name) }
    }

    // MARK: - the mapping

    /// A stored club, its roster and its fixtures, as one value the screens read.
    ///
    /// **`yourRole` is `.admin`, and that is a fact rather than a shortcut.** A club in this book is
    /// one the keeper of this phone started; nobody else can see it and nobody else can change it.
    /// When a server exists, the server says what someone's role is and this mapping goes with it —
    /// which is exactly why `Club` carries the role rather than assuming it.
    static func assemble(_ stored: StoredClub, from book: ClubBook) throws -> Club {
        let members = try book.members(of: stored.id).map { m in
            ClubMember(id: m.id, name: m.name,
                       role: OrgRole(rawValue: m.role) ?? .member,
                       // The permissive default would list a child. `ClubBook` already collapses an
                       // unreadable band to `unknown`; this is the same direction, kept twice on purpose.
                       ageBand: AgeBand(rawValue: m.ageBand) ?? .unknown,
                       joined: ClubStore.joined.string(from: m.joinedAt))
        }
        let fixtures = try book.fixtures(of: stored.id).map { f in
            Fixture(id: f.id, title: f.title, when: ClubStore.when.string(from: f.when),
                    venue: f.venue, state: FixtureState(rawValue: f.state) ?? .scheduled)
        }
        return Club(id: stored.id, name: stored.name,
                    kind: OrgKind(rawValue: stored.kind) ?? .club,
                    meta: ClubStore.meta(members.count),
                    accentHex: stored.accentHex,
                    // Nothing on this device has been verified by anybody, so nothing wears the mark.
                    verified: false,
                    yourRole: .admin,
                    members: members,
                    fixtures: fixtures,
                    // Nothing has been sent, because there is nowhere to send it.
                    announcements: [])
    }

    static func meta(_ members: Int) -> String {
        members == 0 ? "No members yet" : "\(members) member\(members == 1 ? "" : "s")"
    }

    static let when: DateFormatter = {
        let f = DateFormatter()
        f.setLocalizedDateFormatFromTemplate("EEE d MMM HH:mm")
        return f
    }()

    static let joined: DateFormatter = {
        let f = DateFormatter()
        f.setLocalizedDateFormatFromTemplate("MMM y")
        return f
    }()
}

// MARK: - the flow

/// Where the Clubs tab is. A small enum rather than a NavigationStack, for the reason the Play flow
/// gives: the screens are few, the transitions are known, and a route that cannot be constructed
/// cannot be reached.
public enum ClubRoute: Equatable {
    case list
    case newClub
    case club(String)
    case members(String)
    case newMember(String)
    case fixtures(String)
    case newFixture(String)
    case announce(String)
    case member(club: String, member: String)
}

/// The Clubs tab.
public struct ClubsFlow: View {
    @ObservedObject private var store: ClubStore
    @State private var route: ClubRoute = .list

    public init(store: ClubStore) { self.store = store }

    public var body: some View {
        content
            // A refusal is shown where it happened, over the screen that caused it.
            .overlay(alignment: .bottom) {
                if let problem = store.writeProblem {
                    Snackbar(problem, tone: .error, actionLabel: "Dismiss") { store.writeProblem = nil }
                        .padding(.horizontal, ThroSpacing.spaceScreenGutter)
                        .padding(.bottom, ThroSpacing.spacing4)
                }
            }
    }

    /// The club a route names, or nil if it has gone — which happens after a delete, and must send
    /// the flow home rather than show an empty screen.
    private func club(_ id: String) -> Club? { store.club(id) }

    @ViewBuilder private var content: some View {
        switch route {
        case .list:
            if let problem = store.openProblem {
                ErrorState(title: "Clubs cannot be opened",
                           what: problem,
                           safe: "Your matches are in a different file and are not affected.",
                           todo: "Nothing is shown here rather than something wrong. Reopening the app tries again.",
                           actionLabel: "Try again", onAction: { store.refresh() })
                    .padding(ThroSpacing.spaceScreenGutter)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    .background(ThroColor.colorBackgroundPrimary.ignoresSafeArea())
            } else {
                ClubsScreen(clubs: store.clubs,
                            onOpen: { route = .club($0.id) },
                            onCreate: { route = .newClub })
            }

        case .newClub:
            NewClubScreen(onBack: { route = .list }) { name, kind, accent in
                if store.createClub(name: name, kind: kind, accentHex: accent) { route = .list }
            }

        case .club(let id):
            if let c = club(id) {
                ClubScreen(club: c,
                           onBack: { route = .list },
                           onAnnounce: { route = .announce(id) },
                           onSeeMembers: { route = .members(id) },
                           onFixtures: { route = .fixtures(id) })
            } else { gone }

        case .members(let id):
            if let c = club(id) {
                ClubMembersScreen(club: c, onBack: { route = .club(id) },
                                  onAdd: addMemberAction(id, if: c.mayManageMembers),
                                  onRemove: removeMemberAction(id, if: c.mayManageMembers),
                                  onOpen: { route = .member(club: id, member: $0.id) })
            } else { gone }

        case .newMember(let id):
            if let c = club(id) {
                NewMemberScreen(club: c, onBack: { route = .members(id) }) { name, role, band in
                    if store.addMember(to: id, name: name, role: role, ageBand: band) { route = .members(id) }
                }
            } else { gone }

        case .fixtures(let id):
            if let c = club(id) {
                FixturesScreen(club: c, onBack: { route = .club(id) },
                               onAdd: { route = .newFixture(id) },
                               onMove: moveFixtureAction(id, if: c.mayManageFixtures))
            } else { gone }

        case .newFixture(let id):
            if let c = club(id) {
                NewFixtureScreen(club: c, onBack: { route = .fixtures(id) }) { title, when, venue in
                    if store.addFixture(to: id, title: title, when: when, venue: venue) { route = .fixtures(id) }
                }
            } else { gone }

        case .member(let clubId, let memberId):
            if let c = club(clubId), let m = c.visibleMembers.first(where: { $0.id == memberId }) {
                ProfileScreen(name: m.name,
                              meta: "\(m.role.label) · \(c.name) · joined \(m.joined)",
                              heading: "Figures",
                              figures: ClubsFlow.figures(for: m),
                              clubs: [c],
                              onBack: { route = .members(clubId) })
            } else { gone }

        case .announce(let id):
            if let c = club(id) {
                AnnounceScreen(club: c, onBack: { route = .club(id) })
            } else { gone }
        }
    }

    // The three controls that exist only for someone who may use them. Written as functions with a
    // declared return type rather than a ternary at the call site, because `allowed ? { … } : nil`
    // is exactly the shape Swift cannot infer a type for.

    private func addMemberAction(_ id: String, if allowed: Bool) -> (() -> Void)? {
        allowed ? { route = .newMember(id) } : nil
    }

    private func removeMemberAction(_ id: String, if allowed: Bool) -> ((String) -> Void)? {
        allowed ? { store.removeMember($0, from: id) } : nil
    }

    private func moveFixtureAction(_ id: String, if allowed: Bool) -> ((String, FixtureState) -> Void)? {
        allowed ? { store.move($0, in: id, to: $1) } : nil
    }

    /// What this device can honestly say about a member's darts, which is nothing.
    ///
    /// A figure here would have to come from matches attributed to this person, and nothing on this
    /// device is attributed to anybody: a local match is two names typed at the oche, not two
    /// accounts. `Figure.unavailable` exists for exactly this — a dash with the reason under it,
    /// never a zero and never a blank.
    static func figures(for member: ClubMember) -> [ProfileScreen.Figure] {
        let why = "Needs an account. Matches on this phone are not attributed to anybody."
        if let average = member.threeDartAverage {
            return [ProfileScreen.Figure(value: String(format: "%.2f", average), label: "3-dart average"),
                    ProfileScreen.Figure(value: "—", label: "Checkout %", unavailable: why),
                    ProfileScreen.Figure(value: "—", label: "Legs won", unavailable: why)]
        }
        return [ProfileScreen.Figure(value: "—", label: "3-dart average", unavailable: why),
                ProfileScreen.Figure(value: "—", label: "Checkout %", unavailable: why),
                ProfileScreen.Figure(value: "—", label: "Legs won", unavailable: why)]
    }

    /// A club that was there and is not. Only reachable by deleting one, and it says which.
    @ViewBuilder private var gone: some View {
        EmptyState(title: "That club is gone",
                   message: "It is no longer on this device.",
                   actionLabel: "Back to clubs", onAction: { route = .list })
            .padding(ThroSpacing.spaceScreenGutter)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background(ThroColor.colorBackgroundPrimary.ignoresSafeArea())
    }
}

// MARK: - starting a club

/// Starting a club, a league or a tournament.
///
/// The accent is typed as six hex digits rather than picked from a palette, and that is deliberate:
/// PD-010 forbids engineering from introducing a colour the token layer does not have, and a club's
/// own colour belongs to the club. Whatever they type is safe — `Branding` proves no colour in the
/// cube can make the app unreadable — so the field can accept anything a colour is and refuse
/// anything that is not one.
public struct NewClubScreen: View {
    @State private var name: String = ""
    @State private var kind: OrgKind = .club
    @State private var accent: String = ""
    private let onBack: () -> Void
    private let onCreate: (String, OrgKind, String?) -> Void

    public init(onBack: @escaping () -> Void = {},
                onCreate: @escaping (String, OrgKind, String?) -> Void = { _, _, _ in }) {
        self.onBack = onBack
        self.onCreate = onCreate
    }

    private var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var typedAccent: String? {
        let t = accent.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : t
    }
    private var accentColour: Color? { typedAccent.flatMap { Color.thro(hex: $0) } }
    private var accentError: String? {
        guard let typed = typedAccent, accentColour == nil else { return nil }
        return "Six hex digits, like 0F3D2E. \"\(typed)\" is not a colour."
    }
    private var initials: String {
        Club(id: "", name: trimmedName.isEmpty ? "Your club" : trimmedName, kind: kind, meta: "").initials
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            TopBar("Start a club", onBack: onBack)
            ScrollView {
                VStack(alignment: .leading, spacing: ThroSpacing.spacing5) {
                    HStack(spacing: ThroSpacing.spacing4) {
                        Badge(initials, size: 64, accent: accentColour)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(trimmedName.isEmpty ? "Your club" : trimmedName)
                                .thro(ThroTypography.heading3)
                                .foregroundStyle(ThroColor.colorTextPrimary)
                                .fixedSize(horizontal: false, vertical: true)
                            Text(kind.label)
                                .thro(ThroTypography.metadata)
                                .foregroundStyle(ThroColor.colorTextSecondary)
                        }
                        Spacer(minLength: 0)
                    }
                    ThroTextField("Name", text: $name, placeholder: "The Feathers",
                                  helper: "As people say it. The badge takes up to three letters from it.")
                    VStack(alignment: .leading, spacing: ThroSpacing.spacing2) {
                        Text("Kind")
                            .thro(ThroTypography.label.weight(.semibold))
                            .foregroundStyle(ThroColor.colorTextPrimary)
                        SegmentedControl(OrgKind.allCases.map { (kind: OrgKind) in (kind, kind.label) },
                                         selection: $kind)
                    }
                    ThroTextField("Accent colour", text: $accent, placeholder: "0F3D2E",
                                  helper: "Optional. Six hex digits — the club's own colour. Text on it is chosen for you so it always reads.",
                                  error: accentError)
                    Note("A club you start is kept on this phone. Nobody else can see it, and nothing about it is sent anywhere.")
                }
                .padding(.horizontal, ThroSpacing.spaceScreenGutter)
                .padding(.top, ThroSpacing.spacing5)
                .padding(.bottom, ThroSpacing.spacing5)
            }
            ThroButton("Start \(kind.label.lowercased())", variant: .primary, size: .large, fullWidth: true,
                       disabled: trimmedName.isEmpty || accentError != nil) {
                onCreate(trimmedName, kind, typedAccent)
            }
            .padding(.horizontal, ThroSpacing.spaceScreenGutter)
            .padding(.bottom, ThroSpacing.spacing6)
        }
        .background(ThroColor.colorBackgroundPrimary.ignoresSafeArea())
    }
}

// MARK: - adding a member

/// Adding somebody to the roster. The age question is asked plainly and answered honestly, because
/// what follows from it — who is listed, who is reached — follows whether or not anybody was asked.
public struct NewMemberScreen: View {
    private let club: Club
    @State private var name: String = ""
    @State private var role: OrgRole = .member
    @State private var band: AgeBand = .adult
    private let onBack: () -> Void
    private let onAdd: (String, OrgRole, AgeBand) -> Void

    public init(club: Club, onBack: @escaping () -> Void = {},
                onAdd: @escaping (String, OrgRole, AgeBand) -> Void = { _, _, _ in }) {
        self.club = club
        self.onBack = onBack
        self.onAdd = onAdd
    }

    private var trimmed: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }

    private var consequence: String {
        switch band {
        case .adult:
            return "Listed to everyone inside the club, and reached by announcements."
        case .minor:
            return "Listed only to an admin, and not reached by any announcement until THRØ has taken safeguarding advice."
        case .unknown:
            return "Treated exactly as under 18 — listed only to an admin, and not reached — because what is not known is whether they are a child."
        }
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            TopBar("Add a member", eyebrow: club.name, onBack: onBack)
            ScrollView {
                VStack(alignment: .leading, spacing: ThroSpacing.spacing5) {
                    ThroTextField("Name", text: $name, placeholder: "Alex Doherty")
                    VStack(alignment: .leading, spacing: ThroSpacing.spacing2) {
                        Text("Role")
                            .thro(ThroTypography.label.weight(.semibold))
                            .foregroundStyle(ThroColor.colorTextPrimary)
                        SegmentedControl([(OrgRole.member, "Member"), (OrgRole.official, "Official"),
                                          (OrgRole.admin, "Admin")], selection: $role)
                        Text("An official can announce and keep the fixture list. An admin can do those and manage the roster.")
                            .thro(ThroTypography.metadata)
                            .foregroundStyle(ThroColor.colorTextSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    VStack(alignment: .leading, spacing: ThroSpacing.spacing2) {
                        Text("Age")
                            .thro(ThroTypography.label.weight(.semibold))
                            .foregroundStyle(ThroColor.colorTextPrimary)
                        SegmentedControl([(AgeBand.adult, "18 or over"), (AgeBand.minor, "Under 18"),
                                          (AgeBand.unknown, "Not given")], selection: $band)
                        Note(consequence, icon: band == .adult ? .info : .shield)
                    }
                }
                .padding(.horizontal, ThroSpacing.spaceScreenGutter)
                .padding(.top, ThroSpacing.spacing5)
                .padding(.bottom, ThroSpacing.spacing5)
            }
            ThroButton("Add to \(club.name)", variant: .primary, size: .large, fullWidth: true,
                       disabled: trimmed.isEmpty) {
                onAdd(trimmed, role, band)
            }
            .padding(.horizontal, ThroSpacing.spaceScreenGutter)
            .padding(.bottom, ThroSpacing.spacing6)
        }
        .background(ThroColor.colorBackgroundPrimary.ignoresSafeArea())
    }
}

// MARK: - adding a fixture

/// Scheduling a fixture (PD-009, the official's list). The date is picked with the platform's own
/// control, the way Settings uses the platform's own toggle: it is the operating system's, not a
/// component the export was expected to draw.
public struct NewFixtureScreen: View {
    private let club: Club
    @State private var title: String = ""
    @State private var venue: String = ""
    @State private var when: Date
    private let onBack: () -> Void
    private let onAdd: (String, Date, String) -> Void

    public init(club: Club, now: Date = Date(), onBack: @escaping () -> Void = {},
                onAdd: @escaping (String, Date, String) -> Void = { _, _, _ in }) {
        self.club = club
        self.onBack = onBack
        self.onAdd = onAdd
        // Next week at eight in the evening: a darts night, and never a time already gone.
        var when = Calendar.current.date(byAdding: .day, value: 7, to: now) ?? now
        when = Calendar.current.date(bySettingHour: 20, minute: 0, second: 0, of: when) ?? when
        _when = State(initialValue: when)
    }

    private var trimmed: String { title.trimmingCharacters(in: .whitespacesAndNewlines) }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            TopBar("Add a fixture", eyebrow: club.name, onBack: onBack)
            ScrollView {
                VStack(alignment: .leading, spacing: ThroSpacing.spacing5) {
                    ThroTextField("Fixture", text: $title, placeholder: "Home to The Bell")
                    ThroTextField("Venue", text: $venue, placeholder: "The Feathers")
                    VStack(alignment: .leading, spacing: ThroSpacing.spacing2) {
                        Text("When")
                            .thro(ThroTypography.label.weight(.semibold))
                            .foregroundStyle(ThroColor.colorTextPrimary)
                        DatePicker("When", selection: $when)
                            .labelsHidden()
                            .tint(ThroColor.throGreen)
                    }
                    Note("A fixture carries no result. A result comes from a scored match and the evidence behind it.")
                }
                .padding(.horizontal, ThroSpacing.spaceScreenGutter)
                .padding(.top, ThroSpacing.spacing5)
                .padding(.bottom, ThroSpacing.spacing5)
            }
            ThroButton("Add fixture", variant: .primary, size: .large, fullWidth: true,
                       disabled: trimmed.isEmpty) {
                onAdd(trimmed, when, venue.trimmingCharacters(in: .whitespacesAndNewlines))
            }
            .padding(.horizontal, ThroSpacing.spaceScreenGutter)
            .padding(.bottom, ThroSpacing.spacing6)
        }
        .background(ThroColor.colorBackgroundPrimary.ignoresSafeArea())
    }
}

// MARK: - one person's page (ADR-016)

/// A person who plays on this phone, and what this phone can honestly say about their darts.
///
/// This is the profile screen with real numbers in it. They are real because the matches on this
/// device now say **who** each name referred to (ADR-016), so a person's visits can be pooled across
/// every match they played here — through the same audited honesty layer a single match's figures
/// go through, not a second arithmetic written for profiles.
///
/// What it does not claim: these are self-reported matches on one phone. They are attributable, not
/// verified, and the screen says so where the export puts the verification line.
public struct PersonScreen: View {
    private let person: LocalPerson
    private let journal: Journal?
    private let clubs: [Club]
    private let onBack: () -> Void
    @State private var figures: [StatLine] = []
    @State private var problem: String?

    public init(person: LocalPerson, journal: Journal?, clubs: [Club] = [],
                onBack: @escaping () -> Void = {}) {
        self.person = person
        self.journal = journal
        self.clubs = clubs
        self.onBack = onBack
    }

    public var body: some View {
        ProfileScreen(name: person.name,
                      meta: problem ?? "Matches played on this phone",
                      heading: "On this phone",
                      figures: figures.map {
                          ProfileScreen.Figure(value: $0.value, label: $0.label, unavailable: $0.note)
                      },
                      clubs: clubs,
                      onBack: onBack)
            .task { load() }
    }

    private func load() {
        guard let journal else {
            problem = "The journal could not be opened, so there are no figures to show."
            return
        }
        do {
            figures = try PersonSummary.figures(for: person.id, in: journal)
            problem = nil
        } catch {
            figures = []
            problem = "Their matches could not be read: \(error)"
        }
    }
}

