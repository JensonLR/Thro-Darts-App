import SwiftUI
import ThroDesign
import ThroTokens

// The club, league, tournament and profile screens (PD-010).
//
// Assembled from ThroDesign, which is assembled from the approved export. One element these needed
// that the export does not draw is `Badge`, recorded rather than slipped in; four glyphs they needed
// (lock, shield, calendar, search) were already in the export's own icon set and were ported.
//
// Two things these screens say out loud, because saying nothing would be a lie of omission:
//  - who is NOT on the membership list, and why;
//  - who an announcement will NOT reach, before it is sent.

// MARK: - small shared pieces

/// A quiet line with an icon, used where a screen has to explain itself. The same shape the Play
/// screens already use for "matches on this device are self-reported".
struct Note: View {
    private let text: String
    private let icon: ThroIcon
    private let tone: Color

    init(_ text: String, icon: ThroIcon = .info, tone: Color = ThroColor.colorTextSecondary) {
        self.text = text
        self.icon = icon
        self.tone = tone
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Icon(icon, size: 16).foregroundStyle(tone).padding(.top, 2)
            // LocalizedStringKey, so the emphasis in the text is emphasis and not four asterisks.
            Text(LocalizedStringKey(text))
                .thro(ThroTypography.metadata)
                .foregroundStyle(tone)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// The 44-point back chevron the scoring screen already uses, where a TopBar costs height.
struct BackChevron: View {
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Icon(.chevronLeft, size: 20)
                .foregroundStyle(ThroColor.colorTextPrimary)
                .frame(width: 44, height: 44, alignment: .leading)
        }
        .accessibilityLabel("Back")
    }
}

struct FixtureRow: View {
    let fixture: Fixture
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline, spacing: ThroSpacing.spacing2) {
                Text(fixture.title)
                    .thro(ThroTypography.label.weight(.bold))
                    .foregroundStyle(ThroColor.colorTextPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: ThroSpacing.spacing2)
                Tag(fixture.state.label, tone: fixture.state == .postponed ? .warning
                    : fixture.state == .played ? .brand : .neutral)
            }
            Text("\(fixture.when) · \(fixture.venue)")
                .thro(ThroTypography.metadata)
                .foregroundStyle(ThroColor.colorTextSecondary)
        }
        .padding(.vertical, ThroSpacing.spacing3)
        .accessibilityElement(children: .combine)
    }
}

struct MemberRow: View {
    let member: ClubMember
    var showRoleTag: Bool = true

    var body: some View {
        HStack(spacing: ThroSpacing.spacing3) {
            PlayerIdentity(PlayerRef(name: member.name), size: .small)
            Spacer(minLength: ThroSpacing.spacing2)
            if showRoleTag, member.role != .member { Tag(member.role.label, tone: member.role == .admin ? .brand : .neutral) }
        }
        .padding(.vertical, ThroSpacing.spacing2)
    }
}

// MARK: - Clubs

/// The Clubs tab: what you belong to, and one line about what is public.
public struct ClubsScreen: View {
    private let clubs: [Club]
    private let onOpen: (Club) -> Void
    private let onSearch: () -> Void

    public init(clubs: [Club], onOpen: @escaping (Club) -> Void = { _ in },
                onSearch: @escaping () -> Void = {}) {
        self.clubs = clubs
        self.onOpen = onOpen
        self.onSearch = onSearch
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            TopBar("Clubs")
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    if clubs.isEmpty {
                        EmptyState(title: "No clubs yet",
                                   message: "A club or league's front page is public. What is inside it — members, results, announcements — is not.",
                                   actionLabel: "Search for a club", onAction: onSearch)
                            .padding(.top, ThroSpacing.spacing6)
                    } else {
                        Eyebrow("Yours").padding(.top, ThroSpacing.spacing5)
                        ThroDivider().padding(.top, ThroSpacing.spacing2)
                        ForEach(clubs) { club in
                            Button { onOpen(club) } label: {
                                OrganisationRow(initials: club.initials, name: club.name,
                                                meta: "\(club.kind.label) · \(club.meta)",
                                                accent: club.accentHex.flatMap { Color.thro(hex: $0) },
                                                trailing: club.yourRole?.label)
                            }
                            .buttonStyle(.plain)
                            ThroDivider()
                        }
                        Eyebrow("Find one").padding(.top, ThroSpacing.spaceSectionGap)
                        Text("A club or league's front page is public. What is inside it — members, results, announcements — is not.")
                            .thro(ThroTypography.body)
                            .foregroundStyle(ThroColor.colorTextSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.top, ThroSpacing.spacing2)
                        ThroButton("Search for a club", variant: .secondary, size: .large,
                                   fullWidth: true, action: onSearch)
                            .padding(.top, ThroSpacing.spacing4)
                    }
                    Note("Nothing here has left this phone. Clubs are not connected to anything yet.")
                        .padding(.top, ThroSpacing.spaceSectionGap)
                }
                .padding(.horizontal, ThroSpacing.spaceScreenGutter)
                .padding(.bottom, ThroSpacing.spacing6)
            }
        }
        .background(ThroColor.colorBackgroundPrimary.ignoresSafeArea())
    }
}

/// One club. A stranger sees the front; a member sees the front and the inside (PD-009).
public struct ClubScreen: View {
    private let club: Club
    private let onBack: () -> Void
    private let onAnnounce: () -> Void
    private let onSeeMembers: () -> Void

    public init(club: Club, onBack: @escaping () -> Void = {}, onAnnounce: @escaping () -> Void = {},
                onSeeMembers: @escaping () -> Void = {}) {
        self.club = club
        self.onBack = onBack
        self.onAnnounce = onAnnounce
        self.onSeeMembers = onSeeMembers
    }

    private var accent: Color { club.accentHex.flatMap { Color.thro(hex: $0) } ?? ThroColor.throGreen }
    private var roleLine: String? {
        guard let r = club.yourRole else { return nil }
        return "You are \(r == .admin ? "an admin" : r == .official ? "an official" : "a member")"
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 0) {
                BackChevron(action: onBack)
                Spacer()
                if club.mayAnnounce {
                    Button(action: onAnnounce) {
                        Text("Announce")
                            .thro(ThroTypography.label.weight(.semibold))
                            .foregroundStyle(ThroColor.colorTextBrand)
                    }
                }
            }
            .padding(.top, ThroSpacing.spacing3)
            .padding(.leading, -12)
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    OrganisationHeader(initials: club.initials, name: club.name, kind: club.kind.label,
                                       meta: club.meta, accent: accent, verified: club.verified,
                                       role: roleLine)
                    if club.isMember { inside } else { front }
                }
                .padding(.horizontal, ThroSpacing.spaceScreenGutter)
                .padding(.bottom, ThroSpacing.spacing6)
            }
        }
        .background(ThroColor.colorBackgroundPrimary.ignoresSafeArea())
    }

    /// What anyone may see: the club exists, and when it plays.
    @ViewBuilder private var front: some View {
        Eyebrow("Next fixtures").padding(.top, ThroSpacing.spacing5)
        ThroDivider().padding(.top, ThroSpacing.spacing2)
        ForEach(Array(club.fixtures.filter { !$0.state.isTerminal }.prefix(3))) { f in
            FixtureRow(fixture: f)
            ThroDivider()
        }
        // The boundary, stated rather than implied — a page that simply stops looks broken.
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 10) {
                Icon(.lock, size: 18).foregroundStyle(ThroColor.colorTextSecondary).padding(.top, 1)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Members only").thro(ThroTypography.label.weight(.bold))
                        .foregroundStyle(ThroColor.colorTextPrimary)
                    Text("Who plays here, results, and the club's announcements are for members. Ask an admin to add you.")
                        .thro(ThroTypography.metadata)
                        .foregroundStyle(ThroColor.colorTextSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(ThroSpacing.spacing4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(ThroColor.colorBackgroundRaised, in: RoundedRectangle(cornerRadius: ThroSpacing.radiusCard))
        .overlay(RoundedRectangle(cornerRadius: ThroSpacing.radiusCard)
            .strokeBorder(ThroColor.colorBorderDefault, lineWidth: 1))
        .padding(.top, ThroSpacing.spaceSectionGap)
        Note("A club's front is public so a league can advertise a season. Everything past it is not.")
            .padding(.top, ThroSpacing.spaceSectionGap)
    }

    /// What a member may see.
    @ViewBuilder private var inside: some View {
        if !club.announcements.isEmpty {
            Eyebrow("From the club").padding(.top, ThroSpacing.spacing5)
            VStack(alignment: .leading, spacing: ThroSpacing.spacing4) {
                ForEach(Array(club.announcements.enumerated()), id: \.element.id) { index, a in
                    HStack(alignment: .top, spacing: ThroSpacing.spacing3) {
                        Rectangle()
                            .fill(index == 0 ? ThroColor.throGreen : ThroColor.colorBorderStrong)
                            .frame(width: 3)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(a.subject).thro(ThroTypography.label.weight(.bold))
                                .foregroundStyle(ThroColor.colorTextPrimary)
                                .fixedSize(horizontal: false, vertical: true)
                            Text("\(a.author) · \(a.ago) · reached \(a.reached) of \(a.of)")
                                .thro(ThroTypography.metadata)
                                .foregroundStyle(ThroColor.colorTextSecondary)
                        }
                        Spacer(minLength: 0)
                    }
                    .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.top, ThroSpacing.spacing2)
        }
        HStack(alignment: .firstTextBaseline) {
            Eyebrow("Members")
            Spacer()
            Button(action: onSeeMembers) {
                Text("See all")
                    .thro(ThroTypography.metadata.weight(.semibold))
                    .foregroundStyle(ThroColor.colorTextBrand)
            }
        }
        .padding(.top, ThroSpacing.spaceSectionGap)
        ThroDivider().padding(.top, ThroSpacing.spacing2)
        ForEach(Array(club.visibleMembers.prefix(3))) { m in
            MemberRow(member: m, showRoleTag: false)
            ThroDivider()
        }
    }
}

/// The membership list, and the count it is not showing (PD-009).
public struct ClubMembersScreen: View {
    private let club: Club
    private let onBack: () -> Void

    public init(club: Club, onBack: @escaping () -> Void = {}) {
        self.club = club
        self.onBack = onBack
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            TopBar("Members", eyebrow: club.name, onBack: onBack)
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ThroDivider().padding(.top, ThroSpacing.spacing4)
                    ForEach(club.visibleMembers) { m in
                        MemberRow(member: m)
                        ThroDivider()
                    }
                    // Said, not silently shorter. An official is told they cannot see them either.
                    if club.hiddenMembers > 0 {
                        Note("**\(club.hiddenMembers) member\(club.hiddenMembers == 1 ? " is" : "s are") not shown.** "
                             + "Members under 18, and members whose age has not been given, are listed only to an "
                             + "admin — including to officials. Nothing about them appears here.",
                             icon: .shield)
                            .padding(ThroSpacing.spacing4)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(ThroColor.colorBackgroundSecondary,
                                        in: RoundedRectangle(cornerRadius: ThroSpacing.radiusCard))
                            .padding(.top, ThroSpacing.spacing5)
                    }
                }
                .padding(.horizontal, ThroSpacing.spaceScreenGutter)
                .padding(.bottom, ThroSpacing.spacing6)
            }
        }
        .background(ThroColor.colorBackgroundPrimary.ignoresSafeArea())
    }
}

/// The official's fixture list (PD-009). A fixture carries no result.
public struct FixturesScreen: View {
    private let club: Club
    private let onBack: () -> Void
    private let onAdd: () -> Void

    public init(club: Club, onBack: @escaping () -> Void = {}, onAdd: @escaping () -> Void = {}) {
        self.club = club
        self.onBack = onBack
        self.onAdd = onAdd
    }

    private var upcoming: [Fixture] { club.fixtures.filter { !$0.state.isTerminal } }
    private var done: [Fixture] { club.fixtures.filter(\.state.isTerminal) }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            TopBar("Fixtures", eyebrow: club.name, onBack: onBack,
                   actions: club.mayManageFixtures ? [TopBar.Action(icon: .plus, label: "Add", action: onAdd)] : [])
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    if !upcoming.isEmpty {
                        Eyebrow("To come").padding(.top, ThroSpacing.spacing4)
                        ThroDivider().padding(.top, ThroSpacing.spacing1)
                        ForEach(upcoming) { f in FixtureRow(fixture: f); ThroDivider() }
                    }
                    if !done.isEmpty {
                        Eyebrow("Played").padding(.top, ThroSpacing.spaceSectionGap)
                        ThroDivider().padding(.top, ThroSpacing.spacing1)
                        ForEach(done) { f in FixtureRow(fixture: f); ThroDivider() }
                    }
                    if club.fixtures.isEmpty {
                        EmptyState(title: "No fixtures yet",
                                   message: club.mayManageFixtures
                                        ? "Add one and it appears on the club's public page."
                                        : "An official adds them.")
                            .padding(.top, ThroSpacing.spacing6)
                    }
                    Note("A fixture carries no result. A result comes from a scored match and the evidence behind it, so a fixture that could assert one would be a second place a score came from.")
                        .padding(.top, ThroSpacing.spaceSectionGap)
                }
                .padding(.horizontal, ThroSpacing.spaceScreenGutter)
                .padding(.bottom, ThroSpacing.spacing6)
            }
        }
        .background(ThroColor.colorBackgroundPrimary.ignoresSafeArea())
    }
}

/// Composing an announcement, and who it will not reach (PD-009, and OD-010 while it is open).
///
/// The count and the reason are shown **before** it is sent, not after, because an official who
/// thinks they have told everybody has been failed by the app. It is not presented as a setting,
/// because it is not one.
public struct AnnounceScreen: View {
    private let club: Club
    @State private var subject: String = ""
    @State private var body_: String = ""
    private let onBack: () -> Void
    private let onSend: (String, String) -> Void

    public init(club: Club, onBack: @escaping () -> Void = {},
                onSend: @escaping (String, String) -> Void = { _, _ in }) {
        self.club = club
        self.onBack = onBack
        self.onSend = onSend
    }

    private var canSend: Bool {
        !subject.trimmingCharacters(in: .whitespaces).isEmpty
            && !body_.trimmingCharacters(in: .whitespaces).isEmpty
            && club.delivery.reaches > 0
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            TopBar("New announcement", eyebrow: club.name, onBack: onBack)
            ScrollView {
                VStack(alignment: .leading, spacing: ThroSpacing.spacing4) {
                    ThroTextField("Subject", text: $subject, placeholder: "What has happened")
                    // The export draws no multi-line field, so this is the approved one with the
                    // help text doing the work a taller box would — rather than a field invented to
                    // look like one. A textarea is a design commission, not an engineering choice.
                    ThroTextField("Message", text: $body_, placeholder: "The detail",
                                  helper: "Kept short on purpose: an announcement is a notice, not a letter.")
                    deliveryPanel
                }
                .padding(.horizontal, ThroSpacing.spaceScreenGutter)
                .padding(.top, ThroSpacing.spacing5)
                .padding(.bottom, ThroSpacing.spacing5)
            }
            VStack(spacing: ThroSpacing.spacing3) {
                ThroButton("Send to \(club.delivery.reaches) member\(club.delivery.reaches == 1 ? "" : "s")",
                           variant: .primary, size: .large, fullWidth: true, disabled: !canSend) {
                    onSend(subject, body_)
                }
                Text("Your name is on it. Every member sees who sent it.")
                    .thro(ThroTypography.metadata)
                    .foregroundStyle(ThroColor.colorTextSecondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, ThroSpacing.spaceScreenGutter)
            .padding(.bottom, ThroSpacing.spacing6)
        }
        .background(ThroColor.colorBackgroundPrimary.ignoresSafeArea())
    }

    private var deliveryPanel: some View {
        let d = club.delivery
        return VStack(alignment: .leading, spacing: ThroSpacing.spacing2) {
            Text("Reaches \(d.reaches) of \(d.of) members")
                .thro(ThroTypography.label.weight(.bold))
                .foregroundStyle(ThroColor.colorTextPrimary)
            ForEach(Array(d.withheld.lines.enumerated()), id: \.offset) { _, line in
                Text(LocalizedStringKey("**\(line.count)** — \(line.why)"))
                    .thro(ThroTypography.metadata)
                    .foregroundStyle(ThroColor.colorTextSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if d.withheld.total > 0 {
                Note("This is not a setting you can turn off.", icon: .shield)
                    .padding(.top, ThroSpacing.spacing1)
            }
        }
        .padding(ThroSpacing.spacing4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(ThroColor.colorBackgroundRaised, in: RoundedRectangle(cornerRadius: ThroSpacing.radiusCard))
        .overlay(RoundedRectangle(cornerRadius: ThroSpacing.radiusCard)
            .strokeBorder(ThroColor.colorBorderDefault, lineWidth: 1))
    }
}

/// A player's own page: who they are, what their figures are, and where they play.
public struct ProfileScreen: View {
    public struct Figure: Identifiable, Sendable {
        public let id = UUID()
        public let value: String
        public let label: String
        /// Why a figure is a dash. Present exactly when the value is one.
        public let unavailable: String?

        public init(value: String, label: String, unavailable: String? = nil) {
            self.value = value
            self.label = label
            self.unavailable = unavailable
        }
    }

    private let name: String
    private let meta: String
    private let figures: [Figure]
    private let clubs: [Club]
    private let onBack: () -> Void

    public init(name: String, meta: String, figures: [Figure], clubs: [Club],
                onBack: @escaping () -> Void = {}) {
        self.name = name
        self.meta = meta
        self.figures = figures
        self.clubs = clubs
        self.onBack = onBack
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 0) { BackChevron(action: onBack); Spacer() }
                .padding(.top, ThroSpacing.spacing3)
                .padding(.leading, -12)
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: ThroSpacing.spacing4) {
                        PlayerIdentity(PlayerRef(name: name), size: .large)
                        Spacer(minLength: 0)
                    }
                    Text(meta)
                        .thro(ThroTypography.metadata)
                        .foregroundStyle(ThroColor.colorTextSecondary)
                        .padding(.top, ThroSpacing.spacing2)
                    HStack(spacing: 6) { Tag("Not rated"); Tag("Self-reported") }
                        .padding(.top, ThroSpacing.spacing2)

                    Eyebrow("Last 20 legs").padding(.top, ThroSpacing.spaceSectionGap)
                    VStack(alignment: .leading, spacing: ThroSpacing.spacing4) {
                        ForEach(Array(stride(from: 0, to: figures.count, by: 3)), id: \.self) { start in
                            HStack(alignment: .top, spacing: ThroSpacing.spacing4) {
                                ForEach(figures[start..<min(start + 3, figures.count)]) { f in
                                    VStack(alignment: .leading, spacing: 0) {
                                        Text(f.value)
                                            .thro(ThroTypography.heading2.family(.sport).weight(.semibold))
                                            .foregroundStyle(ThroColor.colorTextPrimary)
                                        Text(f.label)
                                            .thro(ThroTypography.metadata)
                                            .foregroundStyle(ThroColor.colorTextSecondary)
                                        if let why = f.unavailable {
                                            Text(why)
                                                .thro(ThroTypography.metadata)
                                                .foregroundStyle(ThroColor.colorTextTertiary)
                                                .fixedSize(horizontal: false, vertical: true)
                                        }
                                    }
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                }
                            }
                        }
                    }
                    .padding(.top, ThroSpacing.spacing3)
                    Note("Every figure here comes from matches scored on this phone and confirmed by nobody. A dash means the figure cannot be computed honestly yet, and says why.")
                        .padding(.top, ThroSpacing.spacing3)

                    if !clubs.isEmpty {
                        Eyebrow("Clubs and leagues").padding(.top, ThroSpacing.spaceSectionGap)
                        ThroDivider().padding(.top, ThroSpacing.spacing2)
                        ForEach(clubs) { c in
                            OrganisationRow(initials: c.initials, name: c.name,
                                            meta: "\(c.kind.label) · \(c.yourRole?.label ?? "Member")",
                                            accent: c.accentHex.flatMap { Color.thro(hex: $0) })
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
