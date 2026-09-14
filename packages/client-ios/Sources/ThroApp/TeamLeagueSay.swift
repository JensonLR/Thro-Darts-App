import SwiftUI
import ThroDesign
import ThroNet
import ThroTokens

// What a team says about which league it plays in (PD-049), on the team's own page.
//
// THRØ lists 329 leagues and three of them have teams, because teams come from a league's own published
// pages and those pages are closed to a reader that gives its own name (PD-048). This is the other
// direction: the side says where it plays, and the map fills from the people who play there.
//
// It is said as a say. The rows here never sit under the league's own listing on this page — that is the
// *Playing in* list above, which comes from the league — and the note under them says which is which.

/// The say, and the way to make one. Holds its own picker, so the team's page drops it in as one line.
struct TeamLeagueSay: View {
    @ObservedObject var teams: TeamsModel
    let front: TeamFront
    let api: ThroAPI?

    @State private var choosing = false

    private var said: [TeamFront.LeagueSaid] { front.saysItPlaysIn ?? [] }
    private var runsIt: Bool { TeamFrontScreen.runsIt(front.yourRole) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if !said.isEmpty {
                Eyebrow("The team says it plays in").padding(.top, ThroSpacing.spacing3)
                ThroDivider().padding(.top, ThroSpacing.spacing2)
                ForEach(said) { league in
                    HStack(alignment: .firstTextBaseline, spacing: ThroSpacing.spacing3) {
                        Text(league.name)
                            .thro(ThroTypography.bodyLarge.weight(.semibold))
                            .foregroundStyle(ThroColor.colorTextPrimary)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: ThroSpacing.spacing2)
                        if runsIt {
                            ThroTextButton("Not any more", tone: .quiet, alignment: .trailing) {
                                Task { await teams.stopsSayingItPlaysIn(front.teamId, league: league.leagueId, api) }
                            }
                        }
                    }
                    .padding(.vertical, ThroSpacing.spacing3)
                    ThroDivider()
                }
                Note("Said by the team, not listed by the league. A league's own divisions come from its own pages.")
                    .padding(.top, ThroSpacing.spacing3)
            }
            if runsIt {
                ThroButton(said.isEmpty ? "Say which league you play in" : "Say another league",
                           variant: .secondary, size: .large, fullWidth: true) { choosing = true }
                    .padding(.top, ThroSpacing.spacing4)
            }
        }
        .sheet(isPresented: $choosing) {
            LeagueSayPicker(teams: teams, front: front, api: api, onDone: { choosing = false })
        }
    }
}

/// Which league. Every league THRØ lists, found by name — there are hundreds, so it is a search and not
/// a list, and the ones already said are marked rather than hidden, so nobody wonders where theirs went.
struct LeagueSayPicker: View {
    @ObservedObject var teams: TeamsModel
    let front: TeamFront
    let api: ThroAPI?
    let onDone: () -> Void

    @State private var leagues: Nearby.Loading<[PublicLeague]> = .loading
    @State private var query = ""
    @State private var saying: UUID?

    var body: some View {
        VStack(spacing: 0) {
            TopBar("Which league?", eyebrow: front.name, onBack: onDone)
            ScrollView {
                VStack(alignment: .leading, spacing: ThroSpacing.spacing3) {
                    ThroTextField("Find your league", text: $query, placeholder: "Stockton, Redcar, Billingham")
                        .autocorrectionDisabled()
                    switch leagues {
                    case .loading:
                        HStack(spacing: ThroSpacing.spacing2) {
                            ProgressView()
                            Text("Reading the leagues").thro(ThroTypography.body).foregroundStyle(ThroColor.colorTextSecondary)
                        }
                        .padding(.vertical, ThroSpacing.spacing4)
                    case .failed(let why):
                        Text(why).thro(ThroTypography.body).foregroundStyle(ThroColor.colorTextSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    case .loaded(let list):
                        results(list)
                    }
                    if let note = teams.note {
                        Snackbar(note, tone: .error)
                    }
                    Note("Saying it puts your team on that league's map, marked as your own say. It does not enter you into the league — that is between the side and its secretary.")
                        .padding(.top, ThroSpacing.spaceSectionGap)
                }
                .padding(.horizontal, ThroSpacing.spaceScreenGutter)
                .padding(.vertical, ThroSpacing.spacing5)
                .throReadable()
            }
        }
        .background(ThroColor.colorBackgroundPrimary.ignoresSafeArea())
        .task {
            guard case .loading = leagues else { return }
            guard let api else { leagues = .failed("This build names no server."); return }
            do { leagues = .loaded(try await api.leagues()) } catch { leagues = .failed(LeaguesModel.explain(error)) }
        }
    }

    @ViewBuilder private func results(_ list: [PublicLeague]) -> some View {
        let hits = LeagueAtlas.leaguesNamed(query, in: list, limit: 12)
        if query.trimmingCharacters(in: .whitespaces).count < 2 {
            Text("\(list.count) leagues are listed. Type two letters of yours.")
                .thro(ThroTypography.body).foregroundStyle(ThroColor.colorTextSecondary)
        } else if hits.isEmpty {
            Text("No league listed by that name. If yours is missing, tell THRØ and it goes on the map.")
                .thro(ThroTypography.body).foregroundStyle(ThroColor.colorTextSecondary)
                .fixedSize(horizontal: false, vertical: true)
        } else {
            ThroDivider()
            ForEach(hits) { league in
                let already = (front.saysItPlaysIn ?? []).contains { $0.leagueId == league.id }
                Button {
                    guard !already else { return }
                    saying = league.id
                    Task {
                        await teams.saysItPlaysIn(front.teamId, league: league.id, api)
                        saying = nil
                        if teams.note == nil { onDone() }
                    }
                } label: {
                    HStack(spacing: ThroSpacing.spacing3) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(league.name)
                                .thro(ThroTypography.bodyLarge.weight(.semibold))
                                .foregroundStyle(ThroColor.colorTextPrimary)
                                .multilineTextAlignment(.leading)
                            Text(LeagueBoardWords.leagueMeta(league, teams: league.shownSeason?.divisions.flatMap(\.teams).count ?? 0,
                                                             divisions: league.shownSeason?.divisions.count ?? 0, distance: nil))
                                .thro(ThroTypography.label)
                                .foregroundStyle(ThroColor.colorTextSecondary)
                                .multilineTextAlignment(.leading)
                        }
                        Spacer(minLength: ThroSpacing.spacing2)
                        if already {
                            Tag("Said", tone: .success)
                        } else if saying == league.id {
                            ProgressView()
                        } else {
                            Icon(.chevronRight, size: 18).foregroundStyle(ThroColor.colorTextSecondary)
                        }
                    }
                    .padding(.vertical, ThroSpacing.spacing3)
                    .throRowTapTarget()
                }
                .buttonStyle(ThroPressStyle(radius: ThroSpacing.radiusCard, pressedFill: ThroColor.colorSurfaceSecondary, scales: false))
                ThroDivider()
            }
        }
    }
}
