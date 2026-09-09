package thro.api

import java.sql.Connection
import java.time.Instant
import java.time.LocalDate
import java.time.temporal.ChronoUnit
import java.util.UUID
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue
import org.postgresql.util.PSQLException
import thro.authz.ObjectRef
import thro.authz.ObjectType
import thro.competition.InboxSection
import thro.competition.MembershipRole
import thro.competition.RegistrationFact
import thro.competition.SubmissionState
import thro.competition.Transport

/**
 * THRØ Secretary end to end (execution plan §7), against a real PostgreSQL.
 *
 * The scenario is one league season with an example registration policy — a fixture in this test,
 * not any real league's rules — one team joining it, and three players: an adult with an account,
 * a placeholder the captain typed in, and a claimed minor. What the test exists to prove is not the
 * happy path but the refusals: THRØ cannot say the league accepted anything, a team admin cannot
 * say it either, a placeholder or a minor without consent never leaves THRØ, a draft policy
 * registers nobody, and no task is manufactured.
 *
 * Skipped cleanly when no database is configured, rather than passing silently.
 */
class SecretaryTest {

    /** True when [block] is refused with a message containing [fragment]; prints the message otherwise, so a wrong refusal is visible. */
    private fun refused(fragment: String, block: () -> Unit): Boolean {
        val message = try {
            block(); return false
        } catch (e: PSQLException) {
            e.serverErrorMessage?.message ?: e.message!!
        } catch (e: IllegalStateException) {
            e.message!!
        } catch (e: IllegalArgumentException) {
            e.message!!
        }
        if (!message.contains(fragment)) println("  refused, but not for '$fragment': $message")
        return message.contains(fragment)
    }

    @Test
    fun `a sporting fact entered once produces the administration that follows, and never the league's answer`() {
        if (!TestDatabase.configured) {
            println("no database configured (set PGHOST) — secretary tests skipped")
            return
        }
        val c: Connection = TestDatabase.migrated()
        val orgs = Organisations(c)
        val sec = Secretary(c)
        val rel = Relations(c)
        var passed = 0
        fun check(name: String, cond: Boolean) {
            assertTrue(cond, "FAILED: $name")
            println("  PASS  $name")
            passed++
        }
        fun state(id: UUID) = sec.submissionState(id)
        fun version(id: UUID) = c.prepareStatement("SELECT row_version FROM competition.submission WHERE submission_id = ?")
            .use { ps -> ps.setObject(1, id); ps.executeQuery().use { rs -> rs.next(); rs.getInt(1) } }
        fun taskState(id: UUID) = c.prepareStatement("SELECT state FROM competition.admin_task WHERE task_id = ?")
            .use { ps -> ps.setObject(1, id); ps.executeQuery().use { rs -> rs.next(); rs.getString(1) } }

        // --- the world ------------------------------------------------------------------------------
        val ade = UUID.randomUUID()      // Riverside A admin
        val lee = UUID.randomUUID()      // league season admin (the secretary)
        val gil = UUID.randomUUID()      // Grange A admin
        val device = UUID.randomUUID()
        val t0 = Instant.parse("2026-09-01T18:00:00Z")
        val league = orgs.createLeague("Teesside Thursday League")
        val season = orgs.openSeason(league, "2026/27", LocalDate.of(2026, 9, 1), LocalDate.of(2027, 5, 31))
        rel.grant(lee, "admin", ObjectRef(ObjectType.LEAGUE_SEASON, season.toString()))
        val riverside = orgs.createTeam("Riverside A", by = ade)
        val grange = orgs.createTeam("Grange A", by = gil)
        rel.grant(ade, "admin", ObjectRef(ObjectType.TEAM, riverside.toString()))
        rel.grant(gil, "admin", ObjectRef(ObjectType.TEAM, grange.toString()))
        val venue = orgs.createVenue("Riverside Club")
        orgs.openTenure(riverside, venue, from = t0)

        // The example policy: name, age band and consent required, seven days before the first fixture.
        val policyV1 = orgs.draftPolicy(
            "league_season", season, "registration", 1, LocalDate.of(2026, 9, 1),
            """{"requires":["name","age_band","consent"],"deadline_days_before_first_fixture":7}""", by = lee,
        )

        // Three people.
        fun account(name: String, ageBand: String, via: String): UUID {
            val id = UUID.randomUUID()
            c.prepareStatement("INSERT INTO identity.account (account_id, display_name, age_band, age_assurance, created_via) VALUES (?, ?, ?, ?, ?)")
                .use { ps ->
                    ps.setObject(1, id); ps.setString(2, name); ps.setString(3, ageBand)
                    ps.setString(4, if (ageBand == "unknown") "none" else "self_declared"); ps.setString(5, via); ps.executeUpdate()
                }
            return id
        }
        val samAccount = account("Sam Wilson", "adult", "self")
        val sam = orgs.createPlayer(source = "self"); orgs.claim(sam, samAccount, "self_created")
        val joAccount = account("Jo Bloggs", "unknown", "team_admin")           // typed in by the captain; unclaimed
        val jo = orgs.createPlayer(source = "team_admin", by = ade)
        val kimAccount = account("Kim Park", "minor", "self")
        val kim = orgs.createPlayer(source = "self"); orgs.claim(kim, kimAccount, "self_created")

        check("a self-created account carries its own consent record", c.prepareStatement(
            "SELECT consent_basis FROM identity.account WHERE account_id = ?",
        ).use { ps -> ps.setObject(1, samAccount); ps.executeQuery().use { rs -> rs.next(); rs.getString(1) == "self" } })
        check("an account somebody else typed in starts with no consent basis, whatever was passed", c.prepareStatement(
            "SELECT consent_basis FROM identity.account WHERE account_id = ?",
        ).use { ps -> ps.setObject(1, joAccount); ps.executeQuery().use { rs -> rs.next(); rs.getString(1) == "none" } })

        // --- 1. Nothing is owed until the facts line up ---------------------------------------------
        orgs.addMember(riverside, sam, MembershipRole.CAPTAIN, from = t0)
        check("a member of a team affiliated to nothing owes nothing", sec.reconcileTeam(riverside, t0.plusSeconds(1)).isEmpty())
        orgs.affiliate(riverside, season, from = t0)
        c.prepareStatement("UPDATE competition.team_affiliation SET status = 'accepted', accepted_at = clock_timestamp() WHERE team_id = ?")
            .use { ps -> ps.setObject(1, riverside); ps.executeUpdate() }
        check("an affiliation with no approved policy owes nothing either", sec.reconcileTeam(riverside, t0.plusSeconds(1)).isEmpty())
        orgs.approvePolicy(policyV1, by = lee)
        orgs.affiliate(grange, season, from = t0)
        c.prepareStatement("UPDATE competition.team_affiliation SET status = 'accepted', accepted_at = clock_timestamp() WHERE team_id = ?")
            .use { ps -> ps.setObject(1, grange); ps.executeUpdate() }
        val firstFixtureAt = Instant.parse("2026-10-08T19:30:00Z")
        val fixture = orgs.scheduleFixture(season, null, riverside, grange, at = firstFixtureAt)

        // --- 2. The fact: Sam is a member. Reconciliation derives exactly one task ------------------
        val created = sec.reconcileTeam(riverside, t0.plusSeconds(2), by = ade)
        check("an active member of an affiliated team under an approved policy owes one registration", created.size == 1)
        val samTask = created.single()
        check("the task is due seven days before the team's first fixture", c.prepareStatement(
            "SELECT due_at, due_rule, due_anchor_fixture_id, policy_id FROM competition.admin_task WHERE task_id = ?",
        ).use { ps ->
            ps.setObject(1, samTask)
            ps.executeQuery().use { rs ->
                rs.next() && rs.getTimestamp(1).toInstant() == firstFixtureAt.minus(7, ChronoUnit.DAYS) &&
                    rs.getString(2) == "days_before_first_fixture:7" && rs.getObject(3) == fixture && rs.getObject(4) == policyV1
            }
        })
        check("running the reconciliation again manufactures nothing", sec.reconcileTeam(riverside, t0.plusSeconds(3)).isEmpty())
        check("the same task cannot be inserted twice by hand either", refused("task_one_open_per_subject") {
            c.prepareStatement(
                """
                INSERT INTO competition.admin_task (task_id, kind, owner_team_id, source_kind, subject_player_id, subject_league_season_id, reason, policy_id)
                VALUES (?, 'registration_required', ?, 'reconciliation', ?, ?, 'dup', ?)
                """.trimIndent(),
            ).use { ps -> ps.setObject(1, UUID.randomUUID()); ps.setObject(2, riverside); ps.setObject(3, sam); ps.setObject(4, season); ps.setObject(5, policyV1); ps.executeUpdate() }
        })

        // --- 3. Assessment: Sam has everything; a submission is prepared ------------------------------
        val samAssessed = sec.assessRegistration(samTask, by = ade)
        check("an adult with a claimed account and their own consent is missing nothing", samAssessed.missing.isEmpty() && samAssessed.submissionId != null)
        val samSub = samAssessed.submissionId!!
        check("the submission is ready and the task waits on the league", state(samSub) == "ready" && taskState(samTask) == "waiting_league")
        check("the league does not see a submission before it is sent", sec.submissionsForLeague(season).isEmpty())

        // --- 4. Sending needs a person; delivery needs the transport's evidence ----------------------
        check("THRO alone cannot submit", refused("needs a named person") {
            c.prepareStatement("INSERT INTO competition.submission_transition (submission_id, expected_version, from_state, to_state) VALUES (?, ${version(samSub)}, 'ready', 'submitted')")
                .use { ps -> ps.setObject(1, samSub); ps.executeUpdate() }
        })
        check("the team admin submits", sec.submit(samSub, by = ade) is Secretary.Moved.Ok && state(samSub) == "submitted")
        check("a replayed transition carrying the old version is refused as stale", refused("stale transition") {
            c.prepareStatement("INSERT INTO competition.submission_transition (submission_id, expected_version, from_state, to_state, actor_id) VALUES (?, 2, 'ready', 'submitted', ?)")
                .use { ps -> ps.setObject(1, samSub); ps.setObject(2, ade); ps.executeUpdate() }
        })
        // The CHECK constraint refuses it before the trigger runs: 'delivery' evidence is a delivery row, or nothing.
        check("a message id typed into a form is not delivery evidence", refused("transition_evidence_is_consistent") {
            c.prepareStatement("INSERT INTO competition.submission_transition (submission_id, expected_version, from_state, to_state, evidence_kind, note) VALUES (?, ${version(samSub)}, 'submitted', 'delivered', 'delivery', 'msg-123')")
                .use { ps -> ps.setObject(1, samSub); ps.executeUpdate() }
        })
        val bounce = sec.recordDeliveryAttempt(samSub, Transport.EMAIL, "smtp", "msg-1", status = "failed", detail = "mailbox full")
        check("a failed delivery attempt is delivery_failed, not delivered", bounce is Secretary.Moved.Ok && state(samSub) == "delivery_failed")
        check("a failed delivery cannot be called delivered", refused("does not move") {
            sec.recordDeliveryAttempt(samSub, Transport.EMAIL, "smtp", "msg-1b", status = "delivered").let { if (it is Secretary.Moved.Refused) throw IllegalStateException(it.why) }
        })
        sec.retry(samSub, by = ade); sec.submit(samSub, by = ade)
        val delivered = sec.recordDeliveryAttempt(samSub, Transport.EMAIL, "smtp", "msg-2", status = "delivered")
        check("a delivery attempt that reports delivered moves it", delivered is Secretary.Moved.Ok && state(samSub) == "delivered")
        check("both attempts are on the record", c.prepareStatement("SELECT count(*) FROM competition.submission_delivery WHERE submission_id = ?")
            .use { ps -> ps.setObject(1, samSub); ps.executeQuery().use { rs -> rs.next(); rs.getInt(1) == 2 } })
        check("now the league sees it", sec.submissionsForLeague(season) == listOf(samSub to "delivered"))

        // --- 5. Acknowledgement and acceptance are the league's words ----------------------------------
        check("the team admin cannot acknowledge on the league's behalf",
            sec.acknowledge(samSub, by = ade, note = "they got it") is Secretary.Moved.Refused && state(samSub) == "delivered")
        check("THRO alone cannot acknowledge", refused("THRO alone") {
            c.prepareStatement("INSERT INTO competition.submission_transition (submission_id, expected_version, from_state, to_state, evidence_kind, note) VALUES (?, ${version(samSub)}, 'delivered', 'acknowledged', 'human_confirmation', 'x')")
                .use { ps -> ps.setObject(1, samSub); ps.executeUpdate() }
        })
        val reply = sec.captureArtefact(samSub, "counterparty_message", "s3://thro/artefacts/reply-1.eml", "a".repeat(64), by = lee)
        check("the league secretary acknowledges with their reply on file",
            sec.acknowledge(samSub, by = lee, artefactId = reply) is Secretary.Moved.Ok && state(samSub) == "acknowledged")
        check("an acceptance must say from which date", refused("from which date") {
            sec.answer(samSub, SubmissionState.ACCEPTED, by = lee, artefactId = reply).let { if (it is Secretary.Moved.Refused) throw IllegalStateException(it.why) }
        })
        check("an acceptance with conditions is not an acceptance", refused("accepted_conditional") {
            sec.answer(samSub, SubmissionState.ACCEPTED, by = lee, artefactId = reply, registeredFrom = LocalDate.of(2026, 9, 15), conditions = "subject to fee")
                .let { if (it is Secretary.Moved.Refused) throw IllegalStateException(it.why) }
        })
        check("the team admin cannot accept their own player", sec.answer(samSub, SubmissionState.ACCEPTED, by = ade, note = "yes", registeredFrom = LocalDate.of(2026, 9, 15)) is Secretary.Moved.Refused)
        check("Sam is not registered before the league says so", !orgs.isRegistered(sam, season, Instant.parse("2026-09-20T00:00:00Z")))
        val accepted = sec.answer(samSub, SubmissionState.ACCEPTED, by = lee, artefactId = reply, registeredFrom = LocalDate.of(2026, 9, 15))
        check("the league secretary accepts from 15 September", accepted is Secretary.Moved.Ok && state(samSub) == "accepted")
        check("Sam is registered from that date, under the policy in force on it, and not before",
            orgs.isRegistered(sam, season, Instant.parse("2026-09-20T00:00:00Z")) && !orgs.isRegistered(sam, season, Instant.parse("2026-09-10T00:00:00Z")) &&
                c.prepareStatement("SELECT policy_id FROM competition.player_registration WHERE player_id = ? AND status = 'registered'")
                    .use { ps -> ps.setObject(1, sam); ps.executeQuery().use { rs -> rs.next() && rs.getObject(1) == policyV1 } })
        check("the task is done, with its history", taskState(samTask) == "done" && c.prepareStatement(
            "SELECT array_agg(to_state ORDER BY at) FROM competition.admin_task_event WHERE task_id = ?",
        ).use { ps -> ps.setObject(1, samTask); ps.executeQuery().use { rs -> rs.next(); (rs.getArray(1).array as Array<*>).toList() == listOf("waiting_league", "done") } })
        check("every transition names who moved it, and the league's ones name the league", c.prepareStatement(
            "SELECT array_agg(coalesce(actor_id::text, 'THRO') ORDER BY at) FROM competition.submission_transition WHERE submission_id = ? AND to_state IN ('acknowledged','accepted')",
        ).use { ps -> ps.setObject(1, samSub); ps.executeQuery().use { rs -> rs.next(); (rs.getArray(1).array as Array<*>).all { it == lee.toString() } } })
        check("a terminal submission does not move", refused("does not move") {
            c.prepareStatement("INSERT INTO competition.submission_transition (submission_id, expected_version, from_state, to_state, actor_id, evidence_kind, note) VALUES (?, ${version(samSub)}, 'accepted', 'rejected', ?, 'human_confirmation', 'changed mind')")
                .use { ps -> ps.setObject(1, samSub); ps.setObject(2, lee); ps.executeUpdate() }
        })
        check("no application role may update a submission row directly", refused("permission denied") {
            c.createStatement().use { it.execute("SET ROLE app_competition") }
            try {
                c.prepareStatement("UPDATE competition.submission SET state = 'accepted' WHERE submission_id = ?").use { ps -> ps.setObject(1, samSub); ps.executeUpdate() }
            } finally { c.createStatement().use { it.execute("RESET ROLE") } }
        })

        // --- 6. Jo: a placeholder the captain typed in. Nothing about Jo leaves THRO -----------------
        orgs.addMember(riverside, jo, from = t0)
        val joTask = sec.reconcileTeam(riverside, t0.plusSeconds(4), by = ade).single()
        val joAssessed = sec.assessRegistration(joTask, by = ade)
        check("an unclaimed placeholder is missing its name, age band and consent — THRO holds none of them for a player nobody has claimed",
            joAssessed.missing == setOf(RegistrationFact.NAME, RegistrationFact.AGE_BAND, RegistrationFact.CONSENT) && taskState(joTask) == "waiting_player")
        check("the missing facts are materialised on the task", c.prepareStatement("SELECT missing_facts FROM competition.admin_task WHERE task_id = ?")
            .use { ps -> ps.setObject(1, joTask); ps.executeQuery().use { rs -> rs.next(); (rs.getArray(1).array as Array<*>).size == 3 } })
        // Even if someone forged a submission row for Jo, the gate refuses to send it.
        val forged = UUID.randomUUID()
        c.prepareStatement(
            "INSERT INTO competition.submission (submission_id, kind, from_team_id, to_league_season_id, subject_player_id, subject_league_season_id, policy_id) VALUES (?, 'player_registration', ?, ?, ?, ?, ?)",
        ).use { ps -> ps.setObject(1, forged); ps.setObject(2, riverside); ps.setObject(3, season); ps.setObject(4, jo); ps.setObject(5, season); ps.setObject(6, policyV1); ps.executeUpdate() }
        c.prepareStatement("INSERT INTO competition.submission_transition (submission_id, expected_version, from_state, to_state) VALUES (?, 1, 'draft', 'ready')").use { ps -> ps.setObject(1, forged); ps.executeUpdate() }
        check("a submission about an unclaimed player cannot be submitted, whoever tries", sec.submit(forged, by = ade).let { it is Secretary.Moved.Refused && it.why.contains("PD-029") })

        // --- 7. Kim: a claimed minor. Their guardian's consent is the player's task, not the captain's --
        orgs.addMember(riverside, kim, from = t0)
        val kimTask = sec.reconcileTeam(riverside, t0.plusSeconds(5), by = ade).single()
        val kimAssessed = sec.assessRegistration(kimTask, by = ade)
        check("a minor with their own account is missing only consent", kimAssessed.missing == setOf(RegistrationFact.CONSENT))
        val kimConsentTask = sec.inboxForPlayer(kim)[InboxSection.UPCOMING]?.singleOrNull { it.kind == "consent_required" }
        check("a consent task is owed by the player, not the team", kimConsentTask != null && taskState(kimConsentTask.taskId) == "open")
        // A self consent from a minor is not enough: unknown is not adult, and minor is not adult.
        sec.recordConsent(kimAccount, "self", givenBy = kimAccount, artefactRef = "in_app_tap")
        check("a minor's own consent does not open the gate", !c.prepareStatement("SELECT identity.player_may_be_disclosed(?)")
            .use { ps -> ps.setObject(1, kim); ps.executeQuery().use { rs -> rs.next(); rs.getBoolean(1) } })
        val guardian = UUID.randomUUID()
        sec.recordConsent(kimAccount, "guardian", givenBy = guardian, artefactRef = "s3://thro/consent/kim-guardian.pdf")
        check("a guardian's consent does, and closes the player's consent task",
            c.prepareStatement("SELECT identity.player_may_be_disclosed(?)").use { ps -> ps.setObject(1, kim); ps.executeQuery().use { rs -> rs.next(); rs.getBoolean(1) } } &&
                taskState(kimConsentTask!!.taskId) == "done")
        val kimAgain = sec.assessRegistration(kimTask, by = ade)
        check("reassessment prepares the submission", kimAgain.submissionId != null && state(kimAgain.submissionId!!) == "ready")
        check("and it can now be submitted", sec.submit(kimAgain.submissionId!!, by = ade) is Secretary.Moved.Ok)

        // --- 8. Policy v2 mid-season: old tasks keep citing v1 --------------------------------------------
        val policyV2 = orgs.draftPolicy(
            "league_season", season, "registration", 2, LocalDate.of(2026, 11, 1),
            """{"requires":["name","age_band","consent"],"manual_requirements":["passport photo"],"deadline_days_before_first_fixture":7}""", by = lee,
        )
        orgs.supersedePolicy(policyV1, LocalDate.of(2026, 10, 31)); orgs.approvePolicy(policyV2, by = lee)
        check("an in-flight task still cites the version it was made under", c.prepareStatement("SELECT policy_id FROM competition.admin_task WHERE task_id = ?")
            .use { ps -> ps.setObject(1, kimTask); ps.executeQuery().use { rs -> rs.next(); rs.getObject(1) == policyV1 } })
        val pat = orgs.createPlayer(source = "self").also { orgs.claim(it, account("Pat Ng", "adult", "self"), "self_created") }
        orgs.addMember(riverside, pat, from = Instant.parse("2026-11-05T18:00:00Z"))
        val patTask = sec.reconcileTeam(riverside, Instant.parse("2026-11-05T19:00:00Z"), by = ade).single()
        check("a new member after v2 is assessed under v2", c.prepareStatement("SELECT policy_id FROM competition.admin_task WHERE task_id = ?")
            .use { ps -> ps.setObject(1, patTask); ps.executeQuery().use { rs -> rs.next(); rs.getObject(1) == policyV2 } })
        val patAssessed = sec.assessRegistration(patTask, by = ade)
        check("a requirement THRO cannot check is a manual step, outstanding by name", patAssessed.manualOutstanding == listOf("passport photo") && patAssessed.submissionId == null)
        sec.confirmManualRequirement(patTask, "passport photo", by = ade, note = "photo handed to the league secretary at the AGM")
        check("a named confirmation with a note satisfies it, and nothing else does", sec.assessRegistration(patTask, by = ade).submissionId != null)

        // --- 9. A registration cannot cite a draft policy, whoever writes it -----------------------------
        val draft = orgs.draftPolicy("league_season", season, "registration", 3, LocalDate.of(2027, 1, 1), "{}", by = lee)
        check("a registration under a draft policy is refused at the row", refused("approved and in force") {
            orgs.register(pat, season, riverside, draft, from = Instant.parse("2027-01-05T00:00:00Z"))
        })

        // --- 10. Deadlines follow the fixture, and the change is logged ---------------------------------
        val moved = OrganisationCommands(c).handle(
            OrganisationCommands.Command.RearrangeFixture(UUID.randomUUID(), device, lee, fixture, firstFixtureAt.plus(14, ChronoUnit.DAYS), expectedVersion = 1),
        )
        check("the league moved the fixture", moved is OrganisationCommands.Result.Applied)
        val changeId = c.prepareStatement("SELECT change_id FROM competition.league_fixture_change WHERE fixture_id = ?").use { ps -> ps.setObject(1, fixture); ps.executeQuery().use { rs -> rs.next(); rs.getObject(1) as UUID } }
        val refreshed = sec.refreshDeadlines(fixture, changeId)
        check("every open task anchored on it is recomputed", refreshed == 3)   // Jo, Kim, Pat; Sam's is done
        check("the old deadline survives in the task's history, against the change that caused it", c.prepareStatement(
            "SELECT from_due_at, to_due_at, cause_change_id FROM competition.admin_task_event WHERE task_id = ? AND from_due_at IS DISTINCT FROM to_due_at",
        ).use { ps ->
            ps.setObject(1, kimTask)
            ps.executeQuery().use { rs ->
                rs.next() && rs.getTimestamp(1).toInstant() == firstFixtureAt.minus(7, ChronoUnit.DAYS) &&
                    rs.getTimestamp(2).toInstant() == firstFixtureAt.plus(7, ChronoUnit.DAYS) && rs.getObject(3) == changeId
            }
        })

        // --- 11. The same engine: results ------------------------------------------------------------------
        val match = UUID.randomUUID()
        Matches(c).open(match, riverside, grange, "Riverside A", "Grange A", playtestFormat(thro.engine.PlayerId("Riverside A")))
        c.prepareStatement("UPDATE competition.league_fixture SET match_id = ?, row_version = 3 WHERE fixture_id = ? AND row_version = 2")
            .use { ps -> ps.setObject(1, match); ps.setObject(2, fixture); check("the fixture is linked to its match once", ps.executeUpdate() == 1) }
        val played = UUID.randomUUID()
        c.prepareStatement("INSERT INTO competition.league_fixture_outcome (outcome_id, fixture_id, kind, legs_home, legs_away, decided_by) VALUES (?, ?, 'played', 5, 4, ?)")
            .use { ps -> ps.setObject(1, played); ps.setObject(2, fixture); ps.setObject(3, ade); ps.executeUpdate() }
        val resultTask = sec.onFixtureOutcome(played, dueAt = firstFixtureAt.plus(16, ChronoUnit.DAYS), by = ade)
        check("a played outcome makes the home team owe the league a result card, prepared and ready", resultTask != null &&
            c.prepareStatement("SELECT state FROM competition.submission WHERE outcome_id = ?").use { ps -> ps.setObject(1, played); ps.executeQuery().use { rs -> rs.next() && rs.getString(1) == "ready" } })
        check("recording it twice manufactures nothing", sec.onFixtureOutcome(played, dueAt = firstFixtureAt.plus(16, ChronoUnit.DAYS)) == null)
        val other = orgs.scheduleFixture(season, null, grange, riverside, at = firstFixtureAt.plus(30, ChronoUnit.DAYS))
        val award = orgs.awardFixture(other, grange, "Riverside could not raise a side", by = lee)
        check("an outcome the league decided itself creates no task — that would be busywork", sec.onFixtureOutcome(award, dueAt = firstFixtureAt) == null)
        val resultSub = c.prepareStatement("SELECT submission_id FROM competition.submission WHERE outcome_id = ?").use { ps -> ps.setObject(1, played); ps.executeQuery().use { rs -> rs.next(); rs.getObject(1) as UUID } }
        sec.submit(resultSub, by = ade); sec.recordDeliveryAttempt(resultSub, Transport.EMAIL, "smtp", "msg-9", status = "delivered")
        orgs.voidOutcome(fixture, supersedes = played, reason = "wrong scoreline entered; to be re-recorded", by = lee)
        check("voiding the outcome supersedes the result submission that carried it", state(resultSub) == "superseded")

        // --- 12. The same engine: a rearrangement is proposed to the opponent, who answers ----------------
        val prop = sec.proposeRearrangement(other, byTeamId = riverside, to = firstFixtureAt.plus(37, ChronoUnit.DAYS), dueAt = firstFixtureAt.plus(20, ChronoUnit.DAYS), by = ade, reason = "venue double-booked")
        check("the proposal reaches the opponent as a delivered submission and an open task of theirs",
            state(prop.submissionId) == "delivered" && taskState(prop.taskId) == "open" &&
                c.prepareStatement("SELECT owner_team_id FROM competition.admin_task WHERE task_id = ?").use { ps -> ps.setObject(1, prop.taskId); ps.executeQuery().use { rs -> rs.next() && rs.getObject(1) == grange } })
        check("the proposer cannot answer their own proposal", sec.acknowledge(prop.submissionId, by = ade, note = "fine by us") is Secretary.Moved.Refused)
        check("the opponent's admin acknowledges and accepts", sec.acknowledge(prop.submissionId, by = gil, note = "seen") is Secretary.Moved.Ok &&
            sec.answer(prop.submissionId, SubmissionState.ACCEPTED, by = gil, note = "agreed") is Secretary.Moved.Ok)
        check("the proposal is accepted and the opponent's task done", taskState(prop.taskId) == "done" &&
            c.prepareStatement("SELECT state, answered_by FROM competition.fixture_rearrangement_proposal WHERE proposal_id = ?").use { ps -> ps.setObject(1, prop.proposalId); ps.executeQuery().use { rs -> rs.next() && rs.getString(1) == "accepted" && rs.getObject(2) == gil } })
        check("the fixture has not moved: a team's agreement is not the league's act",
            c.prepareStatement("SELECT scheduled_at FROM competition.league_fixture WHERE fixture_id = ?").use { ps -> ps.setObject(1, other); ps.executeQuery().use { rs -> rs.next() && rs.getTimestamp(1).toInstant() == firstFixtureAt.plus(30, ChronoUnit.DAYS) } })
        val applied = sec.applyProposal(prop.proposalId, by = lee, deviceId = device, expectedFixtureVersion = 1)
        check("the league applies it through the same command as any rearrangement, and the change cites the proposal",
            applied is OrganisationCommands.Result.Applied &&
                c.prepareStatement("SELECT proposal_id FROM competition.league_fixture_change WHERE fixture_id = ?").use { ps -> ps.setObject(1, other); ps.executeQuery().use { rs -> rs.next() && rs.getObject(1) == prop.proposalId } })

        // --- 13. The inbox ------------------------------------------------------------------------------------
        val now = firstFixtureAt.plus(8, ChronoUnit.DAYS)   // after the recomputed deadline of the 15th? no: the 15th is 7 days before the 22nd
        val inbox = sec.inbox(riverside, now)
        check("the captain's inbox groups by state and deadline",
            inbox[InboxSection.COMPLETED]?.map { it.taskId }?.containsAll(listOf(samTask)) == true &&
                inbox[InboxSection.WAITING_FOR_PLAYER]?.any { it.taskId == joTask } == true &&
                inbox[InboxSection.WAITING_FOR_LEAGUE]?.any { it.taskId == kimTask } == true)

        println("  $passed secretary properties held")
        assertEquals(62, passed)
    }
}
