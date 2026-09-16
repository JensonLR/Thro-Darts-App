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
public class Safety(private val connection: Connection, private val reader: Reader? = null, private val now: () -> Instant = Instant::now) {

    public class Refused(public val why: String, public val status: Int? = null) : Exception(why)

    public data class Report(val reportId: UUID, val subjectKind: String, val subjectId: UUID,
                             val reason: String, val urgent: Boolean, val reportedAt: Instant, val answerDueAt: Instant,
                             /** False for a report THRØ raised itself from its reading of a name (PD-118). */
                             val raisedByAPerson: Boolean = true)
    /**
     * A report as the person answering it needs it: with [subject], the name somebody read (PD-101), and [reading],
     * what THRØ made of it (PD-118) — a hint beside the report, never an answer to it. A moderator cannot judge an
     * id, and the name is exactly the thing most reports are about.
     */
    public data class Queued(val report: Report, val decisions: Int, val subject: String, val reading: Reading? = null)

    public companion object {
        /** What can be reported: the things a person writes that another person reads. */
        public val SUBJECTS: Set<String> = setOf("account", "team", "venue", "league", "match")
        /** The promise the stores hold us to, and the one the queue sorts by. */
        public val ANSWER_WITHIN: Duration = Duration.ofHours(24)
        /** The terms a player accepts before they may write anything anyone else reads. */
        public const val TERMS_VERSION: String = "2026-09-11"
        /**
         * The probability at which THRØ's reading acts on its own (PD-118): a report this likely to concern a child goes
         * to the front of the queue, and a name this likely to be abuse or impersonation is put on the queue. Conservative
         * on purpose — a reading below it changes nothing but the order — and to be revisited against real reports.
         */
        public const val ACTS_AT: Double = 0.85
    }

    /**
     * Reports something. [urgent] is set by the caller for a report raised by, or about, somebody THRØ knows
     * to be a child; it puts the report at the front of the queue and is never left to the day-long clock.
     *
     * With a [reader], the report is read as it arrives (PD-118) and the reading kept beside it; a reading that says a
     * child is likely at risk makes the report urgent as surely as the caller can. A reader that answers nothing, or
     * fails, leaves the report exactly as it was: the reading is beside the report, never in its way.
     */
    public fun report(by: UUID, subjectKind: String, subjectId: UUID, reason: String, urgent: Boolean = false): Report {
        if (subjectKind !in SUBJECTS) throw Refused("THRØ does not know how to report that.")
        val clean = reason.trim()
        if (clean.length !in 3..600) throw Refused("Say what is wrong with it, in a sentence.")
        // Read before it is written: a report is append-only (V040's trigger), so whether it is urgent is decided once.
        val reading = runCatching { reader?.readReport(subjectKind, subjectName(subjectKind, subjectId), clean) }.getOrNull()
        val front = urgent || (reading != null && reading.childSafety >= ACTS_AT)
        val at = now()
        val due = at.plus(ANSWER_WITHIN)
        val id = UUID.randomUUID()
        connection.prepareStatement(
            """INSERT INTO safety.report (report_id, subject_kind, subject_id, reported_by, reason, urgent, reported_at, answer_due_at)
               VALUES (?, ?, ?, ?, ?, ?, ?, ?)""",
        ).use { ps ->
            ps.setObject(1, id); ps.setString(2, subjectKind); ps.setObject(3, subjectId); ps.setObject(4, by)
            ps.setString(5, clean); ps.setBoolean(6, front)
            ps.setTimestamp(7, Timestamp.from(at)); ps.setTimestamp(8, Timestamp.from(due))
            ps.executeUpdate()
        }
        if (reading != null) keep(id, reading.category, reading.categoryConfidence, reading.childSafety, reading.severity, reading.model)
        return Report(id, subjectKind, subjectId, clean, front, at, due)
    }

    /**
     * Reads a name somebody chose (PD-118) — a display name, a team name — and, when it reads as abuse or as
     * impersonation, raises a report of THRØ's own for a person to answer. Nothing is refused and nothing is hidden:
     * a person decides, within the day, as for any report. A name already waiting on the queue is not reported twice.
     * Without a reader, or with one that cannot answer, nothing happens.
     */
    public fun noteName(kind: String, subjectId: UUID, name: String) {
        val reading = runCatching { reader?.readName(kind, name) }.getOrNull() ?: return
        val (category, probability) = when {
            reading.abusive >= ACTS_AT -> "abusive_name" to reading.abusive
            reading.impersonates >= ACTS_AT -> "impersonation" to reading.impersonates
            else -> return
        }
        val waiting = connection.prepareStatement(
            """SELECT count(*) FROM safety.report r
                WHERE r.subject_kind = ? AND r.subject_id = ? AND r.reported_by IS NULL
                  AND NOT EXISTS (SELECT 1 FROM safety.decision d WHERE d.report_id = r.report_id)""",
        ).use { ps -> ps.setString(1, kind); ps.setObject(2, subjectId); ps.executeQuery().use { rs -> rs.next(); rs.getInt(1) } }
        if (waiting > 0) return
        val what = if (category == "abusive_name") "likely abusive" else "likely to be impersonating somebody"
        val reason = "THRØ read the name “$name” as $what (${(probability * 100).toInt()}%). Nobody reported it; please look."
        val at = now()
        val id = UUID.randomUUID()
        connection.prepareStatement(
            """INSERT INTO safety.report (report_id, subject_kind, subject_id, reported_by, reason, urgent, reported_at, answer_due_at)
               VALUES (?, ?, ?, NULL, ?, false, ?, ?)""",
        ).use { ps ->
            ps.setObject(1, id); ps.setString(2, kind); ps.setObject(3, subjectId); ps.setString(4, reason.take(600))
            ps.setTimestamp(5, Timestamp.from(at)); ps.setTimestamp(6, Timestamp.from(at.plus(ANSWER_WITHIN)))
            ps.executeUpdate()
        }
        keep(id, category, probability, null, null, reading.model)
    }

    private fun keep(reportId: UUID, category: String, confidence: Double, childSafety: Double?, severity: Double?, model: String) {
        connection.prepareStatement(
            "INSERT INTO safety.judgment (report_id, category, confidence, child_safety, severity, model, judged_at) VALUES (?, ?, ?, ?, ?, ?, ?)",
        ).use { ps ->
            ps.setObject(1, reportId); ps.setString(2, category); ps.setDouble(3, confidence)
            if (childSafety == null) ps.setNull(4, java.sql.Types.DOUBLE) else ps.setDouble(4, childSafety)
            if (severity == null) ps.setNull(5, java.sql.Types.DOUBLE) else ps.setDouble(5, severity)
            ps.setString(6, model); ps.setTimestamp(7, Timestamp.from(now()))
            ps.executeUpdate()
        }
    }

    /** The name somebody read (PD-101), as the queue shows it. */
    private fun subjectName(kind: String, id: UUID): String = connection.prepareStatement(
        """SELECT CASE ?
              WHEN 'account' THEN (SELECT coalesce(nullif(a.display_name, ''), 'An account with no name') FROM identity.account a WHERE a.account_id = ?)
              WHEN 'team'    THEN (SELECT t.name FROM competition.team t WHERE t.team_id = ?)
              WHEN 'venue'   THEN (SELECT v.name FROM competition.venue v WHERE v.venue_id = ?)
              WHEN 'league'  THEN (SELECT l.name FROM competition.league l WHERE l.league_id = ?)
              WHEN 'match'   THEN 'A match'
            END""",
    ).use { ps ->
        ps.setString(1, kind); for (i in 2..5) ps.setObject(i, id)
        ps.executeQuery().use { rs -> rs.next(); rs.getString(1) ?: "Not on THRØ any more" }
    }

    /**
     * What is waiting to be answered: the urgent first, then what THRØ read as most serious (PD-118), then by the
     * hour it is due. A report with no reading sorts as least serious, never as unread.
     */
    public fun queue(limit: Int = 50): List<Queued> =
        connection.prepareStatement(
            """SELECT r.report_id, r.subject_kind, r.subject_id, r.reason, r.urgent, r.reported_at, r.answer_due_at,
                      (SELECT count(*) FROM safety.decision d WHERE d.report_id = r.report_id),
                      -- The name somebody read (PD-101). A match names nobody: the report says what happened,
                      -- and the people in it are not the moderator's to browse from a queue.
                      CASE r.subject_kind
                        WHEN 'account' THEN (SELECT coalesce(nullif(a.display_name, ''), 'An account with no name')
                                               FROM identity.account a WHERE a.account_id = r.subject_id)
                        WHEN 'team'    THEN (SELECT t.name FROM competition.team t WHERE t.team_id = r.subject_id)
                        WHEN 'venue'   THEN (SELECT v.name FROM competition.venue v WHERE v.venue_id = r.subject_id)
                        WHEN 'league'  THEN (SELECT l.name FROM competition.league l WHERE l.league_id = r.subject_id)
                        WHEN 'match'   THEN 'A match'
                      END,
                      r.reported_by IS NOT NULL,
                      j.category, j.confidence, j.child_safety, j.severity, j.model
                 FROM safety.report r
                 LEFT JOIN safety.judgment j ON j.report_id = r.report_id
                ORDER BY (SELECT count(*) FROM safety.decision d WHERE d.report_id = r.report_id) ASC,
                         r.urgent DESC, coalesce(j.severity, -1) DESC, r.answer_due_at ASC
                LIMIT ?""",
        ).use { ps ->
            ps.setInt(1, limit)
            ps.executeQuery().use { rs ->
                generateSequence {
                    if (!rs.next()) null
                    else Queued(
                        Report(rs.getObject(1) as UUID, rs.getString(2), rs.getObject(3) as UUID, rs.getString(4),
                               rs.getBoolean(5), rs.getTimestamp(6).toInstant(), rs.getTimestamp(7).toInstant(), rs.getBoolean(10)),
                        rs.getInt(8),
                        rs.getString(9) ?: "Not on THRØ any more",
                        rs.getString(11)?.let { category ->
                            val child = rs.getDouble(13).let { if (rs.wasNull()) Double.NaN else it }
                            val severity = rs.getDouble(14).let { if (rs.wasNull()) Double.NaN else it }
                            Reading(category, rs.getDouble(12), child, severity, rs.getString(15))
                        },
                    )
                }.toList()
            }
        }

    /**
     * Answers a report. A second look is a second decision, never an edit of the first.
     *
     * **And the decision does what it says** (PD-103), in the same transaction as the record of it, so the two cannot
     * disagree. *Hidden* takes the thing off every public surface: a team, venue or league goes private, an account's
     * name goes back to the placeholder. *Suspended* is of an account only — it revokes every session and refuses the
     * next sign-in. *Reinstated* undoes whichever of those a decision on this report did. The rest are records.
     */
    public fun decide(reportId: UUID, outcome: String, note: String, by: UUID): UUID {
        if (outcome !in setOf("left", "hidden", "corrected", "account_suspended", "not_upheld", "reinstated")) {
            throw Refused("That is not one of the answers a report can have.")
        }
        val clean = note.trim()
        if (clean.length !in 3..1000) throw Refused("Say why, so the decision can be read back.")
        // A decision on a report that is not there is a mistyped id, not a server fault. Left to the foreign
        // key it would arrive as a 500; asked first, it is answered with what is actually true.
        val (kind, subject) = connection.prepareStatement("SELECT subject_kind, subject_id FROM safety.report WHERE report_id = ?").use { ps ->
            ps.setObject(1, reportId)
            ps.executeQuery().use { rs -> if (rs.next()) rs.getString(1) to (rs.getObject(2) as UUID) else throw Refused("That report is not on the queue.", 404) }
        }
        when (outcome) {
            "hidden" -> hide(kind, subject)
            "account_suspended" -> {
                if (kind != "account") throw Refused("Suspending is of an account. Report the account, and suspend that.")
                if (subject == by) throw Refused("You cannot suspend yourself.")
                Accounts(connection, now).suspend(subject, clean)
            }
            "reinstated" -> {
                val undone = connection.prepareStatement(
                    "SELECT count(*) FROM safety.decision WHERE report_id = ? AND outcome IN ('hidden','account_suspended')",
                ).use { ps -> ps.setObject(1, reportId); ps.executeQuery().use { rs -> rs.next(); rs.getInt(1) } }
                if (undone == 0) throw Refused("There is nothing to reinstate: no decision hid or suspended this.")
                reinstate(kind, subject)
            }
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

    private fun hide(kind: String, subject: UUID) {
        when (kind) {
            // A team's every update bumps its version (V014's trigger); the bump is what makes this an honest write.
            "team" -> connection.prepareStatement("UPDATE competition.team SET visibility = 'private', row_version = row_version + 1 WHERE team_id = ? AND visibility = 'public'")
                .use { ps -> ps.setObject(1, subject); ps.executeUpdate() }
            "venue" -> connection.prepareStatement("UPDATE competition.venue SET visibility = 'private' WHERE venue_id = ?")
                .use { ps -> ps.setObject(1, subject); ps.executeUpdate() }
            "league" -> connection.prepareStatement("UPDATE competition.league SET visibility = 'private' WHERE league_id = ?")
                .use { ps -> ps.setObject(1, subject); ps.executeUpdate() }
            "account" -> Accounts(connection, now).hideName(subject)
            else -> throw Refused("A match names nobody, so there is nothing to hide. Report the account instead.")
        }
    }

    private fun reinstate(kind: String, subject: UUID) {
        when (kind) {
            "team" -> connection.prepareStatement("UPDATE competition.team SET visibility = 'public', row_version = row_version + 1 WHERE team_id = ? AND visibility = 'private'")
                .use { ps -> ps.setObject(1, subject); ps.executeUpdate() }
            "venue" -> connection.prepareStatement("UPDATE competition.venue SET visibility = 'public' WHERE venue_id = ?")
                .use { ps -> ps.setObject(1, subject); ps.executeUpdate() }
            "league" -> connection.prepareStatement("UPDATE competition.league SET visibility = 'public' WHERE league_id = ?")
                .use { ps -> ps.setObject(1, subject); ps.executeUpdate() }
            // A hidden name is not put back — the person chose a new one, or has the placeholder — so for an account
            // reinstating is the suspension lifted.
            "account" -> Accounts(connection, now).reinstate(subject)
        }
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
