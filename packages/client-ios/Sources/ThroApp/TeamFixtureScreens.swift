import SwiftUI
import ThroDesign
import ThroNet
import ThroTokens

// A team's fixtures, and one fixture as the team lives it (PD-106).
//
// **What was missing.** The league's half of a fixture was on the web — schedule it, enter the result, read the table —
// and the team's half was two commands on the wire that no screen sent and nothing read back. A player could join a
// team on THRØ and never see when it was playing; a captain could not say who was in. These two screens are that half:
// the fixtures a side is playing, and for each one who can play, who is picked, and the match it was scored in.

/// The season's fixtures for one team, from the public list: to play first, then played.
public struct TeamFixturesScreen: View {
    private let api: ThroAPI
    private let teamId: UUID
    private let teamName: String
    private let season: TeamFront.SeasonLine
    private let onBack: () -> Void

    @State private var fixtures: [LeagueFixtures.Fixture]?
    @State private var problem: String?
    @State private var open: LeagueFixtures.Fixture?

    public init(api: ThroAPI, teamId: UUID, teamName: String, season: TeamFront.SeasonLine, onBack: @escaping () -> Void) {
        self.api = api; self.teamId = teamId; self.teamName = teamName; self.season = season; self.onBack = onBack
    }

    public var body: some View {
        if let open {
            TeamFixtureScreen(api: api, teamId: teamId, fixture: open, onBack: { self.open = nil })
        } else {
            list
        }
    }

    private var list: some View {
        VStack(spacing: 0) {
            TopBar(season.league, eyebrow: [season.label, season.division].compactMap { $0 }.joined(separator: " · "), onBack: onBack)
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    if let problem {
                        ErrorState(title: "The fixtures could not be read", what: problem, safe: "Nothing on this phone is affected.",
                                   todo: "Try again when you are online.", actionLabel: "Try again") { Task { await load() } }
                    } else if let fixtures {
                        let ours = fixtures.filter { $0.involves(teamId) }
                        // The list opens where the reader is (PD-153). "To play" ran as one flat column
                        // from the first unplayed fixture of the season, so a captain in March scrolled
                        // past five months of settled nights to reach this week's. A fixture whose night
                        // has gone and whose result nobody has entered is not "to play" either — it is the
                        // thing most likely to be why they opened the screen, and it now sits at the top
                        // under its own heading rather than buried in date order among games months away.
                        let now = Date()
                        let undecided = ours.filter { $0.decided == nil }
                        let overdue = undecided.filter { $0.scheduledAt < now }.sorted { $0.scheduledAt > $1.scheduledAt }
                        let toPlay = undecided.filter { $0.scheduledAt >= now }.sorted { $0.scheduledAt < $1.scheduledAt }
                        let played = ours.filter { $0.decided != nil }.reversed()
                        if ours.isEmpty {
                            Text(season.accepted == false
                                 ? "The league has not let \(teamName) in yet. Its fixtures appear here when it does."
                                 : "No fixtures for \(teamName) yet. The league adds them, and they appear here.")
                                .thro(ThroTypography.body).foregroundStyle(ThroColor.colorTextSecondary)
                                .fixedSize(horizontal: false, vertical: true).padding(.top, ThroSpacing.spacing4)
                        }
                        if !overdue.isEmpty {
                            SectionHeader("Waiting on a result", meta: "\(overdue.count)").padding(.top, ThroSpacing.spacing4)
                            ThroDivider().padding(.top, ThroSpacing.spacing2)
                            ForEach(overdue) { f in row(f) }
                        }
                        if !toPlay.isEmpty {
                            SectionHeader("To play", meta: "\(toPlay.count)")
                                .padding(.top, overdue.isEmpty ? ThroSpacing.spacing4 : ThroSpacing.spaceSectionGap)
                            ThroDivider().padding(.top, ThroSpacing.spacing2)
                            ForEach(toPlay) { f in row(f) }
                        }
                        if !played.isEmpty {
                            SectionHeader("Played", meta: "\(played.count)").padding(.top, ThroSpacing.spaceSectionGap)
                            ThroDivider().padding(.top, ThroSpacing.spacing2)
                            ForEach(Array(played)) { f in row(f) }
                        }
                    } else {
                        Text("One moment…").thro(ThroTypography.body).foregroundStyle(ThroColor.colorTextSecondary).padding(.top, ThroSpacing.spacing4)
                    }
                }
                .padding(.horizontal, ThroSpacing.spaceScreenGutter)
                .padding(.bottom, ThroSpacing.spacing6)
            }
        }
        .task { if fixtures == nil { await load() } }
    }

    private func row(_ f: LeagueFixtures.Fixture) -> some View {
        let atHome = f.homeTeamId == teamId
        let opponent = (atHome ? f.away : f.home) ?? "A team"
        return Button { open = f } label: {
            VStack(alignment: .leading, spacing: ThroSpacing.spacing1) {
                HStack {
                    Text("\(atHome ? "v" : "at") \(opponent)").thro(ThroTypography.bodyLarge.weight(.semibold)).foregroundStyle(ThroColor.colorTextPrimary)
                    Spacer()
                    Text(TeamFixtureScreen.score(f, home: atHome)).thro(ThroTypography.body).foregroundStyle(ThroColor.colorTextSecondary)
                }
                Text(TeamFixtureScreen.when(f.scheduledAt) + (f.venue.map { " · \($0)" } ?? "") + (f.state == "rearranged" ? " · rearranged" : ""))
                    .thro(ThroTypography.metadata).foregroundStyle(ThroColor.colorTextSecondary)
            }
            .padding(.vertical, ThroSpacing.spacing3)
            .frame(minHeight: ThroSpacing.touchTargetMinimum)
            .throRowTapTarget()
        }
        .buttonStyle(ThroPressStyle(radius: ThroSpacing.radiusCard, pressedFill: ThroColor.colorSurfaceSecondary, scales: false))
        .accessibilityLabel("\(atHome ? "Home to" : "Away at") \(opponent), \(TeamFixtureScreen.when(f.scheduledAt))")
        .overlay(alignment: .bottom) { ThroDivider() }
    }

    private func load() async {
        guard let season = season.leagueSeasonId else { problem = "This season has no address on THRØ yet."; return }
        do { fixtures = try await api.fixtures(season: season).fixtures; problem = nil }
        catch { problem = ThroAPI.refusal(error) ?? "The fixtures could not be read just now." }
    }
}

/// One fixture: who can play, who is picked, and the match it was played in.
public struct TeamFixtureScreen: View {
    private let api: ThroAPI
    private let teamId: UUID
    private let fixture: LeagueFixtures.Fixture
    private let onBack: () -> Void

    @State private var view: TeamFixtureView?
    @State private var problem: String?
    @State private var note: String?
    @State private var busy = false
    @State private var picking = false
    @State private var picked: [UUID] = []
    @State private var citing = false
    @State private var matches: [MatchOnRecord]?
    @State private var proposals: [FixtureProposal]?
    @State private var proposing = false
    @State private var proposedDate = Date()
    @State private var proposedReason = ""
    @State private var said = ""
    @State private var reading = false
    @State private var readBack: String?
    @State private var proposedVenue: PublicLeague.Venue?
    @State private var venueQuery = ""
    @State private var venueHits: [PublicLeague.Venue] = []
    @State private var venueSaid: String?

    public init(api: ThroAPI, teamId: UUID, fixture: LeagueFixtures.Fixture, onBack: @escaping () -> Void) {
        self.api = api; self.teamId = teamId; self.fixture = fixture; self.onBack = onBack
    }

    public var body: some View {
        VStack(spacing: 0) {
            TopBar(opponentLine, eyebrow: Self.when(fixture.scheduledAt), onBack: onBack)
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    if let problem {
                        ErrorState(title: "The fixture could not be read", what: problem, safe: "Nothing on this phone is affected.",
                                   todo: "Try again when you are online.", actionLabel: "Try again") { Task { await load() } }
                    } else if let v = view {
                        loaded(v)
                    } else {
                        Text("One moment…").thro(ThroTypography.body).foregroundStyle(ThroColor.colorTextSecondary).padding(.top, ThroSpacing.spacing4)
                    }
                }
                .padding(.horizontal, ThroSpacing.spaceScreenGutter)
                .padding(.bottom, ThroSpacing.spacing6)
            }
        }
        .task { if view == nil { await load() } }
    }

    private var opponentLine: String {
        let atHome = fixture.homeTeamId == teamId
        return "\(atHome ? "v" : "at") \((atHome ? fixture.away : fixture.home) ?? "A team")"
    }

    @ViewBuilder private func loaded(_ v: TeamFixtureView) -> some View {
        let me = api.session?.playerId
        if let note {
            Note(note).padding(.top, ThroSpacing.spacing3)
        }
        // Where and what it finished as, if it has.
        VStack(alignment: .leading, spacing: ThroSpacing.spacing1) {
            if let venue = v.venue { Text(venue).thro(ThroTypography.body).foregroundStyle(ThroColor.colorTextSecondary) }
            if let d = fixture.decided {
                Text(Self.score(fixture, home: v.home) + " · " + (d.kind == "played" ? "scored on THRØ" : d.kind == "declared" ? "the league's word" : d.kind))
                    .thro(ThroTypography.body).foregroundStyle(ThroColor.colorTextPrimary)
            }
        }
        .padding(.top, ThroSpacing.spacing3)

        // You.
        if let me, let mine = v.member(me) {
            SectionHeader("Can you play?").padding(.top, ThroSpacing.spaceSectionGap)
            HStack(spacing: ThroSpacing.spacing2) {
                ForEach(["available", "maybe", "unavailable"], id: \.self) { status in
                    ThroButton(Self.availabilityLabel(status), variant: mine.availability == status ? .primary : .secondary, size: .medium) {
                        Task { await say(status, for: mine, in: v) }
                    }
                    .disabled(busy)
                }
            }
            .padding(.top, ThroSpacing.spacing2)
        }

        // The side.
        SectionHeader("The side", meta: "\(v.members.count)").padding(.top, ThroSpacing.spaceSectionGap)
        ThroDivider().padding(.top, ThroSpacing.spacing2)
        ForEach(v.members) { m in
            HStack(spacing: ThroSpacing.spacing3) {
                if picking {
                    let slot = picked.firstIndex(of: m.playerId)
                    Button { toggle(m.playerId) } label: {
                        Icon(slot == nil ? .circle : .circleCheck, size: 22)
                            .foregroundStyle(slot == nil ? ThroColor.colorTextSecondary : ThroColor.colorBackgroundBrand)
                            .throTapTarget()
                    }
                    .buttonStyle(ThroPressStyle(radius: ThroSpacing.radiusCard))
                    .accessibilityLabel(slot == nil ? "Pick \(m.name ?? "this player")" : "Drop \(m.name ?? "this player") from slot \(slot! + 1)")
                }
                PlayerIdentity(PlayerRef(name: m.name ?? "A player", unnamed: m.name == nil), size: .small)
                Spacer()
                if picking, let slot = picked.firstIndex(of: m.playerId) {
                    Text("\(slot + 1)").thro(ThroTypography.metadata).foregroundStyle(ThroColor.colorTextPrimary)
                } else if let slot = v.lineup.players.firstIndex(of: m.playerId) {
                    Text("Picked · \(slot + 1)").thro(ThroTypography.metadata).foregroundStyle(ThroColor.colorTextPrimary)
                } else {
                    Text(Self.availabilityLabel(m.availability)).thro(ThroTypography.metadata).foregroundStyle(ThroColor.colorTextSecondary)
                }
            }
            .padding(.vertical, ThroSpacing.spacing2)
            ThroDivider()
        }
        if v.mayNameLineup && fixture.decided == nil {
            if picking {
                HStack(spacing: ThroSpacing.spacing2) {
                    ThroButton("Name this side", variant: .primary, size: .medium) { Task { await name(in: v) } }.disabled(picked.isEmpty || busy)
                    ThroTextButton("Leave it", tone: .quiet) { picking = false }
                }
                .padding(.top, ThroSpacing.spacing3)
                Note("In the order tapped. Naming a side again replaces the last one; both stay on the record.").padding(.top, ThroSpacing.spacing2)
            } else {
                ThroButton(v.lineup.players.isEmpty ? "Pick the side" : "Change the side", variant: .secondary, size: .medium) {
                    picked = v.lineup.players; picking = true
                }
                .padding(.top, ThroSpacing.spacing3)
            }
        }

        // Moving it (PD-108): a proposal to the other team, and what has been proposed already.
        if fixture.decided == nil {
            SectionHeader("Moving it").padding(.top, ThroSpacing.spaceSectionGap)
            if let proposals {
                ForEach(proposals) { p in
                    Text(ProposalWords.line(p, viewing: teamId))
                        .thro(ThroTypography.metadata).foregroundStyle(ThroColor.colorTextSecondary).padding(.top, ThroSpacing.spacing2)
                    if p.state == "proposed" && p.byTeamId == teamId && v.mayNameLineup {
                        ThroTextButton("Take it back", tone: .quiet) { Task { await withdraw(p) } }.disabled(busy)
                    }
                }
                if proposals.isEmpty {
                    Note("Nobody has proposed another date.").padding(.top, ThroSpacing.spacing2)
                }
            }
            if v.mayNameLineup && !(proposals ?? []).contains(where: { $0.state == "proposed" }) {
                if proposing {
                    // Say it (PD-129): a sentence read into the date below. The form is still the form; this fills it.
                    ThroTextField("Say it", text: $said, placeholder: "the 22nd instead, the pub is shut")
                        .padding(.top, ThroSpacing.spacing2)
                    HStack(spacing: ThroSpacing.spacing2) {
                        ThroButton(reading ? "Reading…" : "Read it", variant: .secondary, size: .medium) { Task { await readIt(in: v) } }
                            .disabled(reading || said.trimmingCharacters(in: .whitespaces).count < 3)
                        if let readBack { Text(readBack).thro(ThroTypography.metadata).foregroundStyle(ThroColor.colorTextSecondary).fixedSize(horizontal: false, vertical: true) }
                    }
                    .padding(.top, ThroSpacing.spacing2)
                    Text("Read by a model at TypeSafe, with the two teams' names and nothing about you. Leave people's names out.")
                        .thro(ThroTypography.metadata).foregroundStyle(ThroColor.colorTextTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, ThroSpacing.spacing2)
                    DatePicker("New date", selection: $proposedDate, in: Date()...)
                        .thro(ThroTypography.body).foregroundStyle(ThroColor.colorTextPrimary).padding(.top, ThroSpacing.spacing2)
                    ThroTextField("Why?", text: $proposedReason, placeholder: "the pub is shut that night")
                        .padding(.top, ThroSpacing.spacing2)
                    // Somewhere else to play it (PD-128), picked from the venues THRØ holds so the other side can be told where.
                    if let chosen = proposedVenue {
                        HStack {
                            Text("At \(chosen.name)").thro(ThroTypography.body).foregroundStyle(ThroColor.colorTextPrimary)
                            Spacer()
                            ThroTextButton("Where it was", tone: .quiet, alignment: .trailing) { proposedVenue = nil; venueQuery = "" }
                        }
                        .frame(minHeight: ThroSpacing.touchTargetMinimum)
                    } else {
                        ThroTextField("Somewhere else? (optional)", text: $venueQuery, placeholder: "a pub or club by name")
                            .padding(.top, ThroSpacing.spacing3)
                            .onChange(of: venueQuery) { _, q in Task { await findVenues(q) } }
                        if let venueSaid {
                            // Said where it was typed: a search that could not run must not read as a pub
                            // THRØ does not hold (PD-137).
                            Note(venueSaid, icon: .info).padding(.top, ThroSpacing.spacing2)
                        }
                        ForEach(venueHits.prefix(4), id: \.venueId) { hit in
                            Button { proposedVenue = hit; venueHits = [] } label: {
                                HStack {
                                    Text([hit.name, hit.locality].compactMap { $0 }.joined(separator: " · ")).thro(ThroTypography.body).foregroundStyle(ThroColor.colorTextPrimary)
                                    Spacer()
                                    Icon(.chevronRight, size: 16).foregroundStyle(ThroColor.colorTextTertiary)
                                }
                                .frame(minHeight: ThroSpacing.touchTargetMinimum).throRowTapTarget()
                            }
                            .buttonStyle(ThroPressStyle(radius: ThroSpacing.radiusCard, pressedFill: ThroColor.colorSurfaceSecondary, scales: false))
                        }
                    }
                    HStack(spacing: ThroSpacing.spacing2) {
                        ThroButton("Propose it to \(v.opponent ?? "the other team")", variant: .primary, size: .medium) { Task { await propose(in: v) } }.disabled(busy)
                        ThroTextButton("Leave it", tone: .quiet) { proposing = false }
                    }
                    .padding(.top, ThroSpacing.spacing3)
                    Note("The other team agrees or declines from their inbox; the league applies what was agreed. Until then the fixture stands where it is.")
                        .padding(.top, ThroSpacing.spacing2)
                } else {
                    ThroButton("Propose another date", variant: .secondary, size: .medium) { proposedDate = v.scheduledAt; proposing = true }
                        .padding(.top, ThroSpacing.spacing3)
                }
            }
        }

        // The match it was played in.
        SectionHeader("On THRØ").padding(.top, ThroSpacing.spaceSectionGap)
        if v.matchId != nil {
            Note("This fixture names the match it was played in, so the league's result for it is read from the darts, not typed.")
                .padding(.top, ThroSpacing.spacing2)
        } else if v.mayNameLineup {
            Note("Scored this fixture on THRØ? Name the match, and the league's result for it becomes a played one rather than the organiser's word. Only somebody who played it may.")
                .padding(.top, ThroSpacing.spacing2)
            if citing {
                if let matches {
                    let finished = matches.filter { $0.winner != nil }
                    if finished.isEmpty {
                        Text("No finished match of yours on THRØ yet.").thro(ThroTypography.body).foregroundStyle(ThroColor.colorTextSecondary).padding(.top, ThroSpacing.spacing2)
                    }
                    ForEach(finished.prefix(10)) { m in
                        Button { Task { await cite(m.matchId) } } label: {
                            HStack {
                                Text(m.seats.map { $0.name ?? "A player" }.joined(separator: " v ")).thro(ThroTypography.body).foregroundStyle(ThroColor.colorTextPrimary)
                                Spacer()
                                Text(Self.when(m.openedAt)).thro(ThroTypography.metadata).foregroundStyle(ThroColor.colorTextSecondary)
                            }
                            .padding(.vertical, ThroSpacing.spacing2)
                            .frame(minHeight: ThroSpacing.touchTargetMinimum)
                            .throRowTapTarget()
                        }
                        .buttonStyle(ThroPressStyle(radius: ThroSpacing.radiusCard, pressedFill: ThroColor.colorSurfaceSecondary, scales: false))
                        .disabled(busy)
                        ThroDivider()
                    }
                } else {
                    Text("One moment…").thro(ThroTypography.body).foregroundStyle(ThroColor.colorTextSecondary)
                }
            } else {
                ThroButton("Name the match", variant: .secondary, size: .medium) { citing = true; Task { await loadMatches() } }
                    .padding(.top, ThroSpacing.spacing3)
            }
        } else {
            Note("Not scored on THRØ yet, as far as the league knows.").padding(.top, ThroSpacing.spacing2)
        }
    }

    // MARK: - acts

    private func load() async {
        do { view = try await api.teamFixture(fixture.fixtureId, team: teamId); problem = nil }
        catch { problem = ThroAPI.refusal(error) ?? "The fixture could not be read just now."; return }
        // The proposals are a second read; a fixture that loads without them is still a fixture.
        proposals = (try? await api.proposals(fixture: fixture.fixtureId)) ?? proposals
    }

    private func withdraw(_ p: FixtureProposal) async {
        busy = true; defer { busy = false }
        do {
            let gone = try await api.withdrawProposal(p.proposalId)
            proposals = (proposals ?? []).map { $0.proposalId == gone.proposalId ? gone : $0 }
            note = "Taken back. The fixture stands where it was."
        } catch { note = (error as? APIError)?.message ?? error.localizedDescription }
    }

    /// Reads the sentence and fills the form with it. Whatever comes back, the form below still works.
    private func readIt(in v: TeamFixtureView) async {
        reading = true; defer { reading = false }
        let text = said.trimmingCharacters(in: .whitespaces)
        do {
            let r = try await api.readMove(fixture: v.fixtureId, team: teamId, text: text)
            readBack = ProposalWords.read(r)
            if let to = ProposalWords.fills(r) {
                proposedDate = to
                proposedReason = ProposalWords.reason(from: text, existing: proposedReason)
            }
        } catch { readBack = ThroAPI.refusal(error) ?? "That could not be read just now. Pick the date below." }
    }

    /// The venues THRØ holds by that name. Two letters before it asks; the last answer wins.
    ///
    /// A search that could not be run is not a search that found nothing (PD-137). Swallowed, it told a
    /// captain THRØ does not hold their pub — and because applying a proposal leaves the venue alone when
    /// none is named, they would then have proposed a move with the pub silently unchanged.
    private func findVenues(_ query: String) async {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard q.count >= 2 else { venueHits = []; venueSaid = nil; return }
        do {
            let found = try await api.venues(matching: q)
            if q == venueQuery.trimmingCharacters(in: .whitespaces) { venueHits = found; venueSaid = nil }
        } catch {
            if q == venueQuery.trimmingCharacters(in: .whitespaces) {
                venueHits = []
                venueSaid = (error as? APIError)?.message ?? "Venues could not be searched just now."
            }
        }
    }

    private func propose(in v: TeamFixtureView) async {
        busy = true; defer { busy = false }
        do {
            let made = try await api.propose(fixture: v.fixtureId, team: teamId, to: proposedDate, reason: proposedReason.trimmingCharacters(in: .whitespaces),
                                             venue: proposedVenue?.venueId)
            proposing = false; proposedReason = ""; proposedVenue = nil; venueQuery = ""
            proposals = [made] + (proposals ?? [])
            note = "Proposed to \(made.toTeam). They answer from their inbox."
        } catch { note = (error as? APIError)?.message ?? error.localizedDescription }
    }

    private func loadMatches() async {
        do { matches = try await api.myMatches() } catch { note = ThroAPI.refusal(error) ?? "Your matches could not be read just now." }
    }

    private func say(_ status: String, for mine: TeamFixtureView.Member, in v: TeamFixtureView) async {
        busy = true; defer { busy = false }
        do {
            let r = try await api.setAvailability(fixture: v.fixtureId, team: teamId, player: mine.playerId, status: status, expectedVersion: mine.availabilityVersion)
            note = r.applied ? nil : (r.reason ?? "That did not go through. The side may have changed; it has been read again.")
            await load()
        } catch { note = ThroAPI.refusal(error) ?? "That could not be saved just now." }
    }

    private func toggle(_ player: UUID) {
        if let i = picked.firstIndex(of: player) { picked.remove(at: i) } else { picked.append(player) }
    }

    private func name(in v: TeamFixtureView) async {
        busy = true; defer { busy = false }
        do {
            let r = try await api.nameLineup(fixture: v.fixtureId, team: teamId, players: picked, expectedVersion: v.lineup.version)
            if r.applied { picking = false; note = nil } else { note = r.reason ?? "The side changed while you were picking it; it has been read again." }
            await load()
        } catch { note = ThroAPI.refusal(error) ?? "The side could not be named just now." }
    }

    private func cite(_ match: UUID) async {
        busy = true; defer { busy = false }
        do { try await api.cite(fixture: fixture.fixtureId, match: match); citing = false; note = nil; await load() }
        catch { note = ThroAPI.refusal(error) ?? "The match could not be named just now." }
    }

    // MARK: - words

    static func availabilityLabel(_ status: String?) -> String {
        switch status { case "available": return "Can play"; case "unavailable": return "Can't play"; case "maybe": return "Maybe"; default: return "Not said" }
    }

    static func score(_ f: LeagueFixtures.Fixture, home: Bool) -> String {
        guard let d = f.decided else { return f.annulled == nil ? "To play" : "Annulled" }
        if let lh = d.legsHome, let la = d.legsAway { return home ? "\(lh)–\(la)" : "\(la)–\(lh)" }
        if let toHome = d.awardedToHome { return (toHome == home) ? "Awarded to us" : "Awarded to them" }
        return d.kind
    }

    static func when(_ date: Date) -> String {
        let f = DateFormatter(); f.locale = Locale(identifier: "en_GB"); f.dateFormat = "EEE d MMM, HH:mm"
        return f.string(from: date)
    }
}


/// A proposal in words (PD-108, PD-128), apart from the screens so it is tested.
enum ProposalWords {
    /// "19 Nov 2026 at 19:30, at Grange Social Club", or the date alone when the place stays as it was. The comma is
    /// there because the date's own words end "at 19:30", and "at 19:30 at the club" trips over itself.
    static func what(_ p: FixtureProposal) -> String {
        RearrangementTaskActions.when(p.to) + (p.venue.map { ", at \($0.name)" } ?? "")
    }

    /// What was read, said back to be checked (PD-129) — or why nothing was, and where to go instead.
    static func read(_ r: MoveReading) -> String {
        r.ready ? "Read as \(r.say). Check it below, then propose it."
                : (r.say.hasSuffix(".") || r.say.hasSuffix("?") ? "\(r.say) Pick the date below." : "\(r.say). Pick the date below.")
    }

    /// The date a reading puts in the form: only one that is ready. A day outside the season is said and not filled in.
    static func fills(_ r: MoveReading) -> Date? { r.ready ? r.to : nil }

    /// The inbox card's sentence: who proposes what, instead of when, and why (PD-142).
    ///
    /// Lifted out of the view it was written in. PD-128 promised that the inbox card says the place, and
    /// nothing could check that promise while the sentence was assembled inside a `Text(...)` — an audit
    /// could name it and no test could reach it.
    static func card(_ p: FixtureProposal) -> String {
        "\(p.byTeam) proposes \(what(p)) instead of \(RearrangementTaskActions.when(p.scheduledAt))"
            + (p.reason.map { " — \($0)" } ?? "")
    }

    /// The agree button's label. It carries the place as well as the date, because this is the one line a
    /// captain reads before agreeing (PD-142).
    static func agree(_ p: FixtureProposal) -> String { "Agree to \(what(p))" }

    /// The reason the form takes after a sentence is read (PD-142): the captain's own words, unless they
    /// have already written a reason of their own, which is theirs and is left alone.
    static func reason(from sentence: String, existing: String) -> String {
        existing.trimmingCharacters(in: .whitespaces).isEmpty ? sentence : existing
    }

    /// The fixture screen's line: who proposed what, why, and where it stands for the team looking.
    static func line(_ p: FixtureProposal, viewing team: UUID) -> String {
        "\(p.byTeam) proposed \(what(p))" + (p.reason.map { " — \($0)" } ?? "") + " · "
            + (p.state == "proposed" ? (p.byTeamId == team ? "waiting for \(p.toTeam)" : "waiting for your answer — it is in your inbox")
                                     : RearrangementTaskActions.standing(p.state))
    }
}
