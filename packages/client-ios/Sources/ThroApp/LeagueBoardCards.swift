import SwiftUI
import ThroDesign
import ThroNet
import ThroTokens

// What the leagues board says in its drawer (PD-046), one card for each thing that can be chosen.
// Each card is handed what it shows and what to do; the screen owns the choosing, the map and the
// camera. Everything here is drawn on the board: chalk on the field, a league's name in its chalk.

/// What the board has chosen.
enum LeagueChoice: Hashable {
    case none
    /// A league with teams: its chip is on and its pubs are lit.
    case league(UUID)
    case pub(UUID)
    case team(UUID)
    /// A league placed by its own point, with no teams listed on THRØ.
    case bare(UUID)
}

/// The board's sentences, kept apart from the drawing so they are tested rather than looked at.
enum LeagueBoardWords {
    /// "47 teams at 18 pubs in 3 leagues. 326 more leagues are on the map with no teams listed yet."
    static func census(_ atlas: LeagueAtlas, bare: Int) -> String {
        let pubs = Set(atlas.entries.compactMap { $0.placed ? $0.venue?.venueId : nil }).count
        let teams = atlas.entries.count, leagues = atlas.leagues.count
        var line = teams == 0 ? "No league has its teams on THRØ yet."
            : "\(count(teams, "team")) at \(count(pubs, "pub")) in \(count(leagues, "league"))."
        if bare > 0 { line += " \(bare) more \(bare == 1 ? "league is" : "leagues are") on the map with no teams listed yet." }
        return line
    }

    /// What the chosen team's eyebrow says, in its league's chalk: "Stockton Thursday · Division One".
    static func teamEyebrow(_ e: LeagueAtlas.Entry) -> String {
        [e.league, e.divided ? e.division : nil].compactMap { $0 }.joined(separator: " · ")
    }

    /// Where and when it plays: "The Thomas Sheraton · Thursday nights · 2025-2026 · 0.4 mi".
    static func teamWhere(_ e: LeagueAtlas.Entry, distance: String?) -> String {
        [e.venue?.name ?? "Its pub is not known yet", e.playsOn.map { "\($0) nights" }, season(e.season), distance]
            .compactMap { $0 }.joined(separator: " · ")
    }

    /// A season's label where it reads as a date. Leagues name their seasons as they like — "2025-2026",
    /// and also "Redcar Darts League 2026", which beside the league's own name says it twice and runs
    /// off the line — so a label longer than a date is left to the league's own page.
    static func season(_ label: String?) -> String? {
        guard let label, label.count <= 12 else { return nil }
        return label
    }

    /// Over the rivals: "Division One · 5 teams", or "The league · 18 teams" where it is not divided —
    /// and, for a team that said it plays there (PD-049), the others who said the same, which is a
    /// different thing from a division and is named as one.
    static func division(_ e: LeagueAtlas.Entry, teams: Int) -> String {
        let what = e.said ? "Said by their players" : (e.divided ? e.division : "The league")
        return "\(what) · \(count(teams, "team"))"
    }

    /// A season's label where it reads as a date and there is one at all.
    static func seasonLabel(_ label: String) -> String? { season(label.isEmpty ? nil : label) }

    /// Whether anybody plays for the team on THRØ, read off its front. Nil while it is being read.
    static func onThro(_ front: TeamFront?) -> String? {
        guard let front else { return nil }
        if front.yourRole != nil { return "You play for it on THRØ." }
        let n = front.roster.count
        if n == 0 { return "Nobody plays for it on THRØ yet." }
        let who = "\(n) of its players \(n == 1 ? "is" : "are") on THRØ"
        // And on whose say-so it is run: a listed team is taken on by one of its own players (PD-047),
        // never appointed by the league, and the board says which it is.
        return front.adopted == true ? "\(who), run by one of them, by their own say." : "\(who)."
    }

    /// Under a league's name: "Thursday nights · Stockton-on-Tees · 18 teams in 1 division · 3.2 mi".
    static func leagueMeta(_ league: PublicLeague, teams: Int, divisions: Int, distance: String?) -> String {
        let spread = teams == 0 ? "no teams listed yet" : "\(count(teams, "team")) in \(count(divisions, "division"))"
        return [league.playsOn.map { "\($0) nights" }, league.locality, spread, distance].compactMap { $0 }.joined(separator: " · ")
    }

    static func count(_ n: Int, _ noun: String) -> String { "\(n) \(noun)\(n == 1 ? "" : "s")" }
}

// MARK: - pieces

/// A league's chalk, as a dot beside its name.
struct ChalkDot: View {
    let chalk: Int
    var body: some View {
        Circle().fill(LeagueChalk.color(chalk)).frame(width: 10, height: 10).accessibilityHidden(true)
    }
}

/// A worded chalk key on the drawer: DIRECTIONS, ITS PAGE, ITS WEBSITE.
struct DrawerKey: View {
    let title: String
    var lit = false
    var seed: Double = 71
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Text(title)
                .thro(ThroTypography.labelStrong.uppercase(true).tracking(em: 0.06))
                .foregroundStyle(ThroColor.colorTextOnBoard)
                .padding(.horizontal, ThroSpacing.spacing4)
        }
        .buttonStyle(ChalkKeyStyle(lit ? .lit : .field, minHeight: ThroSpacing.touchTargetMinimum, seedAngle: seed))
    }
}

/// The cross in a card's corner.
struct DrawerClose: View {
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Icon(.x, size: 18).foregroundStyle(ThroColor.colorTextOnBoardSecondary).throTapTarget()
        }
        .buttonStyle(ThroPressStyle(radius: 22, pressedFill: ThroColor.colorBoardSunken))
        .accessibilityLabel("Close")
    }
}

/// A team in a list on the board: its chalk, its name, and under it either its league line in that
/// chalk or, among its own division, its pub.
struct LeagueTeamRow: View {
    let entry: LeagueAtlas.Entry
    var showsLeague = true
    var trailing: String?
    let action: () -> Void

    /// Under a team among its own division: its pub — or, where the team is named for its pub (the
    /// Starting Gate, at the Starting Gate), the pub's town, since the pub's name would say it twice.
    static func pubUnder(_ e: LeagueAtlas.Entry) -> String {
        guard let venue = e.venue else { return "Its pub is not known yet" }
        func plain(_ s: String) -> String {
            let folded = LeagueAtlas.fold(s)
            return (folded.hasPrefix("the ") ? String(folded.dropFirst(4)) : folded).filter { $0.isLetter || $0.isNumber }
        }
        guard plain(venue.name) == plain(e.team.name) else { return venue.name }
        return venue.locality ?? venue.name
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: ThroSpacing.spacing3) {
                ChalkDot(chalk: entry.chalk)
                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.team.name)
                        .thro(ThroTypography.bodyLarge.weight(.semibold))
                        .foregroundStyle(ThroColor.colorTextOnBoard)
                        .lineLimit(1)
                    Text(showsLeague ? LeagueAtlas.line(entry) : LeagueTeamRow.pubUnder(entry))
                        .thro(ThroTypography.label)
                        .foregroundStyle(showsLeague ? LeagueChalk.color(entry.chalk) : ThroColor.colorTextOnBoardSecondary)
                        .lineLimit(1)
                }
                Spacer(minLength: ThroSpacing.spacing2)
                if let trailing {
                    Text(trailing)
                        .thro(ThroTypography.label.family(.sport))
                        .foregroundStyle(ThroColor.colorTextOnBoardSecondary)
                }
                Icon(.chevronRight, size: 16).foregroundStyle(ThroColor.colorTextOnBoardSecondary)
            }
            .padding(.vertical, ThroSpacing.spacing2)
            .frame(minHeight: ThroSpacing.touchTargetMinimum)
            .throRowTapTarget()
        }
        .buttonStyle(ThroPressStyle(radius: ThroSpacing.radiusCard, pressedFill: ThroColor.colorBoardSunken, scales: false))
    }
}

/// A pub or a league in a list on the board: its pin, its name, one line.
struct LeaguePlaceRow: View {
    let pin: BoardPin
    let name: String
    let line: String
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack(spacing: ThroSpacing.spacing3) {
                pin
                VStack(alignment: .leading, spacing: 2) {
                    Text(name).thro(ThroTypography.bodyLarge.weight(.semibold)).foregroundStyle(ThroColor.colorTextOnBoard).lineLimit(1)
                    Text(line).thro(ThroTypography.label).foregroundStyle(ThroColor.colorTextOnBoardSecondary).lineLimit(1)
                }
                Spacer(minLength: ThroSpacing.spacing2)
                Icon(.chevronRight, size: 16).foregroundStyle(ThroColor.colorTextOnBoardSecondary)
            }
            .padding(.vertical, ThroSpacing.spacing2)
            .frame(minHeight: ThroSpacing.touchTargetMinimum)
            .throRowTapTarget()
        }
        .buttonStyle(ThroPressStyle(radius: ThroSpacing.radiusCard, pressedFill: ThroColor.colorBoardSunken, scales: false))
    }
}

/// A card's head: an eyebrow, the close cross, the name large, one line under it.
struct DrawerHead: View {
    let eyebrow: String
    var eyebrowColor = ThroColor.colorTextOnBoardSecondary
    var chalk: Int?
    let title: String
    var large = false
    let line: String
    let onClose: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: ThroSpacing.spacing1) {
            HStack(alignment: .center, spacing: ThroSpacing.spacing2) {
                if let chalk { ChalkDot(chalk: chalk) }
                Eyebrow(eyebrow, color: eyebrowColor).lineLimit(1)
                Spacer(minLength: 0)
                DrawerClose(action: onClose)
            }
            Text(title)
                .thro((large ? ThroTypography.display : ThroTypography.heading1).family(.sport).weight(.bold).tracking(em: 0))
                .foregroundStyle(ThroColor.colorTextOnBoard)
                .lineLimit(2)
                .minimumScaleFactor(0.6)
            Text(line)
                .thro(ThroTypography.body)
                .foregroundStyle(ThroColor.colorTextOnBoardSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: - cards

/// A pub: who plays there, in which league, and the way there.
struct LeaguePubCard: View {
    let venue: PublicLeague.Venue
    let teams: [LeagueAtlas.Entry]
    let distance: String?
    let onTeam: (UUID) -> Void
    let onDirections: () -> Void
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: ThroSpacing.spacing3) {
            DrawerHead(eyebrow: teams.count == 1 ? "One team plays here" : "\(teams.count) teams play here",
                       title: venue.name, line: [venue.locality, venue.postcode, distance].compactMap { $0 }.joined(separator: " · "),
                       onClose: onClose)
            VStack(spacing: 0) {
                ForEach(teams) { e in LeagueTeamRow(entry: e) { onTeam(e.id) } }
            }
            if venue.basis?.hasPrefix("inferred") ?? false {
                Text("Matched to its teams by name. Tell THRØ if this is the wrong pub.")
                    .thro(ThroTypography.metadata).foregroundStyle(ThroColor.colorTextOnBoardSecondary)
            }
            DrawerKey(title: "Directions", lit: true, seed: 83, action: onDirections)
        }
    }
}

/// A team: its league and division in the league's chalk, where and when it plays, whether anyone
/// plays for it on THRØ, its division nearest first, and its page.
struct LeagueTeamCard: View {
    let entry: LeagueAtlas.Entry
    let rivals: [LeagueAtlas.Rival]
    let onThro: String?
    let distance: String?
    @Binding var allRivals: Bool
    let onRival: (UUID) -> Void
    let onPage: () -> Void
    let onDirections: (() -> Void)?
    let onJoin: (() -> Void)?
    /// Offered only for a listed team nobody runs, to somebody signed in (PD-047).
    let onAdopt: (() -> Void)?
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: ThroSpacing.spacing3) {
            DrawerHead(eyebrow: LeagueBoardWords.teamEyebrow(entry), eyebrowColor: LeagueChalk.color(entry.chalk),
                       chalk: entry.chalk, title: entry.team.name, large: true,
                       line: LeagueBoardWords.teamWhere(entry, distance: distance), onClose: onClose)
            if let onThro {
                Text(onThro).thro(ThroTypography.labelStrong).foregroundStyle(ThroColor.colorTextOnBoard)
            }
            if let onAdopt {
                DrawerKey(title: "It's my team — I'll run it", lit: true, seed: 53, action: onAdopt)
                Text("You become its admin and can give the side a code. The team's page will say it is run by one of its players, by their own say.")
                    .thro(ThroTypography.metadata)
                    .foregroundStyle(ThroColor.colorTextOnBoardSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            // The two things to do come before the division, so neither is below the drawer's fold.
            HStack(spacing: ThroSpacing.spacing3) {
                DrawerKey(title: "Its page", lit: true, seed: 71, action: onPage)
                if let onDirections { DrawerKey(title: "Directions", seed: 83, action: onDirections) }
            }
            if !rivals.isEmpty {
                Eyebrow(LeagueBoardWords.division(entry, teams: rivals.count + 1), color: ThroColor.colorTextOnBoardSecondary)
                    .padding(.top, ThroSpacing.spacing2)
                VStack(spacing: 0) {
                    ForEach(allRivals ? rivals : Array(rivals.prefix(3))) { r in
                        LeagueTeamRow(entry: r.entry, showsLeague: false,
                                      trailing: r.km.map(NearbyLogic.miles) ?? "not on the map") { onRival(r.id) }
                    }
                    if rivals.count > 3 {
                        Button { allRivals.toggle() } label: {
                            Text(allRivals ? "The nearest three" : "All \(rivals.count) others in the division")
                                .thro(ThroTypography.labelStrong)
                                .foregroundStyle(LeagueChalk.color(entry.chalk))
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .throTapTarget(.leading)
                        }
                        .buttonStyle(ThroPressStyle(radius: ThroSpacing.radiusCard, pressedFill: ThroColor.colorBoardSunken, scales: false))
                    }
                }
            }
            if let onJoin {
                Button(action: onJoin) {
                    Text("Got your captain's team code? Join with it")
                        .thro(ThroTypography.labelStrong)
                        .foregroundStyle(ThroColor.colorTextOnBoardSecondary)
                        .frame(maxWidth: .infinity)
                        .throTapTarget()
                }
                .buttonStyle(ThroPressStyle(radius: ThroSpacing.radiusCard, pressedFill: ThroColor.colorBoardSunken, scales: false))
            }
        }
    }
}

/// A league with teams: its divisions, each a row of its teams to touch, and where it came from.
struct LeagueSummaryCard: View {
    let league: PublicLeague
    let chalk: Int
    let divisions: [LeagueAtlas.Division]
    /// Teams that said they play here (PD-049), under their own heading and never in a division.
    var said: [LeagueAtlas.Entry] = []
    let distance: String?
    let onTeam: (UUID) -> Void
    /// Opens the league's table for a season (PD-054). Defaulted, so a board that has no table to show —
    /// a build with no server behind it — builds this card exactly as it did before.
    var onTable: (UUID) -> Void = { _ in }
    let onClose: () -> Void

    var body: some View {
        let teams = divisions.reduce(0) { $0 + $1.teams.count }
        VStack(alignment: .leading, spacing: ThroSpacing.spacing3) {
            DrawerHead(eyebrow: ["League", LeagueBoardWords.season(league.shownSeason?.label)].compactMap { $0 }.joined(separator: " · "),
                       eyebrowColor: LeagueChalk.color(chalk), chalk: chalk, title: league.name,
                       line: LeagueBoardWords.leagueMeta(league, teams: teams, divisions: divisions.count, distance: distance),
                       onClose: onClose)
            // The table is the thing a league member came for, so it is on the league's own card rather
            // than a screen further in (PD-054).
            if let season = league.shownSeason {
                Button { onTable(season.leagueSeasonId) } label: {
                    Text("TABLE").thro(ThroTypography.labelStrong.uppercase(true).tracking(em: 0.06))
                        .foregroundStyle(ThroColor.colorTextOnBoard)
                        .padding(.horizontal, ThroSpacing.spacing4)
                }
                .buttonStyle(ChalkKeyStyle(.lit, minHeight: ThroSpacing.touchTargetMinimum, seedAngle: 53))
                .fixedSize()
            }
            ForEach(divisions) { d in
                VStack(alignment: .leading, spacing: ThroSpacing.spacing2) {
                    if divisions.count > 1 { Eyebrow(d.name, color: ThroColor.colorTextOnBoardSecondary) }
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: ThroSpacing.spacing2) {
                            ForEach(d.teams) { e in teamChip(e) }
                        }
                        .padding(.vertical, 2)
                    }
                    .scrollClipDisabled()
                }
            }
            if !said.isEmpty {
                VStack(alignment: .leading, spacing: ThroSpacing.spacing2) {
                    Eyebrow("Said by their players", color: ThroColor.colorTextOnBoardSecondary)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: ThroSpacing.spacing2) {
                            ForEach(said) { e in teamChip(e) }
                        }
                        .padding(.vertical, 2)
                    }
                    .scrollClipDisabled()
                }
            }
            Text(LeaguesPlot.provenance(league))
                .thro(ThroTypography.metadata).foregroundStyle(ThroColor.colorTextOnBoardSecondary)
                .fixedSize(horizontal: false, vertical: true)
            if !said.isEmpty {
                Text("The teams under *said by their players* put themselves there. The league did not list them.")
                    .thro(ThroTypography.metadata).foregroundStyle(ThroColor.colorTextOnBoardSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func teamChip(_ e: LeagueAtlas.Entry) -> some View {
        Button { onTeam(e.id) } label: {
            Text(e.team.name)
                .thro(ThroTypography.labelStrong)
                .foregroundStyle(ThroColor.colorTextOnBoard)
                .lineLimit(1)
                .padding(.horizontal, ThroSpacing.spacing3)
                .frame(minHeight: ThroSpacing.touchTargetMinimum)
                .background(ThroColor.colorBoardField)
                .overlay(ChalkBox(weight: 2, seedAngle: Double(abs(e.id.hashValue % 90))).fill(LeagueChalk.color(chalk)))
                .contentShape(Rectangle())
        }
        .buttonStyle(ThroPressStyle(radius: 0))
    }
}

/// A league placed by its own point, with no teams on THRØ: where it is, and that it fills in.
struct BareLeagueCard: View {
    let league: PublicLeague
    let distance: String?
    let onWebsite: (() -> Void)?
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: ThroSpacing.spacing3) {
            DrawerHead(eyebrow: "League · no teams on THRØ yet", title: league.name,
                       line: LeagueBoardWords.leagueMeta(league, teams: 0, divisions: 0, distance: distance), onClose: onClose)
            Text("Placed where the league lists itself. Its teams and pubs are not on THRØ yet — if you play in it, tell THRØ and it fills in.")
                .thro(ThroTypography.body).foregroundStyle(ThroColor.colorTextOnBoard)
                .fixedSize(horizontal: false, vertical: true)
            if let onWebsite { DrawerKey(title: "Its website", lit: true, seed: 83, action: onWebsite) }
        }
    }
}
