package thro.api

import java.sql.Connection
import java.util.UUID
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertTrue

/**
 * What happens to a report when it is no longer needed (PD-087).
 *
 * V040 made a report undeletable, and it was right to: a report must not be quietly made to go away by
 * whoever it embarrasses. The DPIA puts the other side — the free text a reporter wrote may be about
 * somebody's health or sexuality, and holding that for ever, about children, is not a defensible position.
 *
 * These hold the resolution: **nobody may delete a report, and time may.** Every one of them would pass if
 * the door had been left open instead, except the first, which is the one that matters.
 */
class RetentionTest {
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

    /**
     * A report about `subject`, decided `days` ago.
     *
     * The decision is inserted with its own `decided_at` rather than made through `Safety.decide` and then
     * backdated — **because backdating is refused**, by the same trigger these tests are about. That is the
     * guarantee working, and it is worth having tripped over: there is no way to make a decision look older
     * than it is, which is what stops somebody accelerating a report out of the database.
     */
    private fun decidedReport(c: Connection, by: UUID, subject: UUID, days: Int, outcome: String = "hidden") {
        val report = Safety(c).report(by, "account", subject, "Something was said.").reportId
        decidedAt(c, report, by, outcome, days)
    }

    private fun decidedAt(c: Connection, report: UUID, by: UUID, outcome: String, days: Int) {
        c.createStatement().use { st ->
            st.execute("INSERT INTO safety.decision (report_id, outcome, note, decided_by, decided_at) " +
                       "VALUES ('$report', '$outcome', 'Looked at it.', '$by', " +
                       "clock_timestamp() - interval '$days days')")
        }
    }

    private fun forget(c: Connection, older: String = "2 years"): Int =
        c.createStatement().use { st ->
            st.executeQuery("SELECT safety.forget_decided(interval '$older')").use { rs -> rs.next(); rs.getInt(1) }
        }

    @Test
    fun `nobody may delete a report, and the exception is not reachable by asking`() {
        if (!configured) return
        migrated().use { c ->
            val ann = account(c, "Ann")
            decidedReport(c, ann, ann, days = 1000)
            // The guarantee V040 made, unchanged. A support script, an administrator and the subject all get
            // this, and there is no argument to `decide` or `report` that changes it.
            assertTrue(assertFailsWith<Exception> {
                c.createStatement().use { st -> st.executeUpdate("DELETE FROM safety.report") }
            }.message!!.contains("a report is kept"))
            assertTrue(assertFailsWith<Exception> {
                c.createStatement().use { st -> st.executeUpdate("DELETE FROM safety.decision") }
            }.message!!.contains("a decision is kept"))
            assertEquals(1, count(c, "SELECT count(*) FROM safety.report"))
        }
    }

    @Test
    fun `a decided report is forgotten once the decision is old enough`() {
        if (!configured) return
        migrated().use { c ->
            val ann = account(c, "Ann")
            decidedReport(c, ann, ann, days = 800)
            assertEquals(1, forget(c))
            assertEquals(0, count(c, "SELECT count(*) FROM safety.report"))
            assertEquals(0, count(c, "SELECT count(*) FROM safety.decision"))
        }
    }

    @Test
    fun `a recent decision is left alone`() {
        if (!configured) return
        migrated().use { c ->
            val ann = account(c, "Ann")
            decidedReport(c, ann, ann, days = 30)
            assertEquals(0, forget(c))
            assertEquals(1, count(c, "SELECT count(*) FROM safety.report"))
        }
    }

    @Test
    fun `an undecided report is never forgotten however old it is`() {
        if (!configured) return
        migrated().use { c ->
            val ann = account(c, "Ann")
            val report = Safety(c).report(ann, "account", ann, "Nobody ever looked at this.").reportId
            // No backdating needed, and none possible: `forget_decided` looks at decisions, and this report
            // has none. A report that has sat unanswered for five years is a failure of process, and deleting
            // it would tidy the evidence of that away — which is the opposite of what retention is for.
            assertTrue(report.toString().isNotEmpty())
            assertEquals(0, forget(c))
            assertEquals(1, count(c, "SELECT count(*) FROM safety.report"))
        }
    }

    @Test
    fun `a report with any recent decision survives, even if an older one exists`() {
        if (!configured) return
        migrated().use { c ->
            val ann = account(c, "Ann")
            val safety = Safety(c)
            val report = safety.report(ann, "account", ann, "Something was said.").reportId
            decidedAt(c, report, ann, "hidden", days = 900)
            // A second, recent decision — somebody looked again. The clock runs from the newest, because the
            // matter is live as long as anybody is still deciding it.
            safety.decide(report, "not_upheld", "Looked again; leaving it.", ann)
            assertEquals(0, forget(c))
            assertEquals(2, count(c, "SELECT count(*) FROM safety.decision"))
        }
    }

    @Test
    fun `what survives is a count, with no words and no reporter`() {
        if (!configured) return
        migrated().use { c ->
            val ann = account(c, "Ann")
            val subject = account(c, "Bob")
            decidedReport(c, ann, subject, days = 800, outcome = "hidden")
            decidedReport(c, ann, subject, days = 900, outcome = "hidden")
            decidedReport(c, ann, subject, days = 850, outcome = "not_upheld")
            assertEquals(3, forget(c))

            // Two hidden and one not upheld, against Bob. A repeat offender still shows across seasons —
            // which is the thing safeguarding needs — and the allegations themselves are gone.
            assertEquals(2, count(c, "SELECT decisions FROM safety.decision_tally " +
                                     "WHERE subject_id = '$subject' AND outcome = 'hidden'"))
            assertEquals(1, count(c, "SELECT decisions FROM safety.decision_tally " +
                                     "WHERE subject_id = '$subject' AND outcome = 'not_upheld'"))
            assertEquals(0, count(c, "SELECT count(*) FROM information_schema.columns " +
                                     "WHERE table_schema = 'safety' AND table_name = 'decision_tally' " +
                                     "AND column_name IN ('reason', 'note', 'reported_by', 'decided_by')"),
                         "the tally must never grow a column that carries what was said or who said it")
        }
    }

    @Test
    fun `forgetting twice adds up rather than starting again`() {
        if (!configured) return
        migrated().use { c ->
            val ann = account(c, "Ann")
            val subject = account(c, "Bob")
            decidedReport(c, ann, subject, days = 800)
            assertEquals(1, forget(c))
            decidedReport(c, ann, subject, days = 900)
            assertEquals(1, forget(c))
            assertEquals(2, count(c, "SELECT decisions FROM safety.decision_tally " +
                                     "WHERE subject_id = '$subject' AND outcome = 'hidden'"),
                         "a tally that reset on the second run would forget the first offence")
        }
    }

    @Test
    fun `the sweep the server runs uses the founder's period and nothing shorter`() {
        if (!configured) return
        // One value in one place: the sweep the server runs on its own clock is the same code path a test
        // can call. A period that lived in two places would drift, and nobody would know which was in force.
        assertEquals("2 years", thro.api.http.Retention.KEEP)
        migrated().use { c ->
            val ann = account(c, "Ann")
            decidedReport(c, ann, ann, days = 700)   // inside two years — 730 days
            assertEquals(0, thro.api.http.Retention.sweep(c))
            assertEquals(1, count(c, "SELECT count(*) FROM safety.report"))

            decidedReport(c, ann, ann, days = 800)   // outside it
            assertEquals(1, thro.api.http.Retention.sweep(c))
            assertEquals(1, count(c, "SELECT count(*) FROM safety.report"), "and the recent one is untouched")
        }
    }

    @Test
    fun `the door closes behind it`() {
        if (!configured) return
        migrated().use { c ->
            val ann = account(c, "Ann")
            decidedReport(c, ann, ann, days = 800)
            assertEquals(1, forget(c))
            // `set_config(..., true)` is transaction-local, and the test's connection is autocommit — so by
            // the time the next statement runs the key is gone. A leak here would mean a pooled connection
            // could delete a report at any time afterwards, which is the whole risk of doing it this way.
            decidedReport(c, ann, ann, days = 10)
            assertTrue(assertFailsWith<Exception> {
                c.createStatement().use { st -> st.executeUpdate("DELETE FROM safety.report") }
            }.message!!.contains("a report is kept"))
        }
    }
}
