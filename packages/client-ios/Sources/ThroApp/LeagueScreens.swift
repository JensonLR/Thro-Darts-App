import SwiftUI
import ThroDesign
import ThroTokens

// A league and a tournament are not a club with a different word on them (PD-019, PD-020, PD-021).
//
// The founder, on the three pages this app had: *"screen view for club league & tournament are all
// the same, this seems wrong, lazy & ugly, really think about what should be visible for each admin
// style."* They were right about the screens and right about the cause — one screen was drawn and
// the word at the top was changed, because nobody had decided what the other two **are**.
//
// The decisions came first and these screens follow from them:
//
//  - **A league is made of teams** (PD-019). Its roster is a list of teams, its fixtures are team v
//    team, its table's rows are teams. Its people are its officials — the ones who run it — which is
//    a different list from its competitors and is shown as one.
//  - **A result comes from two places and always says which** (PD-020). A match scored in THRØ, or
//    an official's word. Both count. They are never drawn the same way.
//  - **A tournament has a shape, chosen once** (PD-021), and the shape decides what the page says.
//
// What is different about each admin's page, stated so it can be argued with:
//
//  | | A club admin sees | A league admin sees | A tournament admin sees |
//  |---|---|---|---|
//  | leads with | the next fixture | **results waiting to be entered** | the shape and the field |
//  | its roster is | people | teams, and officials separately | entrants |
//  | its middle is | the roster | **the table** | what the shape means for this field |
//  | it never shows | a table | a lone "members" list | a table, unless it is a round robin |

// MARK: - shared rows

/// A league fixture: the two teams, when, and what happened if anybody has said.
///
/// **The result and its source are one thing on this row.** A score without its provenance is
/// exactly what PD-020 forbids, so they are drawn together and there is no way to render one
/// without the other.
struct TeamFixtureRow: View {
    let fixture: Fixture
    let home: String
    let away: String
    /// Offered only to somebody who may record one, and only where there is one to record.
    var onRecord: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: ThroSpacing.spacing2) {
            HStack(alignment: .firstTextBaseline, spacing: ThroSpacing.spacing2) {
                Text("\(home) v \(away)")
                    .thro(ThroTypography.label.weight(.bold))
                    .foregroundStyle(ThroColor.colorTextPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: ThroSpacing.spacing2)
                if let result = fixture.result {
                    Text("\(result.home)–\(result.away)")
                        .thro(ThroTypography.heading3.family(.sport).weight(.bold))
                        .foregroundStyle(ThroColor.colorTextPrimary)
                } else {
                    Tag(fixture.state.label, tone: fixture.state == .postponed ? .warning
                        : fixture.state == .cancelled ? .error : .neutral)
                }
            }
            Text("\(fixture.when) · \(fixture.venue)")
                .thro(ThroTypography.metadata)
                .foregroundStyle(ThroColor.colorTextSecondary)
            if let result = fixture.result {
                SourceTag(source: result.source)
            } else if fixture.awaitsResult {
                // The row that needs somebody. Said as a state, not as a red error: nothing is
                // wrong, a result has simply not been entered yet.
                HStack(spacing: ThroSpacing.spacing2) {
                    Tag("No result yet", tone: .warning)
                    if let onRecord {
                        ThroTextButton("Enter the result", action: onRecord)
                    }
                }
            }
        }
        .padding(.vertical, ThroSpacing.spacing3)
        .accessibilityElement(children: .combine)
    }
}

/// Where a result came from, as a tag (PD-020).
///
/// Two tones and they are not decorative: an evidenced result wears the verified tone the rest of
/// the app reserves for things with darts behind them, and somebody's word wears the neutral one.
/// A reader can tell them apart without reading either.
struct SourceTag: View {
    let source: ResultSource

    var body: some View {
        HStack(spacing: 6) {
            Icon(source.isEvidenced ? .circleCheck : .info, size: 13)
            Text(source.label).thro(ThroTypography.metadata)
        }
        .foregroundStyle(source.isEvidenced ? ThroColor.colorStatusVerified : ThroColor.colorTextSecondary)
        .accessibilityLabel(source.label)
    }
}

// MARK: - the table

/// A league table (PD-019, PD-020).
///
/// Every column here is arithmetic over results this device holds. Nothing is stored, so there is no
/// way for a standing to disagree with the fixtures under it — and the **E** column says how many of
/// a row's results came from a match scored in THRØ rather than from somebody typing, which is the
/// whole of PD-020 put on the screen in one number.
struct LeagueTableView: View {
    let rows: [TableRow]
    let pointsForWin: Int
    let pointsForDraw: Int
    /// What the numbers in this table are counted in (PD-022). Nil for a league made before it was
    /// asked — and the table says so rather than labelling every figure with a word nobody chose.
    var unit: ResultUnit?

    /// `static`, so it is not a stored property: a private stored property would drag the
    /// synthesised memberwise initialiser private with it, and this view is built by two others.
    private static let columns: [(String, String)] = [("P", "played"), ("W", "won"), ("D", "drawn"),
                                                      ("L", "lost"), ("+/−", "difference"),
                                                      ("E", "results scored in THRØ"), ("Pts", "points")]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            ThroDivider()
            ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                line(index + 1, row)
                ThroDivider()
            }
            Note(counted + "**\(pointsForWin) point\(pointsForWin == 1 ? "" : "s") for a win, "
                 + "\(pointsForDraw) for a draw.** Sorted on points, then difference, then what a "
                 + "team scored. **E** counts the results in that row that came from a match scored "
                 + "in THRØ — the rest are an official's word, which counts here and can never move "
                 + "a rating.")
                .padding(.top, ThroSpacing.spacing3)
        }
    }

    /// The unit, said once above the arithmetic rather than repeated in every cell — a phone-width
    /// table has no room for the word beside seven numbers, and saying it once is still saying it.
    private var counted: String {
        guard let unit else {
            return "**This league has not said what its results are counted in**, so the figures "
                 + "below are numbers without a unit. An admin can set one until the first result "
                 + "goes in. "
        }
        return "Counted in **\(unit.rawValue)**. "
    }

    /// What a row scored and conceded, with the unit on it. Empty when the league has not said.
    private func spoken(_ row: TableRow) -> String {
        guard let unit else { return "" }
        return "\(unit.counted(row.scoreFor)) for and \(unit.counted(row.scoreAgainst)) against, "
    }

    private var header: some View {
        HStack(spacing: 0) {
            Text("#").thro(ThroTypography.metadata).frame(width: 22, alignment: .leading)
            Text("Team").thro(ThroTypography.metadata)
            Spacer(minLength: ThroSpacing.spacing2)
            ForEach(LeagueTableView.columns, id: \.0) { column in
                Text(column.0)
                    .thro(ThroTypography.metadata)
                    .frame(width: column.0 == "+/−" ? 34 : 26, alignment: .trailing)
                    .accessibilityLabel(unitised(column.1))
            }
        }
        .foregroundStyle(ThroColor.colorTextSecondary)
        .padding(.bottom, ThroSpacing.spacing2)
    }

    private func line(_ position: Int, _ row: TableRow) -> some View {
        HStack(spacing: 0) {
            Text("\(position)")
                .thro(ThroTypography.metadata.family(.sport))
                .foregroundStyle(ThroColor.colorTextSecondary)
                .frame(width: 22, alignment: .leading)
            Text(row.team.name)
                .thro(ThroTypography.label.weight(.semibold))
                .foregroundStyle(ThroColor.colorTextPrimary)
                .lineLimit(1)
            Spacer(minLength: ThroSpacing.spacing2)
            figure("\(row.played)")
            figure("\(row.won)")
            figure("\(row.drawn)")
            figure("\(row.lost)")
            figure(row.difference > 0 ? "+\(row.difference)" : "\(row.difference)", width: 34)
            // The one column that is about trust rather than about darts.
            Text("\(row.evidenced)")
                .thro(ThroTypography.metadata.family(.sport))
                .foregroundStyle(row.evidenced == 0 ? ThroColor.colorTextTertiary
                                 : ThroColor.colorStatusVerified)
                .frame(width: 26, alignment: .trailing)
            Text("\(row.points)")
                .thro(ThroTypography.label.family(.sport).weight(.bold))
                .foregroundStyle(ThroColor.colorTextPrimary)
                .frame(width: 26, alignment: .trailing)
        }
        .padding(.vertical, ThroSpacing.spacing3)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(position). \(row.team.name), played \(row.played), \(row.points) points, "
                            + spoken(row) + "\(row.evidenced) of \(row.played) scored in THRØ")
    }

    /// A column's spoken name with the unit in it, so a screen reader says "leg difference" rather
    /// than "difference" — which is where the unit has room to travel with the number.
    private func unitised(_ name: String) -> String {
        guard let unit, name == "difference" else { return name }
        return "\(unit.rawValue.dropLast()) difference"
    }

    private func figure(_ text: String, width: CGFloat = 26) -> some View {
        Text(text)
            .thro(ThroTypography.metadata.family(.sport))
            .foregroundStyle(ThroColor.colorTextSecondary)
            .frame(width: width, alignment: .trailing)
    }
}

// MARK: - a league's page

/// A league (PD-019, PD-020).
///
/// **What a league admin needs first is not the table — it is the results that are missing from it.**
/// A table with four fixtures unentered is a table that is quietly wrong, and the only person who
/// can fix it is the one looking at the page. So that is what the page leads with, and it appears
/// only for somebody who may act on it.
public struct LeagueScreen: View {
    private let league: Club
    private let badge: Image?
    private let onBack: () -> Void
    private let onTeams: () -> Void
    private let onFixtures: () -> Void
    private let onOfficials: () -> Void
    private let onAnnounce: () -> Void
    private let onEdit: (() -> Void)?
    /// Nil unless this viewer may say what happened (PD-020) — an official's, not only an admin's.
    private let onRecord: ((Fixture) -> Void)?

    public init(league: Club, badge: Image? = nil, onBack: @escaping () -> Void = {},
                onTeams: @escaping () -> Void = {}, onFixtures: @escaping () -> Void = {},
                onOfficials: @escaping () -> Void = {}, onAnnounce: @escaping () -> Void = {},
                onEdit: (() -> Void)? = nil, onRecord: ((Fixture) -> Void)? = nil) {
        self.league = league
        self.badge = badge
        self.onBack = onBack
        self.onTeams = onTeams
        self.onFixtures = onFixtures
        self.onOfficials = onOfficials
        self.onAnnounce = onAnnounce
        self.onEdit = onEdit
        self.onRecord = onRecord
    }

    private var accent: Color { league.accentHex.flatMap { Color.thro(hex: $0) } ?? ThroColor.throGreen }
    private func team(_ id: String?) -> String {
        league.teams.first { $0.id == id }?.name ?? "—"
    }

    /// Written as a function with a declared return type rather than `onRecord.map { … }` at the
    /// call site, for the reason `ClubsFlow` already gives: an optional closure built inline is
    /// exactly the shape Swift will not infer a type for inside a view builder.
    private func recordAction(_ fixture: Fixture) -> (() -> Void)? {
        guard let onRecord, fixture.awaitsResult else { return nil }
        return { onRecord(fixture) }
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            PageBar(onBack: onBack,
                    actions: ClubScreen.actions(edit: onEdit,
                                                announce: league.mayAnnounce ? onAnnounce : nil))
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    OrganisationHeader(initials: league.initials, name: league.name,
                                       kind: "League", meta: league.meta, accent: accent,
                                       verified: league.verified, image: badge)
                    waiting
                    table
                    fixtures
                    teams
                    officials
                    Note("This league is on this phone and nowhere else. Nobody else can see it, and "
                         + "nothing in it has been sent anywhere — so the table is this device's "
                         + "record of what it was told, not a published standing.")
                        .padding(.top, ThroSpacing.spaceSectionGap)
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

    /// The one thing a league admin has to do, above everything else on the page.
    @ViewBuilder private var waiting: some View {
        let outstanding = league.fixturesAwaitingResults
        if !outstanding.isEmpty, let onRecord {
            VStack(alignment: .leading, spacing: ThroSpacing.spacing2) {
                Text("\(outstanding.count) result\(outstanding.count == 1 ? "" : "s") to enter")
                    .thro(ThroTypography.label.weight(.bold))
                    .foregroundStyle(ThroColor.colorTextPrimary)
                Text("These were played and nobody has said what happened, so the table below is "
                     + "missing them.")
                    .thro(ThroTypography.metadata)
                    .foregroundStyle(ThroColor.colorTextSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                ForEach(Array(outstanding.prefix(3))) { f in
                    Button { onRecord(f) } label: {
                        HStack(spacing: ThroSpacing.spacing2) {
                            Text("\(team(f.homeTeamId)) v \(team(f.awayTeamId))")
                                .thro(ThroTypography.label.weight(.semibold))
                                .foregroundStyle(ThroColor.colorTextBrand)
                            Spacer(minLength: 0)
                            Icon(.chevronRight, size: 16).foregroundStyle(ThroColor.colorTextBrand)
                        }
                        .frame(minHeight: ThroSpacing.touchTargetMinimum)
                        .throRowTapTarget()
                    }
                    .buttonStyle(ThroPressStyle(radius: ThroSpacing.radiusCard,
                                                pressedFill: ThroColor.colorSurfaceSecondary,
                                                scales: false))
                }
            }
            .padding(ThroSpacing.spacing4)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(ThroColor.colorBackgroundRaised,
                        in: RoundedRectangle(cornerRadius: ThroSpacing.radiusCard))
            .overlay(RoundedRectangle(cornerRadius: ThroSpacing.radiusCard)
                .strokeBorder(ThroColor.colorBorderDefault, lineWidth: 1))
            .padding(.top, ThroSpacing.spacing5)
        }
    }

    @ViewBuilder private var table: some View {
        Eyebrow("Table").padding(.top, ThroSpacing.spaceSectionGap)
        if league.tableIsWorthShowing {
            LeagueTableView(rows: league.table, pointsForWin: league.pointsForWin,
                            pointsForDraw: league.pointsForDraw, unit: league.unit)
                .padding(.top, ThroSpacing.spacing2)
        } else {
            // Not an empty table. A grid of zeroes reads as a season nobody has won a game in.
            Text(league.teams.count < 2
                 ? "A table needs at least two teams. There \(league.teams.count == 1 ? "is one" : "are none") so far."
                 : "No results yet. The table appears when the first fixture has one.")
                .thro(ThroTypography.body)
                .foregroundStyle(ThroColor.colorTextSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.vertical, ThroSpacing.spacing3)
        }
    }

    @ViewBuilder private var fixtures: some View {
        HStack(alignment: .firstTextBaseline) {
            Eyebrow("Fixtures")
            Spacer()
            ThroTextButton("See all", alignment: .trailing, action: onFixtures)
        }
        .padding(.top, ThroSpacing.spaceSectionGap)
        ThroDivider().padding(.top, ThroSpacing.spacing2)
        ForEach(Array(league.fixtures.prefix(4))) { f in
            TeamFixtureRow(fixture: f, home: team(f.homeTeamId), away: team(f.awayTeamId),
                           onRecord: recordAction(f))
            ThroDivider()
        }
        if league.fixtures.isEmpty {
            Text(league.mayManageFixtures
                 ? "No fixtures yet. Add the teams first, then the fixtures between them."
                 : "No fixtures yet.")
                .thro(ThroTypography.body)
                .foregroundStyle(ThroColor.colorTextSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.vertical, ThroSpacing.spacing3)
        }
    }

    @ViewBuilder private var teams: some View {
        HStack(alignment: .firstTextBaseline) {
            Eyebrow("Teams")
            Spacer()
            ThroTextButton(league.mayManageTeams ? "Manage" : "See all",
                           alignment: .trailing, action: onTeams)
        }
        .padding(.top, ThroSpacing.spaceSectionGap)
        ThroDivider().padding(.top, ThroSpacing.spacing2)
        ForEach(Array(league.teams.prefix(5))) { t in
            HStack(spacing: ThroSpacing.spacing3) {
                Badge(t.initials, size: 36, accent: accent)
                Text(t.name)
                    .thro(ThroTypography.label.weight(.semibold))
                    .foregroundStyle(ThroColor.colorTextPrimary)
                Spacer(minLength: 0)
            }
            .padding(.vertical, ThroSpacing.spacing2)
            ThroDivider()
        }
        if league.teams.isEmpty {
            Text(league.mayManageTeams ? "No teams yet. A league is its teams — add them here."
                                       : "No teams yet.")
                .thro(ThroTypography.body)
                .foregroundStyle(ThroColor.colorTextSecondary)
                .padding(.vertical, ThroSpacing.spacing3)
        }
    }

    /// **The list a club calls "members", and a league does not.** The people in a league are the
    /// ones who run it; the ones who play in it are in the teams. Two different lists, and showing
    /// one under the other's name is what made these three pages the same page.
    @ViewBuilder private var officials: some View {
        HStack(alignment: .firstTextBaseline) {
            Eyebrow("Who runs it")
            Spacer()
            ThroTextButton("See all", alignment: .trailing, action: onOfficials)
        }
        .padding(.top, ThroSpacing.spaceSectionGap)
        ThroDivider().padding(.top, ThroSpacing.spacing2)
        ForEach(Array(league.visibleMembers.filter { $0.role != .member }.prefix(4))) { m in
            MemberRow(member: m)
            ThroDivider()
        }
        if league.visibleMembers.allSatisfy({ $0.role == .member }) {
            Text("You are the only person who runs this league on this phone.")
                .thro(ThroTypography.body)
                .foregroundStyle(ThroColor.colorTextSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.vertical, ThroSpacing.spacing3)
        }
    }
}

// MARK: - a tournament's page

/// A tournament (PD-021).
///
/// **The shape is the page.** A knockout, a round robin and a double elimination are three different
/// competitions, and the thing a tournament admin needs to see is what their shape means for the
/// field they actually have — how many matches that is, and how many byes, and who gets them.
///
/// A **knockout** draws itself here (PD-021): the seeded bracket, the byes at the top of the entry
/// order, and each round created as fixtures once its two sides are known. The other three shapes do
/// not, and the page says which and why rather than handing them a bracket they did not ask for — a
/// round robin is a table, and a groups tournament needs its group sizes and qualifying places set
/// before anything can be drawn at all.
public struct TournamentScreen: View {
    private let tournament: Club
    private let badge: Image?
    private let onBack: () -> Void
    private let onEntrants: () -> Void
    private let onFixtures: () -> Void
    private let onAnnounce: () -> Void
    private let onEdit: (() -> Void)?
    private let onRecord: ((Fixture) -> Void)?
    /// Nil unless this viewer may make the draw. An official's: it creates fixtures.
    private let onDraw: ((Int) -> Void)?
    /// The same, for a shape with more than one bracket.
    private let onDraw2: ((Bracket, Int) -> Void)?
    /// And for one group's round robin.
    private let onDrawGroup: ((Int) -> Void)?

    public init(tournament: Club, badge: Image? = nil, onBack: @escaping () -> Void = {},
                onEntrants: @escaping () -> Void = {}, onFixtures: @escaping () -> Void = {},
                onAnnounce: @escaping () -> Void = {}, onEdit: (() -> Void)? = nil,
                onRecord: ((Fixture) -> Void)? = nil, onDraw: ((Int) -> Void)? = nil,
                onDraw2: ((Bracket, Int) -> Void)? = nil,
                onDrawGroup: ((Int) -> Void)? = nil) {
        self.onDraw = onDraw
        self.onDraw2 = onDraw2
        self.onDrawGroup = onDrawGroup
        self.tournament = tournament
        self.badge = badge
        self.onBack = onBack
        self.onEntrants = onEntrants
        self.onFixtures = onFixtures
        self.onAnnounce = onAnnounce
        self.onEdit = onEdit
        self.onRecord = onRecord
    }

    private var accent: Color {
        tournament.accentHex.flatMap { Color.thro(hex: $0) } ?? ThroColor.throGreen
    }
    private var field: Int { tournament.teams.count }
    private func entrant(_ id: String?) -> String {
        tournament.teams.first { $0.id == id }?.name ?? "—"
    }
    private func recordAction(_ fixture: Fixture) -> (() -> Void)? {
        guard let onRecord, fixture.awaitsResult else { return nil }
        return { onRecord(fixture) }
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            PageBar(onBack: onBack,
                    actions: ClubScreen.actions(edit: onEdit,
                                                announce: tournament.mayAnnounce ? onAnnounce : nil))
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    OrganisationHeader(initials: tournament.initials, name: tournament.name,
                                       kind: tournament.shape?.label ?? "Tournament",
                                       meta: tournament.meta, accent: accent,
                                       verified: tournament.verified, image: badge)
                    shape
                    draw
                    doubleDraw
                    groupStage
                    entrants
                    fixtures
                    if tournament.shape == .roundRobin { table }
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

    /// The shape, what it means, and what it means **for this field** — which is the part a page
    /// that only named the shape would leave the admin to work out on paper.
    @ViewBuilder private var shape: some View {
        Eyebrow("The shape").padding(.top, ThroSpacing.spacing5)
        if let shape = tournament.shape {
            VStack(alignment: .leading, spacing: ThroSpacing.spacing3) {
                Text(shape.label)
                    .thro(ThroTypography.heading3.weight(.bold))
                    .foregroundStyle(ThroColor.colorTextPrimary)
                Text(shape.summary)
                    .thro(ThroTypography.body)
                    .foregroundStyle(ThroColor.colorTextSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                arithmetic(shape)
            }
            .padding(.top, ThroSpacing.spacing2)
        } else {
            // Only reachable for a tournament written before shapes existed. It says so rather than
            // picking one, because a shape decides what every round means.
            Note("This tournament was made before THRØ asked for a shape, so it has none. A shape is "
                 + "chosen when a tournament is made and never after — one that changed would rewrite "
                 + "what the matches already played were for.", icon: .triangleAlert)
                .padding(.top, ThroSpacing.spacing2)
        }
    }

    /// The numbers this shape produces for the field there is. Arithmetic, not an estimate, and
    /// where a number cannot be known yet it says so instead of guessing.
    @ViewBuilder private func arithmetic(_ shape: TournamentShape) -> some View {
        VStack(alignment: .leading, spacing: ThroSpacing.spacing2) {
            if field < 2 {
                Text("Not enough entrants yet — a tournament needs two.")
                    .thro(ThroTypography.metadata)
                    .foregroundStyle(ThroColor.colorTextSecondary)
            } else {
                if let matches = shape.matches(forEntrants: field) {
                    figure("\(matches)", "match\(matches == 1 ? "" : "es") to play",
                           note: shape == .doubleElimination
                               ? "or one more, if the losers' side wins the first final"
                               : nil)
                } else {
                    figure("—", "matches to play",
                           note: "a groups tournament's match count follows from its group sizes, "
                               + "which are set before it starts")
                }
                if shape == .knockout || shape == .groups {
                    let byes = TournamentShape.byes(forEntrants: field)
                    figure("\(byes)", byes == 1 ? "bye in the first round" : "byes in the first round",
                           note: byes == 0
                               ? "\(field) is a power of two, so everybody plays in round one"
                               : "a bye advances an entrant and is not a win — it appears in no record "
                                 + "of results. THRØ has no rating (OD-001), so byes go to whoever was "
                                 + "entered first rather than to a seeding nothing has computed.")
                }
            }
        }
        .padding(.top, ThroSpacing.spacing2)
    }

    private func figure(_ value: String, _ label: String, note: String?) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline, spacing: ThroSpacing.spacing2) {
                Text(value)
                    .thro(ThroTypography.heading2.family(.sport).weight(.semibold))
                    .foregroundStyle(ThroColor.colorTextPrimary)
                Text(label)
                    .thro(ThroTypography.body)
                    .foregroundStyle(ThroColor.colorTextSecondary)
            }
            if let note {
                Text(note)
                    .thro(ThroTypography.metadata)
                    .foregroundStyle(ThroColor.colorTextTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: - groups (PD-021)

    /// The group stage, and the knockout the qualifiers feed.
    @ViewBuilder private var groupStage: some View {
        if tournament.groupsNeedSetup {
            Eyebrow("The groups").padding(.top, ThroSpacing.spaceSectionGap)
            Note("**This tournament has not been told how it is shaped.** How many groups, and how "
                 + "many go through from each, decide what every match in it is for — so THRØ asks "
                 + "rather than guessing. Set them on Edit, before the first result goes in.",
                 icon: .triangleAlert)
                .padding(.top, ThroSpacing.spacing3)
        } else if let groups = tournament.groups {
            Eyebrow("The groups").padding(.top, ThroSpacing.spaceSectionGap)
            Text("\(groups.groups.count) group\(groups.groups.count == 1 ? "" : "s"), top "
                 + "\(groups.qualifiersPerGroup) through from each")
                .thro(ThroTypography.body)
                .foregroundStyle(ThroColor.colorTextSecondary)
                .padding(.top, ThroSpacing.spacing2)
            ForEach(groups.groups) { group in
                groupBlock(group, of: groups)
            }
            groupKnockout(groups)
            Note("Entrants are dealt into groups **snake-wise** over the order they were entered — "
                 + "first seed to A, second to B, and back down again — so group A does not get both "
                 + "the first and the third of them. THRØ has no rating (OD-001), so that order is "
                 + "the order they went in.")
                .padding(.top, ThroSpacing.spacing4)
        }
    }

    @ViewBuilder private func groupBlock(_ group: Groups.Group, of groups: Groups) -> some View {
        roundHeader("Group \(group.name)", ready: groups.readyToDraw(group: group.number).count) {
            onDrawGroup?(group.number)
        }
        if group.entrants.count < 2 {
            Text("Only \(group.entrants.count) entrant\(group.entrants.count == 1 ? "" : "s") in "
                 + "this group — there is nothing to play.")
                .thro(ThroTypography.metadata)
                .foregroundStyle(ThroColor.colorTextSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.vertical, ThroSpacing.spacing3)
        } else {
            LeagueTableView(rows: group.table, pointsForWin: tournament.pointsForWin,
                            pointsForDraw: tournament.pointsForDraw, unit: tournament.unit)
                .padding(.top, ThroSpacing.spacing2)
            ForEach(group.matches) { match in
                drawRow(match)
                ThroDivider()
            }
        }
    }

    /// The knockout after the groups — which waits, on purpose.
    @ViewBuilder private func groupKnockout(_ groups: Groups) -> some View {
        Text("The knockout")
            .thro(ThroTypography.heading3.weight(.bold))
            .foregroundStyle(ThroColor.colorTextPrimary)
            .padding(.top, ThroSpacing.spacing5)
        ForEach(groups.clashes, id: \.self) { clash in
            Note(clash, icon: .triangleAlert, tone: ThroColor.colorStatusError)
                .padding(.top, ThroSpacing.spacing3)
        }
        if let knockout = groups.knockout {
            if let champion = knockout.champion {
                Text("\(champion.name) wins it.")
                    .thro(ThroTypography.heading3.weight(.bold))
                    .foregroundStyle(ThroColor.colorTextPrimary)
                    .padding(.top, ThroSpacing.spacing3)
            }
            ForEach(Array(knockout.rounds.enumerated()), id: \.offset) { index, matches in
                roundHeader(TournamentScreen.roundName(index + 1, of: knockout.rounds.count),
                            ready: knockout.readyToDraw(round: index + 1).count) {
                    onDraw2?(.winners, index + 1)
                }
                ForEach(matches) { match in
                    drawRow(match)
                    ThroDivider()
                }
            }
        } else {
            // Deliberate. A bracket built from half-played tables shows people through who are not.
            Text("The knockout is drawn when every group has finished. A bracket built from a "
                 + "half-played table would show people through who are not.")
                .thro(ThroTypography.body)
                .foregroundStyle(ThroColor.colorTextSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.vertical, ThroSpacing.spacing3)
        }
    }

    @ViewBuilder private var entrants: some View {
        HStack(alignment: .firstTextBaseline) {
            Eyebrow("Entrants")
            Spacer()
            ThroTextButton(tournament.mayManageTeams ? "Manage" : "See all",
                           alignment: .trailing, action: onEntrants)
        }
        .padding(.top, ThroSpacing.spaceSectionGap)
        ThroDivider().padding(.top, ThroSpacing.spacing2)
        // Numbered, because in a knockout the order they were entered is the seeding, and a page
        // that hides that would be hiding which of them gets a bye.
        ForEach(Array(tournament.teams.prefix(8).enumerated()), id: \.element.id) { index, t in
            HStack(spacing: ThroSpacing.spacing3) {
                Text("\(index + 1)")
                    .thro(ThroTypography.metadata.family(.sport))
                    .foregroundStyle(ThroColor.colorTextSecondary)
                    .frame(width: 22, alignment: .leading)
                Text(t.name)
                    .thro(ThroTypography.label.weight(.semibold))
                    .foregroundStyle(ThroColor.colorTextPrimary)
                Spacer(minLength: 0)
            }
            .padding(.vertical, ThroSpacing.spacing2)
            ThroDivider()
        }
        if tournament.teams.isEmpty {
            Text(tournament.mayManageTeams
                 ? "Nobody entered yet. Add them here — the order they go in is the order the byes "
                   + "are given out."
                 : "Nobody entered yet.")
                .thro(ThroTypography.body)
                .foregroundStyle(ThroColor.colorTextSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.vertical, ThroSpacing.spacing3)
        }
    }

    @ViewBuilder private var fixtures: some View {
        HStack(alignment: .firstTextBaseline) {
            Eyebrow("Matches")
            Spacer()
            ThroTextButton("See all", alignment: .trailing, action: onFixtures)
        }
        .padding(.top, ThroSpacing.spaceSectionGap)
        ThroDivider().padding(.top, ThroSpacing.spacing2)
        ForEach(Array(tournament.fixtures.prefix(4))) { f in
            TeamFixtureRow(fixture: f, home: entrant(f.homeTeamId), away: entrant(f.awayTeamId),
                           onRecord: recordAction(f))
            ThroDivider()
        }
        if tournament.fixtures.isEmpty {
            Text("No matches yet.")
                .thro(ThroTypography.body)
                .foregroundStyle(ThroColor.colorTextSecondary)
                .padding(.vertical, ThroSpacing.spacing3)
        }
    }

    // MARK: - the draw (PD-021)

    /// The bracket, round by round.
    ///
    /// **A list per round, not a tree.** A bracket drawn as a tree on a phone is either unreadable or
    /// scrolls in two directions, and what somebody running a tournament needs is *which matches am
    /// I playing next* — which is a list.
    @ViewBuilder private var draw: some View {
        if let draw = tournament.draw {
            Eyebrow("The draw").padding(.top, ThroSpacing.spaceSectionGap)
            // A knockout match cannot end level, and the result screen will take a draw because a
            // league fixture may legitimately be one. So the tournament says so rather than
            // producing a round nobody advances from.
            ForEach(draw.problems, id: \.self) { problem in
                Note(problem, icon: .triangleAlert, tone: ThroColor.colorStatusError)
                    .padding(.top, ThroSpacing.spacing3)
            }
            if let champion = draw.champion {
                Text("\(champion.name) wins it.")
                    .thro(ThroTypography.heading3.weight(.bold))
                    .foregroundStyle(ThroColor.colorTextPrimary)
                    .padding(.top, ThroSpacing.spacing3)
            }
            ForEach(Array(draw.rounds.enumerated()), id: \.offset) { index, matches in
                round(index + 1, matches, of: draw)
            }
            Note("Seeded in the order they were entered, because THRØ has no rating (OD-001) and "
                 + "will not pretend a ranking put anybody anywhere. **A bye is not a win** — it "
                 + "advances an entrant and appears in no record of results.")
                .padding(.top, ThroSpacing.spacing4)
        } else if tournament.shape == .knockout {
            Eyebrow("The draw").padding(.top, ThroSpacing.spaceSectionGap)
            Text("A draw needs at least two entrants.")
                .thro(ThroTypography.body)
                .foregroundStyle(ThroColor.colorTextSecondary)
                .padding(.vertical, ThroSpacing.spacing3)
        }
    }

    @ViewBuilder private func round(_ number: Int, _ matches: [DrawMatch], of draw: Draw) -> some View {
        roundHeader(TournamentScreen.roundName(number, of: draw.rounds.count),
                    ready: draw.readyToDraw(round: number).count) { onDraw?(number) }
        ForEach(matches) { match in
            drawRow(match)
            ThroDivider()
        }
    }

    /// One round's heading, with the control that turns it into fixtures when it is ready.
    @ViewBuilder private func roundHeader(_ title: String, ready: Int,
                                          draw: @escaping () -> Void) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .thro(ThroTypography.labelStrong.weight(.semibold))
                .foregroundStyle(ThroColor.colorTextSecondary)
            Spacer()
            if onDraw != nil, ready > 0 {
                ThroTextButton("Draw \(ready)", alignment: .trailing, action: draw)
            }
        }
        .padding(.top, ThroSpacing.spacing4)
        ThroDivider().padding(.top, ThroSpacing.spacing1)
    }

    /// The double-elimination draw: two sides and a final that may be played twice (PD-021).
    @ViewBuilder private var doubleDraw: some View {
        if let double = tournament.doubleElimination {
            Eyebrow("The draw").padding(.top, ThroSpacing.spaceSectionGap)
            ForEach(double.problems, id: \.self) { problem in
                Note(problem, icon: .triangleAlert, tone: ThroColor.colorStatusError)
                    .padding(.top, ThroSpacing.spacing3)
            }
            if let champion = double.champion {
                Text("\(champion.name) wins it.")
                    .thro(ThroTypography.heading3.weight(.bold))
                    .foregroundStyle(ThroColor.colorTextPrimary)
                    .padding(.top, ThroSpacing.spacing3)
            }
            side("Winners", double.winners, bracket: .winners, of: double)
            if !double.losers.isEmpty {
                side("Losers", double.losers, bracket: .losers, of: double)
            }
            finals(double)
            Note("Lose once and you drop to the losers' side; lose twice and you are out. The "
                 + "losers' side arrives at the final with a loss already, so **they have to win it "
                 + "twice** — which is what the second final is for. Seeded in the order they were "
                 + "entered (OD-001), and **a bye is not a win**: it drops nobody.")
                .padding(.top, ThroSpacing.spacing4)
        } else if tournament.shape == .doubleElimination {
            Eyebrow("The draw").padding(.top, ThroSpacing.spaceSectionGap)
            Text("A draw needs at least two entrants.")
                .thro(ThroTypography.body)
                .foregroundStyle(ThroColor.colorTextSecondary)
                .padding(.vertical, ThroSpacing.spacing3)
        }
    }

    @ViewBuilder private func side(_ name: String, _ rounds: [[DrawMatch]], bracket: Bracket,
                                   of double: DoubleElimination) -> some View {
        Text(name)
            .thro(ThroTypography.heading3.weight(.bold))
            .foregroundStyle(ThroColor.colorTextPrimary)
            .padding(.top, ThroSpacing.spacing5)
        ForEach(Array(rounds.enumerated()), id: \.offset) { index, matches in
            roundHeader(bracket == .winners
                        ? TournamentScreen.roundName(index + 1, of: rounds.count + 1)
                        : "Losers' round \(index + 1)",
                        ready: double.readyToDraw(bracket: bracket, round: index + 1).count) {
                onDraw2?(bracket, index + 1)
            }
            ForEach(matches) { match in
                drawRow(match)
                ThroDivider()
            }
        }
    }

    @ViewBuilder private func finals(_ double: DoubleElimination) -> some View {
        Text("The final")
            .thro(ThroTypography.heading3.weight(.bold))
            .foregroundStyle(ThroColor.colorTextPrimary)
            .padding(.top, ThroSpacing.spacing5)
        roundHeader("Grand final", ready: double.readyToDraw(bracket: .final, round: 1).count) {
            onDraw2?(.final, 1)
        }
        if let grandFinal = double.grandFinal {
            drawRow(grandFinal)
            ThroDivider()
        }
        if let reset = double.reset {
            roundHeader("Second final", ready: double.readyToDraw(bracket: .final, round: 2).count) {
                onDraw2?(.final, 2)
            }
            drawRow(reset)
            ThroDivider()
        }
    }

    private func drawRow(_ match: DrawMatch) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline, spacing: ThroSpacing.spacing2) {
                Text("\(name(match.home)) v \(name(match.away))")
                    .thro(ThroTypography.label.weight(match.isWalkover ? .medium : .semibold))
                    .foregroundStyle(match.isWalkover ? ThroColor.colorTextSecondary
                                     : ThroColor.colorTextPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: ThroSpacing.spacing2)
                if let result = match.fixture?.result {
                    Text("\(result.home)–\(result.away)")
                        .thro(ThroTypography.label.family(.sport).weight(.bold))
                        .foregroundStyle(ThroColor.colorTextPrimary)
                } else if match.isWalkover {
                    Tag("Bye", tone: .neutral)
                } else if match.fixture != nil {
                    Tag("To play", tone: .neutral)
                }
            }
            if let winner = match.winner {
                Text(match.isWalkover ? "\(winner.name) goes through without playing"
                                      : "\(winner.name) goes through")
                    .thro(ThroTypography.metadata)
                    .foregroundStyle(ThroColor.colorTextSecondary)
            } else if match.fixture == nil, match.playable != nil {
                Text("Not drawn yet")
                    .thro(ThroTypography.metadata)
                    .foregroundStyle(ThroColor.colorTextTertiary)
            }
        }
        .padding(.vertical, ThroSpacing.spacing2)
        .accessibilityElement(children: .combine)
    }

    private func name(_ side: Side) -> String {
        switch side {
        case let .entrant(team): return team.name
        case .bye: return "bye"
        case let .winnerOf(round, slot): return "winner of round \(round) match \(slot)"
        case let .loserOf(round, slot): return "loser of round \(round) match \(slot)"
        }
    }

    /// What a round is called. The last one is the final, and the two before it have names people
    /// actually use — a page that said "round 3 of 3" to somebody watching a final would be right
    /// and useless.
    static func roundName(_ number: Int, of total: Int) -> String {
        switch total - number {
        case 0: return "Final"
        case 1: return "Semi-finals"
        case 2: return "Quarter-finals"
        default: return "Round \(number)"
        }
    }

    /// A round robin is the one shape whose standings are a table, so it is the one shape that gets
    /// one. A knockout does not have a table and drawing it one would be drawing a league.
    @ViewBuilder private var table: some View {
        Eyebrow("Standings").padding(.top, ThroSpacing.spaceSectionGap)
        if tournament.teams.count >= 2, tournament.fixtures.contains(where: { $0.result != nil }) {
            LeagueTableView(rows: tournament.standings, pointsForWin: tournament.pointsForWin,
                            pointsForDraw: tournament.pointsForDraw, unit: tournament.unit)
                .padding(.top, ThroSpacing.spacing2)
        } else {
            Text("Standings appear when the first match has a result.")
                .thro(ThroTypography.body)
                .foregroundStyle(ThroColor.colorTextSecondary)
                .padding(.vertical, ThroSpacing.spacing3)
        }
    }
}

// MARK: - keeping the teams

/// A league's teams, or a tournament's entrants (PD-019, PD-021). The same list under the word the
/// thing is actually called.
public struct TeamsScreen: View {
    private let club: Club
    private let onBack: () -> Void
    private let onAdd: (() -> Void)?
    /// Removing a team takes its fixtures with it, so the screen asks first and says the number.
    private let onRemove: ((Team) -> Void)?
    private let fixturesLost: (Team) -> Int

    @State private var removing: Team?

    public init(club: Club, onBack: @escaping () -> Void = {}, onAdd: (() -> Void)? = nil,
                onRemove: ((Team) -> Void)? = nil, fixturesLost: @escaping (Team) -> Int = { _ in 0 }) {
        self.club = club
        self.onBack = onBack
        self.onAdd = onAdd
        self.onRemove = onRemove
        self.fixturesLost = fixturesLost
    }

    private var accent: Color { club.accentHex.flatMap { Color.thro(hex: $0) } ?? ThroColor.throGreen }

    /// Not `.constant(removing != nil)`: a constant binding cannot be set back, so the alert would
    /// have no way to close itself when the platform dismisses it rather than a button doing it.
    private var confirming: Binding<Bool> {
        Binding(get: { removing != nil }, set: { if !$0 { removing = nil } })
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            TopBar(club.competitorNoun.many, eyebrow: club.name, onBack: onBack,
                   actions: onAdd.map {
                       [TopBar.Action(icon: .plus, label: "Add a \(club.competitorNoun.one)", action: $0)]
                   } ?? [])
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ThroDivider().padding(.top, ThroSpacing.spacing4)
                    ForEach(Array(club.teams.enumerated()), id: \.element.id) { index, team in
                        row(index, team)
                        ThroDivider()
                    }
                    if club.teams.isEmpty { empty }
                    if club.kind == .tournament {
                        Note("The order here is the order they were entered, and in a knockout that "
                             + "is the seeding — the byes go to the top of this list. THRØ has no "
                             + "rating (OD-001), so it has nothing else to seed on and does not "
                             + "pretend otherwise.")
                            .padding(.top, ThroSpacing.spacing5)
                    } else {
                        Note("A league's competitors are its **teams**. The people who play for them "
                             + "belong to the teams; the people on the members list are the ones who "
                             + "run the league.")
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
        // Removing a team is not undoable and takes fixtures with it, so it is confirmed with the
        // number in the question rather than with a bare "are you sure".
        .alert("Remove \(removing?.name ?? "")?", isPresented: confirming) {
            Button("Cancel", role: .cancel) { removing = nil }
            Button("Remove", role: .destructive) {
                if let team = removing { onRemove?(team) }
                removing = nil
            }
        } message: {
            let lost = removing.map(fixturesLost) ?? 0
            Text(lost == 0
                 ? "They are in no fixtures, so nothing else goes with them."
                 : "This also removes \(lost) fixture\(lost == 1 ? "" : "s") they are in, and any "
                   + "result recorded against \(lost == 1 ? "it" : "them"). The table will change.")
        }
    }

    private func row(_ index: Int, _ team: Team) -> some View {
        HStack(spacing: ThroSpacing.spacing3) {
            if club.kind == .tournament {
                Text("\(index + 1)")
                    .thro(ThroTypography.metadata.family(.sport))
                    .foregroundStyle(ThroColor.colorTextSecondary)
                    .frame(width: 22, alignment: .leading)
            } else {
                Badge(team.initials, size: 36, accent: accent)
            }
            Text(team.name)
                .thro(ThroTypography.label.weight(.semibold))
                .foregroundStyle(ThroColor.colorTextPrimary)
            Spacer(minLength: ThroSpacing.spacing2)
            if onRemove != nil {
                Button { removing = team } label: {
                    Icon(.x, size: 18)
                        .foregroundStyle(ThroColor.colorTextSecondary)
                        .throTapTarget()
                }
                .buttonStyle(ThroPressStyle(radius: ThroSpacing.radiusStatus))
                .accessibilityLabel("Remove \(team.name)")
            }
        }
        .padding(.vertical, ThroSpacing.spacing2)
    }

    @ViewBuilder private var empty: some View {
        if let onAdd {
            EmptyState(title: club.kind == .tournament ? "Nobody entered yet" : "No teams yet",
                       message: club.kind == .tournament
                           ? "Add everybody who is playing. The order they go in is the order the byes are given out."
                           : "A league is its teams. Add them, then the fixtures between them.",
                       actionLabel: "Add a \(club.competitorNoun.one)", onAction: onAdd)
                .padding(.top, ThroSpacing.spacing6)
        } else {
            EmptyState(title: club.kind == .tournament ? "Nobody entered yet" : "No teams yet",
                       message: "An admin keeps this list.")
                .padding(.top, ThroSpacing.spacing6)
        }
    }
}

/// Adding one team, or one entrant.
public struct NewTeamScreen: View {
    private let club: Club
    @State private var name = ""
    private let onBack: () -> Void
    private let onAdd: (String) -> Void

    public init(club: Club, onBack: @escaping () -> Void = {},
                onAdd: @escaping (String) -> Void = { _ in }) {
        self.club = club
        self.onBack = onBack
        self.onAdd = onAdd
    }

    private var trimmed: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var taken: Bool {
        club.teams.contains { $0.name.localizedCaseInsensitiveCompare(trimmed) == .orderedSame }
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            TopBar("Add a \(club.competitorNoun.one)", eyebrow: club.name, onBack: onBack)
            ScrollView {
                VStack(alignment: .leading, spacing: ThroSpacing.spacing5) {
                    ThroTextField(club.kind == .tournament ? "Entrant" : "Team", text: $name,
                                  placeholder: club.kind == .tournament ? "Sam Rowe" : "The Feathers A",
                                  error: taken ? "There is already one called that." : nil)
                    if club.kind == .tournament {
                        Note("An entrant may be one player or a team of them — THRØ stores the name "
                             + "either way, because a tournament of pairs is still a tournament.")
                    } else {
                        Note("**The Feathers A** and **The Feathers B** are two teams, and the letter "
                             + "is the whole difference between them — so it is kept, in the name and "
                             + "on the badge.")
                    }
                }
                .padding(.horizontal, ThroSpacing.spaceScreenGutter)
                .padding(.vertical, ThroSpacing.spacing5)
            }
            ThroButton("Add", variant: .primary, size: .large, fullWidth: true,
                       disabled: trimmed.isEmpty || taken) { onAdd(trimmed) }
                .padding(.horizontal, ThroSpacing.spaceScreenGutter)
                .padding(.bottom, ThroSpacing.spacing6)
        }
        // The screen arrives (PD-027): one beat, on the design's own curve,
        // withdrawn entirely under Reduce Motion.
        .throEntrance(0)
        .background(ThroColor.colorBackgroundPrimary.ignoresSafeArea())
    }
}

// MARK: - saying what happened (PD-020)

/// Recording a result, and being honest about what kind of thing it is.
///
/// **This screen is where PD-020 either holds or does not.** Two sources, and the difference between
/// them is not a detail: one carries every dart, the other carries somebody's word. So the screen
/// does not offer a score box and a quiet dropdown — it offers the two sources as two different
/// answers to the question *how do you know*, and it says what each one means before it is used.
///
/// Only one of them can be used from here today. Linking a scored match needs a match in this
/// device's journal played by these two teams, and nothing on this phone knows which team a match
/// belonged to (that is B4, an account and an identity). So the strong source is described and not
/// offered, rather than offered and quietly doing the weak thing.
public struct RecordResultScreen: View {
    private let club: Club
    private let fixture: Fixture
    private let home: String
    private let away: String
    @State private var homeScore = ""
    @State private var awayScore = ""
    @State private var official: String
    private let onBack: () -> Void
    private let onRecord: (Int, Int, String) -> Void
    private let onClear: (() -> Void)?

    public init(club: Club, fixture: Fixture, home: String, away: String, official: String = "",
                onBack: @escaping () -> Void = {},
                onRecord: @escaping (Int, Int, String) -> Void = { _, _, _ in },
                onClear: (() -> Void)? = nil) {
        self.club = club
        self.fixture = fixture
        self.home = home
        self.away = away
        _official = State(initialValue: official)
        _homeScore = State(initialValue: fixture.result.map { "\($0.home)" } ?? "")
        _awayScore = State(initialValue: fixture.result.map { "\($0.away)" } ?? "")
        self.onBack = onBack
        self.onRecord = onRecord
        self.onClear = onClear
    }

    private var scores: (home: Int, away: Int)? {
        guard let h = Int(homeScore.trimmingCharacters(in: .whitespaces)),
              let a = Int(awayScore.trimmingCharacters(in: .whitespaces)),
              h >= 0, a >= 0 else { return nil }
        return (h, a)
    }
    private var namedOfficial: String { official.trimmingCharacters(in: .whitespacesAndNewlines) }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            TopBar("Result", eyebrow: "\(home) v \(away)", onBack: onBack)
            ScrollView {
                VStack(alignment: .leading, spacing: ThroSpacing.spacing5) {
                    if let result = fixture.result { existing(result) }
                    boxes
                    ThroTextField("Recorded by", text: $official, placeholder: "Your name",
                                  helper: "This goes on the result, on every screen it appears on "
                                        + "in \(club.name).")
                    Note("**This is your word, and the app will say so.** It counts for the table, "
                         + "and it can never move a rating — a rating built on typed numbers is a "
                         + "rating built on nothing (OD-001).", icon: .shield)
                    ThroDivider()
                    unavailable
                    if let onClear, fixture.result != nil {
                        ThroButton("Remove this result", variant: .destructive, size: .medium,
                                   action: onClear)
                    }
                }
                .padding(.horizontal, ThroSpacing.spaceScreenGutter)
                .padding(.vertical, ThroSpacing.spacing5)
            }
            ThroButton(fixture.result == nil ? "Record the result" : "Change the result",
                       variant: .primary, size: .large, fullWidth: true,
                       disabled: scores == nil || namedOfficial.isEmpty) {
                if let scores { onRecord(scores.home, scores.away, namedOfficial) }
            }
            .padding(.horizontal, ThroSpacing.spaceScreenGutter)
            .padding(.bottom, ThroSpacing.spacing6)
        }
        // The screen arrives (PD-027): one beat, on the design's own curve,
        // withdrawn entirely under Reduce Motion.
        .throEntrance(0)
        .background(ThroColor.colorBackgroundPrimary.ignoresSafeArea())
    }

    /// What is already recorded, and where it came from. Shown first, because changing a result
    /// somebody else entered is a different act from entering one nobody has.
    @ViewBuilder private func existing(_ result: MatchResult) -> some View {
        VStack(alignment: .leading, spacing: ThroSpacing.spacing2) {
            Text("Already recorded")
                .thro(ThroTypography.labelStrong.weight(.semibold))
                .foregroundStyle(ThroColor.colorTextSecondary)
            HStack(alignment: .firstTextBaseline, spacing: ThroSpacing.spacing2) {
                Text("\(result.home)–\(result.away)")
                    .thro(ThroTypography.heading1.family(.sport).weight(.bold))
                    .foregroundStyle(ThroColor.colorTextPrimary)
                if let unit = club.unit {
                    Text(unit.rawValue)
                        .thro(ThroTypography.body)
                        .foregroundStyle(ThroColor.colorTextSecondary)
                }
            }
            SourceTag(source: result.source)
            Text(result.source.explanation)
                .thro(ThroTypography.metadata)
                .foregroundStyle(ThroColor.colorTextTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(ThroSpacing.spacing4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(ThroColor.colorBackgroundRaised,
                    in: RoundedRectangle(cornerRadius: ThroSpacing.radiusCard))
        .overlay(RoundedRectangle(cornerRadius: ThroSpacing.radiusCard)
            .strokeBorder(ThroColor.colorBorderDefault, lineWidth: 1))
    }

    @ViewBuilder private var boxes: some View {
        HStack(alignment: .top, spacing: ThroSpacing.spacing4) {
            score(home, $homeScore)
            Text("v")
                .thro(ThroTypography.heading3)
                .foregroundStyle(ThroColor.colorTextSecondary)
                .padding(.top, 34)
            score(away, $awayScore)
        }
        // What the two numbers ARE (PD-022). A result of 3–1 means nothing without it, and this is
        // the screen where somebody is typing the 3.
        if let unit = club.unit {
            Text("\(unit.label) won by each side.")
                .thro(ThroTypography.metadata)
                .foregroundStyle(ThroColor.colorTextSecondary)
        } else {
            Text("This league has not said what its results are counted in, so these are numbers "
                 + "without a unit. An admin can set one until the first result goes in.")
                .thro(ThroTypography.metadata)
                .foregroundStyle(ThroColor.colorStatusError)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func score(_ name: String, _ text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: ThroSpacing.spacing2) {
            Text(name)
                .thro(ThroTypography.labelStrong.weight(.semibold))
                .foregroundStyle(ThroColor.colorTextSecondary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            TextField("0", text: text)
                .textFieldStyle(.plain)
                .thro(ThroTypography.heading2.family(.sport).weight(.bold))
                .foregroundStyle(ThroColor.colorTextPrimary)
                #if os(iOS)
                .keyboardType(.numberPad)
                #endif
                .padding(.horizontal, ThroSpacing.spacing4)
                .frame(minHeight: 56)
                .background(RoundedRectangle(cornerRadius: ThroSpacing.radiusField)
                    .fill(ThroColor.colorSurfacePrimary))
                .overlay(RoundedRectangle(cornerRadius: ThroSpacing.radiusField)
                    .strokeBorder(ThroColor.colorBorderStrong, lineWidth: 1))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// The stronger source, described where somebody would look for it — not offered as a control
    /// that would refuse, and not left out as though it did not exist.
    private var unavailable: some View {
        VStack(alignment: .leading, spacing: ThroSpacing.spacing2) {
            HStack(spacing: 8) {
                Icon(.circleCheck, size: 16).foregroundStyle(ThroColor.colorTextTertiary)
                Text("From a match scored in THRØ")
                    .thro(ThroTypography.label.weight(.semibold))
                    .foregroundStyle(ThroColor.colorTextTertiary)
            }
            Text("The other way to fill this in, and the one THRØ is for: every visit and every dart "
                 + "behind the score. It needs a match this phone can tie to \(home) and \(away), "
                 + "and a match here is two names typed at an oche — nothing yet says which team "
                 + "somebody played for. That arrives with accounts.")
                .thro(ThroTypography.metadata)
                .foregroundStyle(ThroColor.colorTextTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// Adding a fixture between two teams (PD-019).
///
/// **Not the club's fixture screen with two extra fields.** A club's fixture is a title somebody
/// typed — *"Home to The Bell"* — because a club's opponents are not things this device knows. A
/// league's fixture is between two of its own teams, so it is chosen rather than typed, and its
/// title follows from the choice instead of being a third thing to get wrong.
public struct NewTeamFixtureScreen: View {
    private let club: Club
    @State private var homeId: String
    @State private var awayId: String
    @State private var venue = ""
    @State private var when: Date
    private let onBack: () -> Void
    private let onAdd: (String, String, String, Date, String) -> Void

    public init(club: Club, now: Date = Date(), onBack: @escaping () -> Void = {},
                onAdd: @escaping (String, String, String, Date, String) -> Void = { _, _, _, _, _ in }) {
        self.club = club
        self.onBack = onBack
        self.onAdd = onAdd
        _homeId = State(initialValue: club.teams.first?.id ?? "")
        _awayId = State(initialValue: club.teams.dropFirst().first?.id ?? "")
        // The same default the club's fixture screen uses: next week at eight in the evening.
        var start = Calendar.current.date(byAdding: .day, value: 7, to: now) ?? now
        start = Calendar.current.date(bySettingHour: 20, minute: 0, second: 0, of: start) ?? start
        _when = State(initialValue: start)
    }

    private func name(_ id: String) -> String { club.teams.first { $0.id == id }?.name ?? "" }
    private var sameTeam: Bool { !homeId.isEmpty && homeId == awayId }
    private var ready: Bool { !homeId.isEmpty && !awayId.isEmpty && !sameTeam }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            TopBar("Add a fixture", eyebrow: club.name, onBack: onBack)
            ScrollView {
                VStack(alignment: .leading, spacing: ThroSpacing.spacing5) {
                    if club.teams.count < 2 {
                        EmptyState(title: "Not enough \(club.competitorNoun.many.lowercased())",
                                   message: "A fixture is between two of them, and there "
                                          + "\(club.teams.count == 1 ? "is one" : "are none") "
                                          + "so far. Add them first.")
                    } else {
                        picker("Home", selection: $homeId)
                        picker("Away", selection: $awayId)
                        if sameTeam {
                            Text("A team does not play itself.")
                                .thro(ThroTypography.metadata)
                                .foregroundStyle(ThroColor.colorStatusError)
                        }
                        ThroTextField("Venue", text: $venue, placeholder: "The Feathers")
                        VStack(alignment: .leading, spacing: ThroSpacing.spacing2) {
                            Text("When")
                                .thro(ThroTypography.label.weight(.semibold))
                                .foregroundStyle(ThroColor.colorTextPrimary)
                            DatePicker("When", selection: $when)
                                .labelsHidden()
                                .tint(ThroColor.throGreen)
                        }
                        Note("The fixture will be called **\(name(homeId)) v \(name(awayId))**. "
                             + "It carries no result until somebody says what happened, and when "
                             + "they do the app records where that came from (PD-020).")
                    }
                }
                .padding(.horizontal, ThroSpacing.spaceScreenGutter)
                .padding(.vertical, ThroSpacing.spacing5)
            }
            if club.teams.count >= 2 {
                ThroButton("Add fixture", variant: .primary, size: .large, fullWidth: true,
                           disabled: !ready) {
                    onAdd(homeId, awayId, "\(name(homeId)) v \(name(awayId))", when,
                          venue.trimmingCharacters(in: .whitespacesAndNewlines))
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

    /// The platform's own menu picker — the same standing as the `DatePicker` beside it and the
    /// `PhotosPicker` on the badge screen: an operating-system control, not a component the export
    /// was expected to draw.
    private func picker(_ label: String, selection: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: ThroSpacing.spacing2) {
            Text(label)
                .thro(ThroTypography.label.weight(.semibold))
                .foregroundStyle(ThroColor.colorTextPrimary)
            Picker(label, selection: selection) {
                ForEach(club.teams) { team in
                    Text(team.name).tag(team.id)
                }
            }
            .pickerStyle(.menu)
            .tint(ThroColor.colorTextBrand)
            .frame(maxWidth: .infinity, minHeight: ThroSpacing.touchTargetMinimum, alignment: .leading)
            .padding(.horizontal, ThroSpacing.spacing3)
            .background(RoundedRectangle(cornerRadius: ThroSpacing.radiusField)
                .fill(ThroColor.colorSurfacePrimary))
            .overlay(RoundedRectangle(cornerRadius: ThroSpacing.radiusField)
                .strokeBorder(ThroColor.colorBorderStrong, lineWidth: 1))
        }
    }
}
