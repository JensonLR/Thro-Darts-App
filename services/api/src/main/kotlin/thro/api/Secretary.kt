package thro.api

import java.sql.Connection
import java.sql.Timestamp
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId
import java.util.UUID
import thro.competition.EvidenceKind
import thro.competition.Inbox
import thro.competition.InboxSection
import thro.competition.RegistrationDeadline
import thro.competition.RegistrationFact
import thro.competition.RegistrationFacts
import thro.competition.RegistrationPolicy
import thro.competition.SubmissionState
import thro.competition.SubmissionTransitions
import thro.competition.TaskState
import thro.competition.Transport

/**
 * THRØ Secretary, the store-side half (execution plan §7, migration V016).
 *
 * An administrator enters a sporting fact once; the methods here derive the administration that
 * legitimately follows — a task with an owner, a source, a reason and a deadline, and a submission
 * that moves only with evidence. Three things it never does:
 *
 * - **Manufacture a task.** Tasks come from a set-based reconciliation of facts against approved
 *   policy, and a fact produces its task once. A registered player gets no registration task, and
 *   one who becomes registered by any route has theirs closed.
 * - **Speak for the league.** THRØ takes a submission to `delivered` because it did that and holds
 *   the delivery row. `acknowledged`, `accepted`, `rejected` and `action_required` are the
 *   recipient's words; the trigger refuses them from anyone who does not administer the receiving
 *   side, and this class offers no method that tries otherwise.
 * - **Send a person the league has no basis to know about.** The disclosure gate is a database
 *   function and the trigger calls it (PD-029); this class merely reports the refusal in words.
 *
 * Every method that changes state carries the actor, and the database records it.
 */
public class Secretary(private val connection: Connection) {

    private val london = ZoneId.of("Europe/London")

    // --- 1. Reconciliation: what a team owes, derived, idempotent ---------------------------------

    /**
     * For every active member of [teamId] and every league season the team is affiliated to at
     * [at] whose approved registration policy is in force, creates a `registration_required` task
     * unless the player already holds a live registration or a live registration submission in
     * that season; and closes any open registration task whose player has since become registered
     * by any route. Run it on membership, affiliation, policy approval and season events alike.
     */
    public fun reconcileTeam(teamId: UUID, at: Instant = Instant.now(), by: UUID? = null): List<UUID> {
        val created = mutableListOf<UUID>()
        val today = at.atZone(london).toLocalDate()
        for (season in affiliatedSeasons(teamId, at)) {
            val policy = approvedPolicy(season, "registration", today) ?: continue
            val parsed = RegistrationPolicy.parse(policy.second)
            for (playerId in activeMembers(teamId, at)) {
                val registered = Organisations(connection).isRegistered(playerId, season, at)
                val open = openTask("registration_required", teamId, playerId, season)
                if (registered) {
                    open?.let { closeTask(it, TaskState.DONE, by, "Registered — recorded outside this task") }
                    continue
                }
                if (open != null || liveRegistrationSubmission(playerId, season) != null) continue
                val (due, anchor) = deadlineFor(parsed.deadline, teamId, season)
                created += insertTask(
                    kind = "registration_required", ownerTeam = teamId, sourceKind = "reconciliation", sourceId = null,
                    player = playerId, season = season, policyId = policy.first, dueAt = due, dueRule = parsed.deadline.rule,
                    anchorFixture = anchor, reason = "Register for ${seasonLabel(season)} before playing", by = by,
                )
            }
        }
        return created
    }

    // --- 2. Assessment ---------------------------------------------------------------------------

    public data class Assessment(val missing: Set<RegistrationFact>, val manualOutstanding: List<String>, val submissionId: UUID?)

    /**
     * Assesses a registration task against the policy it cites. Missing facts make it
     * `waiting_player` — and, where the player has an account, a `consent_required` task owned by
     * the player when consent is what is missing. Nothing missing makes a submission `ready` and
     * the task `waiting_league`. Idempotent.
     */
    public fun assessRegistration(taskId: UUID, by: UUID? = null): Assessment {
        val t = task(taskId) ?: throw IllegalArgumentException("no such task")
        require(t.kind == "registration_required") { "not a registration task" }
        val policy = RegistrationPolicy.parse(policyBody(t.policyId!!))
        val facts = factsFor(t.playerId!!)
        val missing = facts.missing(policy)
        val manual = facts.manualOutstanding(policy, confirmedRequirements(taskId))
        if (missing.isNotEmpty() || manual.isNotEmpty()) {
            if (RegistrationFact.CONSENT in missing && facts.accountClaimed) {
                if (openTaskForPlayer("consent_required", t.playerId, t.seasonId!!) == null) {
                    insertTask(
                        kind = "consent_required", ownerPlayer = t.playerId, sourceKind = "reconciliation", sourceId = taskId,
                        player = t.playerId, season = t.seasonId, policyId = t.policyId, dueAt = t.dueAt, dueRule = null,
                        anchorFixture = null, reason = "Confirm THRØ may pass your details to ${seasonLabel(t.seasonId)}", by = by,
                    )
                }
            }
            setMissing(taskId, missing, manual)
            if (t.state != "waiting_player") moveTask(taskId, TaskState.WAITING_PLAYER, by, "Waiting on the player")
            return Assessment(missing, manual, null)
        }
        liveRegistrationSubmission(t.playerId, t.seasonId!!)?.let { return Assessment(emptySet(), emptyList(), it) }
        val submissionId = UUID.randomUUID()
        connection.prepareStatement(
            """
            INSERT INTO competition.submission
              (submission_id, kind, from_team_id, to_league_season_id, subject_player_id, subject_league_season_id, task_id, policy_id, created_by)
            VALUES (?, 'player_registration', ?, ?, ?, ?, ?, ?, ?)
            """.trimIndent(),
        ).use { ps ->
            ps.setObject(1, submissionId); ps.setObject(2, t.ownerTeam); ps.setObject(3, t.seasonId)
            ps.setObject(4, t.playerId); ps.setObject(5, t.seasonId); ps.setObject(6, taskId); ps.setObject(7, t.policyId)
            ps.setObject(8, by); ps.executeUpdate()
        }
        transition(submissionId, SubmissionState.DRAFT, SubmissionState.READY, by = null)
        moveTask(taskId, TaskState.WAITING_LEAGUE, by, "Prepared; awaiting the league")
        return Assessment(emptySet(), emptyList(), submissionId)
    }

    /** A named person confirms a requirement THRØ cannot check. Shown as a manual step, never a tick THRØ gave. */
    public fun confirmManualRequirement(taskId: UUID, requirement: String, by: UUID, note: String) {
        connection.prepareStatement(
            "INSERT INTO competition.admin_task_manual_confirmation (task_id, requirement, confirmed_by, note) VALUES (?, ?, ?, ?)",
        ).use { ps -> ps.setObject(1, taskId); ps.setString(2, requirement); ps.setObject(3, by); ps.setString(4, note); ps.executeUpdate() }
    }

    /** A consent artefact with an actor. Closes the player's consent task when one is open. */
    public fun recordConsent(accountId: UUID, basis: String, givenBy: UUID, artefactRef: String): UUID {
        val id = UUID.randomUUID()
        connection.prepareStatement(
            "INSERT INTO identity.consent_record (consent_id, account_id, basis, given_by, artefact_ref) VALUES (?, ?, ?, ?, ?)",
        ).use { ps -> ps.setObject(1, id); ps.setObject(2, accountId); ps.setString(3, basis); ps.setObject(4, givenBy); ps.setString(5, artefactRef); ps.executeUpdate() }
        connection.prepareStatement(
            """
            SELECT t.task_id FROM competition.admin_task t
              JOIN identity.player_claim c ON c.player_id = t.owner_player_id AND c.revoked_at IS NULL
             WHERE t.kind = 'consent_required' AND c.account_id = ? AND t.state NOT IN ('done','cancelled')
            """.trimIndent(),
        ).use { ps ->
            ps.setObject(1, accountId)
            ps.executeQuery().use { rs -> while (rs.next()) closeTask(rs.getObject(1) as UUID, TaskState.DONE, givenBy, "Consent recorded") }
        }
        return id
    }

    // --- 3. Sending, delivering, and what comes back ------------------------------------------------

    public sealed interface Moved {
        public data class Ok(val submissionId: UUID) : Moved
        public data class Refused(val why: String) : Moved
    }

    /** A named submitter sends it. The disclosure gate is the trigger's; a refusal is reported in its words. */
    public fun submit(submissionId: UUID, by: UUID): Moved = guarded(submissionId) {
        transition(submissionId, SubmissionState.READY, SubmissionState.SUBMITTED, by = by)
    }

    /**
     * The transport code records an attempt. `delivered` or `failed` moves the submission; `sent`
     * (in flight) does not. This is the only way to `delivered` besides a named human confirmation.
     */
    public fun recordDeliveryAttempt(
        submissionId: UUID, transport: Transport, adapter: String, providerRef: String?, status: String, detail: String? = null,
    ): Moved = guarded(submissionId) {
        // Only a submission in flight takes a delivery attempt; the rule says so in its own words
        // before any attempt row is written for a submission that is not being sent.
        val current = SubmissionState.valueOf((submission(submissionId) ?: throw IllegalArgumentException("no such submission")).state.uppercase())
        val to = when (status) { "delivered" -> SubmissionState.DELIVERED; "failed" -> SubmissionState.DELIVERY_FAILED; else -> null }
        if (to != null) {
            when (val v = SubmissionTransitions.check(current, to, EvidenceKind.DELIVERY, actorNamed = false)) {
                is SubmissionTransitions.Verdict.Refused -> throw IllegalStateException(v.why)
                SubmissionTransitions.Verdict.Permitted -> Unit
            }
        }
        val attempt = connection.prepareStatement(
            "SELECT coalesce(max(attempt_no), 0) + 1 FROM competition.submission_delivery WHERE submission_id = ?",
        ).use { ps -> ps.setObject(1, submissionId); ps.executeQuery().use { rs -> rs.next(); rs.getInt(1) } }
        val deliveryId = UUID.randomUUID()
        connection.prepareStatement(
            """
            INSERT INTO competition.submission_delivery (delivery_id, submission_id, attempt_no, transport, adapter, provider_ref, status, detail)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?)
            """.trimIndent(),
        ).use { ps ->
            ps.setObject(1, deliveryId); ps.setObject(2, submissionId); ps.setInt(3, attempt)
            ps.setString(4, transport.name.lowercase()); ps.setString(5, adapter); ps.setString(6, providerRef)
            ps.setString(7, status); ps.setString(8, detail); ps.executeUpdate()
        }
        when (status) {
            "delivered" -> transition(submissionId, SubmissionState.SUBMITTED, SubmissionState.DELIVERED, by = null, evidence = EvidenceKind.DELIVERY, deliveryId = deliveryId)
            "failed" -> transition(submissionId, SubmissionState.SUBMITTED, SubmissionState.DELIVERY_FAILED, by = null, evidence = EvidenceKind.DELIVERY, deliveryId = deliveryId)
            else -> Unit
        }
    }

    /** A named person carried it by hand and says so. The manual step, shown as one. */
    public fun confirmDeliveredByHand(submissionId: UUID, by: UUID, note: String): Moved = guarded(submissionId) {
        transition(submissionId, SubmissionState.SUBMITTED, SubmissionState.DELIVERED, by = by, evidence = EvidenceKind.HUMAN_CONFIRMATION, note = note)
    }

    /** After a failed delivery, the submitter takes it back to ready to try again. */
    public fun retry(submissionId: UUID, by: UUID): Moved = guarded(submissionId) {
        transition(submissionId, SubmissionState.DELIVERY_FAILED, SubmissionState.READY, by = by)
    }

    /** Inbound material from the recipient, retained and attributed. */
    public fun captureArtefact(submissionId: UUID, kind: String, storedRef: String, sha256: String, by: UUID): UUID {
        val id = UUID.randomUUID()
        connection.prepareStatement(
            "INSERT INTO competition.submission_artefact (artefact_id, submission_id, kind, stored_ref, sha256, captured_by) VALUES (?, ?, ?, ?, ?, ?)",
        ).use { ps ->
            ps.setObject(1, id); ps.setObject(2, submissionId); ps.setString(3, kind); ps.setString(4, storedRef)
            ps.setString(5, sha256); ps.setObject(6, by); ps.executeUpdate()
        }
        return id
    }

    /** A named recipient administrator acknowledges receipt, with an artefact or in their own words. */
    public fun acknowledge(submissionId: UUID, by: UUID, artefactId: UUID? = null, note: String? = null): Moved = guarded(submissionId) {
        transition(
            submissionId, SubmissionState.DELIVERED, SubmissionState.ACKNOWLEDGED, by = by,
            evidence = if (artefactId != null) EvidenceKind.ARTEFACT else EvidenceKind.HUMAN_CONFIRMATION,
            artefactId = artefactId, note = note,
        )
    }

    /**
     * The recipient's answer, by a named administrator of the receiving side. `accepted` on a
     * registration creates the registration from the date the league named, under the policy in
     * force on that date, and closes the task. Conditions make it `accepted_conditional`, which
     * registers nobody. `rejected` closes the task; `action_required` hands it back.
     */
    public fun answer(
        submissionId: UUID, answer: SubmissionState, by: UUID, artefactId: UUID? = null, note: String? = null,
        registeredFrom: LocalDate? = null, conditions: String? = null,
    ): Moved = guarded(submissionId) {
        require(answer in setOf(SubmissionState.ACCEPTED, SubmissionState.ACCEPTED_CONDITIONAL, SubmissionState.REJECTED, SubmissionState.ACTION_REQUIRED)) { "not an answer" }
        val s = submission(submissionId) ?: throw IllegalArgumentException("no such submission")
        val from = SubmissionState.valueOf(s.state.uppercase())
        transition(
            submissionId, from, answer, by = by,
            evidence = if (artefactId != null) EvidenceKind.ARTEFACT else EvidenceKind.HUMAN_CONFIRMATION,
            artefactId = artefactId, note = note, registeredFrom = registeredFrom, conditions = conditions,
        )
        if (s.kind == "player_registration" && answer == SubmissionState.ACCEPTED) {
            val governing = approvedPolicy(s.seasonId!!, "registration", registeredFrom!!)?.first
                ?: throw IllegalStateException("no approved registration policy governed ${s.seasonId} on $registeredFrom")
            Organisations(connection).register(
                playerId = s.playerId!!, leagueSeasonId = s.seasonId, teamId = s.fromTeam, policyId = governing,
                from = registeredFrom.atStartOfDay(london).toInstant(), source = "thro", by = by,
            )
        }
        if (s.kind == "fixture_rearrangement") {
            val proposalState = when (answer) {
                SubmissionState.ACCEPTED -> "accepted"
                SubmissionState.REJECTED -> "declined"
                else -> null
            }
            proposalState?.let { answerProposal(s.proposalId!!, it, by) }
        }
        s.taskId?.let { taskId ->
            when (answer) {
                SubmissionState.ACCEPTED, SubmissionState.REJECTED -> closeTask(taskId, TaskState.DONE, by, note ?: answer.name.lowercase())
                SubmissionState.ACTION_REQUIRED -> moveTask(taskId, TaskState.OPEN, by, note ?: "The recipient needs something more")
                else -> Unit
            }
        }
    }

    /** After `action_required`, the submitter prepares it again. */
    public fun prepareAgain(submissionId: UUID, by: UUID): Moved = guarded(submissionId) {
        transition(submissionId, SubmissionState.ACTION_REQUIRED, SubmissionState.READY, by = by)
        submission(submissionId)?.taskId?.let { moveTask(it, TaskState.WAITING_LEAGUE, by, "Prepared again; awaiting the league") }
    }

    // --- 4. The same engine for results and rearrangements ------------------------------------

    /**
     * A played outcome was recorded by the home side: they owe the league a result card. An
     * outcome the league decided itself (awarded, walkover, void) creates nothing — telling a team
     * to send the league its own decision would be busywork.
     */
    public fun onFixtureOutcome(outcomeId: UUID, dueAt: Instant, by: UUID? = null): UUID? {
        val row = connection.prepareStatement(
            """
            SELECT o.kind, f.fixture_id, f.league_season_id, f.home_team_id
              FROM competition.league_fixture_outcome o JOIN competition.league_fixture f ON f.fixture_id = o.fixture_id
             WHERE o.outcome_id = ?
            """.trimIndent(),
        ).use { ps ->
            ps.setObject(1, outcomeId)
            ps.executeQuery().use { rs -> if (rs.next()) listOf(rs.getString(1), rs.getObject(2), rs.getObject(3), rs.getObject(4)) else return null }
        }
        if (row[0] != "played") return null
        val fixtureId = row[1] as UUID; val season = row[2] as UUID; val home = row[3] as UUID
        if (openTaskBySource("result_submission_due", outcomeId) != null) return null
        val policy = approvedPolicy(season, "result_submission", dueAt.atZone(london).toLocalDate())
        val taskId = insertTask(
            kind = "result_submission_due", ownerTeam = home, sourceKind = "fixture_outcome", sourceId = outcomeId,
            fixture = fixtureId, season = season, policyId = policy?.first, dueAt = dueAt, dueRule = null, anchorFixture = null,
            reason = "Send the result to ${seasonLabel(season)}", by = by,
        )
        val submissionId = UUID.randomUUID()
        connection.prepareStatement(
            """
            INSERT INTO competition.submission (submission_id, kind, from_team_id, to_league_season_id, outcome_id, task_id, policy_id, created_by)
            VALUES (?, 'result', ?, ?, ?, ?, ?, ?)
            """.trimIndent(),
        ).use { ps ->
            ps.setObject(1, submissionId); ps.setObject(2, home); ps.setObject(3, season); ps.setObject(4, outcomeId)
            ps.setObject(5, taskId); ps.setObject(6, policy?.first); ps.setObject(7, by); ps.executeUpdate()
        }
        // The result card needs both sides named, or the league is sent a scoreline with nobody on
        // it. Until then the submission stays a draft and the task says which side is missing.
        val missing = lineupsMissing(fixtureId)
        if (missing.isEmpty()) {
            transition(submissionId, SubmissionState.DRAFT, SubmissionState.READY, by = null)
        } else {
            setMissingFacts(taskId, missing)
        }
        return taskId
    }

    /** Which of a fixture's two sides has no lineup named: `home_lineup`, `away_lineup`, or neither. */
    public fun lineupsMissing(fixtureId: UUID): List<String> =
        connection.prepareStatement(
            """
            SELECT CASE WHEN EXISTS (SELECT 1 FROM competition.current_lineup(f.fixture_id, f.home_team_id)) THEN NULL ELSE 'home_lineup' END,
                   CASE WHEN EXISTS (SELECT 1 FROM competition.current_lineup(f.fixture_id, f.away_team_id)) THEN NULL ELSE 'away_lineup' END
              FROM competition.league_fixture f WHERE f.fixture_id = ?
            """.trimIndent(),
        ).use { ps ->
            ps.setObject(1, fixtureId)
            ps.executeQuery().use { rs -> if (rs.next()) listOfNotNull(rs.getString(1), rs.getString(2)) else emptyList() }
        }

    /**
     * A side was named. Any result card for this fixture still waiting on a lineup becomes ready
     * the moment both sides are there; nothing else moves. Returns the submissions made ready.
     */
    public fun onLineupNamed(fixtureId: UUID, by: UUID? = null): List<UUID> {
        val missing = lineupsMissing(fixtureId)
        val waiting = mutableListOf<Pair<UUID, UUID>>()
        connection.prepareStatement(
            """
            SELECT s.submission_id, s.task_id FROM competition.submission s
              JOIN competition.league_fixture_outcome o ON o.outcome_id = s.outcome_id
              JOIN competition.admin_task t ON t.task_id = s.task_id
             WHERE o.fixture_id = ? AND s.kind = 'result' AND s.state = 'draft'
               AND t.state NOT IN ('done','cancelled')
            """.trimIndent(),
        ).use { ps -> ps.setObject(1, fixtureId); ps.executeQuery().use { rs -> while (rs.next()) waiting += (rs.getObject(1) as UUID) to (rs.getObject(2) as UUID) } }
        val readied = mutableListOf<UUID>()
        for ((submissionId, taskId) in waiting) {
            setMissingFacts(taskId, missing)
            if (missing.isEmpty()) {
                transition(submissionId, SubmissionState.DRAFT, SubmissionState.READY, by = by)
                readied += submissionId
            }
        }
        return readied
    }

    /**
     * One team proposes a new date to the other. The opponent owes an answer (their task); the
     * proposal travels as a submission to that team; the league applies an accepted proposal.
     */
    public data class Proposal(val proposalId: UUID, val taskId: UUID, val submissionId: UUID)

    public fun proposeRearrangement(
        fixtureId: UUID, byTeamId: UUID, to: Instant, dueAt: Instant, by: UUID, reason: String? = null, venueId: UUID? = null,
    ): Proposal {
        val (home, away) = connection.prepareStatement("SELECT home_team_id, away_team_id FROM competition.league_fixture WHERE fixture_id = ?")
            .use { ps -> ps.setObject(1, fixtureId); ps.executeQuery().use { rs -> rs.next(); (rs.getObject(1) as UUID) to (rs.getObject(2) as UUID) } }
        require(byTeamId == home || byTeamId == away) { "only one of the two teams proposes" }
        val opponent = if (byTeamId == home) away else home
        val proposalId = UUID.randomUUID()
        connection.prepareStatement(
            """
            INSERT INTO competition.fixture_rearrangement_proposal
              (proposal_id, fixture_id, proposed_by_team_id, to_team_id, proposed_at, proposed_venue_id, reason, proposed_by)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?)
            """.trimIndent(),
        ).use { ps ->
            ps.setObject(1, proposalId); ps.setObject(2, fixtureId); ps.setObject(3, byTeamId); ps.setObject(4, opponent)
            ps.setObject(5, Timestamp.from(to)); ps.setObject(6, venueId); ps.setString(7, reason); ps.setObject(8, by); ps.executeUpdate()
        }
        val taskId = insertTask(
            kind = "rearrangement_answer_due", ownerTeam = opponent, sourceKind = "rearrangement_proposal", sourceId = proposalId,
            fixture = fixtureId, season = null, policyId = null, dueAt = dueAt, dueRule = null, anchorFixture = null,
            reason = "Answer the proposed new date", by = by,
        )
        val submissionId = UUID.randomUUID()
        connection.prepareStatement(
            """
            INSERT INTO competition.submission (submission_id, kind, from_team_id, to_team_id, proposal_id, task_id, created_by)
            VALUES (?, 'fixture_rearrangement', ?, ?, ?, ?, ?)
            """.trimIndent(),
        ).use { ps ->
            ps.setObject(1, submissionId); ps.setObject(2, byTeamId); ps.setObject(3, opponent); ps.setObject(4, proposalId)
            ps.setObject(5, taskId); ps.setObject(6, by); ps.executeUpdate()
        }
        transition(submissionId, SubmissionState.DRAFT, SubmissionState.READY, by = null)
        transition(submissionId, SubmissionState.READY, SubmissionState.SUBMITTED, by = by)
        // Delivered in-app: the opponent's inbox is the transport, and the delivery row says so.
        recordDeliveryAttempt(submissionId, Transport.API, "in_app_inbox", providerRef = taskId.toString(), status = "delivered")
        return Proposal(proposalId, taskId, submissionId)
    }

    private fun answerProposal(proposalId: UUID, state: String, by: UUID) {
        val version = connection.prepareStatement("SELECT row_version FROM competition.fixture_rearrangement_proposal WHERE proposal_id = ?")
            .use { ps -> ps.setObject(1, proposalId); ps.executeQuery().use { rs -> rs.next(); rs.getInt(1) } }
        connection.prepareStatement(
            """
            UPDATE competition.fixture_rearrangement_proposal
               SET state = ?, answered_by = ?, answered_at = clock_timestamp(), row_version = ?
             WHERE proposal_id = ? AND row_version = ?
            """.trimIndent(),
        ).use { ps ->
            ps.setString(1, state); ps.setObject(2, by); ps.setInt(3, version + 1); ps.setObject(4, proposalId); ps.setInt(5, version)
            check(ps.executeUpdate() == 1) { "stale write on proposal $proposalId" }
        }
    }

    /**
     * The league applies an accepted proposal through the same command every rearrangement goes
     * through, and the change log records which proposal it applied.
     */
    public fun applyProposal(proposalId: UUID, by: UUID, deviceId: UUID, expectedFixtureVersion: Int): OrganisationCommands.Result {
        val (fixtureId, at, venue, version) = connection.prepareStatement(
            "SELECT fixture_id, proposed_at, proposed_venue_id, row_version FROM competition.fixture_rearrangement_proposal WHERE proposal_id = ? AND state = 'accepted'",
        ).use { ps ->
            ps.setObject(1, proposalId)
            ps.executeQuery().use { rs ->
                require(rs.next()) { "proposal $proposalId is not accepted" }
                listOf(rs.getObject(1) as UUID, rs.getTimestamp(2).toInstant(), rs.getObject(3) as UUID?, rs.getInt(4))
            }
        }
        setSetting("thro.proposal", proposalId.toString())
        val result = try {
            OrganisationCommands(connection).handle(
                OrganisationCommands.Command.RearrangeFixture(UUID.randomUUID(), deviceId, by, fixtureId as UUID, at as Instant, expectedFixtureVersion, venue as UUID?),
            )
        } finally {
            setSetting("thro.proposal", "")
        }
        if (result is OrganisationCommands.Result.Applied) {
            connection.prepareStatement("UPDATE competition.fixture_rearrangement_proposal SET state = 'applied', row_version = ? WHERE proposal_id = ? AND row_version = ?")
                .use { ps -> ps.setInt(1, (version as Int) + 1); ps.setObject(2, proposalId); ps.setInt(3, version); ps.executeUpdate() }
        }
        return result
    }

    /**
     * A fixture moved: every open task whose deadline was derived from it is recomputed, and the
     * recomputation is logged against the change that caused it. The original deadline stays in
     * the task's history.
     */
    public fun refreshDeadlines(fixtureId: UUID, causeChangeId: UUID? = null): Int {
        var changed = 0
        connection.prepareStatement(
            """
            SELECT t.task_id, t.due_rule, t.due_at, t.row_version, t.owner_team_id, t.subject_league_season_id
              FROM competition.admin_task t
             WHERE t.due_anchor_fixture_id = ? AND t.state NOT IN ('done','cancelled') AND t.due_rule LIKE 'days_before_first_fixture:%'
            """.trimIndent(),
        ).use { ps ->
            ps.setObject(1, fixtureId)
            ps.executeQuery().use { rs ->
                val rows = generateSequence {
                    if (rs.next()) listOf(rs.getObject(1), rs.getString(2), rs.getTimestamp(3)?.toInstant(), rs.getInt(4), rs.getObject(5), rs.getObject(6)) else null
                }.toList()
                for (r in rows) {
                    val days = (r[1] as String).substringAfter(':').toInt()
                    val (due, anchor) = deadlineFor(RegistrationDeadline.DaysBeforeFirstFixture(days), r[4] as UUID, r[5] as UUID)
                    if (due != r[2]) {
                        setSetting("thro.cause_change", causeChangeId?.toString() ?: "")
                        setSetting("thro.note", "deadline recomputed after the fixture moved")
                        try {
                            connection.prepareStatement(
                                "UPDATE competition.admin_task SET due_at = ?, due_anchor_fixture_id = ?, row_version = ? WHERE task_id = ? AND row_version = ?",
                            ).use { ps2 ->
                                ps2.setObject(1, due?.let { Timestamp.from(it) }); ps2.setObject(2, anchor)
                                ps2.setInt(3, (r[3] as Int) + 1); ps2.setObject(4, r[0]); ps2.setInt(5, r[3] as Int)
                                changed += ps2.executeUpdate()
                            }
                        } finally {
                            setSetting("thro.cause_change", ""); setSetting("thro.note", "")
                        }
                    }
                }
            }
        }
        return changed
    }

    // --- 5. Reading ---------------------------------------------------------------------------------

    public data class InboxItem(val taskId: UUID, val kind: String, val reason: String, val dueAt: Instant?, val state: String, val section: InboxSection)

    public fun inbox(teamId: UUID, now: Instant = Instant.now()): Map<InboxSection, List<InboxItem>> =
        inboxWhere("owner_team_id = ?", teamId, now)

    public fun inboxForPlayer(playerId: UUID, now: Instant = Instant.now()): Map<InboxSection, List<InboxItem>> =
        inboxWhere("owner_player_id = ?", playerId, now)

    private fun inboxWhere(where: String, id: UUID, now: Instant): Map<InboxSection, List<InboxItem>> {
        val endOfToday = now.atZone(london).toLocalDate().plusDays(1).atStartOfDay(london).toInstant().minusSeconds(1)
        val items = mutableListOf<InboxItem>()
        connection.prepareStatement(
            "SELECT task_id, kind, reason, due_at, state FROM competition.admin_task WHERE $where ORDER BY due_at NULLS LAST, created_at",
        ).use { ps ->
            ps.setObject(1, id)
            ps.executeQuery().use { rs ->
                while (rs.next()) {
                    val due = rs.getTimestamp(4)?.toInstant()
                    val state = TaskState.valueOf(rs.getString(5).uppercase())
                    items += InboxItem(rs.getObject(1) as UUID, rs.getString(2), rs.getString(3), due, rs.getString(5), Inbox.sectionOf(state, due, now, endOfToday))
                }
            }
        }
        return items.groupBy { it.section }
    }

    /** What the league's administration sees: nothing before it was sent. Drafts are the team's. */
    public fun submissionsForLeague(seasonId: UUID): List<Pair<UUID, String>> {
        val out = mutableListOf<Pair<UUID, String>>()
        connection.prepareStatement(
            """
            SELECT submission_id, state FROM competition.submission
             WHERE to_league_season_id = ? AND state NOT IN ('draft','ready') ORDER BY created_at
            """.trimIndent(),
        ).use { ps -> ps.setObject(1, seasonId); ps.executeQuery().use { rs -> while (rs.next()) out += (rs.getObject(1) as UUID) to rs.getString(2) } }
        return out
    }

    public fun submissionState(submissionId: UUID): String = submission(submissionId)?.state ?: throw IllegalArgumentException("no such submission")

    // --- internals --------------------------------------------------------------------------------

    private fun guarded(submissionId: UUID, block: () -> Unit): Moved = try {
        block(); Moved.Ok(submissionId)
    } catch (e: org.postgresql.util.PSQLException) {
        Moved.Refused(e.serverErrorMessage?.message ?: e.message ?: "refused")
    } catch (e: IllegalStateException) {
        Moved.Refused(e.message ?: "refused")
    }

    private fun transition(
        submissionId: UUID, from: SubmissionState, to: SubmissionState, by: UUID?,
        evidence: EvidenceKind? = null, deliveryId: UUID? = null, artefactId: UUID? = null,
        note: String? = null, registeredFrom: LocalDate? = null, conditions: String? = null,
    ) {
        // The pure rule first, so the refusal reads as the product's sentence; the trigger then
        // enforces the same rule — plus what only the database can check — for anyone who bypasses
        // this class.
        when (val v = SubmissionTransitions.check(from, to, evidence, actorNamed = by != null)) {
            is SubmissionTransitions.Verdict.Refused -> throw IllegalStateException(v.why)
            SubmissionTransitions.Verdict.Permitted -> Unit
        }
        val version = submission(submissionId)?.version ?: throw IllegalArgumentException("no such submission")
        connection.prepareStatement(
            """
            INSERT INTO competition.submission_transition
              (submission_id, expected_version, actor_id, from_state, to_state, evidence_kind, delivery_id, artefact_id, note, registered_from, conditions)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """.trimIndent(),
        ).use { ps ->
            ps.setObject(1, submissionId); ps.setInt(2, version); ps.setObject(3, by)
            ps.setString(4, from.name.lowercase()); ps.setString(5, to.name.lowercase())
            ps.setString(6, evidence?.name?.lowercase()); ps.setObject(7, deliveryId); ps.setObject(8, artefactId)
            ps.setString(9, note); ps.setObject(10, registeredFrom); ps.setString(11, conditions)
            ps.executeUpdate()
        }
    }

    private data class TaskRow(
        val taskId: UUID, val kind: String, val ownerTeam: UUID?, val playerId: UUID?, val seasonId: UUID?,
        val policyId: UUID?, val reason: String, val state: String, val version: Int, val dueAt: Instant?,
    )

    private fun task(taskId: UUID): TaskRow? = connection.prepareStatement(
        "SELECT task_id, kind, owner_team_id, subject_player_id, subject_league_season_id, policy_id, reason, state, row_version, due_at FROM competition.admin_task WHERE task_id = ?",
    ).use { ps ->
        ps.setObject(1, taskId)
        ps.executeQuery().use { rs ->
            if (rs.next()) TaskRow(
                rs.getObject(1) as UUID, rs.getString(2), rs.getObject(3) as UUID?, rs.getObject(4) as UUID?, rs.getObject(5) as UUID?,
                rs.getObject(6) as UUID?, rs.getString(7), rs.getString(8), rs.getInt(9), rs.getTimestamp(10)?.toInstant(),
            ) else null
        }
    }

    private fun insertTask(
        kind: String, ownerTeam: UUID? = null, ownerPlayer: UUID? = null, sourceKind: String, sourceId: UUID?,
        player: UUID? = null, fixture: UUID? = null, season: UUID?, policyId: UUID?, dueAt: Instant?, dueRule: String?,
        anchorFixture: UUID?, reason: String, by: UUID?,
    ): UUID {
        val id = UUID.randomUUID()
        connection.prepareStatement(
            """
            INSERT INTO competition.admin_task
              (task_id, kind, owner_team_id, owner_player_id, source_kind, source_id, subject_player_id, subject_fixture_id,
               subject_league_season_id, reason, policy_id, due_at, due_rule, due_anchor_fixture_id, created_by)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """.trimIndent(),
        ).use { ps ->
            ps.setObject(1, id); ps.setString(2, kind); ps.setObject(3, ownerTeam); ps.setObject(4, ownerPlayer)
            ps.setString(5, sourceKind); ps.setObject(6, sourceId); ps.setObject(7, player); ps.setObject(8, fixture)
            ps.setObject(9, season); ps.setString(10, reason); ps.setObject(11, policyId)
            ps.setObject(12, dueAt?.let { Timestamp.from(it) }); ps.setString(13, dueRule); ps.setObject(14, anchorFixture); ps.setObject(15, by)
            ps.executeUpdate()
        }
        return id
    }

    private fun moveTask(taskId: UUID, to: TaskState, by: UUID?, note: String) {
        val t = task(taskId) ?: throw IllegalArgumentException("no such task")
        setSetting("thro.actor", by?.toString() ?: ""); setSetting("thro.note", note)
        try {
            val n = connection.prepareStatement("UPDATE competition.admin_task SET state = ?, row_version = ? WHERE task_id = ? AND row_version = ?")
                .use { ps -> ps.setString(1, to.name.lowercase()); ps.setInt(2, t.version + 1); ps.setObject(3, taskId); ps.setInt(4, t.version); ps.executeUpdate() }
            check(n == 1) { "stale write: task $taskId is not at version ${t.version}" }
        } finally {
            setSetting("thro.actor", ""); setSetting("thro.note", "")
        }
    }

    private fun closeTask(taskId: UUID, to: TaskState, by: UUID?, note: String) = moveTask(taskId, to, by, note)

    private fun setMissingFacts(taskId: UUID, facts: List<String>) {
        val t = task(taskId) ?: return
        connection.prepareStatement("UPDATE competition.admin_task SET missing_facts = ?, row_version = ? WHERE task_id = ? AND row_version = ?")
            .use { ps -> ps.setArray(1, connection.createArrayOf("text", facts.toTypedArray())); ps.setInt(2, t.version + 1); ps.setObject(3, taskId); ps.setInt(4, t.version); ps.executeUpdate() }
    }

    private fun setMissing(taskId: UUID, missing: Set<RegistrationFact>, manual: List<String>) {
        val t = task(taskId) ?: return
        val facts = missing.map { it.name.lowercase() } + manual.map { "manual:$it" }
        connection.prepareStatement("UPDATE competition.admin_task SET missing_facts = ?, row_version = ? WHERE task_id = ? AND row_version = ?")
            .use { ps -> ps.setArray(1, connection.createArrayOf("text", facts.toTypedArray())); ps.setInt(2, t.version + 1); ps.setObject(3, taskId); ps.setInt(4, t.version); ps.executeUpdate() }
    }

    private fun setSetting(name: String, value: String) {
        connection.prepareStatement("SELECT set_config(?, ?, false)").use { ps -> ps.setString(1, name); ps.setString(2, value); ps.executeQuery().close() }
    }

    private fun openTask(kind: String, ownerTeam: UUID, player: UUID, season: UUID): UUID? = connection.prepareStatement(
        "SELECT task_id FROM competition.admin_task WHERE kind = ? AND owner_team_id = ? AND subject_player_id = ? AND subject_league_season_id = ? AND state NOT IN ('done','cancelled')",
    ).use { ps ->
        ps.setString(1, kind); ps.setObject(2, ownerTeam); ps.setObject(3, player); ps.setObject(4, season)
        ps.executeQuery().use { rs -> if (rs.next()) rs.getObject(1) as UUID else null }
    }

    private fun openTaskForPlayer(kind: String, player: UUID, season: UUID): UUID? = connection.prepareStatement(
        "SELECT task_id FROM competition.admin_task WHERE kind = ? AND owner_player_id = ? AND subject_league_season_id = ? AND state NOT IN ('done','cancelled')",
    ).use { ps ->
        ps.setString(1, kind); ps.setObject(2, player); ps.setObject(3, season)
        ps.executeQuery().use { rs -> if (rs.next()) rs.getObject(1) as UUID else null }
    }

    private fun openTaskBySource(kind: String, sourceId: UUID): UUID? = connection.prepareStatement(
        "SELECT task_id FROM competition.admin_task WHERE kind = ? AND source_id = ? AND state NOT IN ('done','cancelled')",
    ).use { ps -> ps.setString(1, kind); ps.setObject(2, sourceId); ps.executeQuery().use { rs -> if (rs.next()) rs.getObject(1) as UUID else null } }

    private fun confirmedRequirements(taskId: UUID): Set<String> {
        val out = mutableSetOf<String>()
        connection.prepareStatement("SELECT requirement FROM competition.admin_task_manual_confirmation WHERE task_id = ?")
            .use { ps -> ps.setObject(1, taskId); ps.executeQuery().use { rs -> while (rs.next()) out += rs.getString(1) } }
        return out
    }

    private fun activeMembers(teamId: UUID, at: Instant): List<UUID> {
        val out = mutableListOf<UUID>()
        connection.prepareStatement(
            """
            SELECT player_id FROM competition.team_membership
             WHERE team_id = ? AND status = 'active' AND valid_from <= ? AND (valid_until IS NULL OR valid_until > ?)
            """.trimIndent(),
        ).use { ps ->
            ps.setObject(1, teamId); ps.setObject(2, Timestamp.from(at)); ps.setObject(3, Timestamp.from(at))
            ps.executeQuery().use { rs -> while (rs.next()) out += rs.getObject(1) as UUID }
        }
        return out
    }

    private fun affiliatedSeasons(teamId: UUID, at: Instant): List<UUID> {
        val out = mutableListOf<UUID>()
        connection.prepareStatement(
            """
            SELECT league_season_id FROM competition.team_affiliation
             WHERE team_id = ? AND status = 'accepted' AND valid_from <= ? AND (valid_until IS NULL OR valid_until > ?)
            """.trimIndent(),
        ).use { ps ->
            ps.setObject(1, teamId); ps.setObject(2, Timestamp.from(at)); ps.setObject(3, Timestamp.from(at))
            ps.executeQuery().use { rs -> while (rs.next()) out += rs.getObject(1) as UUID }
        }
        return out
    }

    /** (policy id, parsed body) of the approved policy of [kind] in force on [on], or null. Season authority only. */
    private fun approvedPolicy(season: UUID, kind: String, on: LocalDate): Pair<UUID, Map<String, Any?>>? = connection.prepareStatement(
        """
        SELECT policy_id, body::text FROM competition.policy
         WHERE authority_kind = 'league_season' AND league_season_id = ? AND kind = ? AND approval_state IN ('approved','superseded')
           AND effective_from <= ? AND (effective_to IS NULL OR effective_to >= ?)
         ORDER BY version DESC LIMIT 1
        """.trimIndent(),
    ).use { ps ->
        ps.setObject(1, season); ps.setString(2, kind); ps.setObject(3, on); ps.setObject(4, on)
        ps.executeQuery().use { rs -> if (rs.next()) (rs.getObject(1) as UUID) to Json.parseObject(rs.getString(2)) else null }
    }

    private fun policyBody(policyId: UUID): Map<String, Any?> = connection.prepareStatement(
        "SELECT body::text FROM competition.policy WHERE policy_id = ? AND approval_state <> 'draft'",
    ).use { ps ->
        ps.setObject(1, policyId)
        ps.executeQuery().use { rs -> if (rs.next()) Json.parseObject(rs.getString(1)) else throw IllegalStateException("policy $policyId is not approved") }
    }

    /** (due instant, anchor fixture) for a deadline rule. */
    private fun deadlineFor(deadline: RegistrationDeadline, teamId: UUID, season: UUID): Pair<Instant?, UUID?> = when (deadline) {
        is RegistrationDeadline.On -> deadline.date.atTime(23, 59).atZone(london).toInstant() to null
        is RegistrationDeadline.DaysBeforeFirstFixture -> connection.prepareStatement(
            """
            SELECT fixture_id, scheduled_at FROM competition.league_fixture
             WHERE league_season_id = ? AND (home_team_id = ? OR away_team_id = ?)
             ORDER BY scheduled_at LIMIT 1
            """.trimIndent(),
        ).use { ps ->
            ps.setObject(1, season); ps.setObject(2, teamId); ps.setObject(3, teamId)
            ps.executeQuery().use { rs ->
                if (rs.next()) rs.getTimestamp(2).toInstant().minusSeconds(deadline.days * 86_400L) to (rs.getObject(1) as UUID) else null to null
            }
        }
        RegistrationDeadline.None -> null to null
    }

    /**
     * What THRØ knows about a player: through the live claim to the account, or nothing. Consent is
     * the disclosure gate itself — the same database function the submit trigger calls — so the
     * assessment can never say "consent recorded" of a minor whose only consent is their own.
     */
    private fun factsFor(playerId: UUID): RegistrationFacts = connection.prepareStatement(
        """
        SELECT a.display_name, a.age_band, identity.player_may_be_disclosed(c.player_id)
          FROM identity.player_claim c JOIN identity.account a ON a.account_id = c.account_id
         WHERE c.player_id = ? AND c.revoked_at IS NULL
        """.trimIndent(),
    ).use { ps ->
        ps.setObject(1, playerId)
        ps.executeQuery().use { rs ->
            if (!rs.next()) RegistrationFacts(hasName = false, ageBandKnown = false, accountClaimed = false, consentRecorded = false)
            else RegistrationFacts(
                hasName = !rs.getString(1).isNullOrBlank(), ageBandKnown = rs.getString(2) != "unknown",
                accountClaimed = true, consentRecorded = rs.getBoolean(3),
            )
        }
    }

    private fun liveRegistrationSubmission(playerId: UUID, season: UUID): UUID? = connection.prepareStatement(
        """
        SELECT submission_id FROM competition.submission
         WHERE kind = 'player_registration' AND subject_player_id = ? AND subject_league_season_id = ?
           AND state NOT IN ('withdrawn','rejected','superseded')
        """.trimIndent(),
    ).use { ps -> ps.setObject(1, playerId); ps.setObject(2, season); ps.executeQuery().use { rs -> if (rs.next()) rs.getObject(1) as UUID else null } }

    private data class SubmissionRow(
        val kind: String, val state: String, val version: Int, val fromTeam: UUID, val playerId: UUID?, val seasonId: UUID?,
        val proposalId: UUID?, val taskId: UUID?,
    )

    private fun submission(id: UUID): SubmissionRow? = connection.prepareStatement(
        "SELECT kind, state, row_version, from_team_id, subject_player_id, subject_league_season_id, proposal_id, task_id FROM competition.submission WHERE submission_id = ?",
    ).use { ps ->
        ps.setObject(1, id)
        ps.executeQuery().use { rs ->
            if (rs.next()) SubmissionRow(
                rs.getString(1), rs.getString(2), rs.getInt(3), rs.getObject(4) as UUID, rs.getObject(5) as UUID?,
                rs.getObject(6) as UUID?, rs.getObject(7) as UUID?, rs.getObject(8) as UUID?,
            ) else null
        }
    }

    private fun seasonLabel(season: UUID): String = connection.prepareStatement(
        "SELECT l.name || ' ' || s.label FROM competition.league_season s JOIN competition.league l ON l.league_id = s.league_id WHERE s.league_season_id = ?",
    ).use { ps -> ps.setObject(1, season); ps.executeQuery().use { rs -> if (rs.next()) rs.getString(1) else "the league" } }
}

/**
 * The smallest JSON object reader that will do for a policy body: flat keys, strings, numbers,
 * booleans, nulls, and arrays. A policy body is small and reviewed by a human before approval;
 * anything this cannot read is a body that should not have been approved.
 */
internal object Json {
    fun parseObject(text: String): Map<String, Any?> {
        val v = Parser(text.trim()).value()
        require(v is Map<*, *>) { "a policy body is a JSON object" }
        @Suppress("UNCHECKED_CAST")
        return v as Map<String, Any?>
    }

    private class Parser(val s: String) {
        var i = 0
        var depth = 0
        fun ws() { while (i < s.length && s[i].isWhitespace()) i++ }
        fun value(): Any? {
            ws()
            return when {
                s.startsWith("{", i) -> nested { obj() }
                s.startsWith("[", i) -> nested { arr() }
                s.startsWith("\"", i) -> str()
                s.startsWith("true", i) -> { i += 4; true }
                s.startsWith("false", i) -> { i += 5; false }
                s.startsWith("null", i) -> { i += 4; null }
                else -> num()
            }
        }
        /** Nesting is bounded, so a body of a hundred thousand brackets is refused rather than overflowing the stack. */
        fun <T> nested(block: () -> T): T {
            require(++depth <= 32) { "JSON nested deeper than 32 levels" }
            try { return block() } finally { depth-- }
        }
        fun obj(): Map<String, Any?> {
            val m = linkedMapOf<String, Any?>(); i++; ws()
            if (s[i] == '}') { i++; return m }
            while (true) {
                ws(); val k = str(); ws(); require(s[i] == ':'); i++
                m[k] = value(); ws()
                if (s[i] == ',') { i++; continue }
                require(s[i] == '}'); i++; return m
            }
        }
        fun arr(): List<Any?> {
            val l = mutableListOf<Any?>(); i++; ws()
            if (s[i] == ']') { i++; return l }
            while (true) {
                l += value(); ws()
                if (s[i] == ',') { i++; continue }
                require(s[i] == ']'); i++; return l
            }
        }
        fun str(): String {
            require(s[i] == '"'); i++
            val b = StringBuilder()
            while (s[i] != '"') {
                if (s[i] == '\\') { i++; b.append(when (s[i]) { 'n' -> '\n'; 't' -> '\t'; else -> s[i] }) } else b.append(s[i])
                i++
            }
            i++; return b.toString()
        }
        fun num(): Number {
            val start = i
            while (i < s.length && (s[i].isDigit() || s[i] in "-+.eE")) i++
            val t = s.substring(start, i)
            return if (t.any { it in ".eE" }) t.toDouble() else t.toLong()
        }
    }
}
