package thro.api

import java.sql.Connection
import java.util.UUID
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue
import thro.authz.ObjectRef
import thro.authz.ObjectType
import thro.engine.PlayerId
import thro.trust.IneligibilityReason
import thro.trust.VerificationState
import thro.trust.eligibilityOf

/**
 * Disputes, adjudication and quarantine.
 *
 * The property worth stating plainly: none of these destroys anything. A dispute does not unmake a
 * result, a quarantine does not hide one, and neither is stored as a verification state — they are
 * separate facts that the derived label and the eligibility answer both read.
 *
 * Skipped cleanly when no database is configured, rather than passing silently.
 */
class DisputeTest {

    private val configured = TestDatabase.configured
    private fun migrated(): Connection = TestDatabase.migrated()

    @Test
    fun `a dispute suspends belief without destroying anything`() {
        if (!configured) {
            println("no database configured (set PGHOST) — dispute tests skipped")
            return
        }
        val c = migrated()
        val h = CommandHandler(c)
        val d = Disputes(c)
        val att = Attestations(c)
        val rel = Relations(c)
        var passed = 0
        fun check(name: String, cond: Boolean) {
            assertTrue(cond, "FAILED: $name")
            println("  PASS  $name")
            passed++
        }

        val eventId = UUID.randomUUID()
        val eventObj = ObjectRef(ObjectType.EVENT, eventId.toString())
        val alice = UUID.randomUUID()
        val bob = UUID.randomUUID()
        val dana = UUID.randomUUID()
        val match = UUID.randomUUID()
        Matches(c).open(match, alice, bob, "Alice", "Bob", playtestFormat(PlayerId("Alice")), eventId)
        rel.grant(dana, "official", eventObj)
        rel.link(ObjectRef(ObjectType.MATCH, match.toString()), eventObj)
        rel.grant(alice, "participant", ObjectRef(ObjectType.MATCH, match.toString()))
        rel.grant(bob, "participant", ObjectRef(ObjectType.MATCH, match.toString()))

        var seq = 0L
        fun visit(player: String, total: Int, darts: Int? = null, atDouble: Int? = null) {
            seq += 1
            h.handle(
                VisitCommand(
                    commandId = UUID.randomUUID(), matchId = match, deviceId = alice, deviceSeq = seq,
                    actorId = alice, actorRole = "participant", correlationId = UUID.randomUUID(),
                    player = player, visitTotal = total, dartsUsed = darts, dartsAtDouble = atDouble,
                    occurredAt = "2026-09-04T19:00:00Z", occurredTz = "Europe/London",
                ),
            )
        }
        visit("Alice", 180); visit("Bob", 60); visit("Alice", 180); visit("Bob", 60)
        visit("Alice", 141, 3, 1)
        att.attest(match, 1, bob, attested = true, deviceId = UUID.randomUUID(), deviceSeq = 1)

        check("the match starts rateable", eligibilityOf(att.provenanceOf(match)!!, true).eligible)

        // --- a participant disputes ---------------------------------------------------------------
        val raised = d.raise(match, bob, 1, "the checkout was 140 not 141", UUID.randomUUID(), 2)
        check("a participant can raise a dispute", raised is Disputes.Result.Raised)
        val p1 = att.provenanceOf(match)!!
        check("the match shows as disputed", VerificationState.of(p1) == VerificationState.DISPUTED)
        check("and stops being rateable", !eligibilityOf(p1, true).eligible)
        check("for the stated reason", IneligibilityReason.DISPUTED in eligibilityOf(p1, true).reasons)
        check("but the result is not unmade", att.provenanceOf(match)!!.participants.size == 2)
        c.prepareStatement("SELECT count(*) FROM evidence.event WHERE match_id = ? AND event_type='VisitRecorded'").use { ps ->
            ps.setObject(1, match)
            ps.executeQuery().use { rs -> rs.next(); check("and no evidence is removed", rs.getInt(1) == 5) }
        }

        val outsider = d.raise(match, UUID.randomUUID(), 1, "I disagree", UUID.randomUUID(), 3)
        check("a non-participant cannot dispute", outsider is Disputes.Result.Refused)

        // --- adjudication carries the conflict-of-interest exclusion -------------------------------
        val herMatch = UUID.randomUUID()
        Matches(c).open(herMatch, dana, alice, "Dana", "Alice", playtestFormat(PlayerId("Dana")), eventId)
        rel.link(ObjectRef(ObjectType.MATCH, herMatch.toString()), eventObj)
        rel.grant(dana, "participant", ObjectRef(ObjectType.MATCH, herMatch.toString()))
        var hs = 0L
        fun herVisit(player: String, total: Int, darts: Int? = null, atDouble: Int? = null) {
            hs += 1
            h.handle(
                VisitCommand(
                    commandId = UUID.randomUUID(), matchId = herMatch, deviceId = dana, deviceSeq = hs,
                    actorId = dana, actorRole = "participant", correlationId = UUID.randomUUID(),
                    player = player, visitTotal = total, dartsUsed = darts, dartsAtDouble = atDouble,
                    occurredAt = "2026-09-04T19:00:00Z", occurredTz = "Europe/London",
                ),
            )
        }
        herVisit("Dana", 180)
        val hers = d.raise(herMatch, alice, 1, "wrong", UUID.randomUUID(), 1)
        val hersId = (hers as Disputes.Result.Raised).disputeId
        val refused = d.adjudicate(hersId, dana, "rejected", UUID.randomUUID(), 2)
        check("an official cannot rule on their own match", refused is Disputes.Result.Refused)
        check(
            "and is told why",
            (refused as Disputes.Result.Refused).why.contains("also playing"),
        )

        // --- but can rule on someone else's ---------------------------------------------------------
        val id = (raised as Disputes.Result.Raised).disputeId
        val ruled = d.adjudicate(id, dana, "rejected", UUID.randomUUID(), 4)
        check("an official can rule on a match they are not in", ruled is Disputes.Result.Resolved)
        check("the dispute closes", d.openDisputeCount(match) == 0)
        val p2 = att.provenanceOf(match)!!
        check("and the match becomes rateable again", eligibilityOf(p2, true).eligible)

        val again = d.adjudicate(id, dana, "upheld", UUID.randomUUID(), 5)
        check("a resolved dispute cannot be re-ruled", again is Disputes.Result.Refused)

        // --- quarantine is orthogonal, and carries no accusation --------------------------------------
        val q = d.quarantine(match, dana, "device_fault", "clock skew on one device", UUID.randomUUID(), 6)
        check("a match can be quarantined", q is Disputes.Result.Quarantined)
        val p3 = att.provenanceOf(match)!!
        check("eligibility is suspended", !eligibilityOf(p3, true).eligible)
        check("for the stated reason", IneligibilityReason.QUARANTINED in eligibilityOf(p3, true).reasons)
        check(
            "but the verification label is untouched",
            VerificationState.of(p3) == VerificationState.of(p2),
        )
        check("and the result keeps its place", d.isQuarantined(match))

        val lifted = d.lift((q as Disputes.Result.Quarantined).quarantineId, dana, UUID.randomUUID(), 7)
        check("quarantine is reversible", lifted is Disputes.Result.Lifted)
        check("and eligibility returns", eligibilityOf(att.provenanceOf(match)!!, true).eligible)
        check("the lift is recorded, not deleted", !d.isQuarantined(match))
        c.prepareStatement("SELECT count(*) FROM trust.quarantine WHERE match_id = ?").use { ps ->
            ps.setObject(1, match)
            ps.executeQuery().use { rs -> rs.next(); check("the quarantine row survives", rs.getInt(1) == 1) }
        }

        println("  $passed dispute properties held")
        assertEquals(23, passed)
    }
}
