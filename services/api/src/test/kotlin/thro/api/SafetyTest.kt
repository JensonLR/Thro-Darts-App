package thro.api

import java.sql.Connection
import java.time.Instant
import java.util.UUID
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertFalse
import kotlin.test.assertTrue

/**
 * Reporting, blocking and the terms (PD-050): what the stores require of an app that carries what people
 * write, held against a real database.
 */
class SafetyTest {
    private val configured = TestDatabase.configured
    private fun migrated(): Connection = TestDatabase.migrated()

    private fun account(c: Connection, name: String): UUID {
        val id = UUID.randomUUID()
        c.createStatement().use { st ->
            st.execute("INSERT INTO identity.account (account_id, display_name, age_band, age_assurance) " +
                       "VALUES ('$id', '$name', 'adult', 'self_declared')")
        }
        return id
    }

    private fun count(c: Connection, sql: String): Int =
        c.createStatement().use { st -> st.executeQuery(sql).use { rs -> rs.next(); rs.getInt(1) } }

    @Test
    fun `a report is raised, answered within a day, and kept whatever is decided`() {
        if (!configured) return
        migrated().use { c ->
            val at = Instant.parse("2026-09-11T21:00:00Z")
            val safety = Safety(c) { at }
            val ann = account(c, "Ann")
            val moderator = account(c, "Moderator")
            val team = Organisations(c).createTeam("A Rude Name", "Stockton-on-Tees")

            assertEquals("THRØ does not know how to report that.",
                         assertFailsWith<Safety.Refused> { safety.report(ann, "weather", team, "it is raining") }.why)
            assertEquals("Say what is wrong with it, in a sentence.",
                         assertFailsWith<Safety.Refused> { safety.report(ann, "team", team, " ") }.why)

            val report = safety.report(ann, "team", team, "  The name is a slur.  ")
            assertEquals("The name is a slur.", report.reason, "trimmed, and kept as they wrote it")
            assertEquals(at.plus(Safety.ANSWER_WITHIN), report.answerDueAt, "answered within a day, as the stores require")
            assertFalse(report.urgent)

            assertEquals(listOf(report.reportId), safety.queue().map { it.report.reportId })
            assertEquals(0, safety.queue().first().decisions, "nobody has answered it yet")

            assertEquals("That is not one of the answers a report can have.",
                         assertFailsWith<Safety.Refused> { safety.decide(report.reportId, "ignored", "no", moderator) }.why)
            safety.decide(report.reportId, "hidden", "The name is hidden until the team renames it.", moderator)
            assertEquals(1, safety.queue().first().decisions)
            assertEquals(1, count(c, "SELECT count(*) FROM safety.report"), "a report is kept, whatever was decided")

            // A second look is a second decision, never an edit of the first.
            safety.decide(report.reportId, "corrected", "The team renamed itself.", moderator)
            assertEquals(2, count(c, "SELECT count(*) FROM safety.decision WHERE report_id = '${report.reportId}'"))
        }
    }

    @Test
    fun `a report raised by or about a child goes to the front of the queue`() {
        if (!configured) return
        migrated().use { c ->
            val at = Instant.parse("2026-09-11T21:00:00Z")
            val ann = account(c, "Ann")
            val team = Organisations(c).createTeam("The Sun Inn", "Stockton-on-Tees")
            val ordinary = Safety(c) { at }.report(ann, "team", team, "The name is wrong.")
            val urgent = Safety(c) { at.plusSeconds(60) }.report(ann, "account", ann, "A child is being contacted.", urgent = true)

            assertEquals(listOf(urgent.reportId, ordinary.reportId), Safety(c) { at }.queue().map { it.report.reportId },
                         "the urgent one first, though it was raised later")
        }
    }

    @Test
    fun `a block needs no reason, is lifted rather than deleted, and both sides are blocked`() {
        if (!configured) return
        migrated().use { c ->
            val at = Instant.parse("2026-09-11T21:00:00Z")
            val safety = Safety(c) { at }
            val ann = account(c, "Ann")
            val bea = account(c, "Bea")

            assertEquals("You cannot block yourself.", assertFailsWith<Safety.Refused> { safety.block(ann, ann) }.why)
            assertFalse(safety.blocked(ann, bea))

            safety.block(ann, bea)
            safety.block(ann, bea)
            assertEquals(1, count(c, "SELECT count(*) FROM safety.block"), "blocking twice is blocking once")
            assertTrue(safety.blocked(ann, bea))
            assertTrue(safety.blocked(bea, ann), "the one who was blocked cannot reach back either")
            assertEquals(listOf(bea), safety.blocking(ann))
            assertTrue(safety.blocking(bea).isEmpty(), "and it is not their block to manage")

            Safety(c) { at.plusSeconds(60) }.lift(ann, bea)
            assertFalse(safety.blocked(ann, bea))
            assertEquals(1, count(c, "SELECT count(*) FROM safety.block"), "the block is kept, marked lifted")
            assertEquals(1, count(c, "SELECT count(*) FROM safety.block WHERE lifted_at IS NOT NULL"))

            Safety(c) { at.plusSeconds(120) }.block(ann, bea)
            assertEquals(2, count(c, "SELECT count(*) FROM safety.block"), "blocking again is a new block")
        }
    }

    @Test
    fun `the terms are accepted once per version, and the version is what was agreed to`() {
        if (!configured) return
        migrated().use { c ->
            val safety = Safety(c) { Instant.parse("2026-09-11T21:00:00Z") }
            val ann = account(c, "Ann")

            assertFalse(safety.hasAcceptedTerms(ann), "nobody posts before agreeing")
            safety.acceptTerms(ann)
            safety.acceptTerms(ann)
            assertTrue(safety.hasAcceptedTerms(ann))
            assertEquals(1, count(c, "SELECT count(*) FROM safety.terms_acceptance WHERE account_id = '$ann'"))

            assertFalse(safety.hasAcceptedTerms(ann, "2027-01-01"), "new terms are a new agreement")
            safety.acceptTerms(ann, "2027-01-01")
            assertEquals(2, count(c, "SELECT count(*) FROM safety.terms_acceptance WHERE account_id = '$ann'"),
                         "and what they agreed to on each day is still readable")
        }
    }
}
