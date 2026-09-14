package thro.journal

import java.sql.DriverManager

/**
 * Adjudicating a journal that survived a process being killed.
 *
 * ADR-011 requires a kill test and a power-cut test on every release candidate, and says that **an
 * unowned manual test is a test that runs once.** The iOS kill test is automated and needs a
 * connected iPhone, a Mac and a person; nothing ran on a build server at all. This is the part that
 * can: a JVM is forked, it writes visits under the journal's own transaction discipline, it is sent
 * `SIGKILL` mid-write, and what survives is adjudicated here.
 *
 * **What it proves and what it does not.** It proves the transaction discipline: that an
 * acknowledged commit is on disk and that the sequence has no hole, through a process death the
 * writer had no chance to prepare for. It does **not** prove durability against power loss — the
 * kernel, the filesystem and the drive are all still running through a `SIGKILL`, so a journal that
 * only ever reached the OS page cache passes this and would lose data to a pulled battery. That is
 * the whole reason ADR-011 asks for two tests and says the easy one does not stand in for the hard
 * one. `docs/runbooks/DURABILITY_KILL_TEST.md` puts it in a table.
 */
public object Kill {

    /** What a killed journal looks like when it is reopened. */
    public data class Report(
        val opened: Boolean,
        val integrity: String,
        val tableFound: Boolean,
        val rowCount: Int,
        val maxSeq: Int,
        /** Sequence numbers missing from 1..maxSeq. A hole is a lost commit, not a slow one. */
        val holes: List<Int>,
    )

    public sealed interface Verdict {
        public val line: String

        public data class Pass(val why: String) : Verdict {
            override val line: String get() = "PASS — $why"
        }

        public data class Fail(val why: String) : Verdict {
            override val line: String get() = "FAIL — $why"
        }

        /** The run measured nothing. Not a pass: a test that could not run is not a test that passed. */
        public data class Void(val why: String) : Verdict {
            override val line: String get() = "VOID — $why"
        }

        public val passed: Boolean get() = this is Pass
    }

    /**
     * The rule, ported from `KillProbe.verdict` on iOS so that both platforms are judged the same
     * way.
     *
     * One-directional on purpose: the journal may legitimately hold **more** than was seen
     * acknowledged, because `SIGKILL` discards a buffered acknowledgement for a write that did land.
     * It may never hold less, and it may never have a gap.
     */
    public fun verdict(report: Report, lastAck: Int?): Verdict {
        if (!report.opened) return Verdict.Fail("the journal could not be reopened after the kill")
        if (report.integrity != "ok") return Verdict.Fail("integrity_check reported: ${report.integrity}")
        if (report.holes.isNotEmpty()) {
            val named = report.holes.take(20).joinToString(",")
            val more = if (report.holes.size > 20) " (first 20 of ${report.holes.size})" else ""
            return Verdict.Fail(
                "${report.holes.size} acknowledged visit(s) missing from the sequence: $named$more",
            )
        }
        if (lastAck != null && lastAck > report.maxSeq) {
            if (!report.tableFound) {
                return Verdict.Fail(
                    "the journal table is gone entirely: console recorded $lastAck acknowledgement(s)",
                )
            }
            return Verdict.Fail(
                "${lastAck - report.maxSeq} acknowledged visit(s) missing: " +
                    "console recorded $lastAck, journal holds ${report.maxSeq}",
            )
        }
        if (!report.tableFound) {
            return Verdict.Void(
                "no journal table at this path — the journal is absent or was never written, " +
                    "so this run measured nothing",
            )
        }
        if (report.rowCount == 0) {
            return Verdict.Void("the journal is empty — nothing was acknowledged, so there is nothing to adjudicate")
        }
        return if (lastAck == null) {
            Verdict.Pass("journal intact and contiguous (no acknowledgement record supplied)")
        } else {
            Verdict.Pass("nothing acknowledged was lost")
        }
    }

    /**
     * Reads a journal file that has been through a kill.
     *
     * Opened directly rather than through [Journal], because [Journal.open] verifies the
     * configuration and migrates — both of which would *write*, and a forensic read must not touch
     * the thing it is examining.
     */
    public fun inspect(path: String): Report {
        val connection = try {
            DriverManager.getConnection("jdbc:sqlite:$path")
        } catch (_: Exception) {
            return Report(opened = false, integrity = "(not opened)", tableFound = false, rowCount = 0, maxSeq = 0, holes = emptyList())
        }
        connection.use { c ->
            val integrity = c.createStatement().use { s ->
                s.executeQuery("PRAGMA integrity_check;").use { r -> if (r.next()) r.getString(1) else "(no result)" }
            }
            val tableFound = c.createStatement().use { s ->
                s.executeQuery("SELECT name FROM sqlite_master WHERE type='table' AND name='journal';")
                    .use { r -> r.next() }
            }
            if (!tableFound) {
                return Report(true, integrity, tableFound = false, rowCount = 0, maxSeq = 0, holes = emptyList())
            }
            val seqs = mutableListOf<Int>()
            c.createStatement().use { s ->
                s.executeQuery("SELECT device_seq FROM journal ORDER BY device_seq;").use { r ->
                    while (r.next()) seqs.add(r.getInt(1))
                }
            }
            val max = seqs.maxOrNull() ?: 0
            val present = seqs.toSet()
            val holes = (1..max).filter { it !in present }
            return Report(true, integrity, tableFound = true, rowCount = seqs.size, maxSeq = max, holes = holes)
        }
    }
}
