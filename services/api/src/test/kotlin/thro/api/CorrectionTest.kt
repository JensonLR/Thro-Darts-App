package thro.api

import java.sql.Connection
import java.util.UUID
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue
import thro.authz.ObjectRef
import thro.authz.ObjectType
import thro.engine.PlayerId

/**
 * The conflict-of-interest rule in the running system.
 *
 * The unit tests in `thro-authz` prove the rule algebra. These prove it is actually consulted:
 * an official correcting a match they are playing in is refused by the *service*, the refusal is
 * recorded, and no evidence is written.
 *
 * Skipped cleanly when no database is configured, rather than passing silently.
 */
class CorrectionTest {

    private val configured = TestDatabase.configured
    private fun migrated(): Connection = TestDatabase.migrated()

    @Test
    fun `an official cannot correct a match they are playing in`() {
        if (!configured) {
            println("no database configured (set PGHOST) — correction tests skipped")
            return
        }
        val c = migrated()
        val h = CommandHandler(c)
        val rel = Relations(c)
        val corrections = Corrections(c)
        var passed = 0
        fun check(name: String, cond: Boolean) {
            assertTrue(cond, "FAILED: $name")
            println("  PASS  $name")
            passed++
        }

        val eventId = UUID.randomUUID()
        val dana = UUID.randomUUID()      // tournament director, and also a competitor
        val alice = UUID.randomUUID()
        val bob = UUID.randomUUID()
        val eventObj = ObjectRef(ObjectType.EVENT, eventId.toString())

        // Two matches at the same event. Dana officiates both and plays in the second.
        val theirs = UUID.randomUUID()
        val hers = UUID.randomUUID()
        Matches(c).open(theirs, alice, bob, "Alice", "Bob", playtestFormat(PlayerId("Alice")), eventId)
        Matches(c).open(hers, dana, alice, "Dana", "Alice", playtestFormat(PlayerId("Dana")), eventId)

        rel.grant(dana, "official", eventObj)
        rel.link(ObjectRef(ObjectType.MATCH, theirs.toString()), eventObj)
        rel.link(ObjectRef(ObjectType.MATCH, hers.toString()), eventObj)
        rel.grant(alice, "participant", ObjectRef(ObjectType.MATCH, theirs.toString()))
        rel.grant(bob, "participant", ObjectRef(ObjectType.MATCH, theirs.toString()))
        rel.grant(dana, "participant", ObjectRef(ObjectType.MATCH, hers.toString()))
        rel.grant(alice, "participant", ObjectRef(ObjectType.MATCH, hers.toString()))

        var seq = 0L
        fun visit(match: UUID, player: String, total: Int): UUID {
            seq += 1
            val r = h.handle(
                VisitCommand(
                    commandId = UUID.randomUUID(), matchId = match, deviceId = alice, deviceSeq = seq,
                    actorId = alice, actorRole = "participant", correlationId = UUID.randomUUID(),
                    player = player, visitTotal = total, dartsUsed = null,
                    occurredAt = "2026-09-04T19:00:00Z", occurredTz = "Europe/London",
                ),
            )
            assertTrue(r is CommandResult.Applied, "visit was not applied: $r")
            c.prepareStatement(
                "SELECT event_id FROM evidence.event WHERE match_id = ? AND device_seq = ?",
            ).use { ps ->
                ps.setObject(1, match); ps.setLong(2, seq)
                ps.executeQuery().use { rs -> rs.next(); return rs.getObject(1) as UUID }
            }
        }

        fun events(match: UUID, type: String): Int {
            c.prepareStatement(
                "SELECT count(*) FROM evidence.event WHERE match_id = ? AND event_type = ?",
            ).use { ps ->
                ps.setObject(1, match); ps.setString(2, type)
                ps.executeQuery().use { rs -> rs.next(); return rs.getInt(1) }
            }
        }

        val theirVisit = visit(theirs, "Alice", 100)
        seq = 0L
        val herVisit = visit(hers, "Dana", 100)

        // --- the job Dana is there to do -------------------------------------------------------
        val ok = corrections.correctVisit(theirs, theirVisit, dana, 140, UUID.randomUUID(), 900)
        check("the director can correct a match they are not in", ok is Corrections.Result.Corrected)
        check("and the correction is appended", events(theirs, "VisitCorrected") == 1)
        check("the original is not touched", events(theirs, "VisitRecorded") == 1)

        c.prepareStatement(
            "SELECT corrects_event_id, payload->>'was' AS was, payload->>'visitTotal' AS now_ FROM evidence.event WHERE event_type='VisitCorrected' AND match_id = ?",
        ).use { ps ->
            ps.setObject(1, theirs)
            ps.executeQuery().use { rs ->
                rs.next()
                check("the correction names what it supersedes", rs.getObject(1) == theirVisit)
                check("and records what the value was", rs.getString("was") == "100")
                check("and what it became", rs.getString("now_") == "140")
            }
        }

        // --- the same director, the same role, her own match -------------------------------------
        val refused = corrections.correctVisit(hers, herVisit, dana, 140, UUID.randomUUID(), 901)
        check("she cannot correct her own match", refused is Corrections.Result.Refused)
        check(
            "and is told why in terms she can act on",
            (refused as Corrections.Result.Refused).why.contains("also playing"),
        )
        check("the exclusion is named", refused.excludedBy != null)
        check("and no evidence was written", events(hers, "VisitCorrected") == 0)

        // --- a stranger --------------------------------------------------------------------------
        val stranger = corrections.correctVisit(theirs, theirVisit, bob, 140, UUID.randomUUID(), 902)
        check("a competitor cannot correct anything", stranger is Corrections.Result.Refused)

        // --- both decisions are on the record ------------------------------------------------------
        c.prepareStatement(
            "SELECT allowed, granted_by, excluded_by FROM audit.decision WHERE object_id = ? ORDER BY seq",
        ).use { ps ->
            ps.setString(1, hers.toString())
            ps.executeQuery().use { rs ->
                rs.next()
                check("the refusal is audited", !rs.getBoolean("allowed"))
                check("with the authority she did hold", rs.getString("granted_by")?.contains("official") == true)
                check("and the reason it did not apply", rs.getString("excluded_by")?.contains("participant") == true)
            }
        }
        check("the audit chain is intact", Audit(c).firstBrokenLink() == null)

        // --- revocation takes effect on the next request, not on token expiry -----------------------
        rel.revoke(dana, "official", eventObj)
        val afterRevoke = corrections.correctVisit(theirs, theirVisit, dana, 60, UUID.randomUUID(), 903)
        check("a removed official loses authority immediately", afterRevoke is Corrections.Result.Refused)

        println("  $passed correction properties held")
        assertEquals(16, passed)
    }
}
