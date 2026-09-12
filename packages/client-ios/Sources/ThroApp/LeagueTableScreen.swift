import SwiftUI
import ThroDesign
import ThroNet
import ThroTokens

// A league's table, as THRØ computed it (PD-054).
//
// **Five things on a row, not eight columns.** The table THRØ draws for a club kept on this phone has seven
// number columns in fixed widths totalling 212 points, which crowds an iPhone SE and does not grow when the
// reader's text does. This screen does not repeat that: the position and the name read across, the figures
// that decide the order sit at the end, and won-drawn-lost goes on a second line where it has room. Nothing
// here is a fixed width, so it holds at every text size and on every screen.
//
// **The rules are printed.** PD-054 allows THRØ a standard only on the condition that it is never silent, so
// the sentence under the table says whose rules ordered it — the league's own, or THRØ's — every time.

/// A league season's table, read from THRØ.
public struct LeagueTableScreen: View {
    private let seasonId: UUID
    private let leagueName: String
    private let api: ThroAPI?
    private let onBack: () -> Void

    @State private var state: TeamsModel.Loading<LeagueStandings> = .idle
    /// The fixtures beside the table (PD-062). Loaded separately and allowed to fail on its own: the table
    /// is what this screen is for, and losing its companion must not take the subject down with it.
    @State private var fixtures: TeamsModel.Loading<LeagueFixtures> = .idle

    public init(seasonId: UUID, leagueName: String, api: ThroAPI?, onBack: @escaping () -> Void) {
        self.seasonId = seasonId
        self.leagueName = leagueName
        self.api = api
        self.onBack = onBack
    }

    public var body: some View {
        VStack(spacing: 0) {
            TopBar("Table", eyebrow: leagueName, onBack: onBack)
            switch state {
            case .idle, .loading:
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            case .failed(let why):
                ErrorState(title: "The table could not be read", what: why,
                           safe: "Nothing about the league or its results is affected.",
                           todo: "Try again with a connection.", actionLabel: "Try again", onAction: { Task { await load() } })
                    .padding(ThroSpacing.spaceScreenGutter)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            case .loaded(let table):
                loaded(table)
            }
        }
        .background(ThroColor.colorBackgroundPrimary.ignoresSafeArea())
        .task(id: seasonId) { await load() }
    }

    private func load() async {
        guard let api else { state = .failed("This build names no server."); return }
        state = .loading
        fixtures = .loading
        // Both at once: they are read from the same rows on the server and a reader compares them, so
        // fetching one after the other would show a table beside an empty column for no reason.
        async let table = api.standings(season: seasonId)
        async let list = api.fixtures(season: seasonId)
        do { state = .loaded(try await table) }
        catch { state = .failed(ThroAPI.refusal(error) ?? "The table could not be read just now.") }
        do { fixtures = .loaded(try await list) }
        catch { fixtures = .failed(ThroAPI.refusal(error) ?? "The fixtures could not be read just now.") }
    }

    @ViewBuilder private func loaded(_ table: LeagueStandings) -> some View {
        // The width comes from here rather than from inside the scroll view, where a geometry reader takes
        // all the height it can reach (PD-062).
        GeometryReader { proxy in
            ScrollView {
                ThroBeside(width: proxy.size.width) {
                    standings(table)
                } aside: {
                    stillToPlay
                }
                .padding(.horizontal, ThroSpacing.spaceScreenGutter)
                .padding(.bottom, ThroSpacing.spacing6)
            }
        }
    }

    @ViewBuilder private func standings(_ table: LeagueStandings) -> some View {
            VStack(alignment: .leading, spacing: 0) {
                Text(table.label)
                    .thro(ThroTypography.metadata).foregroundStyle(ThroColor.colorTextSecondary)
                    .padding(.top, ThroSpacing.spacing4)

                if table.divisions.allSatisfy({ $0.rows.isEmpty }) {
                    EmptyState(title: "No results yet",
                               message: "When this league's fixtures start carrying results, the table fills itself in. "
                                      + "THRØ works it out from the results rather than keeping a table of its own.")
                        .padding(.top, ThroSpacing.spacing5)
                } else {
                    ForEach(table.divisions) { division in
                        SectionHeader(division.name, meta: "\(division.rows.count)")
                            .padding(.top, ThroSpacing.spaceSectionGap)
                        ThroDivider().padding(.top, ThroSpacing.spacing2)
                        ForEach(division.rows) { row in
                            line(row)
                            ThroDivider()
                        }
                        if division.awaitingResults > 0 {
                            Note(LeagueTableWords.awaiting(division.awaitingResults))
                                .padding(.top, ThroSpacing.spacing3)
                        }
                    }
                }

                // PD-054's condition: the rules that ordered the table are named under it, every time.
                Note(table.rules.says + " " + LeagueTableWords.ordered(table.rules))
                    .padding(.top, ThroSpacing.spaceSectionGap)
            }
    }

    /// What is left to play, and what has already been decided — the other half of a league's own data.
    ///
    /// Beside the table on a screen with room and under it on a phone, which is the whole of PD-062: these
    /// are two objects a reader compares, not one object split in half.
    @ViewBuilder private var stillToPlay: some View {
        VStack(alignment: .leading, spacing: 0) {
            switch fixtures {
            case .idle, .loading:
                SectionHeader("Still to play", meta: nil).padding(.top, ThroSpacing.spacing4)
                ProgressView().padding(.top, ThroSpacing.spacing4)
            case .failed(let why):
                SectionHeader("Still to play", meta: nil).padding(.top, ThroSpacing.spacing4)
                // A quiet note, not an error state: the table beside this one loaded, and a full-page
                // refusal for the companion would shout about the half that did not matter.
                Note(why).padding(.top, ThroSpacing.spacing3)
            case .loaded(let list):
                let next = list.toPlay
                let done = list.decided
                SectionHeader("Still to play", meta: next.isEmpty ? nil : "\(next.count)")
                    .padding(.top, ThroSpacing.spacing4)
                ThroDivider().padding(.top, ThroSpacing.spacing2)
                if next.isEmpty {
                    Note(LeagueTableWords.everythingPlayed).padding(.top, ThroSpacing.spacing3)
                } else {
                    ForEach(next.prefix(6)) { fixture in
                        fixtureLine(fixture)
                        ThroDivider()
                    }
                    if next.count > 6 {
                        Note(LeagueTableWords.andMore(next.count - 6)).padding(.top, ThroSpacing.spacing3)
                    }
                }
                if !done.isEmpty {
                    SectionHeader("Already in", meta: "\(done.count)")
                        .padding(.top, ThroSpacing.spaceSectionGap)
                    ThroDivider().padding(.top, ThroSpacing.spacing2)
                    ForEach(done.prefix(5)) { fixture in
                        fixtureLine(fixture)
                        ThroDivider()
                    }
                }
            }
        }
    }

    /// One fixture: who, when and where — or what it finished as, where it has finished.
    private func fixtureLine(_ f: LeagueFixtures.Fixture) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(LeagueTableWords.sides(f))
                .thro(ThroTypography.bodyLarge.weight(.semibold))
                .foregroundStyle(ThroColor.colorTextPrimary)
                .lineLimit(2)
            Text(LeagueTableWords.when(f))
                .thro(ThroTypography.metadata)
                .foregroundStyle(ThroColor.colorTextSecondary)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, ThroSpacing.spacing3)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(LeagueTableWords.spokenFixture(f))
    }

    /// One row: who, then what decided where they are, then the detail underneath.
    private func line(_ row: LeagueStandings.Row) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: ThroSpacing.spacing3) {
            Text("\(row.position)")
                .thro(ThroTypography.metadata.family(.sport))
                .foregroundStyle(ThroColor.colorTextSecondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(row.name)
                    .thro(ThroTypography.bodyLarge.weight(.semibold))
                    .foregroundStyle(ThroColor.colorTextPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                Text(LeagueTableWords.detail(row))
                    .thro(ThroTypography.metadata)
                    .foregroundStyle(ThroColor.colorTextSecondary)
                    .lineLimit(2)
            }
            Spacer(minLength: ThroSpacing.spacing2)
            VStack(alignment: .trailing, spacing: 2) {
                Text("\(row.points)")
                    .thro(ThroTypography.bodyLarge.family(.sport).weight(.bold))
                    .foregroundStyle(ThroColor.colorTextPrimary)
                Text(LeagueTableWords.difference(row.legDifference))
                    .thro(ThroTypography.metadata.family(.sport))
                    .foregroundStyle(ThroColor.colorTextSecondary)
            }
        }
        .padding(.vertical, ThroSpacing.spacing3)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(LeagueTableWords.spoken(row))
    }
}

/// The words this screen says, apart from the drawing so they are tested rather than looked at.
enum LeagueTableWords {

    /// "14 played · 10 won, 1 drawn, 3 lost · 9 scored on THRØ"
    static func detail(_ row: LeagueStandings.Row) -> String {
        var parts = ["\(row.played) played", "\(row.won) won, \(row.drawn) drawn, \(row.lost) lost"]
        if row.awardedFor + row.awardedAgainst > 0 {
            let n = row.awardedFor + row.awardedAgainst
            parts.append(n == 1 ? "1 not played" : "\(n) not played")
        }
        // PD-020 on one row: what came from a match scored on THRØ, and what came from somebody's word.
        if row.evidenced > 0 { parts.append("\(row.evidenced) scored on THRØ") }
        return parts.joined(separator: " · ")
    }

    static func difference(_ n: Int) -> String { n > 0 ? "+\(n)" : "\(n)" }

    /// What separated the rows, named rather than implied — and never claimed when nothing did.
    static func ordered(_ rules: LeagueStandings.Rules) -> String {
        let by = rules.orderedBy.map { step in
            switch step {
            case "points": return "points"
            case "leg_difference": return "leg difference"
            case "legs_for": return "legs won"
            case "head_to_head": return "who beat whom"
            case "played": return "matches played"
            default: return step.replacingOccurrences(of: "_", with: " ")
            }
        }
        guard !by.isEmpty else { return "" }
        return "Ordered on " + by.joined(separator: ", then ") + "."
    }

    /// A table with results missing is a table that is quietly wrong, so it says so out loud.
    static func awaiting(_ n: Int) -> String {
        n == 1
            ? "**One fixture has been played with no result entered**, so this table is not finished."
            : "**\(n) fixtures have been played with no result entered**, so this table is not finished."
    }

    // --- the fixtures beside the table (PD-062) -------------------------------------------------

    static let everythingPlayed = "Every fixture in this season has a result."

    static func andMore(_ n: Int) -> String {
        n == 1 ? "And one more after those." : "And \(n) more after those."
    }

    /// A team THRØ may not name is *"A team"* and never a blank, because a fixture with one side missing
    /// reads as a bug rather than as a side that asked not to be listed (PD-056).
    static func side(_ name: String?) -> String { name ?? "A team" }

    /// "Grange A v Riverside A" while it is to come, "Grange A 5–2 Riverside A" once it is decided, and
    /// "Grange A awarded, Riverside A" where nobody played — an award never invents a scoreline (ADR-012).
    static func sides(_ f: LeagueFixtures.Fixture) -> String {
        let home = side(f.home), away = side(f.away)
        guard let d = f.decided else { return "\(home) v \(away)" }
        if let h = d.legsHome, let a = d.legsAway { return "\(home) \(h)–\(a) \(away)" }
        let word = d.kind == "walkover" ? "walkover" : "awarded"
        guard let toHome = d.awardedToHome else { return "\(home) v \(away) · \(word)" }
        return toHome ? "\(home) \(word), \(away)" : "\(home), \(away) \(word)"
    }

    /// When and where, and what kind of result it was where that is not obvious from the scoreline.
    ///
    /// **A declared result says so.** It counts in the table exactly as a played one does and it is not
    /// evidence, and the difference is invisible in "5–2" unless this says it (PD-055).
    static func when(_ f: LeagueFixtures.Fixture) -> String {
        var parts = [dayAndMonth(f.scheduledAt)]
        if f.state != "scheduled" { parts.append(f.state) }
        if let venue = f.venue { parts.append(venue) }
        if f.decided?.kind == "declared" { parts.append("the league's word") }
        // PD-065: an annulled fixture is open, and says so rather than sitting among the ones nobody has
        // got round to. The reason is carried because a result withdrawn without one is a result a league
        // cannot answer for; whoever withdrew it is not named, because this is public.
        if let annulled = f.annulled { parts.append("annulled, to be replayed — " + annulled.reason) }
        return parts.joined(separator: " · ")
    }

    /// "Thu 24 Sep" — the day matters in a league that plays on one.
    static func dayAndMonth(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_GB")
        f.setLocalizedDateFormatFromTemplate("EEE d MMM")
        return f.string(from: date)
    }

    static func spokenFixture(_ f: LeagueFixtures.Fixture) -> String {
        // An en dash between two numerals is not a word, and read out "5–2" is the same sound as
        // fifty-two. The table's own figures learned this; so does this one.
        let said = sides(f).replacingOccurrences(of: "–", with: " to ")
        return said + ". " + when(f) + "."
    }

    static func spoken(_ row: LeagueStandings.Row) -> String {
        "\(row.position). \(row.name), \(row.points) point\(row.points == 1 ? "" : "s"), "
            + "\(row.played) played, leg difference \(difference(row.legDifference))."
    }
}
