package thro.api

import java.sql.Connection
import java.sql.Timestamp
import java.time.Duration
import java.time.Instant
import java.util.UUID

/**
 * Reports, blocks and the terms (PD-050, V040).
 *
 * The four things Apple's guideline 1.2 and Google Play's user-generated-content policy ask of an app that
 * carries what people write: it can be reported, people can be blocked, somebody answers, and there is a way
 * to reach us. Three of them are here; the fourth is an address in the terms.
 *
 * **A report is a record.** It names the thing, keeps who raised it and when, and carries the hour by which
 * it is answered. Nothing is destroyed by a report: a decision hides, corrects, suspends or leaves it, and
 * says which. **A block needs no reason** — a player may want to be left alone — and is lifted, never
 * deleted. **Accepting the terms** is recorded with the version accepted, because "which version" is the
 * only honest answer to "what did they agree to".
 */
public class Safety(private val connection: Connection, private val now: () -> Instant = Instant::now) {

    public class Refused(public val why: String, public val status: Int? = null) : Exception(why)

    public data class Report(val reportId: UUID, val subjectKind: String, val subjectId: UUID,
                             val reason: String, val urgent: Boolean, val reportedAt: Instant, val answerDueAt: Instant)
    public data class Queued(val report: Report, val decisions: Int)

    public companion object {
        /** What can be reported: the things a person writes that another person reads. */
        public val SUBJECTS: Set<String> = setOf("account", "team", "venue", "league", "match")
        /** The promise the stores hold us to, and the one the queue sorts by. */
        public val ANSWER_WITHIN: Duration = Duration.ofHours(24)
        /** The terms a player accepts before they may write anything anyone else reads. */
        public const val TERMS_VERSION: String = "2026-09-11"
    }

    /**
     * Reports something. [urgent] is set by the caller for a report raised by, or about, somebody THRØ knows
     * to be a child; it puts the report at the front of the queue and is never left to the day-long clock.
     */
    public fun report(by: UUID, subjectKind: String, subjectId: UUID, reason: String, urgent: Boolean = false): Report {
        if (subjectKind !in SUBJECTS) throw Refused("THRØ does not know how to report that.")
        val clean = reason.trim()
        if (clean.length !in 3..600) throw Refused("Say what is wrong with it, in a sentence.")
        val at = now()
        val due = at.plus(ANSWER_WITHIN)
        val id = UUID.randomUUID()
        connection.prepareStatement(
            """INSERT INTO safety.report (report_id, subject_kind, subject_id, reported_by, reason, urgent, reported_at, answer_due_at)
               VALUES (?, ?, ?, ?, ?, ?, ?, ?)""",
        ).use { ps ->
            ps.setObject(1, id); ps.setString(2, subjectKind); ps.setObject(3, subjectId); ps.setObject(4, by)
            ps.setString(5, clean); ps.setBoolean(6, urgent)
            ps.setTimestamp(7, Timestamp.from(at)); ps.setTimestamp(8, Timestamp.from(due))
            ps.executeUpdate()
        }
        return Report(id, subjectKind, subjectId, clean, urgent, at, due)
    }

    /** What is waiting to be answered: the urgent first, then by the hour it is due. */
    public fun queue(limit: Int = 50): List<Queued> =
        connection.prepareStatement(
            """SELECT r.report_id, r.subject_kind, r.subject_id, r.reason, r.urgent, r.reported_at, r.answer_due_at,
                      (SELECT count(*) FROM safety.decision d WHERE d.report_id = r.report_id)
                 FROM safety.report r
                ORDER BY (SELECT count(*) FROM safety.decision d WHERE d.report_id = r.report_id) ASC,
                         r.urgent DESC, r.answer_due_at ASC
                LIMIT ?""",
        ).use { ps ->
            ps.setInt(1, limit)
            ps.executeQuery().use { rs ->
                generateSequence {
                    if (!rs.next()) null
                    else Queued(
                        Report(rs.getObject(1) as UUID, rs.getString(2), rs.getObject(3) as UUID, rs.getString(4),
                               rs.getBoolean(5), rs.getTimestamp(6).toInstant(), rs.getTimestamp(7).toInstant()),
                        rs.getInt(8),
                    )
                }.toList()
            }
        }

    /** Answers a report. A second look is a second decision, never an edit of the first. */
    public fun decide(reportId: UUID, outcome: String, note: String, by: UUID): UUID {
        if (outcome !in setOf("left", "hidden", "corrected", "account_suspended", "not_upheld")) {
            throw Refused("That is not one of the answers a report can have.")
        }
        val clean = note.trim()
        if (clean.length !in 3..1000) throw Refused("Say why, so the decision can be read back.")
        // A decision on a report that is not there is a mistyped id, not a server fault. Left to the foreign
        // key it would arrive as a 500; asked first, it is answered with what is actually true.
        connection.prepareStatement("SELECT 1 FROM safety.report WHERE report_id = ?").use { ps ->
            ps.setObject(1, reportId)
            if (!ps.executeQuery().use { it.next() }) throw Refused("That report is not on the queue.", 404)
        }
        val id = UUID.randomUUID()
        connection.prepareStatement(
            "INSERT INTO safety.decision (decision_id, report_id, outcome, note, decided_by) VALUES (?, ?, ?, ?, ?)",
        ).use { ps ->
            ps.setObject(1, id); ps.setObject(2, reportId); ps.setString(3, outcome)
            ps.setString(4, clean); ps.setObject(5, by); ps.executeUpdate()
        }
        return id
    }

    /**
     * One account asks not to be reached by another. Saying it twice is saying it once.
     *
     * The hour is written from this class's clock rather than left to the column's default, exactly as a
     * report's is. A class that is handed a clock must use it everywhere or it has not got one: letting the
     * database stamp `clock_timestamp()` here while [lift] reads the injected clock put the block in one time
     * and its lifting in another, and a lift a minute after a block made at a fixed hour then matched no row
     * at all.
     */
    public fun block(blocker: UUID, blocked: UUID) {
        if (blocker == blocked) throw Refused("You cannot block yourself.")
        connection.prepareStatement(
            "INSERT INTO safety.block (blocker_id, blocked_id, blocked_at) VALUES (?, ?, ?) ON CONFLICT DO NOTHING",
        ).use { ps ->
            ps.setObject(1, blocker); ps.setObject(2, blocked); ps.setTimestamp(3, Timestamp.from(now()))
            ps.executeUpdate()
        }
    }

    /**
     * And lifts it. The row is kept, marked lifted; blocking again later is a new block.
     *
     * Whether the lift comes after the block is V040's `a_lift_comes_after` to enforce, not this statement's
     * to screen for. The screen was here, as `AND ? > blocked_at`, and it turned a nonsensical lift into a
     * silent no-op: somebody asked to unblock, nothing happened, and nothing said so. A constraint that
     * raises is the better half of that trade — it cannot be reached by a sane clock, and it is loud.
     */
    public fun lift(blocker: UUID, blocked: UUID) {
        connection.prepareStatement(
            "UPDATE safety.block SET lifted_at = ? WHERE blocker_id = ? AND blocked_id = ? AND lifted_at IS NULL",
        ).use { ps ->
            ps.setTimestamp(1, Timestamp.from(now())); ps.setObject(2, blocker); ps.setObject(3, blocked)
            ps.executeUpdate()
        }
    }

    /** Whether either has blocked the other: asked wherever one person could reach another. */
    public fun blocked(a: UUID, b: UUID): Boolean =
        connection.prepareStatement("SELECT safety.is_blocked(?, ?)").use { ps ->
            ps.setObject(1, a); ps.setObject(2, b)
            ps.executeQuery().use { rs -> rs.next() && rs.getBoolean(1) }
        }

    /** The accounts this one has blocked, for the list they manage it from. */
    public fun blocking(account: UUID): List<UUID> =
        connection.prepareStatement(
            "SELECT blocked_id FROM safety.block WHERE blocker_id = ? AND lifted_at IS NULL ORDER BY blocked_at DESC",
        ).use { ps ->
            ps.setObject(1, account)
            ps.executeQuery().use { rs -> generateSequence { if (rs.next()) rs.getObject(1) as UUID else null }.toList() }
        }

    /** Records that this account accepted this version of the terms. Accepting twice changes nothing. */
    public fun acceptTerms(account: UUID, version: String = TERMS_VERSION) {
        connection.prepareStatement(
            "INSERT INTO safety.terms_acceptance (account_id, version) VALUES (?, ?) ON CONFLICT DO NOTHING",
        ).use { ps -> ps.setObject(1, account); ps.setString(2, version); ps.executeUpdate() }
    }

    /** Whether they have accepted the version now in force — the gate before anybody writes anything. */
    public fun hasAcceptedTerms(account: UUID, version: String = TERMS_VERSION): Boolean =
        connection.prepareStatement(
            "SELECT 1 FROM safety.terms_acceptance WHERE account_id = ? AND version = ?",
        ).use { ps ->
            ps.setObject(1, account); ps.setString(2, version)
            ps.executeQuery().use { it.next() }
        }

    public fun json(r: Report): String =
        """{"reportId":"${r.reportId}","subjectKind":"${r.subjectKind}","subjectId":"${r.subjectId}",""" +
            """"urgent":${r.urgent},"reportedAt":"${r.reportedAt}","answerDueAt":"${r.answerDueAt}"}"""
}
