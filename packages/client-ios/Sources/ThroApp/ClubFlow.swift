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
    /// The pictures this device holds (PD-014). Nil when the folder could not be made, which leaves
    /// every badge as initials — a smaller loss than failing to open the app.
    public let images: ImageStore?
    /// Decoded pictures, kept so a list of clubs does not read the same file off disk on every frame.
    private var decoded: [String: Image] = [:]
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
        images = try? ClubStore.openImages()
        refresh()
    }

    /// For previews and tests: a store over a book the caller made.
    public init(book: ClubBook, images: ImageStore? = nil) {
        self.book = book
        self.images = images
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

    static func openImages() throws -> ImageStore {
        let support = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                                  appropriateFor: nil, create: true)
        let dir = support.appendingPathComponent("THRO", isDirectory: true)
            .appendingPathComponent("images", isDirectory: true)
        return try ImageStore(directory: dir)
    }

    // MARK: - pictures (PD-014)

    /// The picture behind an asset id, or nil — which is not a failure. A badge that cannot be read
    /// falls back to the club's initials, which is a mark rather than a complaint.
    public func image(_ assetId: String?) -> Image? {
        guard let assetId else { return nil }
        if let cached = decoded[assetId] { return cached }
        guard let data = images?.data(assetId), let image = Image.thro(data: data) else { return nil }
        decoded[assetId] = image
        return image
    }

    /// Stores a picked image and puts it on a club. Passing nil takes the badge off.
    ///
    /// The bytes are re-encoded and stripped of metadata on the way in, always — a phone photograph
    /// carries the place it was taken, and a club badge picked by a fifteen-year-old carries their
    /// house. That is engineering's rule, not a setting.
    @discardableResult
    public func setBadge(_ picked: Data?, on clubId: String) -> Bool {
        guard let book else { writeProblem = openProblem ?? "no club book on this device"; return false }
        do {
            let previous = try book.clubs().first { $0.id == clubId }?.badgeAssetId
            var assetId: String?
            if let picked {
                guard let images else { throw ImageStore.Failure.notStored("no image folder on this device") }
                assetId = try images.put(picked)
            }
            try book.setBadge(assetId, on: clubId)
            sweep(previous)
            writeProblem = nil
            refresh()
            return true
        } catch {
            writeProblem = "\(error)"
            return false
        }
    }

    /// Stores a picked image against a member. Refused for anybody not recorded as an adult, by the
    /// book rather than by this screen — see `ImagePolicy`.
    @discardableResult
    public func setAvatar(_ picked: Data?, forMember memberId: String, in clubId: String) -> Bool {
        guard let book else { writeProblem = openProblem ?? "no club book on this device"; return false }
        do {
            let previous = try book.members(of: clubId).first { $0.id == memberId }?.avatarAssetId
            var assetId: String?
            if let picked {
                guard let images else { throw ImageStore.Failure.notStored("no image folder on this device") }
                assetId = try images.put(picked)
            }
            try book.setAvatar(assetId, forMember: memberId, in: clubId)
            sweep(previous)
            writeProblem = nil
            refresh()
            return true
        } catch {
            writeProblem = "\(error)"
            return false
        }
    }

    /// Removes a file nothing points at any more. Deleting an image means deleting it, and a folder
    /// that only ever grows is how a phone fills up with faces nobody asked to keep.
    private func sweep(_ assetId: String?) {
        guard let assetId, let book, let images else { return }
        decoded[assetId] = nil
        guard let referenced = try? book.referencedAssetIds(), !referenced.contains(assetId) else { return }
        try? images.delete(assetId)
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
    public func createClub(name: String, kind: OrgKind, accentHex: String?,
                           shape: TournamentShape? = nil, unit: ResultUnit? = nil) -> Bool {
        write { try $0.createClub(name: name, kind: kind.rawValue, accentHex: accentHex,
                                  shape: shape?.rawValue, unit: unit?.rawValue) }
    }

    /// What a league's results are counted in (PD-022). Refused by the book once there is a result
    /// to reinterpret, and the refusal is kept and shown rather than dropped.
    @discardableResult
    public func setUnit(_ unit: ResultUnit, on clubId: String) -> Bool {
        write { try $0.setUnit(unit.rawValue, on: clubId) }
    }

    /// How a groups tournament is shaped (PD-021). Refused by the book once a group match has a
    /// result, because changing how many qualify then changes what those matches were for.
    @discardableResult
    public func setGroups(count: Int, qualifiers: Int, on clubId: String) -> Bool {
        write { try $0.setGroups(count: count, qualifiers: qualifiers, on: clubId) }
    }

    /// Creates the fixtures for one group's round robin (PD-021).
    @discardableResult
    public func drawGroup(_ number: Int, in clubId: String, when: Date, venue: String) -> Bool {
        guard let club = club(clubId), let groups = club.groups else {
            writeProblem = "this tournament has no groups to draw"
            return false
        }
        let ready = groups.readyToDraw(group: number)
        guard !ready.isEmpty else {
            writeProblem = "that group is already drawn"
            return false
        }
        return write { book in
            for match in ready {
                guard let sides = match.playable else { continue }
                try book.addFixture(to: clubId, title: "\(sides.home.name) v \(sides.away.name)",
                                    when: when, venue: venue,
                                    homeTeam: sides.home.id, awayTeam: sides.away.id,
                                    round: match.round, slot: match.slot,
                                    bracket: Bracket.group.rawValue)
            }
        }
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
    public func addFixture(to clubId: String, title: String, when: Date, venue: String,
                           homeTeam: String? = nil, awayTeam: String? = nil) -> Bool {
        write { try $0.addFixture(to: clubId, title: title, when: when, venue: venue,
                                  homeTeam: homeTeam, awayTeam: awayTeam) }
    }

    // MARK: - teams and results (PD-019, PD-020)

    /// Creates the fixtures for one round of a knockout draw (PD-021).
    ///
    /// **It draws what is ready and nothing else.** A match whose two sides are not both known yet
    /// is not created — there is nobody to put in it — and a walkover is never created at all,
    /// because nobody plays it and a fixture for it would be a match in the record that never
    /// happened. The store re-derives the draw from what it has just written, so the count it
    /// returns is what actually exists rather than what was intended.
    @discardableResult
    public func drawRound(_ round: Int, in clubId: String, when: Date, venue: String,
                          bracket: Bracket? = nil) -> Bool {
        guard let club = club(clubId) else {
            writeProblem = "that tournament is not on this device"
            return false
        }
        let ready: [DrawMatch]
        if let bracket, let double = club.doubleElimination {
            ready = double.readyToDraw(bracket: bracket, round: round)
        } else if bracket == nil, let draw = club.draw {
            ready = draw.readyToDraw(round: round)
        } else {
            writeProblem = "this tournament has no draw to make"
            return false
        }
        guard !ready.isEmpty else {
            writeProblem = "there is nothing to draw there yet"
            return false
        }
        return write { book in
            for match in ready {
                guard let sides = match.playable else { continue }
                try book.addFixture(to: clubId, title: "\(sides.home.name) v \(sides.away.name)",
                                    when: when, venue: venue,
                                    homeTeam: sides.home.id, awayTeam: sides.away.id,
                                    round: match.round, slot: match.slot,
                                    bracket: match.bracket?.rawValue)
            }
        }
    }

    @discardableResult
    public func addTeam(to clubId: String, name: String) -> Bool {
        write { try $0.addTeam(to: clubId, name: name) }
    }

    /// Removes a team **and the fixtures it was in**. `fixturesLost` says how many that is, so the
    /// screen can say the number before it happens rather than the admin finding out after.
    @discardableResult
    public func removeTeam(_ teamId: String, from clubId: String) -> Bool {
        write { try $0.removeTeam(teamId, from: clubId) }
    }

    public func fixturesLost(removing teamId: String, from clubId: String) -> Int {
        guard let book else { return 0 }
        return (try? book.fixtureCount(forTeam: teamId, in: clubId)) ?? 0
    }

    /// Records an official's word about a fixture (PD-020). Marked as theirs everywhere it is shown.
    @discardableResult
    public func recordResult(fixture: String, in clubId: String, home: Int, away: Int,
                             by official: String) -> Bool {
        write { try $0.recordResult(fixture: fixture, in: clubId, home: home, away: away,
                                    source: "recorded", recordedBy: official) }
    }

    /// Attaches a match scored in THRØ to a fixture. **This is the strong source**, and the client
    /// cannot fabricate one: it takes the id of a match that is in this device's journal.
    @discardableResult
    public func linkResult(fixture: String, in clubId: String, home: Int, away: Int,
                           matchId: String) -> Bool {
        write { try $0.recordResult(fixture: fixture, in: clubId, home: home, away: away,
                                    source: "scored", matchId: matchId) }
    }

    @discardableResult
    public func clearResult(fixture: String, in clubId: String) -> Bool {
        write { try $0.clearResult(fixture: fixture, in: clubId) }
    }

    @discardableResult
    public func setPoints(win: Int, draw: Int, on clubId: String) -> Bool {
        write { try $0.setPoints(win: win, draw: draw, on: clubId) }
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
                       joined: ClubStore.joined.string(from: m.joinedAt),
                       avatarAssetId: m.avatarAssetId)
        }
        let teams = try book.teams(of: stored.id).map { Team(id: $0.id, name: $0.name) }
        // Keyed by fixture, because a fixture has at most one result and a screen asks per row.
        let results = try Dictionary(book.results(of: stored.id).map { ($0.fixtureId, $0) },
                                     uniquingKeysWith: { first, _ in first })
        let fixtures = try book.fixtures(of: stored.id).map { f in
            Fixture(id: f.id, title: f.title, when: ClubStore.when.string(from: f.when),
                    venue: f.venue, state: FixtureState(rawValue: f.state) ?? .scheduled,
                    homeTeamId: f.homeTeamId, awayTeamId: f.awayTeamId,
                    result: ClubStore.result(results[f.id]),
                    round: f.round, slot: f.slot, bracket: f.bracket)
        }
        let kind = OrgKind(rawValue: stored.kind) ?? .club
        return Club(id: stored.id, name: stored.name,
                    kind: kind,
                    meta: ClubStore.meta(kind, members: members.count, teams: teams.count),
                    accentHex: stored.accentHex,
                    // Nothing on this device has been verified by anybody, so nothing wears the mark.
                    verified: false,
                    yourRole: .admin,
                    members: members,
                    fixtures: fixtures,
                    // Nothing has been sent, because there is nowhere to send it.
                    announcements: [],
                    badgeAssetId: stored.badgeAssetId,
                    teams: teams,
                    shape: stored.shape.flatMap(TournamentShape.init(rawValue:)),
                    pointsForWin: stored.pointsForWin,
                    pointsForDraw: stored.pointsForDraw,
                    unit: stored.unit.flatMap(ResultUnit.init(rawValue:)),
                    groupCount: stored.groupCount,
                    qualifiersPerGroup: stored.qualifiersPerGroup)
    }

    /// A stored result as the screens want it, or nil.
    ///
    /// A row that says `scored` with no match, or `recorded` with nobody's name, becomes **nil**
    /// rather than a result with its provenance missing. `ClubBook` already refuses to write one and
    /// already drops one on read; this is the same answer a third time, because a result whose
    /// source cannot be shown is the one thing PD-020 says must never reach a table.
    static func result(_ stored: StoredResult?) -> MatchResult? {
        guard let stored else { return nil }
        let source: ResultSource
        switch stored.source {
        case "scored":
            guard let matchId = stored.matchId else { return nil }
            source = .scored(matchId: matchId)
        case "recorded":
            guard let by = stored.recordedBy, !by.isEmpty else { return nil }
            source = .recorded(by: by)
        default:
            return nil
        }
        return MatchResult(home: stored.home, away: stored.away, source: source)
    }

    /// The line under a name. A league is counted in teams, because a league's roster is its teams
    /// (PD-019) and "24 members" on a league of eight teams tells nobody anything they wanted.
    static func meta(_ kind: OrgKind, members: Int, teams: Int) -> String {
        switch kind {
        case .league:
            return teams == 0 ? "No teams yet" : "\(teams) team\(teams == 1 ? "" : "s")"
        case .tournament:
            return teams == 0 ? "No entrants yet" : "\(teams) entrant\(teams == 1 ? "" : "s")"
        case .club:
            return members == 0 ? "No members yet" : "\(members) member\(members == 1 ? "" : "s")"
        }
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
    /// The club's own name, colour and badge. **This case is why the badge picker did nothing**:
    /// `EditClubScreen` was written, tested and never routed to, so no club on a phone could be
    /// renamed, recoloured or given a badge. Nothing was broken — it simply could not be reached.
    case edit(String)
    case memberPicture(club: String, member: String)
    /// A league's teams, or a tournament's entrants (PD-019, PD-021). One route, because they are
    /// one stored thing; the screen uses the word the organisation actually calls them.
    case teams(String)
    case newTeam(String)
    /// Saying what happened in a fixture, and where that came from (PD-020).
    case result(club: String, fixture: String)
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
                            badge: { store.image($0.badgeAssetId) },
                            onOpen: { route = .club($0.id) },
                            onCreate: { route = .newClub })
            }

        case .newClub:
            NewClubScreen(onBack: { route = .list }) { name, kind, accent, shape, unit in
                if store.createClub(name: name, kind: kind, accentHex: accent, shape: shape,
                                    unit: unit) {
                    route = .list
                }
            }

        // **Three kinds, three screens.** They were one screen with the word at the top changed,
        // which is what the founder called wrong, lazy and ugly. What each one shows now follows
        // from what each one *is* — PD-019, PD-020 and PD-021 decided that before any of this was
        // drawn.
        case .club(let id):
            if let c = club(id) {
                switch c.kind {
                case .club:
                    ClubScreen(club: c,
                               badge: store.image(c.badgeAssetId),
                               picture: { store.image($0.avatarAssetId) },
                               onBack: { route = .list },
                               onAnnounce: { route = .announce(id) },
                               onSeeMembers: { route = .members(id) },
                               onFixtures: { route = .fixtures(id) },
                               onEdit: editAction(id, if: c.mayEditIdentity))
                case .league:
                    LeagueScreen(league: c,
                                 badge: store.image(c.badgeAssetId),
                                 onBack: { route = .list },
                                 onTeams: { route = .teams(id) },
                                 onFixtures: { route = .fixtures(id) },
                                 onOfficials: { route = .members(id) },
                                 onAnnounce: { route = .announce(id) },
                                 onEdit: editAction(id, if: c.mayEditIdentity),
                                 onRecord: resultAction(id, if: c.mayRecordResults))
                case .tournament:
                    TournamentScreen(tournament: c,
                                     badge: store.image(c.badgeAssetId),
                                     onBack: { route = .list },
                                     onEntrants: { route = .teams(id) },
                                     onFixtures: { route = .fixtures(id) },
                                     onAnnounce: { route = .announce(id) },
                                     onEdit: editAction(id, if: c.mayEditIdentity),
                                     onRecord: resultAction(id, if: c.mayRecordResults),
                                     onDraw: drawAction(id, if: c.mayManageFixtures),
                                     onDraw2: bracketDrawAction(id, if: c.mayManageFixtures),
                                     onDrawGroup: groupDrawAction(id, if: c.mayManageFixtures))
                }
            } else { gone }

        case .teams(let id):
            if let c = club(id) {
                TeamsScreen(club: c,
                            onBack: { route = .club(id) },
                            onAdd: c.mayManageTeams ? { route = .newTeam(id) } : nil,
                            onRemove: removeTeamAction(id, if: c.mayManageTeams),
                            fixturesLost: { store.fixturesLost(removing: $0.id, from: id) })
            } else { gone }

        case .newTeam(let id):
            if let c = club(id), c.mayManageTeams {
                NewTeamScreen(club: c, onBack: { route = .teams(id) }) { name in
                    if store.addTeam(to: id, name: name) { route = .teams(id) }
                }
            } else { gone }

        case .result(let clubId, let fixtureId):
            if let c = club(clubId), c.mayRecordResults,
               let f = c.fixtures.first(where: { $0.id == fixtureId }), f.isBetweenTeams {
                RecordResultScreen(club: c, fixture: f,
                                   home: ClubsFlow.team(f.homeTeamId, in: c),
                                   away: ClubsFlow.team(f.awayTeamId, in: c),
                                   onBack: { route = .club(clubId) },
                                   onRecord: { home, away, official in
                                       if store.recordResult(fixture: fixtureId, in: clubId,
                                                             home: home, away: away, by: official) {
                                           route = .club(clubId)
                                       }
                                   },
                                   onClear: f.result == nil ? nil : {
                                       if store.clearResult(fixture: fixtureId, in: clubId) {
                                           route = .club(clubId)
                                       }
                                   })
            } else { gone }

        case .edit(let id):
            if let c = club(id) {
                EditClubScreen(club: c, currentBadge: store.image(c.badgeAssetId),
                               onBack: { route = .club(id) },
                               onSave: { edits in
                                   guard store.rename(id, to: edits.name, accentHex: edits.accentHex)
                                   else { return }
                                   // Each write only if that thing actually changed. A save that
                                   // touched nothing must not rewrite the file and drop the badge on
                                   // the way past.
                                   if edits.picked != nil || edits.removeBadge {
                                       guard store.setBadge(edits.picked, on: id) else { return }
                                   }
                                   if edits.pointsForWin != c.pointsForWin
                                       || edits.pointsForDraw != c.pointsForDraw {
                                       guard store.setPoints(win: edits.pointsForWin,
                                                             draw: edits.pointsForDraw, on: id)
                                       else { return }
                                   }
                                   if let unit = edits.unit, unit != c.unit {
                                       guard store.setUnit(unit, on: id) else { return }
                                   }
                                   if let count = edits.groupCount, let through = edits.qualifiersPerGroup,
                                      count != c.groupCount || through != c.qualifiersPerGroup {
                                       guard store.setGroups(count: count, qualifiers: through, on: id)
                                       else { return }
                                   }
                                   route = .club(id)
                               },
                               onDelete: {
                                   if store.delete(id) { route = .list }
                               })
            } else { gone }

        case .members(let id):
            if let c = club(id) {
                ClubMembersScreen(club: c, onBack: { route = .club(id) },
                                  onAdd: addMemberAction(id, if: c.mayManageMembers),
                                  onRemove: removeMemberAction(id, if: c.mayManageMembers),
                                  onOpen: { route = .member(club: id, member: $0.id) },
                                  picture: { store.image($0.avatarAssetId) })
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
                               onMove: moveFixtureAction(id, if: c.mayManageFixtures),
                               onRecord: resultAction(id, if: c.mayRecordResults))
            } else { gone }

        case .newFixture(let id):
            if let c = club(id) {
                // A club's fixture is a title somebody typed; a league's or a tournament's is
                // between two of its own teams, so it is chosen and the title follows.
                if c.kind == .club {
                    NewFixtureScreen(club: c, onBack: { route = .fixtures(id) }) { title, when, venue in
                        if store.addFixture(to: id, title: title, when: when, venue: venue) {
                            route = .fixtures(id)
                        }
                    }
                } else {
                    NewTeamFixtureScreen(club: c, onBack: { route = .fixtures(id) }) { home, away, title, when, venue in
                        if store.addFixture(to: id, title: title, when: when, venue: venue,
                                            homeTeam: home, awayTeam: away) {
                            route = .fixtures(id)
                        }
                    }
                }
            } else { gone }

        case .member(let clubId, let memberId):
            if let c = club(clubId), let m = c.visibleMembers.first(where: { $0.id == memberId }) {
                let refusal = PicturePolicy.refusal(for: m.ageBand)
                ProfileScreen(name: m.name,
                              meta: "\(m.role.label) · \(c.name) · joined \(m.joined)",
                              heading: "Figures",
                              figures: ClubsFlow.figures(for: m),
                              clubs: [c],
                              picture: store.image(m.avatarAssetId),
                              // The reason, but only to the person who could otherwise have set one.
                              // To anybody else it is a fact about a member they cannot act on.
                              pictureNote: c.mayManageMembers ? refusal : nil,
                              onEditPicture: pictureAction(clubId, memberId,
                                                           if: c.mayManageMembers && refusal == nil),
                              onBack: { route = .members(clubId) })
            } else { gone }

        case .memberPicture(let clubId, let memberId):
            if let c = club(clubId), let m = c.visibleMembers.first(where: { $0.id == memberId }),
               c.mayManageMembers {
                EditMemberPictureScreen(member: m, club: c,
                                        current: store.image(m.avatarAssetId),
                                        onBack: { route = .member(club: clubId, member: memberId) },
                                        onSave: { picked, removed in
                                            guard picked != nil || removed else {
                                                route = .member(club: clubId, member: memberId)
                                                return
                                            }
                                            if store.setAvatar(picked, forMember: memberId, in: clubId) {
                                                route = .member(club: clubId, member: memberId)
                                            }
                                        })
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

    private func editAction(_ id: String, if allowed: Bool) -> (() -> Void)? {
        allowed ? { route = .edit(id) } : nil
    }

    private func pictureAction(_ clubId: String, _ memberId: String, if allowed: Bool) -> (() -> Void)? {
        allowed ? { route = .memberPicture(club: clubId, member: memberId) } : nil
    }

    private func resultAction(_ id: String, if allowed: Bool) -> ((Fixture) -> Void)? {
        allowed ? { route = .result(club: id, fixture: $0.id) } : nil
    }

    private func removeTeamAction(_ id: String, if allowed: Bool) -> ((Team) -> Void)? {
        allowed ? { store.removeTeam($0.id, from: id) } : nil
    }

    /// Making the draw creates fixtures, so it is an official's, like every other fixture write.
    ///
    /// The date is a week out at eight in the evening — the same default the fixture screens use —
    /// and the venue is left blank rather than guessed: a drawn round is a set of matches somebody
    /// then arranges, and inventing a venue would be putting words in their mouth on every row.
    private func drawAction(_ id: String, if allowed: Bool) -> ((Int) -> Void)? {
        guard allowed else { return nil }
        return { round in
            store.drawRound(round, in: id, when: ClubsFlow.nextWeek(), venue: "")
        }
    }

    /// The same, for a shape with more than one bracket.
    private func bracketDrawAction(_ id: String, if allowed: Bool) -> ((Bracket, Int) -> Void)? {
        guard allowed else { return nil }
        return { bracket, round in
            store.drawRound(round, in: id, when: ClubsFlow.nextWeek(), venue: "", bracket: bracket)
        }
    }

    private func groupDrawAction(_ id: String, if allowed: Bool) -> ((Int) -> Void)? {
        guard allowed else { return nil }
        return { number in
            store.drawGroup(number, in: id, when: ClubsFlow.nextWeek(), venue: "")
        }
    }

    /// A week out at eight in the evening — the same default the fixture screens use. The venue is
    /// left blank rather than guessed: a drawn round is a set of matches somebody then arranges, and
    /// inventing a venue would be putting words in their mouth on every row.
    static func nextWeek(from now: Date = Date()) -> Date {
        var when = Calendar.current.date(byAdding: .day, value: 7, to: now) ?? now
        when = Calendar.current.date(bySettingHour: 20, minute: 0, second: 0, of: when) ?? when
        return when
    }

    /// A team's name inside its own league. Static, because the record-result screen needs it while
    /// the flow is building it rather than after.
    static func team(_ id: String?, in club: Club) -> String {
        club.teams.first { $0.id == id }?.name ?? "—"
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
    /// A tournament's shape (PD-021). Asked here because it is asked **once**: a shape decides what
    /// every round means, so there is no write that changes it afterwards, and a screen that let one
    /// be picked later would be offering something the store refuses.
    @State private var shape: TournamentShape = .knockout
    /// What a league counts its results in (PD-022). Asked here because it is the one thing about a
    /// league that **cannot be answered afterwards** — a stored `3–1` with no unit on it cannot be
    /// reinterpreted, and by then nobody remembers what they meant.
    @State private var unit: ResultUnit = .legs
    private let onBack: () -> Void
    private let onCreate: (String, OrgKind, String?, TournamentShape?, ResultUnit?) -> Void

    public init(onBack: @escaping () -> Void = {},
                onCreate: @escaping (String, OrgKind, String?, TournamentShape?, ResultUnit?) -> Void
                    = { _, _, _, _, _ in }) {
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
                        Text(NewClubScreen.whatItIs(kind))
                            .thro(ThroTypography.metadata)
                            .foregroundStyle(ThroColor.colorTextSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.top, 2)
                    }
                    if kind == .tournament { shapes }
                    if kind == .league { units }
                    // Swatches drawn AS the badge will be drawn, rather than six hex digits typed
                    // blind. The initials on each are in whichever neutral THRØ chooses for that
                    // colour, so the choice is made by looking at the result.
                    AccentPicker(hex: $accent, initials: Club(id: "", name: name.isEmpty ? "New" : name,
                                                              kind: kind, meta: "").initials)
                    if let accentError {
                        Text(accentError)
                            .thro(ThroTypography.metadata)
                            .foregroundStyle(ThroColor.colorStatusError)
                    }
                    Note("A \(kind.label.lowercased()) you start is kept on this phone. Nobody else can see it, and nothing about it is sent anywhere.")
                }
                .padding(.horizontal, ThroSpacing.spaceScreenGutter)
                .padding(.top, ThroSpacing.spacing5)
                .padding(.bottom, ThroSpacing.spacing5)
            }
            ThroButton("Start \(kind.label.lowercased())", variant: .primary, size: .large, fullWidth: true,
                       disabled: trimmedName.isEmpty || accentError != nil) {
                onCreate(trimmedName, kind, typedAccent, kind == .tournament ? shape : nil,
                         kind == .league ? unit : nil)
            }
            .padding(.horizontal, ThroSpacing.spaceScreenGutter)
            .padding(.bottom, ThroSpacing.spacing6)
        }
        .background(ThroColor.colorBackgroundPrimary.ignoresSafeArea())
    }

    /// The shape, chosen once (PD-021), with what each one means beside it rather than four words
    /// somebody has to already know.
    @ViewBuilder private var shapes: some View {
        VStack(alignment: .leading, spacing: ThroSpacing.spacing2) {
            Text("Shape")
                .thro(ThroTypography.label.weight(.semibold))
                .foregroundStyle(ThroColor.colorTextPrimary)
            ForEach(TournamentShape.allCases, id: \.rawValue) { option in
                Button { shape = option } label: {
                    HStack(alignment: .top, spacing: ThroSpacing.spacing3) {
                        Icon(shape == option ? .circleCheck : .circle, size: 20)
                            .foregroundStyle(shape == option ? ThroColor.colorTextBrand
                                             : ThroColor.colorBorderStrong)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(option.label)
                                .thro(ThroTypography.label.weight(.semibold))
                                .foregroundStyle(ThroColor.colorTextPrimary)
                            Text(option.summary)
                                .thro(ThroTypography.metadata)
                                .foregroundStyle(ThroColor.colorTextSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.vertical, ThroSpacing.spacing2)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(shape == option ? [.isSelected] : [])
            }
            Note("**Chosen once.** A tournament keeps its shape, because changing it would change "
                 + "what the matches already played were for.")
        }
    }

    /// What a league's results are counted in (PD-022), asked once and fixed as soon as there is a
    /// result to reinterpret.
    @ViewBuilder private var units: some View {
        VStack(alignment: .leading, spacing: ThroSpacing.spacing2) {
            Text("Results counted in")
                .thro(ThroTypography.label.weight(.semibold))
                .foregroundStyle(ThroColor.colorTextPrimary)
            SegmentedControl(ResultUnit.allCases.map { (unit: ResultUnit) in (unit, unit.label) },
                             selection: $unit)
            Text(unit.summary)
                .thro(ThroTypography.metadata)
                .foregroundStyle(ThroColor.colorTextSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 2)
            Note("**Asked now because it cannot be asked later.** A result of 3–1 means nothing "
                 + "without it, and a number already entered cannot be reinterpreted. You can "
                 + "change this until the first result goes in, and not after.")
        }
    }

    /// One line on what each kind actually is, because the difference between them is the thing this
    /// app got wrong: they were three words for one screen.
    static func whatItIs(_ kind: OrgKind) -> String {
        switch kind {
        case .club:
            return "People who play together, with a roster and a fixture list."
        case .league:
            return "Teams that play each other over a season, with a table. Its members are the "
                 + "people who run it; the people who play are in the teams (PD-019)."
        case .tournament:
            return "One competition with a shape — knockout, groups, round robin or double "
                 + "elimination — chosen now and kept."
        }
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
                      // A person on this phone has no recorded age — the person table holds a name
                      // and nothing else — so by the app's own rule they may not have a picture, and
                      // the page says which rule rather than simply having no picture on it.
                      // **PD-023 settled where one does come from**: an account, where the person in
                      // the photograph answers for their own age rather than whoever is holding the
                      // phone answering for them. That is B4, and nothing here changes until it lands.
                      pictureNote: PicturePolicy.refusal(for: .unknown),
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

// MARK: - editing a club (PD-014)

/// A club's name, its colour and its badge.
///
/// The badge is the first place an image enters THRØ at all, and three things about it are rules
/// rather than choices:
///
///  - **Every image is decoded and written out again**, at badge size, carrying nothing it came
///    with. A phone photograph carries the place it was taken.
///  - **Nothing has left this phone.** There is no server to publish to, so the screening the
///    founder chose (PD-014) happens at a publish that does not exist yet — and the screen says so
///    rather than implying an image has been checked when nothing has checked it.
///  - **Removing it removes it.** The file goes when nothing points at it any more, rather than
///    lingering in a folder that only ever grows.
public struct EditClubScreen: View {
    /// Everything one save changes. A struct rather than six positional arguments, because a
    /// six-parameter closure is a call site where two `Int`s can be swapped and nothing notices.
    public struct Edits {
        public let name: String
        public let accentHex: String?
        public let picked: Data?
        public let removeBadge: Bool
        /// A league's points (PD-019). Unchanged for a club and a tournament, which have no table.
        public let pointsForWin: Int
        public let pointsForDraw: Int
        /// A groups tournament's setup (PD-021), when it may still be set.
        public let groupCount: Int?
        public let qualifiersPerGroup: Int?
        /// A league's unit (PD-022), when it may still be set. Nil means leave it as it is — which
        /// is what it always means once a result exists, because the store refuses it then anyway.
        public let unit: ResultUnit?
    }

    private let club: Club
    private let currentBadge: Image?
    @State private var name: String
    @State private var accent: String
    @State private var pickedData: Data?
    @State private var removeBadge = false
    @State private var win: String
    @State private var draw: String
    @State private var unit: ResultUnit
    @State private var groupCount: String
    @State private var qualifiers: String
    private let onBack: () -> Void
    private let onSave: (Edits) -> Void
    private let onDelete: () -> Void

    public init(club: Club, currentBadge: Image? = nil, onBack: @escaping () -> Void = {},
                onSave: @escaping (Edits) -> Void = { _ in },
                onDelete: @escaping () -> Void = {}) {
        self.club = club
        self.currentBadge = currentBadge
        _name = State(initialValue: club.name)
        _accent = State(initialValue: club.accentHex ?? "")
        _win = State(initialValue: "\(club.pointsForWin)")
        _draw = State(initialValue: "\(club.pointsForDraw)")
        _unit = State(initialValue: club.unit ?? .legs)
        _groupCount = State(initialValue: club.groupCount.map { "\($0)" } ?? "")
        _qualifiers = State(initialValue: club.qualifiersPerGroup.map { "\($0)" } ?? "")
        self.onBack = onBack
        self.onSave = onSave
        self.onDelete = onDelete
    }

    /// The two numbers, once both are whole and at least one. Named apart from the section that
    /// draws them, because a type cannot have two members with the same name — which is what the
    /// first version of this had.
    private var groupSetup: (count: Int, qualifiers: Int)? {
        guard let c = Int(groupCount.trimmingCharacters(in: .whitespaces)),
              let q = Int(qualifiers.trimmingCharacters(in: .whitespaces)),
              c >= 1, q >= 1 else { return nil }
        return (c, q)
    }

    private var points: (win: Int, draw: Int)? {
        guard let w = Int(win.trimmingCharacters(in: .whitespaces)),
              let d = Int(draw.trimmingCharacters(in: .whitespaces)), w >= 0, d >= 0 else { return nil }
        return (w, d)
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

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            TopBar("Edit", eyebrow: club.name, onBack: onBack)
            ScrollView {
                VStack(alignment: .leading, spacing: ThroSpacing.spacing5) {
                    // The one picker, rather than this screen's own copy of one. A member's
                    // picture is chosen with the same control, which is how the two stay alike.
                    PicturePicker(subject: .organisation(initials: club.initials, accent: accentColour),
                                  size: 72, current: currentBadge, refusedBecause: nil,
                                  picked: $pickedData, removed: $removeBadge)
                    ThroTextField("Name", text: $name)
                    AccentPicker(hex: $accent, initials: club.initials)
                    if club.kind == .league { scoring }
                    if club.shape == .groups { grouping }
                    if let accentError {
                        Text(accentError)
                            .thro(ThroTypography.metadata)
                            .foregroundStyle(ThroColor.colorStatusError)
                    }
                    Note("The badge is resized and written out again on this phone, and everything the "
                         + "original carried — including where a photograph was taken — is dropped. Nothing "
                         + "has left the phone: an image is checked when it is published, and there is "
                         + "nowhere to publish to yet.")
                    ThroDivider()
                    ThroButton("Delete this \(club.kind.label.lowercased())", variant: .destructive,
                               size: .medium, action: onDelete)
                }
                .padding(.horizontal, ThroSpacing.spaceScreenGutter)
                .padding(.vertical, ThroSpacing.spacing5)
            }
            ThroButton("Save", variant: .primary, size: .large, fullWidth: true,
                       disabled: trimmedName.isEmpty || accentError != nil) {
                onSave(Edits(name: trimmedName, accentHex: typedAccent, picked: pickedData,
                             removeBadge: removeBadge,
                             pointsForWin: points?.win ?? club.pointsForWin,
                             pointsForDraw: points?.draw ?? club.pointsForDraw,
                             groupCount: club.setupIsStillOpen ? groupSetup?.count : nil,
                             qualifiersPerGroup: club.setupIsStillOpen ? groupSetup?.qualifiers : nil,
                             unit: (club.kind == .league && club.setupIsStillOpen) ? unit : nil))
            }
            .padding(.horizontal, ThroSpacing.spaceScreenGutter)
            .padding(.bottom, ThroSpacing.spacing6)
        }
        .background(ThroColor.colorBackgroundPrimary.ignoresSafeArea())
    }

    /// What a win and a draw are worth in this league.
    ///
    /// **Asked rather than assumed.** Points per win differ between real leagues, and a constant
    /// buried in a table calculation would be THRØ quietly deciding a league's rules for it. The
    /// default is the common one and it is on the screen where it can be argued with — which is also
    /// why OD-022 exists rather than this being treated as settled.
    @ViewBuilder private var scoring: some View {
        VStack(alignment: .leading, spacing: ThroSpacing.spacing3) {
            Text("Points")
                .thro(ThroTypography.labelStrong.weight(.semibold))
                .foregroundStyle(ThroColor.colorTextSecondary)
            HStack(spacing: ThroSpacing.spacing4) {
                ThroTextField("For a win", text: $win)
                ThroTextField("For a draw", text: $draw)
            }
            if points == nil {
                Text("Both are whole numbers, and neither is negative.")
                    .thro(ThroTypography.metadata)
                    .foregroundStyle(ThroColor.colorStatusError)
            }
            Note("The table is worked out from these every time it is drawn — nothing is stored, so "
                 + "changing them changes the table rather than leaving it disagreeing with itself.")
            counting
        }
    }

    /// How a groups tournament is shaped (PD-021).
    ///
    /// **Asked, never guessed.** How many groups and how many go through decide what every match in
    /// the tournament is for, and they are set before it starts. Like the league's unit, they may be
    /// changed only while no result depends on them.
    @ViewBuilder private var grouping: some View {
        VStack(alignment: .leading, spacing: ThroSpacing.spacing3) {
            Text("Groups")
                .thro(ThroTypography.labelStrong.weight(.semibold))
                .foregroundStyle(ThroColor.colorTextSecondary)
            if club.setupIsStillOpen {
                HStack(spacing: ThroSpacing.spacing4) {
                    ThroTextField("How many groups", text: $groupCount)
                    ThroTextField("Top how many through", text: $qualifiers)
                }
                if groupSetup == nil {
                    Text("Both are whole numbers, and both are at least one.")
                        .thro(ThroTypography.metadata)
                        .foregroundStyle(ThroColor.colorStatusError)
                }
                Note("Entrants are dealt into the groups snake-wise over the order they were "
                     + "entered. **You can change this until the first result goes in, and not "
                     + "after** — changing how many qualify once people have played changes what "
                     + "those matches were for.")
            } else {
                Text(club.groupCount.map { "\($0) groups, top \(club.qualifiersPerGroup ?? 0) through" }
                     ?? "Never set")
                    .thro(ThroTypography.body)
                    .foregroundStyle(ThroColor.colorTextPrimary)
                Note("**Settled.** Matches have been played under this, and half the field would "
                     + "find out afterwards that the thing they were competing for had moved.")
            }
        }
    }

    /// What this league's results are counted in (PD-022).
    ///
    /// **Offered only while there is nothing to reinterpret.** Once a result is in, changing the unit
    /// would turn every number already entered into a claim about something else — so the control is
    /// gone and the screen says what it settled on and why, rather than a disabled picker that would
    /// refuse. `ClubBook.setUnit` refuses it too, so this is a screen agreeing with a store rather
    /// than a screen being trusted.
    @ViewBuilder private var counting: some View {
        VStack(alignment: .leading, spacing: ThroSpacing.spacing2) {
            Text("Results counted in")
                .thro(ThroTypography.labelStrong.weight(.semibold))
                .foregroundStyle(ThroColor.colorTextSecondary)
            if club.setupIsStillOpen {
                SegmentedControl(ResultUnit.allCases.map { (u: ResultUnit) in (u, u.label) },
                                 selection: $unit)
                Text(unit.summary)
                    .thro(ThroTypography.metadata)
                    .foregroundStyle(ThroColor.colorTextSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                Note(club.unit == nil
                     ? "**This league has never said.** It was made before THRØ asked, so its "
                       + "figures have no unit on them. Set one now — after the first result goes "
                       + "in it cannot be changed."
                     : "You can change this until the first result goes in, and not after.")
            } else {
                Text(club.unit?.label ?? "Not set")
                    .thro(ThroTypography.body)
                    .foregroundStyle(ThroColor.colorTextPrimary)
                Note("**Settled.** This league has results in it, and changing what they are "
                     + "counted in would quietly turn every number already entered into a claim "
                     + "about something else.")
            }
        }
    }
}

/// A member's picture.
///
/// One thing on one screen, which is honest about what this build can change about a person: their
/// picture, and nothing else. Their role and their age are set when they are added and there is no
/// way to change either — `ClubBook` has no write for it — so this screen does not pretend there is.
///
/// It is reachable only for a member who may actually have a picture. The refusal is still built,
/// because `PicturePicker` refuses on its own and a screen that depends on its caller having checked
/// is a screen that breaks the day somebody routes to it differently.
public struct EditMemberPictureScreen: View {
    private let member: ClubMember
    private let club: Club
    private let current: Image?
    @State private var picked: Data?
    @State private var removed = false
    private let onBack: () -> Void
    private let onSave: (Data?, Bool) -> Void

    public init(member: ClubMember, club: Club, current: Image? = nil,
                onBack: @escaping () -> Void = {},
                onSave: @escaping (Data?, Bool) -> Void = { _, _ in }) {
        self.member = member
        self.club = club
        self.current = current
        self.onBack = onBack
        self.onSave = onSave
    }

    private var refusal: String? { PicturePolicy.refusal(for: member.ageBand) }
    /// Nothing picked and nothing removed is not a save, it is a change of mind.
    private var changed: Bool { picked != nil || removed }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            TopBar("Picture", eyebrow: member.name, onBack: onBack)
            ScrollView {
                VStack(alignment: .leading, spacing: ThroSpacing.spacing5) {
                    PicturePicker(subject: .person(initials: member.initials), size: 88,
                                  current: current, refusedBecause: refusal,
                                  picked: $picked, removed: $removed)
                    Note("The picture is resized and written out again on this phone, and everything "
                         + "the original carried — including where a photograph was taken — is "
                         + "dropped. Nothing has left the phone: an image is checked when it is "
                         + "published, and there is nowhere to publish to yet.")
                    // Said on the screen where somebody is putting a real person's face into an app,
                    // rather than only in a document nobody on a phone will read.
                    Note("\(member.name) has not been asked. This is \(club.name)'s copy of a "
                         + "picture of somebody who has no account here and cannot remove it "
                         + "themselves — so use one they would be happy to be shown by.",
                         icon: .shield)
                }
                .padding(.horizontal, ThroSpacing.spaceScreenGutter)
                .padding(.vertical, ThroSpacing.spacing5)
            }
            if refusal == nil {
                ThroButton("Save", variant: .primary, size: .large, fullWidth: true,
                           disabled: !changed) {
                    onSave(picked, removed)
                }
                .padding(.horizontal, ThroSpacing.spaceScreenGutter)
                .padding(.bottom, ThroSpacing.spacing6)
            }
        }
        .background(ThroColor.colorBackgroundPrimary.ignoresSafeArea())
    }
}
