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
    /// The chevron's ink: the page's text on paper, chalk on the brand field (`BoardHeader`).
    var ink: Color = ThroColor.colorTextPrimary
    var body: some View {
        Button(action: action) {
            Icon(.chevronLeft, size: 20)
                .foregroundStyle(ink)
                .frame(width: 44, height: 44, alignment: .leading)
                // Without this the 44 points are decoration: SwiftUI hit-tests the chevron's ink,
                // so three quarters of the target did nothing.
                .contentShape(Rectangle())
        }
        .buttonStyle(ThroPressStyle(radius: ThroSpacing.radiusStatus))
        .accessibilityLabel("Back")
    }
}

/// The bar at the top of a page that has its own full-bleed header underneath — a club, a league, a
/// tournament, a profile. Back on the left, worded actions on the right.
///
/// **This exists because four screens hand-rolled it and all four were wrong the same way.** The
/// founder, on a screenshot: *"no back button on view screen for clubs etc. still ugly cropped view
/// as seen in ss top right."* The back chevron was off the left edge of the phone and "Announce" was
/// cut in half by the right edge.
///
/// The cause was mine, twice over. The first version put a −12 inset on the whole row, which shifted
/// every trailing item off the right edge. The correction moved that inset onto the chevron — the
/// right principle, *a negative inset belongs to the thing it is insetting* — and missed that **the
/// row had no gutter to inset from at all**. So the chevron went to x = −12, and the last action sat
/// flush against the screen edge with nothing to spare.
///
/// The geometry, written down once so it cannot be got wrong a third time:
///
///  - `BackChevron` draws its 20-point glyph at the **leading edge** of its own 44-point target.
///  - So a row with the screen gutter on it, and no inset anywhere, lands the glyph exactly on the
///    gutter — where the text below it starts — while the touch target still reaches into the
///    margin. **The negative inset was never needed; the gutter was.**
///  - Every action is `fixedSize`, so a label is never squeezed into an ellipsis by a neighbour, and
///    the `Spacer` yields before the words do.
struct PageBar: View {
    struct Action: Identifiable {
        let label: String
        let action: () -> Void
        var id: String { label }
    }

    let onBack: () -> Void
    var actions: [Action] = []
    /// Chalk when the bar sits on the brand field rather than on paper.
    var ink: Color = ThroColor.colorTextPrimary

    var body: some View {
        HStack(spacing: ThroSpacing.spacing4) {
            BackChevron(action: onBack, ink: ink)
            Spacer(minLength: ThroSpacing.spacing2)
            ForEach(actions) { action in
                ThroTextButton(action.label, alignment: .trailing, action: action.action)
            }
        }
        .padding(.horizontal, ThroSpacing.spaceScreenGutter)
        .padding(.top, ThroSpacing.spacing3)
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
    /// Their picture, when this device holds one. A roster reads as faces where there are faces and
    /// as initials where there are not, rather than as one or the other everywhere.
    var picture: Image? = nil

    var body: some View {
        HStack(spacing: ThroSpacing.spacing3) {
            PlayerIdentity(PlayerRef(name: member.name), size: .small, picture: picture)
            Spacer(minLength: ThroSpacing.spacing2)
            if showRoleTag, member.role != .member { Tag(member.role.label, tone: member.role == .admin ? .brand : .neutral) }
        }
        .padding(.vertical, ThroSpacing.spacing2)
    }
}

// MARK: - Clubs

/// One club. A stranger sees the front; a member sees the front and the inside (PD-009).
public struct ClubScreen: View {
    private let club: Club
    private let onBack: () -> Void
    private let onAnnounce: () -> Void
    private let onSeeMembers: () -> Void
    private let onFixtures: () -> Void
    private let badge: Image?
    /// A member's picture, looked up rather than held: the store decodes each file once and this
    /// screen asks for it, so a roster does not read the same bytes off disk on every frame.
    private let picture: (ClubMember) -> Image?
    /// Nil when the viewer may not change the club. Absent rather than disabled, for the reason the
    /// members list gives: an admin-only action shown greyed out tells a member what they are missing.
    private let onEdit: (() -> Void)?

    public init(club: Club, badge: Image? = nil, picture: @escaping (ClubMember) -> Image? = { _ in nil },
                onBack: @escaping () -> Void = {},
                onAnnounce: @escaping () -> Void = {}, onSeeMembers: @escaping () -> Void = {},
                onFixtures: @escaping () -> Void = {}, onEdit: (() -> Void)? = nil) {
        self.club = club
        self.badge = badge
        self.picture = picture
        self.onBack = onBack
        self.onAnnounce = onAnnounce
        self.onSeeMembers = onSeeMembers
        self.onFixtures = onFixtures
        self.onEdit = onEdit
    }

    /// The bar's actions, built where their types are declared rather than inline in a view builder.
    static func actions(edit: (() -> Void)?, announce: (() -> Void)?) -> [PageBar.Action] {
        var out: [PageBar.Action] = []
        if let edit { out.append(PageBar.Action(label: "Edit", action: edit)) }
        if let announce { out.append(PageBar.Action(label: "Announce", action: announce)) }
        return out
    }

    private var accent: Color { club.accentHex.flatMap { Color.thro(hex: $0) } ?? ThroColor.throGreen }
    private var roleLine: String? {
        guard let r = club.yourRole else { return nil }
        return "You are \(r == .admin ? "an admin" : r == .official ? "an official" : "a member")"
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            PageBar(onBack: onBack, actions: ClubScreen.actions(edit: onEdit,
                                                               announce: club.mayAnnounce ? onAnnounce : nil))
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    OrganisationHeader(initials: club.initials, name: club.name, kind: club.kind.label,
                                       meta: club.meta, accent: accent, verified: club.verified,
                                       role: roleLine, image: badge)
                    if club.isMember { inside } else { front }
                }
                .padding(.horizontal, ThroSpacing.spaceScreenGutter)
                .padding(.bottom, ThroSpacing.spacing6)
            }
        }
        // The screen arrives (PD-027): one beat, on the design's own curve,
        // withdrawn entirely under Reduce Motion.
        .throEntrance(0)
        .background(ThroColor.colorBackgroundPrimary.ignoresSafeArea())
    }

    /// What anyone may see: the club exists, and when it plays.
    @ViewBuilder private var front: some View {
        sectionHeading("Next fixtures", action: "See all", onAction: onFixtures)
            .padding(.top, ThroSpacing.spacing5)
        ThroDivider().padding(.top, ThroSpacing.spacing2)
        ForEach(Array(club.fixtures.filter { !$0.state.isTerminal }.prefix(3))) { f in
            FixtureRow(fixture: f)
            ThroDivider()
        }
        if club.fixtures.filter({ !$0.state.isTerminal }).isEmpty {
            Text("Nothing scheduled.")
                .thro(ThroTypography.body)
                .foregroundStyle(ThroColor.colorTextSecondary)
                .padding(.vertical, ThroSpacing.spacing3)
        }
        // The boundary, stated rather than implied — a page that simply stops looks broken.
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 10) {
                Icon(.lock, size: 18).foregroundStyle(ThroColor.colorTextSecondary).padding(.top, 1)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Members only").thro(ThroTypography.label.weight(.bold))
                        .foregroundStyle(ThroColor.colorTextPrimary)
                    Text("Who plays here, results, and the team's announcements are for members. Ask an admin to add you.")
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
        Note("A team's front is public so a league can advertise a season. Everything past it is not.")
            .padding(.top, ThroSpacing.spaceSectionGap)
    }

    /// What a member may see.
    @ViewBuilder private var inside: some View {
        if !club.announcements.isEmpty {
            Eyebrow("From the team").padding(.top, ThroSpacing.spacing5)
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
        sectionHeading("Fixtures", action: club.mayManageFixtures ? "Keep the list" : "See all",
                       onAction: onFixtures)
            .padding(.top, ThroSpacing.spaceSectionGap)
        ThroDivider().padding(.top, ThroSpacing.spacing2)
        ForEach(Array(club.upcomingFixtures.prefix(3))) { f in
            FixtureRow(fixture: f)
            ThroDivider()
        }
        // Recently played, which this page used to hide entirely. A club with a season behind it and
        // nothing booked said "Nothing scheduled", which reads as a club that has never played.
        if !club.playedFixtures.isEmpty {
            Eyebrow(club.upcomingFixtures.isEmpty ? "Last played" : "Recently played")
                .padding(.top, ThroSpacing.spacing4)
            ThroDivider().padding(.top, ThroSpacing.spacing1)
            ForEach(Array(club.playedFixtures.prefix(club.upcomingFixtures.isEmpty ? 3 : 2))) { f in
                FixtureRow(fixture: f)
                ThroDivider()
            }
        }
        if club.fixtures.isEmpty {
            Text(club.mayManageFixtures ? "No fixtures yet. You keep this list." : "No fixtures yet.")
                .thro(ThroTypography.body)
                .foregroundStyle(ThroColor.colorTextSecondary)
                .padding(.vertical, ThroSpacing.spacing3)
        } else if club.upcomingFixtures.isEmpty {
            // The two are different facts and the page must not show the second as the first.
            Text(club.mayManageFixtures
                 ? "Nothing scheduled — every fixture here has been played or cancelled. You keep this list."
                 : "Nothing scheduled. Everything here has been played or cancelled.")
                .thro(ThroTypography.body)
                .foregroundStyle(ThroColor.colorTextSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.vertical, ThroSpacing.spacing3)
        }
        sectionHeading("Members", action: "See all", onAction: onSeeMembers)
            .padding(.top, ThroSpacing.spaceSectionGap)
        ThroDivider().padding(.top, ThroSpacing.spacing2)
        ForEach(Array(club.visibleMembers.prefix(3))) { m in
            MemberRow(member: m, showRoleTag: false, picture: picture(m))
            ThroDivider()
        }
        if club.members.isEmpty {
            Text(club.mayManageMembers ? "Nobody on the roster yet. You keep it." : "Nobody on the roster yet.")
                .thro(ThroTypography.body)
                .foregroundStyle(ThroColor.colorTextSecondary)
                .padding(.vertical, ThroSpacing.spacing3)
        }
    }

    /// An eyebrow with the one link that belongs beside it. The export puts the link on the
    /// baseline of the eyebrow, so it is built once rather than three times.
    private func sectionHeading(_ title: String, action: String, onAction: @escaping () -> Void) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Eyebrow(title)
            Spacer()
            ThroTextButton(action, alignment: .trailing, action: onAction)
        }
    }
}

/// The membership list, and the count it is not showing (PD-009).
public struct ClubMembersScreen: View {
    private let club: Club
    private let onBack: () -> Void
    /// Nil when the viewer may not manage the roster: the control is absent rather than disabled,
    /// because an admin-only action shown greyed out tells a member what they are missing.
    private let onAdd: (() -> Void)?
    private let onRemove: ((String) -> Void)?
    private let onOpen: ((ClubMember) -> Void)?
    private let picture: (ClubMember) -> Image?

    public init(club: Club, onBack: @escaping () -> Void = {},
                onAdd: (() -> Void)? = nil, onRemove: ((String) -> Void)? = nil,
                onOpen: ((ClubMember) -> Void)? = nil,
                picture: @escaping (ClubMember) -> Image? = { _ in nil }) {
        self.club = club
        self.onBack = onBack
        self.onAdd = onAdd
        self.onRemove = onRemove
        self.onOpen = onOpen
        self.picture = picture
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            TopBar("Members", eyebrow: club.name, onBack: onBack,
                   actions: onAdd.map { [TopBar.Action(icon: .plus, label: "Add a member", action: $0)] } ?? [])
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ThroDivider().padding(.top, ThroSpacing.spacing4)
                    ForEach(club.visibleMembers) { m in
                        HStack(spacing: 0) {
                            if let onOpen {
                                Button { onOpen(m) } label: {
                                    MemberRow(member: m, picture: picture(m)).throRowTapTarget()
                                }
                                .buttonStyle(ThroPressStyle(radius: ThroSpacing.radiusCard,
                                                            pressedFill: ThroColor.colorSurfaceSecondary,
                                                            scales: false))
                            } else {
                                MemberRow(member: m, picture: picture(m))
                            }
                            if let onRemove {
                                Button { onRemove(m.id) } label: {
                                    Icon(.x, size: 18)
                                        .foregroundStyle(ThroColor.colorTextSecondary)
                                        .throTapTarget()
                                }
                                .buttonStyle(ThroPressStyle(radius: ThroSpacing.radiusStatus))
                                .accessibilityLabel("Remove \(m.name)")
                            }
                        }
                        ThroDivider()
                    }
                    if club.visibleMembers.isEmpty && club.hiddenMembers == 0 {
                        if let onAdd {
                            EmptyState(title: "Nobody here yet",
                                       message: "Add the people who play for this team. Each person's age is asked, because who is listed and who is reached follows from it.",
                                       actionLabel: "Add a member", onAction: onAdd)
                                .padding(.top, ThroSpacing.spacing6)
                        } else {
                            EmptyState(title: "Nobody here yet", message: "An admin keeps the roster.")
                                .padding(.top, ThroSpacing.spacing6)
                        }
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
        // The screen arrives (PD-027): one beat, on the design's own curve,
        // withdrawn entirely under Reduce Motion.
        .throEntrance(0)
        .background(ThroColor.colorBackgroundPrimary.ignoresSafeArea())
    }
}

/// The official's fixture list (PD-009). A fixture carries no result.
public struct FixturesScreen: View {
    private let club: Club
    private let onBack: () -> Void
    private let onAdd: () -> Void
    /// Nil when the viewer may not keep the list. Cancelled and played are terminal, which is why
    /// the controls disappear once a fixture is in one of them rather than failing when tapped.
    private let onMove: ((String, FixtureState) -> Void)?
    /// Nil unless this viewer may say what happened (PD-020). A club never has one: a club's fixture
    /// is a title somebody typed, so there are no two sides for a score to belong to.
    private let onRecord: ((Fixture) -> Void)?

    public init(club: Club, onBack: @escaping () -> Void = {}, onAdd: @escaping () -> Void = {},
                onMove: ((String, FixtureState) -> Void)? = nil,
                onRecord: ((Fixture) -> Void)? = nil) {
        self.club = club
        self.onBack = onBack
        self.onAdd = onAdd
        self.onMove = onMove
        self.onRecord = onRecord
    }

    private func team(_ id: String?) -> String { club.teams.first { $0.id == id }?.name ?? "—" }

    private func recordAction(_ f: Fixture) -> (() -> Void)? {
        guard let onRecord, f.awaitsResult else { return nil }
        return { onRecord(f) }
    }

    /// One row, drawn as what it is: a team fixture carries a score and where it came from; a club's
    /// carries a typed title and a state.
    @ViewBuilder private func row(_ f: Fixture) -> some View {
        if f.isBetweenTeams {
            TeamFixtureRow(fixture: f, home: team(f.homeTeamId), away: team(f.awayTeamId),
                           onRecord: recordAction(f))
        } else {
            FixtureRow(fixture: f)
        }
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
                        ForEach(upcoming) { f in
                            row(f)
                            // What this phone can do with a fixture, for anybody looking at it —
                            // not only the official who keeps the list. A reminder and a calendar
                            // entry belong to the player, not to the club.
                            FixturePlanControls(fixture: f)
                            if let onMove { moves(f, onMove) }
                            ThroDivider()
                        }
                    }
                    if !done.isEmpty {
                        Eyebrow("Played").padding(.top, ThroSpacing.spaceSectionGap)
                        ThroDivider().padding(.top, ThroSpacing.spacing1)
                        ForEach(done) { f in row(f); ThroDivider() }
                    }
                    if club.fixtures.isEmpty {
                        // The sentence said *add one* and the only control was the `+` glyph in
                        // the bar. On an empty screen the thing to do next is the whole page, so
                        // it gets the button every other empty state in this app has.
                        EmptyState(title: "No fixtures yet",
                                   message: club.mayManageFixtures
                                        ? "Add one and it appears on the team's public page."
                                        : "An official adds them.",
                                   actionLabel: club.mayManageFixtures ? "Add a fixture" : nil,
                                   onAction: onAdd)
                            .padding(.top, ThroSpacing.spacing6)
                    }
                    // Two different true sentences, because PD-020 changed one of them for leagues
                    // and tournaments and not for clubs. Shipping the old one on a league page would
                    // be a screen contradicting the build.
                    Note(club.kind == .team
                         ? "A fixture carries no result. A result comes from a scored match and the "
                           + "evidence behind it, so a fixture that could assert one would be a "
                           + "second place a score came from."
                         : "A result here is **evidence with a source on it** (PD-020): a match "
                           + "scored in THRØ, or an official's word marked as theirs. Never a bare "
                           + "number, and the two are never drawn the same way.")
                        .padding(.top, ThroSpacing.spaceSectionGap)
                    // Said once, here, rather than under every row. A reminder never leaves the
                    // phone; a calendar entry goes into an app that is not THRØ and may well sync
                    // to iCloud, and finding the venue hands the words to Maps. Each of those is
                    // the player's own action, and each is worth knowing before it is taken.
                    Note("A reminder is scheduled by this phone and delivered by it — nothing is "
                         + "sent anywhere. **Adding a fixture to your calendar puts it in your "
                         + "calendar app**, which is not THRØ and may sync wherever you have it set "
                         + "to; THRØ asks only for permission to add, never to read. Finding the "
                         + "venue searches Maps for the venue exactly as it is typed here — THRØ "
                         + "does not know where it is.")
                        .padding(.top, ThroSpacing.spacing4)
                }
                .padding(.horizontal, ThroSpacing.spaceScreenGutter)
                .padding(.bottom, ThroSpacing.spacing6)
            }
        }
        // The screen arrives (PD-027): one beat, on the design's own curve,
        // withdrawn entirely under Reduce Motion.
        .throEntrance(0)
        .background(ThroColor.colorBackgroundPrimary.ignoresSafeArea())
    }

    /// The moves a fixture has left. `played` and `cancelled` are not offered back out of, because
    /// the domain refuses them and an app that offers a refusal is an app that lies.
    private func moves(_ f: Fixture, _ move: @escaping (String, FixtureState) -> Void) -> some View {
        HStack(spacing: ThroSpacing.spacing2) {
            ForEach([FixtureState.postponed, .played, .cancelled].filter { $0 != f.state }, id: \.rawValue) { to in
                ThroButton(label(to), variant: to == .cancelled ? .destructive : .ghost,
                           size: .small) { move(f.id, to) }
            }
            Spacer(minLength: 0)
        }
        .padding(.bottom, ThroSpacing.spacing3)
    }

    private func label(_ s: FixtureState) -> String {
        switch s {
        case .postponed: return "Postpone"
        case .played: return "Played"
        case .cancelled: return "Cancel"
        case .scheduled: return "Reschedule"
        }
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
    /// Nil when there is nowhere to send it, which in this build is always: an announcement needs a
    /// connection and an identity, and neither exists (Gate 6, B4). The screen is still reachable
    /// because everything it says about **who would be reached** is true today and is the part an
    /// official most needs to see. The send is refused with the reason rather than pretended, which
    /// is the whole difference between an unfinished feature and a dishonest one.
    private let onSend: ((String, String) -> Void)?

    public init(club: Club, onBack: @escaping () -> Void = {},
                onSend: ((String, String) -> Void)? = nil) {
        self.club = club
        self.onBack = onBack
        self.onSend = onSend
    }

    private var written: Bool {
        !subject.trimmingCharacters(in: .whitespaces).isEmpty
            && !body_.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private var canSend: Bool { written && club.delivery.reaches > 0 && onSend != nil }

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
                    onSend?(subject, body_)
                }
                Text(onSend == nil
                     ? "Nothing can be sent yet: an announcement needs a connection and this build has none. What is above is what would happen when it does."
                     : "Your name is on it. Every member sees who sent it.")
                    .thro(ThroTypography.metadata)
                    .foregroundStyle(ThroColor.colorTextSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, ThroSpacing.spaceScreenGutter)
            .padding(.bottom, ThroSpacing.spacing6)
        }
        // The screen arrives (PD-027): one beat, on the design's own curve,
        // withdrawn entirely under Reduce Motion.
        .throEntrance(0)
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
    /// The one figure the page leads with, drawn big.
    ///
    /// A profile is read for one thing before anything else — *how have I been playing* — and the
    /// old page buried that answer in the fourth cell of a three-across grid at the same size as
    /// the count of legs won. The founder's player put it plainly: **"just make what's needed big,
    /// that's the main hiccup u see."** It is a `StatItem` like every other figure here, so a
    /// headline that cannot be computed says why in the same words a small one would.
    public typealias Headline = StatItem

    private let name: String
    private let meta: String
    private let heading: String
    private let headline: Headline?
    private let figures: [StatItem]
    private let clubs: [Club]
    /// Their picture, when they have one (PD-014).
    private let picture: Image?
    /// Why they have no picture, for the one viewer who would otherwise go looking for the control.
    /// Never shown alongside `onEditPicture` — a screen says either "here is how" or "here is why
    /// not", and showing both would mean one of them is wrong.
    private let pictureNote: String?
    /// Nil unless this viewer may set it. Absent rather than disabled, as everywhere else here.
    private let onEditPicture: (() -> Void)?
    private let onBack: () -> Void
    /// Takes this person off the phone. Offered at the foot of the page, as a quiet destructive
    /// action, and only where the caller can do it.
    private let onRemove: (() -> Void)?

    public init(name: String, meta: String, heading: String = "Last 20 legs",
                headline: Headline? = nil,
                figures: [StatItem], clubs: [Club], picture: Image? = nil,
                pictureNote: String? = nil, onEditPicture: (() -> Void)? = nil,
                onBack: @escaping () -> Void = {}, onRemove: (() -> Void)? = nil) {
        self.name = name
        self.meta = meta
        self.heading = heading
        self.headline = headline
        self.figures = figures
        self.clubs = clubs
        self.picture = picture
        self.pictureNote = pictureNote
        self.onEditPicture = onEditPicture
        self.onBack = onBack
        self.onRemove = onRemove
    }

    /// How big the mark is on a profile.
    ///
    /// **96 and not 52.** `PlayerIdentity(.large)` draws a 52 pt mark, which is right in a roster
    /// row and wrong as the subject of a page: a profile picture at list size reads as a list that
    /// happens to have one row. `PersonMark` already takes any size — it was extracted for exactly
    /// this — so nothing is drawn twice to get it.
    public static let markSize: CGFloat = 96

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            PageBar(onBack: onBack)
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    header
                    if let headline { headlineFigure(headline) }
                    Eyebrow(heading).padding(.top, ThroSpacing.spaceSectionGap)
                    // **`StatGrid`, not a grid of its own.** The old page took each figure apart
                    // into a value, a label and an optional reason and drew all three the same
                    // whatever the basis was — so a **bounded** figure on a profile, which the
                    // honesty layer marks as a range everywhere else, was drawn as though it were
                    // exact. That is not a layout preference; it is the one thing this app's
                    // statistics exist to communicate, lost in the mapping between two types.
                    StatGrid(figures).padding(.top, ThroSpacing.spacing3)
                    Note("Every figure here comes from matches scored on this phone and confirmed by nobody. A dash means the figure cannot be computed honestly yet, and says why.")
                        .padding(.top, ThroSpacing.spacing4)

                    if !clubs.isEmpty {
                        Eyebrow("Teams and leagues").padding(.top, ThroSpacing.spaceSectionGap)
                        ThroDivider().padding(.top, ThroSpacing.spacing2)
                        ForEach(clubs) { c in
                            OrganisationRow(initials: c.initials, name: c.name,
                                            meta: "\(c.kind.label) · \(c.yourRole?.label ?? "Member")",
                                            accent: c.accentHex.flatMap { Color.thro(hex: $0) })
                            ThroDivider()
                        }
                    }
                    if let onRemove {
                        ThroButton("Remove from this phone", variant: .destructive, size: .medium, action: onRemove)
                            .padding(.top, ThroSpacing.spaceSectionGap)
                    }
                }
                .padding(.horizontal, ThroSpacing.spaceScreenGutter)
                .padding(.bottom, ThroSpacing.spacing6)
            }
        }
        // The screen arrives (PD-027): one beat, on the design's own curve,
        // withdrawn entirely under Reduce Motion.
        .throEntrance(0)
        .background(ThroColor.colorBackgroundPrimary.ignoresSafeArea())
    }

    /// The picture, the name and what kind of page this is — the three things a profile is.
    ///
    /// Laid out as a column and not a row: a 96 pt mark beside a name leaves the name about 200
    /// points on a 4.7-inch phone, which truncates anybody with two names. The mark leads, the name
    /// follows at `heading1`, and the meta and the two tags sit under it.
    @ViewBuilder private var header: some View {
        VStack(alignment: .leading, spacing: ThroSpacing.spacing3) {
            PersonMark(initials: ProfileScreen.initials(of: name),
                       size: ProfileScreen.markSize, picture: picture)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: ThroSpacing.spacing2) {
                Text(name)
                    .thro(ThroTypography.heading1.weight(.bold).tracking(em: -0.01))
                    .foregroundStyle(ThroColor.colorTextPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(meta)
                    .thro(ThroTypography.metadata)
                    .foregroundStyle(ThroColor.colorTextSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 6) { Tag("Not rated"); Tag("Self-reported") }
                if let onEditPicture {
                    ThroTextButton(picture == nil ? "Add a picture" : "Change picture",
                                   action: onEditPicture)
                } else if let pictureNote {
                    Text(pictureNote)
                        .thro(ThroTypography.metadata)
                        .foregroundStyle(ThroColor.colorTextTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .accessibilityElement(children: .contain)
    }

    /// The headline figure. Big, in the sport family, with its window under it.
    @ViewBuilder private func headlineFigure(_ item: Headline) -> some View {
        VStack(alignment: .leading, spacing: ThroSpacing.spacing2) {
            Eyebrow(item.label)
            HStack(alignment: .firstTextBaseline, spacing: ThroSpacing.spacing3) {
                // `ratingHero` is a **size**, and this is the first thing in the app to use it.
                // The role exists because a hero figure about a player was always intended; PD-018
                // decided what that figure honestly is, and it is not a rating. What PD-018 forbids
                // is the word, and the word here is "Recent form" over a note ending "Not a rating."
                // OD-001 stays open and nothing about it moves: no rating VALUE exists anywhere in
                // this build, which is registered absence claim #2 and is the claim that matters.
                Text(item.value)
                    .thro(ThroTypography.ratingHero.family(.sport).weight(.bold))
                    .foregroundStyle(StatGrid.valueColour(item.confidence))
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                if item.confidence == .range { Tag("Range", tone: .neutral, shape: .basis) }
            }
            if let note = item.note {
                Text(note)
                    .thro(item.confidence == .unavailable ? ThroTypography.body
                                                          : ThroTypography.metadata)
                    .foregroundStyle(StatGrid.noteColour(item.confidence))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.top, ThroSpacing.spaceSectionGap)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(item.label)
        .accessibilityValue(StatGrid.spokenValue(item))
        .accessibilityHint(item.note ?? "")
    }

    /// The initials a name is drawn as when there is no picture. The same rule `LocalPerson` and
    /// `ClubMember` use, restated here because this screen is handed a name and not a record — and
    /// stated once rather than in each of the two call sites.
    static func initials(of name: String) -> String {
        let letters = name.split(separator: " ").prefix(2).compactMap { $0.first }
        return letters.isEmpty ? "?" : letters.map(String.init).joined().uppercased()
    }
}
