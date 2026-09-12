import SwiftUI
import ThroDesign
import ThroNet
import ThroTokens

// The wall, drawn (PD-079).
//
// **Everything here is the board.** A league table on a pub wall drawn as a plain list would be the one
// surface in THRØ that looked like a spreadsheet, on the biggest screen the brand ever gets. So it is the
// same green field, the same chalk, the same typography as the phone — at the size a room reads from, which
// is the only thing that changes.
//
// **Nothing here scrolls and nothing here is tapped.** The rotation turns the pages; the remote is used once,
// on the setup screen, and then never again.

/// The type a room reads, which is the phone's type at the top of the same ladder.
///
/// **Not a TV scale invented for the occasion.** `ThroTypeRole.sized` exists for the density ladder and
/// says every size passed to it should be one of the approved four — 96, 72, 56, 40 — which is the ladder
/// the scoring screen steps *down* when a phone is short of room. A wall has the opposite problem and takes
/// the same steps upward. The first build of this screen used the phone's roles unchanged and produced a
/// league table in twenty-point type on a screen six metres away; it was legible in a screenshot and
/// useless in a pub, which is the whole reason for looking at a thing on the device it runs on.
enum ThroVenueType {
    static let league = ThroTypography.display.sized(72)
    static let panel = ThroTypography.heading1.sized(56)
    /// **The largest thing after the heading**, because it is what somebody looks up to find. The first
    /// build had it the same size as the figures beside it, and a table where "Grange A" reads smaller
    /// than the "2" next to it is a table that answers the wrong question first.
    static let team = ThroTypography.heading2.sized(56)
    static let points = ThroTypography.heading1.sized(56)
    static let figure = ThroTypography.heading2.sized(40).weight(.semibold)
    static let position = ThroTypography.heading2.sized(40).weight(.regular)
    static let column = ThroTypography.eyebrow.sized(24)
    static let foot = ThroTypography.metadata.sized(24)
    static let aside = ThroTypography.bodyLarge.sized(32)
    /// The right-hand column of a fixture list. Quieter than the sides: a venue is where, not who.
    static let where_ = ThroTypography.bodyLarge.sized(32)
}

/// The whole of a venue screen: choose a season once, then show it forever.
public struct ThroVenueScreen: View {
    @StateObject private var wall: ThroVenueWall
    @State private var season: UUID?
    private let choice: ThroVenueChoice
    private let api: ThroAPI

    public init(api: ThroAPI, choice: ThroVenueChoice = ThroVenueChoice()) {
        self.api = api
        self.choice = choice
        _wall = StateObject(wrappedValue: ThroVenueWall(api: api))
        _season = State(initialValue: choice.season)
    }

    public var body: some View {
        Group {
            if let season {
                ThroVenueChannel(wall: wall, season: season)
            } else {
                ThroVenueChooser(api: api) { chosen in
                    choice.season = chosen
                    season = chosen
                }
            }
        }
    }
}

/// A build that was never told where THRØ is.
///
/// It says so on the wall rather than showing an empty league forever. A screen that looks like a league
/// with nothing in it sends somebody looking for a fault in the league.
public struct ThroVenueUnconfigured: View {
    public init() {}

    public var body: some View {
        ThroBoard(lamp: UnitPoint(x: 0.5, y: 0.3), grainSeed: 0x404) {
            VStack(alignment: .leading, spacing: ThroSpacing.spacing4) {
                Text("THRØ")
                    .thro(ThroTypography.display)
                    .foregroundStyle(ThroColor.colorTextOnBoard)
                Text("This screen has not been told where THRØ is.")
                    .thro(ThroTypography.heading2)
                    .foregroundStyle(ThroColor.throChalk.opacity(0.8))
                Text("The app was built without a server address. Nothing it could show would be real.")
                    .thro(ThroTypography.bodyLarge)
                    .foregroundStyle(ThroColor.throChalk.opacity(0.6))
            }
            .padding(ThroSpacing.spaceSectionGap * 2)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }
}

/// The rotation: one panel at a time, turning by itself.
public struct ThroVenueChannel: View {
    @ObservedObject private var wall: ThroVenueWall
    private let season: UUID
    @State private var startedAt = Date()
    @State private var now = Date()

    /// A second, because the panel turn has to land on the second it is due rather than up to five late,
    /// and because the "heard" line counts in minutes and should not jump two at a time.
    private let tick = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    public init(wall: ThroVenueWall, season: UUID) {
        _wall = ObservedObject(wrappedValue: wall)
        self.season = season
    }

    private var panels: [ThroVenuePanel] {
        ThroVenueRota.panels(standings: wall.standings, fixtures: wall.fixtures)
    }

    public var body: some View {
        ThroBoard(lamp: UnitPoint(x: 0.5, y: 0.18), grainSeed: 0xE1E1) {
            VStack(alignment: .leading, spacing: ThroSpacing.spacing6) {
                head
                if let panel = ThroVenueRota.showing(panels, since: startedAt, now: now) {
                    body(of: panel)
                        .transition(.opacity)
                        .id(panel.id)
                } else {
                    nothing
                }
                Spacer(minLength: 0)
                foot
            }
            .padding(.horizontal, ThroSpacing.spaceSectionGap * 2)
            .padding(.vertical, ThroSpacing.spaceSectionGap)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .animation(.easeInOut(duration: 0.35), value: ThroVenueRota.showing(panels, since: startedAt, now: now))
        .onReceive(tick) { now = $0 }
        .task(id: season) { await wall.watch(season: season) }
    }

    private var head: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(wall.standings?.league ?? "THRØ")
                .thro(ThroVenueType.league)
                .foregroundStyle(ThroColor.colorTextOnBoard)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Spacer(minLength: ThroSpacing.spacing6)
            if let label = wall.standings?.label {
                Text(label.uppercased())
                    .thro(ThroVenueType.column)
                    .foregroundStyle(ThroColor.throChalk.opacity(0.65))
                    .lineLimit(1)
            }
        }
    }

    private var foot: some View {
        HStack(spacing: ThroSpacing.spacing4) {
            // The wall says when it last heard, for the reason every other surface does: this one is left
            // on all evening with nobody reloading it, so it is the likeliest of all of them to be showing
            // something that quietly stopped being true.
            Text(ThroVenueWords.heard(at: wall.heardAt, now: now))
                .thro(ThroVenueType.foot)
                .foregroundStyle(ThroColor.throChalk.opacity(0.5))
            if let trouble = wall.trouble {
                Text(trouble)
                    .thro(ThroVenueType.foot)
                    .foregroundStyle(ThroColor.throBronzeOnink)
            }
            Spacer(minLength: 0)
            if let rules = wall.standings?.rules {
                // Whose rules ordered the table, on the table, exactly as PD-054 requires everywhere else.
                Text(rules.says)
                    .thro(ThroVenueType.foot)
                    .foregroundStyle(ThroColor.throChalk.opacity(0.5))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
        }
    }

    private var nothing: some View {
        VStack(alignment: .leading, spacing: ThroSpacing.spacing4) {
            Text(ThroVenueWords.nothingYet)
                .thro(ThroVenueType.panel)
                .foregroundStyle(ThroColor.colorTextOnBoard)
            Text(ThroVenueWords.nothingYetHint)
                .thro(ThroVenueType.aside)
                .foregroundStyle(ThroColor.throChalk.opacity(0.7))
        }
        .padding(.top, ThroSpacing.spaceSectionGap)
    }

    @ViewBuilder private func body(of panel: ThroVenuePanel) -> some View {
        switch panel {
        case let .table(division, page, of, rows):
            ThroVenueTable(division: division, page: page, of: of, rows: rows)
        case let .toPlay(page, of, fixtures):
            ThroVenueFixtures(title: ThroVenueWords.toPlay, page: page, of: of, fixtures: fixtures,
                              showing: .toPlay, now: now)
        case let .results(page, of, fixtures):
            ThroVenueFixtures(title: ThroVenueWords.results, page: page, of: of, fixtures: fixtures,
                              showing: .results, now: now)
        }
    }
}

/// A division's table, at the size a room reads it from.
public struct ThroVenueTable: View {
    private let division: String
    private let page: Int
    private let of: Int
    private let rows: [LeagueStandings.Row]

    public init(division: String, page: Int, of: Int, rows: [LeagueStandings.Row]) {
        self.division = division
        self.page = page
        self.of = of
        self.rows = rows
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: ThroSpacing.spacing4) {
            ThroVenueHeading(division, page: page, of: of)
            VStack(spacing: ThroSpacing.spacing2) {
                header
                ForEach(rows) { row in
                    HStack(spacing: ThroSpacing.spacing4) {
                        Text("\(row.position)")
                            .thro(ThroVenueType.position)
                            .monospacedDigit()
                            .foregroundStyle(ThroColor.throChalk.opacity(0.55))
                            .frame(width: 90, alignment: .trailing)
                        Text(row.name)
                            .thro(ThroVenueType.team)
                            .foregroundStyle(ThroColor.colorTextOnBoard)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        figure("\(row.played)")
                        figure("\(row.won)")
                        figure("\(row.drawn)")
                        figure("\(row.lost)")
                        figure(row.legDifference > 0 ? "+\(row.legDifference)" : "\(row.legDifference)")
                        Text("\(row.points)")
                            .thro(ThroVenueType.points)
                            .monospacedDigit()
                            .foregroundStyle(ThroColor.throGreenOnink)
                            .frame(width: 150, alignment: .trailing)
                    }
                }
            }
            // Capped, and not the width of a television. With the name column taking all the slack the
            // figures ended up at the far edge with two metres of green between them and the team they
            // belong to — a table you have to sweep your eyes across is a table nobody reads from the bar.
            .frame(maxWidth: 1560, alignment: .leading)
        }
    }

    private var header: some View {
        HStack(spacing: ThroSpacing.spacing4) {
            Text("").frame(width: 90)
            Text("TEAM")
                .thro(ThroVenueType.column)
                .foregroundStyle(ThroColor.throChalk.opacity(0.5))
                .frame(maxWidth: .infinity, alignment: .leading)
            ForEach(["P", "W", "D", "L", "+/–"], id: \.self) { column in
                Text(column)
                    .thro(ThroVenueType.column)
                    .foregroundStyle(ThroColor.throChalk.opacity(0.5))
                    .frame(width: 120, alignment: .trailing)
            }
            Text("PTS")
                .thro(ThroVenueType.column)
                .foregroundStyle(ThroColor.throChalk.opacity(0.5))
                .frame(width: 150, alignment: .trailing)
        }
        .frame(maxWidth: 1560, alignment: .leading)
    }

    private func figure(_ text: String) -> some View {
        Text(text)
            .thro(ThroVenueType.figure)
            .monospacedDigit()
            .foregroundStyle(ThroColor.throChalk.opacity(0.8))
            .frame(width: 120, alignment: .trailing)
    }
}

/// Fixtures — the ones to come, or the ones just played.
public struct ThroVenueFixtures: View {
    public enum Showing { case toPlay, results }

    private let title: String
    private let page: Int
    private let of: Int
    private let fixtures: [LeagueFixtures.Fixture]
    private let showing: Showing
    private let now: Date

    public init(title: String, page: Int, of: Int, fixtures: [LeagueFixtures.Fixture],
                showing: Showing, now: Date = Date()) {
        self.title = title
        self.page = page
        self.of = of
        self.fixtures = fixtures
        self.showing = showing
        self.now = now
    }

    private static let when: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "EEE d MMM · HH:mm"
        return f
    }()

    public var body: some View {
        VStack(alignment: .leading, spacing: ThroSpacing.spacing4) {
            ThroVenueHeading(title, page: page, of: of)
            VStack(spacing: ThroSpacing.spacing2) {
                ForEach(fixtures) { fixture in
                    HStack(spacing: ThroSpacing.spacing4) {
                        Text(Self.when.string(from: fixture.scheduledAt))
                            .thro(ThroVenueType.aside)
                            .monospacedDigit()
                            .foregroundStyle(ThroColor.throChalk.opacity(0.6))
                            .frame(width: 320, alignment: .leading)
                        Text(ThroVenueWords.sides(fixture))
                            .thro(ThroVenueType.team)
                            .foregroundStyle(ThroColor.colorTextOnBoard)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Text(right(fixture))
                            .thro(showing == .results ? ThroVenueType.figure : ThroVenueType.where_)
                            .monospacedDigit()
                            .foregroundStyle(colour(fixture))
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                            .frame(width: 340, alignment: .trailing)
                    }
                }
            }
        }
    }

    /// The right-hand column: the result where there is one, the venue where there is not, and the fact
    /// that a night has been and gone with nothing entered where that is what happened.
    private func right(_ fixture: LeagueFixtures.Fixture) -> String {
        switch showing {
        case .results: return ThroVenueWords.outcome(fixture)
        case .toPlay:
            if ThroVenueWords.awaiting(fixture, now: now) { return ThroVenueWords.awaitingResult }
            if fixture.state == "postponed" { return "Postponed" }
            return fixture.venue ?? ""
        }
    }

    private func colour(_ fixture: LeagueFixtures.Fixture) -> Color {
        if showing == .toPlay && ThroVenueWords.awaiting(fixture, now: now) { return ThroColor.throBronzeOnink }
        if showing == .results { return ThroColor.throGreenOnink }
        // A venue is where, not who: quieter than the sides beside it, or a room reads the pub's name
        // as the fixture.
        return ThroColor.throChalk.opacity(0.45)
    }
}

/// A panel's heading, with its page number where there is more than one page.
struct ThroVenueHeading: View {
    private let title: String
    private let page: Int
    private let of: Int

    init(_ title: String, page: Int, of: Int) {
        self.title = title
        self.page = page
        self.of = of
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: ThroSpacing.spacing4) {
            Text(title)
                .thro(ThroVenueType.panel)
                .foregroundStyle(ThroColor.colorTextOnBoard)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            if of > 1 {
                // A page number, because a table that turns while somebody is halfway down it should say
                // that is what happened rather than look like rows appearing and vanishing.
                Text("\(page) of \(of)")
                    .thro(ThroVenueType.foot)
                    .foregroundStyle(ThroColor.throChalk.opacity(0.5))
            }
            Spacer(minLength: 0)
        }
    }
}
