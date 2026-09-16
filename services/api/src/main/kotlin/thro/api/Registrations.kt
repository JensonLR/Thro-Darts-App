package thro.api

import java.sql.Connection
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId
import java.util.UUID
import thro.authz.ObjectRef
import thro.authz.ObjectType
import thro.competition.RegistrationPolicy
import thro.competition.SubmissionState
import thro.competition.Transport

/**
 * Registering players with a league run on THRØ (PD-107): the HTTP shape over the Secretary's domain.
 *
 * **What the domain already held, and what was missing.** `Secretary` reconciles a team against the league's approved
 * registration policy into tasks, assesses a task into what is missing and what a person must confirm, prepares a
 * submission, moves it through a state machine whose every transition needs the right mover and the right evidence,
 * and registers the player only on the league's answer — all held by `SecretaryTest`, and none of it reachable from
 * a phone or a browser. This is the reachable half: who may call what.
 *
 * **Sent is not accepted.** A submission to a league on THRØ is *delivered* the moment it is sent, because the league's
 * page is the delivery; it is *accepted* only when the season's administrator says so, from a date. Nothing here makes a
 * player registered except that answer.
 */
public class Registrations(private val connection: Connection, private val now: () -> Instant = Instant::now) {

    public class Refused(public val why: String, public val status: Int) : Exception(why)

    private val london = ZoneId.of("Europe/London")
    private val rel get() = Relations(connection)
    private val sec get() = Secretary(connection)

    private fun runsSeason(by: UUID, season: UUID) =
        rel.decide(by, "league_season.administer", ObjectRef(ObjectType.LEAGUE_SEASON, season.toString())).allowed
    private fun runsTeam(by: UUID, team: UUID) =
        rel.decide(by, "team.manage", ObjectRef(ObjectType.TEAM, team.toString())).allowed

    // --- the league says what a registration needs ------------------------------------------------------------

    public data class Policy(val policyId: UUID, val version: Int, val effectiveFrom: LocalDate, val approved: Boolean, val body: Map<String, Any?>)

    /**
     * Sets the season's registration policy: drafted and approved in one act by the season's administrator, in force
     * from today, superseding the one before it from yesterday. The body is read by the same strict parser the
     * Secretary executes, so a rule THRØ cannot execute is refused here rather than silently broken later.
     */
    public fun setPolicy(season: UUID, by: UUID, requires: List<String>, manual: List<String>, deadlineDays: Int?, closesOn: LocalDate?): Policy {
        if (!Fixtures(connection).seasonExists(season)) throw Refused("THRØ has no such league season.", 404)
        if (!runsSeason(by, season)) throw Refused("You do not administer this league season.", 403)
        val fields = LinkedHashMap<String, Any?>()
        fields["requires"] = requires
        if (manual.isNotEmpty()) fields["manual_requirements"] = manual
        when {
            closesOn != null -> fields["registration_closes_on"] = closesOn.toString()
            deadlineDays != null -> fields["deadline_days_before_first_fixture"] = deadlineDays
            else -> throw Refused("A registration policy says when registration closes: a date, or days before the first fixture.", 400)
        }
        try { RegistrationPolicy.parse(fields) } catch (e: IllegalArgumentException) { throw Refused(e.message ?: "That policy cannot be executed.", 400) }
        val today = now().atZone(london).toLocalDate()
        val orgs = Organisations(connection)
        val current = sec.registrationPolicy(season, today)
        val version = (connection.prepareStatement("SELECT coalesce(max(version), 0) FROM competition.policy WHERE league_season_id = ? AND kind = 'registration'")
            .use { ps -> ps.setObject(1, season); ps.executeQuery().use { rs -> rs.next(); rs.getInt(1) } }) + 1
        // The stored body is the parser's vocabulary, written the one way it reads: strings, a list of strings, a number.
        val q = thro.api.http.Contract::q
        val body = fields.entries.joinToString(",", "{", "}") { (k, v) ->
            q(k) + ":" + when (v) { is List<*> -> v.joinToString(",", "[", "]") { q(it.toString()) }; is Number -> v.toString(); else -> q(v.toString()) }
        }
        val wasAuto = connection.autoCommit
        connection.autoCommit = false
        try {
            // The old one ends today and the new one starts today: both are in force for the day, and the Secretary
            // reads the higher version, so a policy set twice in a day is the later one without an empty gap.
            if (current != null) orgs.supersedePolicy(current.first, today)
            val id = orgs.draftPolicy("league_season", season, "registration", version, today, body, by = by)
            orgs.approvePolicy(id, by = by)
            connection.commit()
            return Policy(id, version, today, true, fields)
        } catch (e: Exception) { connection.rollback(); throw e } finally { connection.autoCommit = wasAuto }
    }

    public fun policy(season: UUID, by: UUID): Policy? {
        if (!Fixtures(connection).seasonExists(season)) throw Refused("THRØ has no such league season.", 404)
        if (!runsSeason(by, season)) throw Refused("You do not administer this league season.", 403)
        val (id, body) = sec.registrationPolicy(season, now().atZone(london).toLocalDate()) ?: return null
        val (version, from) = connection.prepareStatement("SELECT version, effective_from FROM competition.policy WHERE policy_id = ?").use { ps ->
            ps.setObject(1, id); ps.executeQuery().use { rs -> rs.next(); rs.getInt(1) to rs.getObject(2, LocalDate::class.java) }
        }
        return Policy(id, version, from, true, body)
    }

    // --- the team finds out who owes one, and prepares each --------------------------------------------------------

    public data class Reconciled(val created: List<UUID>, val dueAt: Instant?)

    public fun reconcile(team: UUID, by: UUID): Reconciled {
        if (!runsTeam(by, team)) throw Refused("Only whoever runs the team finds out what it owes.", 403)
        val created = sec.reconcileTeam(team, now(), by = by)
        val due = created.firstOrNull()?.let { t ->
            connection.prepareStatement("SELECT due_at FROM competition.admin_task WHERE task_id = ?").use { ps ->
                ps.setObject(1, t); ps.executeQuery().use { rs -> if (rs.next()) rs.getTimestamp(1)?.toInstant() else null }
            }
        }
        return Reconciled(created, due)
    }

    private fun ownedTask(taskId: UUID, by: UUID): UUID {
        val team = sec.taskOwnerTeam(taskId) ?: throw Refused("THRØ has no such task.", 404)
        if (!runsTeam(by, team)) throw Refused("Only whoever runs the team acts on its tasks.", 403)
        return team
    }

    public data class Assessed(val missing: List<String>, val manualOutstanding: List<String>, val submissionId: UUID?, val state: String?)

    public fun assess(taskId: UUID, by: UUID): Assessed {
        ownedTask(taskId, by)
        val a = try { sec.assessRegistration(taskId, by = by) } catch (e: IllegalArgumentException) { throw Refused(e.message ?: "That task cannot be assessed.", 409) }
        return Assessed(a.missing.map { it.name.lowercase() }.sorted(), a.manualOutstanding, a.submissionId, a.submissionId?.let { sec.submissionState(it) })
    }

    public fun confirm(taskId: UUID, requirement: String, note: String, by: UUID) {
        ownedTask(taskId, by)
        if (requirement.isBlank()) throw Refused("Say which requirement is confirmed.", 400)
        if (note.trim().length < 3) throw Refused("Say how it was met, so the confirmation can be read back.", 400)
        sec.confirmManualRequirement(taskId, requirement.trim(), by, note.trim())
    }

    // --- sending, and the league's answer -------------------------------------------------------------------------

    private fun parties(submissionId: UUID) = sec.submissionParties(submissionId) ?: throw Refused("THRØ has no such submission.", 404)

    /** Sent, and — because the league is on THRØ — delivered at once by the one transport a page is: the API's. */
    public fun submit(submissionId: UUID, by: UUID): String {
        val (team, _) = parties(submissionId)
        if (!runsTeam(by, team)) throw Refused("Only whoever runs the team sends its submissions.", 403)
        when (val m = sec.submit(submissionId, by)) {
            is Secretary.Moved.Refused -> throw Refused(m.why, 409)
            is Secretary.Moved.Ok -> {}
        }
        when (val d = sec.recordDeliveryAttempt(submissionId, Transport.API, "thro", submissionId.toString(), status = "delivered")) {
            is Secretary.Moved.Refused -> throw Refused(d.why, 409)
            is Secretary.Moved.Ok -> {}
        }
        return sec.submissionState(submissionId)
    }

    public data class Listed(val submissionId: UUID, val state: String, val playerId: UUID, val player: String?, val teamId: UUID, val team: String,
                             val taskId: UUID?, val createdAt: Instant)

    /** What the league's administration sees: every registration sent to it, newest first, the player by name where THRØ may. */
    public fun list(season: UUID, by: UUID): List<Listed> {
        if (!Fixtures(connection).seasonExists(season)) throw Refused("THRØ has no such league season.", 404)
        if (!runsSeason(by, season)) throw Refused("You do not administer this league season.", 403)
        return connection.prepareStatement(
            """SELECT s.submission_id, s.state, s.subject_player_id, t.team_id, t.name, s.task_id,
                      coalesce((SELECT min(tr.at) FROM competition.submission_transition tr WHERE tr.submission_id = s.submission_id AND tr.to_state = 'submitted'), s.created_at),
                      (SELECT CASE WHEN identity.player_may_be_disclosed(c.player_id) AND a.display_name <> ? THEN a.display_name END
                         FROM identity.player_claim c JOIN identity.account a ON a.account_id = c.account_id AND a.deleted_at IS NULL
                        WHERE c.player_id = s.subject_player_id AND c.revoked_at IS NULL)
                 FROM competition.submission s JOIN competition.team t ON t.team_id = s.from_team_id
                WHERE s.kind = 'player_registration' AND s.to_league_season_id = ? AND s.state NOT IN ('draft','ready')
                ORDER BY s.created_at DESC""",
        ).use { ps ->
            ps.setString(1, Accounts.PLACEHOLDER_NAME); ps.setObject(2, season)
            ps.executeQuery().use { rs ->
                generateSequence {
                    if (!rs.next()) null else Listed(rs.getObject(1) as UUID, rs.getString(2), rs.getObject(3) as UUID, rs.getString(8),
                                                     rs.getObject(4) as UUID, rs.getString(5), rs.getObject(6) as UUID?, rs.getTimestamp(7).toInstant())
                }.toList()
            }
        }
    }

    /** The league's answer: accepted from a date, or rejected with a reason. Acknowledged on the way if it had not been. */
    public fun answer(submissionId: UUID, by: UUID, answer: String, note: String?, registeredFrom: LocalDate?): String {
        val (_, season) = parties(submissionId)
        if (season == null || !runsSeason(by, season)) throw Refused("Only the season's administration answers a registration.", 403)
        val to = when (answer) { "accepted" -> SubmissionState.ACCEPTED; "rejected" -> SubmissionState.REJECTED; else -> throw Refused("An answer is accepted or rejected.", 400) }
        if (to == SubmissionState.REJECTED && note.isNullOrBlank()) throw Refused("A rejection says why.", 400)
        if (sec.submissionState(submissionId) == "delivered") {
            when (val m = sec.acknowledge(submissionId, by, note = "read on THRØ")) {
                is Secretary.Moved.Refused -> throw Refused(m.why, 409)
                is Secretary.Moved.Ok -> {}
            }
        }
        when (val m = sec.answer(submissionId, to, by, note = note ?: "answered on THRØ", registeredFrom = registeredFrom)) {
            is Secretary.Moved.Refused -> throw Refused(m.why, 409)
            is Secretary.Moved.Ok -> {}
        }
        return sec.submissionState(submissionId)
    }

    // --- words ----------------------------------------------------------------------------------------------------

    public fun json(p: Policy?): String {
        if (p == null) return """{"policy":null}"""
        val q = thro.api.http.Contract::q
        fun strings(key: String) = ((p.body[key] as? List<*>).orEmpty()).joinToString(",") { q(it.toString()) }
        return """{"policy":{"policyId":"${p.policyId}","version":${p.version},"effectiveFrom":"${p.effectiveFrom}","approved":${p.approved},""" +
            """"requires":[${strings("requires")}],"manualRequirements":[${strings("manual_requirements")}],""" +
            """"deadlineDaysBeforeFirstFixture":${p.body["deadline_days_before_first_fixture"] ?: "null"},""" +
            """"registrationClosesOn":${(p.body["registration_closes_on"] as? String)?.let(q) ?: "null"}}}"""
    }

    public fun json(r: Reconciled): String =
        """{"created":${r.created.size},"tasks":[${r.created.joinToString(",") { "\"$it\"" }}],"dueAt":${r.dueAt?.let { "\"$it\"" } ?: "null"}}"""

    public fun json(a: Assessed): String {
        val q = thro.api.http.Contract::q
        return """{"missing":[${a.missing.joinToString(",") { q(it) }}],"manualOutstanding":[${a.manualOutstanding.joinToString(",") { q(it) }}],""" +
            """"submissionId":${a.submissionId?.let { "\"$it\"" } ?: "null"},"state":${a.state?.let(q) ?: "null"}}"""
    }

    public data class Registered(val registrationId: UUID, val playerId: UUID, val player: String?, val teamId: UUID?, val team: String?, val from: Instant, val until: Instant?,
                                 val source: String, val supersedes: UUID?)

    /** Who is registered in the season, by any route — the Secretary's, the organiser's, an import — newest first. */
    public fun registered(season: UUID): List<Registered> = connection.prepareStatement(
        """SELECT r.registration_id, r.player_id, t.team_id, t.name, r.valid_from, r.valid_until, r.source, r.supersedes_registration_id,
                  (SELECT CASE WHEN identity.player_may_be_disclosed(c.player_id) AND a.display_name <> ? THEN a.display_name END
                     FROM identity.player_claim c JOIN identity.account a ON a.account_id = c.account_id AND a.deleted_at IS NULL
                    WHERE c.player_id = r.player_id AND c.revoked_at IS NULL)
             FROM competition.player_registration r LEFT JOIN competition.team t ON t.team_id = r.team_id
            WHERE r.league_season_id = ? AND r.status = 'registered' ORDER BY r.valid_from DESC""",
    ).use { ps ->
        ps.setString(1, Accounts.PLACEHOLDER_NAME); ps.setObject(2, season)
        ps.executeQuery().use { rs ->
            generateSequence {
                if (!rs.next()) null
                else Registered(rs.getObject(1) as UUID, rs.getObject(2) as UUID, rs.getString(9), rs.getObject(3) as UUID?, rs.getString(4), rs.getTimestamp(5).toInstant(),
                                rs.getTimestamp(6)?.toInstant(), rs.getString(7), rs.getObject(8) as UUID?)
            }.toList()
        }
    }

    public fun json(rows: List<Listed>, registered: List<Registered> = emptyList()): String {
        val q = thro.api.http.Contract::q
        val london = ZoneId.of("Europe/London")
        return """{"registrations":[""" + rows.joinToString(",") {
            """{"submissionId":"${it.submissionId}","state":${q(it.state)},"playerId":"${it.playerId}","player":${it.player?.let(q) ?: "null"},""" +
                """"teamId":"${it.teamId}","team":${q(it.team)},"taskId":${it.taskId?.let { t -> "\"$t\"" } ?: "null"},"sentAt":"${it.createdAt}"}"""
        } + """],"registered":[""" + registered.joinToString(",") {
            """{"registrationId":"${it.registrationId}","playerId":"${it.playerId}","player":${it.player?.let(q) ?: "null"},"teamId":${it.teamId?.let { t -> "\"$t\"" } ?: "null"},""" +
                """"team":${it.team?.let(q) ?: "null"},"from":"${it.from.atZone(london).toLocalDate()}","until":${it.until?.let { u -> "\"${u.atZone(london).toLocalDate()}\"" } ?: "null"},""" +
                """"source":${q(it.source)},"supersedes":${it.supersedes?.let { s -> "\"$s\"" } ?: "null"}}"""
        } + "]}"
    }
}
