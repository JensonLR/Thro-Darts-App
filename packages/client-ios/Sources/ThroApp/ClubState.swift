import Foundation

// Clubs, leagues and tournaments on the phone (PD-009, PD-010).
//
// These are the same rules `packages/organisation` states in Kotlin, restated here because a screen
// has to know what to draw before anything has been asked of a server. **The Kotlin is the
// reference and, when a server exists, the server is authoritative**: this copy decides what a
// screen shows, never what a person may do. That is the same division the rest of the client keeps —
// the engine decides an outcome, the journal records it, and the screen renders what it is told.
//
// `ClubStateTests` holds both copies to the same three assertions, which is the cheapest guard
// available while the two cannot be run against one corpus.

public enum OrgKind: String, Sendable, CaseIterable {
    case club, league, tournament

    public var label: String {
        switch self {
        case .club: return "Club"
        case .league: return "League"
        case .tournament: return "Tournament"
        }
    }
}

public enum OrgRole: String, Sendable, Comparable {
    case member, official, admin

    private var rank: Int {
        switch self { case .member: return 0; case .official: return 1; case .admin: return 2 }
    }
    public static func < (a: OrgRole, b: OrgRole) -> Bool { a.rank < b.rank }

    public var label: String {
        switch self {
        case .member: return "Member"
        case .official: return "Official"
        case .admin: return "Admin"
        }
    }
}

/// The age dimension, as `packages/authz` defines it: unknown is a value, and it is treated as the
/// most restrictive case, because the thing not known is whether this is a child.
public enum AgeBand: String, Sendable { case unknown, minor, adult }

public struct ClubMember: Identifiable, Equatable, Sendable {
    public let id: String
    public let name: String
    public let role: OrgRole
    public let ageBand: AgeBand
    public let joined: String
    /// Nil when the figure cannot be computed honestly, which is a fact and not an absence.
    public let threeDartAverage: Double?
    /// Their picture, when they have one. **Only ever an adult** (PD-014): the store refuses to
    /// write one for anybody else and refuses to hand one back if the age stops saying adult.
    public let avatarAssetId: String?

    public init(id: String, name: String, role: OrgRole, ageBand: AgeBand = .adult,
                joined: String, threeDartAverage: Double? = nil, avatarAssetId: String? = nil) {
        self.avatarAssetId = avatarAssetId
        self.id = id
        self.name = name
        self.role = role
        self.ageBand = ageBand
        self.joined = joined
        self.threeDartAverage = threeDartAverage
    }

    public var initials: String {
        name.split(separator: " ").prefix(2).compactMap { $0.first }.map(String.init).joined().uppercased()
    }
}

public enum FixtureState: String, Sendable {
    case scheduled, postponed, cancelled, played

    public var label: String { rawValue.capitalized }
    public var isTerminal: Bool { self == .cancelled || self == .played }
}

public struct Fixture: Identifiable, Equatable, Sendable {
    public let id: String
    public let title: String
    public let when: String
    public let venue: String
    public let state: FixtureState

    public init(id: String, title: String, when: String, venue: String, state: FixtureState = .scheduled) {
        self.id = id
        self.title = title
        self.when = when
        self.venue = venue
        self.state = state
    }
}

public struct Announcement: Identifiable, Equatable, Sendable {
    public let id: String
    public let subject: String
    public let author: String
    public let ago: String
    public let reached: Int
    public let of: Int

    public init(id: String, subject: String, author: String, ago: String, reached: Int, of: Int) {
        self.id = id
        self.subject = subject
        self.author = author
        self.ago = ago
        self.reached = reached
        self.of = of
    }
}

/// Why an announcement will not reach somebody. Counted and named on the compose screen before it is
/// sent, because an official who thinks they have told everybody has been failed by the app.
public struct Withheld: Equatable, Sendable {
    public let minors: Int
    public let ageNotGiven: Int

    public var total: Int { minors + ageNotGiven }

    /// One line per reason, in the order the screen shows them. Empty when nobody is withheld.
    public var lines: [(count: String, why: String)] {
        var out: [(String, String)] = []
        if minors > 0 {
            out.append(("\(minors) member\(minors == 1 ? "" : "s") under 18",
                        "nobody under 18 is sent a message until THRØ has taken safeguarding advice."))
        }
        if ageNotGiven > 0 {
            out.append(("\(ageNotGiven) member\(ageNotGiven == 1 ? "" : "s") whose age is not given",
                        "treated the same way, because what is not known is whether they are a child."))
        }
        return out
    }

    public static func == (a: Withheld, b: Withheld) -> Bool {
        a.minors == b.minors && a.ageNotGiven == b.ageNotGiven
    }
}

public struct Club: Identifiable, Equatable, Sendable {
    public let id: String
    public let name: String
    public let kind: OrgKind
    public let meta: String
    /// The club's accent as six hex digits. Nil means it has chosen none and wears the brand's.
    public let accentHex: String?
    public let verified: Bool
    /// The club's badge, when it has one (PD-014). Nil is ordinary: a club may prefer its initials.
    public let badgeAssetId: String?
    /// The viewer's own role here, or nil if they are not a member. PD-009: a stranger sees the front.
    public let yourRole: OrgRole?
    public let members: [ClubMember]
    public let fixtures: [Fixture]
    public let announcements: [Announcement]

    public init(id: String, name: String, kind: OrgKind, meta: String, accentHex: String? = nil,
                verified: Bool = false, yourRole: OrgRole? = nil, members: [ClubMember] = [],
                fixtures: [Fixture] = [], announcements: [Announcement] = [],
                badgeAssetId: String? = nil) {
        self.badgeAssetId = badgeAssetId
        self.id = id
        self.name = name
        self.kind = kind
        self.meta = meta
        self.accentHex = accentHex
        self.verified = verified
        self.yourRole = yourRole
        self.members = members
        self.fixtures = fixtures
        self.announcements = announcements
    }

    /// A badge carries at most three letters, and "The Feathers A" is FA rather than TFA: the words
    /// a club's name shares with every other club's carry no information at that size.
    /// "A" is NOT here, and that is the point: Feathers A and Feathers B are different clubs, and a
    /// badge that dropped the letter would give them the same one.
    private static let skipped: Set<String> = ["the", "of", "and", "&"]
    public var initials: String {
        let words = name.split(whereSeparator: { $0 == " " || $0 == "-" })
            .filter { !Club.skipped.contains($0.lowercased()) }
        let letters = words.compactMap { $0.first }.map { String($0).uppercased() }.joined()
        return String(letters.prefix(3))
    }

    // MARK: - PD-009

    /// Whether the viewer is inside. A stranger sees the front and nothing else.
    public var isMember: Bool { yourRole != nil }

    /// Who the viewer may see on the membership list.
    ///
    /// A member recorded as a minor — or whose age is not established, treated the same way — is
    /// listed **only to an admin**, and not to an official either: running a club is not a reason to
    /// see a child. A property rather than a convention, so a screen cannot render the list without it.
    public var visibleMembers: [ClubMember] {
        guard let role = yourRole else { return [] }
        if role == .admin { return members }
        return members.filter { $0.ageBand == .adult }
    }

    /// How many members the list is not showing, and why. Shown rather than a quietly shorter list.
    public var hiddenMembers: Int { members.count - visibleMembers.count }

    /// Still to come, newest first. `postponed` counts: it has not been played and it is still on.
    public var upcomingFixtures: [Fixture] { fixtures.filter { !$0.state.isTerminal } }

    /// Played, most recent first. **Cancelled is not played** — nobody threw — so it is in neither
    /// list, which is why these two do not sum to `fixtures`.
    public var playedFixtures: [Fixture] { fixtures.filter { $0.state == .played } }

    /// Whether this organisation has ever had a fixture at all. Distinct from having nothing
    /// scheduled: the club page used to show the second as the first, so a club with a season behind
    /// it and nothing booked read as one that had never played.
    public var hasEverHadAFixture: Bool { !fixtures.isEmpty }

    public var mayAnnounce: Bool { (yourRole ?? .member) >= .official && isMember }
    public var mayManageFixtures: Bool { (yourRole ?? .member) >= .official && isMember }
    public var mayManageMembers: Bool { yourRole == .admin }

    /// Who an announcement would reach, and who it would not.
    public var delivery: (reaches: Int, of: Int, withheld: Withheld) {
        let minors = members.filter { $0.ageBand == .minor }.count
        let unknown = members.filter { $0.ageBand == .unknown }.count
        let withheld = Withheld(minors: minors, ageNotGiven: unknown)
        return (members.count - withheld.total, members.count, withheld)
    }
}
