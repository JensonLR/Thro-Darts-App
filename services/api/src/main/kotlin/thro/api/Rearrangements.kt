package thro.api

import java.sql.Connection
import java.time.Duration
import java.time.Instant
import java.time.ZoneId
import java.util.UUID
import thro.authz.ObjectRef
import thro.authz.ObjectType
import thro.competition.SubmissionState

/**
 * Moving a fixture by agreement (PD-108): the HTTP shape over the Secretary's rearrangement proposals.
 *
 * **What was there.** `Secretary.proposeRearrangement` carried one team's proposed date to the other as a delivered
 * submission and an open task of theirs; the opponent's answer went through the same state machine as every other
 * submission; and `applyProposal` moved the fixture through the one command every rearrangement goes through, so the
 * change log names the proposal. All of it reachable from a test and from nothing else; on the wire, the only way to
 * move a fixture was the organiser's `RearrangeFixture` command, which asks nobody.
 *
 * **A proposal is not a move.** A team proposes; the opponent agrees or declines; the league applies what was agreed.
 * Until it does, the fixture stands where it was — the league's fixture list, not a team's, is the record.
 */
public class Rearrangements(private val connection: Connection, private val now: () -> Instant = Instant::now) {

    public class Refused(public val why: String, public val status: Int) : Exception(why)

    /** How long the opponent has to answer, unless the fixture itself comes first. */
    private val answerWindow: Duration = Duration.ofDays(7)
    private val london = ZoneId.of("Europe/London")
    private val rel get() = Relations(connection)
    private val sec get() = Secretary(connection)

    private fun runsSeason(by: UUID, season: UUID) =
        rel.decide(by, "league_season.administer", ObjectRef(ObjectType.LEAGUE_SEASON, season.toString())).allowed
    private fun runsTeam(by: UUID, team: UUID) =
        rel.decide(by, "team.manage", ObjectRef(ObjectType.TEAM, team.toString())).allowed

    private data class FixtureRow(val season: UUID, val home: UUID, val away: UUID, val at: Instant, val version: Int,
                                  val seasonStarts: java.time.LocalDate, val seasonEnds: java.time.LocalDate)

    private fun fixture(fixtureId: UUID): FixtureRow? = connection.prepareStatement(
        """SELECT f.league_season_id, f.home_team_id, f.away_team_id, f.scheduled_at, f.row_version, s.starts_on, s.ends_on
             FROM competition.league_fixture f JOIN competition.league_season s ON s.league_season_id = f.league_season_id
            WHERE f.fixture_id = ?""",
    ).use { ps ->
        ps.setObject(1, fixtureId)
        ps.executeQuery().use { rs ->
            if (!rs.next()) null
            else FixtureRow(rs.getObject(1) as UUID, rs.getObject(2) as UUID, rs.getObject(3) as UUID, rs.getTimestamp(4).toInstant(), rs.getInt(5),
                            rs.getObject(6, java.time.LocalDate::class.java), rs.getObject(7, java.time.LocalDate::class.java))
        }
    }

    public data class Proposal(
        val proposalId: UUID, val fixtureId: UUID, val state: String, val to: Instant, val reason: String?,
        val byTeamId: UUID, val byTeam: String, val toTeamId: UUID, val toTeam: String, val createdAt: Instant, val answeredAt: Instant?,
        val scheduledAt: Instant, val fixtureVersion: Int, val leagueSeasonId: UUID,
    )

    private fun proposals(where: String, id: UUID): List<Proposal> = connection.prepareStatement(
        """SELECT p.proposal_id, p.fixture_id, p.state, p.proposed_at, p.reason, p.proposed_by_team_id, b.name, p.to_team_id, t.name,
                  p.created_at, p.answered_at, f.scheduled_at, f.row_version, f.league_season_id
             FROM competition.fixture_rearrangement_proposal p
             JOIN competition.league_fixture f ON f.fixture_id = p.fixture_id
             JOIN competition.team b ON b.team_id = p.proposed_by_team_id
             JOIN competition.team t ON t.team_id = p.to_team_id
            WHERE $where ORDER BY p.created_at DESC""",
    ).use { ps ->
        ps.setObject(1, id)
        ps.executeQuery().use { rs ->
            generateSequence {
                if (!rs.next()) null
                else Proposal(rs.getObject(1) as UUID, rs.getObject(2) as UUID, rs.getString(3), rs.getTimestamp(4).toInstant(), rs.getString(5),
                              rs.getObject(6) as UUID, rs.getString(7), rs.getObject(8) as UUID, rs.getString(9),
                              rs.getTimestamp(10).toInstant(), rs.getTimestamp(11)?.toInstant(), rs.getTimestamp(12).toInstant(), rs.getInt(13), rs.getObject(14) as UUID)
            }.toList()
        }
    }

    private fun one(proposalId: UUID): Proposal = proposals("p.proposal_id = ?", proposalId).firstOrNull() ?: throw Refused("THRØ has no such proposal.", 404)

    // --- one team proposes ------------------------------------------------------------------------------------------

    public fun propose(fixtureId: UUID, teamId: UUID, to: Instant, reason: String?, by: UUID): Proposal {
        val f = fixture(fixtureId) ?: throw Refused("THRØ has no such fixture.", 404)
        if (teamId != f.home && teamId != f.away) throw Refused("That team is not in this fixture.", 403)
        if (!runsTeam(by, teamId)) throw Refused("Only whoever runs the team proposes a date for it.", 403)
        val day = to.atZone(london).toLocalDate()
        if (day.isBefore(f.seasonStarts) || day.isAfter(f.seasonEnds)) throw Refused("The new date must fall inside the season, ${f.seasonStarts} to ${f.seasonEnds}.", 400)
        if (!to.isAfter(now())) throw Refused("The new date is in the past.", 400)
        if (proposals("p.fixture_id = ? AND p.state = 'proposed'", fixtureId).isNotEmpty()) throw Refused("A proposal for this fixture is already waiting for an answer.", 409)
        val due = minOf(now().plus(answerWindow), f.at)
        val made = try { sec.proposeRearrangement(fixtureId, teamId, to, due, by, reason?.trim()?.takeIf { it.isNotEmpty() }) }
            catch (e: org.postgresql.util.PSQLException) { throw Refused("A proposal for this fixture is already waiting for an answer.", 409) }
        return one(made.proposalId)
    }

    // --- both teams and the league read -----------------------------------------------------------------------------

    public fun ofFixture(fixtureId: UUID, viewer: UUID): List<Proposal> {
        val f = fixture(fixtureId) ?: throw Refused("THRØ has no such fixture.", 404)
        val teams = Teams(connection)
        val may = runsSeason(viewer, f.season) || teams.roleOf(viewer, f.home) != null || teams.roleOf(viewer, f.away) != null
        if (!may) throw Refused("A fixture's proposals are for its two teams and its league.", 403)
        return proposals("p.fixture_id = ?", fixtureId)
    }

    /** One proposal, for the same readers as its fixture's list. */
    public fun read(proposalId: UUID, viewer: UUID): Proposal {
        val p = one(proposalId)
        return ofFixture(p.fixtureId, viewer).first { it.proposalId == proposalId }
    }

    /** The season's open requests — proposed, or agreed and not yet applied — for the league that will apply them. */
    public fun openInSeason(season: UUID, by: UUID): List<Proposal> {
        if (!Fixtures(connection).seasonExists(season)) throw Refused("THRØ has no such league season.", 404)
        if (!runsSeason(by, season)) throw Refused("You do not administer this league season.", 403)
        return proposals("f.league_season_id = ? AND p.state IN ('proposed','accepted')", season)
    }

    // --- the opponent answers ---------------------------------------------------------------------------------------

    public fun answer(proposalId: UUID, answer: String, note: String?, by: UUID): Proposal {
        val p = one(proposalId)
        if (!runsTeam(by, p.toTeamId)) throw Refused("Only whoever runs the team the date was proposed to answers it.", 403)
        val to = when (answer) { "accepted" -> SubmissionState.ACCEPTED; "rejected", "declined" -> SubmissionState.REJECTED; else -> throw Refused("An answer is accepted or rejected.", 400) }
        if (to == SubmissionState.REJECTED && note.isNullOrBlank()) throw Refused("A refusal says why.", 400)
        if (p.state != "proposed") throw Refused("This proposal was already ${p.state}.", 409)
        val submission = connection.prepareStatement("SELECT submission_id FROM competition.submission WHERE proposal_id = ?")
            .use { ps -> ps.setObject(1, proposalId); ps.executeQuery().use { rs -> if (rs.next()) rs.getObject(1) as UUID else null } }
            ?: throw Refused("This proposal never reached the opponent.", 409)
        if (sec.submissionState(submission) == "delivered") {
            when (val m = sec.acknowledge(submission, by, note = "read on THRØ")) { is Secretary.Moved.Refused -> throw Refused(m.why, 409); is Secretary.Moved.Ok -> {} }
        }
        when (val m = sec.answer(submission, to, by, note = note?.trim() ?: "agreed on THRØ")) { is Secretary.Moved.Refused -> throw Refused(m.why, 409); is Secretary.Moved.Ok -> {} }
        return one(proposalId)
    }

    // --- the league applies -----------------------------------------------------------------------------------------

    public sealed interface Applied {
        public data class Moved(val proposal: Proposal, val version: Int) : Applied
        public data class Stale(val currentVersion: Int, val current: String) : Applied
    }

    public fun apply(proposalId: UUID, expectedVersion: Int, by: UUID, device: UUID): Applied {
        val p = one(proposalId)
        if (!runsSeason(by, p.leagueSeasonId)) throw Refused("Only the league applies an agreed date.", 403)
        if (p.state != "accepted") throw Refused("Only an accepted proposal is applied; this one is ${p.state}.", 409)
        return when (val r = sec.applyProposal(proposalId, by, device, expectedVersion)) {
            is OrganisationCommands.Result.Applied -> Applied.Moved(one(proposalId), r.version)
            is OrganisationCommands.Result.Stale -> Applied.Stale(r.currentVersion, r.current)
            is OrganisationCommands.Result.Refused -> throw Refused(r.why, 422)
            is OrganisationCommands.Result.Replayed -> throw Refused("That command was already applied.", 409)
        }
    }

    // --- words ------------------------------------------------------------------------------------------------------

    public fun json(p: Proposal): String {
        val q = thro.api.http.Contract::q
        return """{"proposalId":"${p.proposalId}","fixtureId":"${p.fixtureId}","leagueSeasonId":"${p.leagueSeasonId}","state":${q(p.state)},"to":"${p.to}",""" +
            """"reason":${p.reason?.let(q) ?: "null"},"byTeamId":"${p.byTeamId}","byTeam":${q(p.byTeam)},"toTeamId":"${p.toTeamId}","toTeam":${q(p.toTeam)},""" +
            """"proposedAt":"${p.createdAt}","answeredAt":${p.answeredAt?.let { "\"$it\"" } ?: "null"},"scheduledAt":"${p.scheduledAt}","fixtureVersion":${p.fixtureVersion}}"""
    }

    public fun json(list: List<Proposal>): String = """{"proposals":[${list.joinToString(",") { json(it) }}]}"""
}
