package thro.api

import java.sql.Connection
import java.util.UUID
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue
import thro.engine.PlayerId
import thro.trust.Attestation
import thro.trust.VerificationState
import thro.trust.eligibilityOf

/**
 * Per-leg participant attestation, end to end — PD-002's mechanism.
 *
 * PD-002 said plainly that with the design as it stands, results outside an organised competition
 * would not rate, because player-to-player confirmation was not authorable at all. These tests
 * exercise the path that makes it authorable.
 *
 * Skipped cleanly when no database is configured, rather than passing silently.
 */
class AttestationTest {

    private val configured = TestDatabase.configured
    private fun migrated(): Connection = TestDatabase.migrated()

    @Test
    fun `confirmation is what turns a played match into a rateable one`() {
        if (!configured) {
            println("no database configured (set PGHOST) — attestation tests skipped")
            return
        }
        val c = migrated()
        val h = CommandHandler(c)
        val att = Attestations(c)
        var passed = 0
        fun check(name: String, cond: Boolean) {
            assertTrue(cond, "FAILED: $name")
            println("  PASS  $name")
            passed++
        }

        val match = UUID.randomUUID()
        val homeId = UUID.randomUUID()
        val awayId = UUID.randomUUID()
        val scorer = UUID.randomUUID()
        Matches(c).open(match, homeId, awayId, "Home", "Away", playtestFormat(PlayerId("Home")))

        var seq = 0L
        fun visit(player: String, total: Int, darts: Int? = null, atDouble: Int? = null) {
            seq += 1
            val r = h.handle(
                VisitCommand(
                    commandId = UUID.randomUUID(), matchId = match, deviceId = scorer,
                    deviceSeq = seq, actorId = if (player == "Home") homeId else awayId,
                    actorRole = "participant", correlationId = UUID.randomUUID(),
                    player = player, visitTotal = total, dartsUsed = darts, dartsAtDouble = atDouble,
                    occurredAt = "2026-09-04T19:00:00Z", occurredTz = "Europe/London",
                ),
            )
            assertTrue(r is CommandResult.Applied, "visit $seq was not applied: $r")
        }

        // Home wins a leg 501 = 180 + 180 + 141.
        visit("Home", 180); visit("Away", 60)
        visit("Home", 180); visit("Away", 60)
        visit("Home", 141, 3, 1)

        val before = att.provenanceOf(match)!!
        check("before confirmation the result is self-reported", before.attestation == Attestation.SELF_REPORTED)
        check("and shows as such", VerificationState.of(before) == VerificationState.SELF_REPORTED)
        check("and cannot move a rating", !eligibilityOf(before, true).eligible)
        check("but it is still a played result", before.outcomeType == thro.trust.OutcomeType.PLAYED)

        // The player who did NOT score confirms the leg.
        val r = att.attest(match, 1, awayId, attested = true, deviceId = UUID.randomUUID(), deviceSeq = 1)
        check("the opponent's confirmation is recorded", r is Attestations.Result.Recorded)

        val after = att.provenanceOf(match)!!
        check("the result becomes participant-confirmed", after.attestation == Attestation.PARTICIPANT_CONFIRMED)
        check("both competitors now stand behind it", after.backers == setOf(homeId, awayId))
        check("and it becomes rateable", eligibilityOf(after, true).eligible)
        check("and can establish a rating", eligibilityOf(after, true).qualifying)

        // --- a disagreement is not a confirmation -----------------------------------------------
        val m2 = UUID.randomUUID()
        val h2 = UUID.randomUUID()
        val a2 = UUID.randomUUID()
        Matches(c).open(m2, h2, a2, "Home", "Away", playtestFormat(PlayerId("Home")))
        var s2 = 0L
        fun visit2(player: String, total: Int, darts: Int? = null, atDouble: Int? = null) {
            s2 += 1
            h.handle(
                VisitCommand(
                    commandId = UUID.randomUUID(), matchId = m2, deviceId = scorer, deviceSeq = s2,
                    actorId = if (player == "Home") h2 else a2, actorRole = "participant",
                    correlationId = UUID.randomUUID(), player = player, visitTotal = total,
                    dartsUsed = darts, dartsAtDouble = atDouble,
                    occurredAt = "2026-09-04T19:00:00Z", occurredTz = "Europe/London",
                ),
            )
        }
        visit2("Home", 180); visit2("Away", 60); visit2("Home", 180); visit2("Away", 60)
        visit2("Home", 141, 3, 1)
        att.attest(m2, 1, a2, attested = false, deviceId = UUID.randomUUID(), deviceSeq = 1)
        val disagreed = att.provenanceOf(m2)!!
        check("a disagreement does not confirm", disagreed.attestation == Attestation.SELF_REPORTED)
        check("and the match stays unrateable", !eligibilityOf(disagreed, true).eligible)

        // --- an outsider cannot attest -----------------------------------------------------------
        val outsider = att.attest(match, 1, UUID.randomUUID(), true, UUID.randomUUID(), 2)
        check("a stranger cannot attest", outsider is Attestations.Result.Refused)

        // --- the attestation is evidence, in trust's own stream ----------------------------------
        c.prepareStatement(
            "SELECT count(*) FROM evidence.event WHERE match_id = ? AND event_type = 'LegAttested'",
        ).use { ps ->
            ps.setObject(1, match)
            ps.executeQuery().use { rs ->
                rs.next()
                check("the confirmation is itself evidence", rs.getInt(1) == 1)
            }
        }

        // --- confirming one leg of a longer match is not agreeing to the match --------------------
        val m3 = UUID.randomUUID()
        val h3 = UUID.randomUUID()
        val a3 = UUID.randomUUID()
        Matches(c).open(m3, h3, a3, "Home", "Away", playtestFormat(PlayerId("Home")))
        var s3 = 0L
        // Driven from the engine's own state rather than assuming who throws: the loser of a leg
        // throws first in the next one, and hardcoding "Home" made the second leg silently never
        // happen, which made this test pass for the wrong reason.
        fun visit3(total: Int, darts: Int? = null, atDouble: Int? = null) {
            val state = h.replayFor(m3, scorer, "Home", "Away")
            val thrower = state.thrower ?: return
            s3 += 1
            val r = h.handle(
                VisitCommand(
                    commandId = UUID.randomUUID(), matchId = m3, deviceId = scorer, deviceSeq = s3,
                    actorId = if (thrower.value == "Home") h3 else a3, actorRole = "participant",
                    correlationId = UUID.randomUUID(), player = thrower.value, visitTotal = total,
                    dartsUsed = darts, dartsAtDouble = atDouble,
                    occurredAt = "2026-09-04T19:00:00Z", occurredTz = "Europe/London",
                ),
            )
            assertTrue(r is CommandResult.Applied, "m3 visit $s3 ($thrower $total) was refused: $r")
        }
        // Two complete legs: whoever is to throw scores 180, 180, 141 while the other throws 60s.
        repeat(2) {
            visit3(180); visit3(60); visit3(180); visit3(60); visit3(141, 3, 1)
        }
        // Both legs really did complete — otherwise the assertion below proves nothing.
        c.prepareStatement(
            """
            SELECT count(*) FROM evidence.event WHERE match_id = ?
              AND payload->>'effect' IN ('leg_won','set_won','match_won')
            """.trimIndent(),
        ).use { ps ->
            ps.setObject(1, m3)
            ps.executeQuery().use { rs -> rs.next(); check("two legs were played", rs.getInt(1) == 2) }
        }
        att.attest(m3, 1, a3, attested = true, deviceId = UUID.randomUUID(), deviceSeq = 1)
        val partial = att.provenanceOf(m3)!!
        check(
            "confirming one leg of two does not confirm the match",
            partial.attestation == Attestation.SELF_REPORTED,
        )
        att.attest(m3, 2, a3, attested = true, deviceId = UUID.randomUUID(), deviceSeq = 2)
        check(
            "confirming every leg does",
            att.provenanceOf(m3)!!.attestation == Attestation.PARTICIPANT_CONFIRMED,
        )

        println("  $passed attestation properties held")
        assertEquals(16, passed)
    }
}
