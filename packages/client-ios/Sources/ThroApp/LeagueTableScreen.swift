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
        do { state = .loaded(try await api.standings(season: seasonId)) }
        catch { state = .failed(ThroAPI.refusal(error) ?? "The table could not be read just now.") }
    }

    @ViewBuilder private func loaded(_ table: LeagueStandings) -> some View {
        ScrollView {
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
            .padding(.horizontal, ThroSpacing.spaceScreenGutter)
            .padding(.bottom, ThroSpacing.spacing6)
            .throReadable()
        }
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

    static func spoken(_ row: LeagueStandings.Row) -> String {
        "\(row.position). \(row.name), \(row.points) point\(row.points == 1 ? "" : "s"), "
            + "\(row.played) played, leg difference \(difference(row.legDifference))."
    }
}
