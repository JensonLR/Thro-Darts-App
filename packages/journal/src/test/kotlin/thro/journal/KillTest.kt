package thro.journal

import thro.engine.Command
import java.io.BufferedReader
import java.io.InputStreamReader
import java.nio.file.Files
import java.nio.file.Path
import java.util.concurrent.TimeUnit
import kotlin.test.AfterTest
import kotlin.test.BeforeTest
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue

/**
 * The kill test, on a build server.
 *
 * ADR-011 requires a kill test and a power-cut test on every release candidate and says that **an
 * unowned manual test is a test that runs once.** The iOS kill test is automated and needs a
 * connected iPhone, a Mac and a person, so nothing checked this on a push. This does, on Linux, in a
 * few seconds.
 *
 * **The kill is real.** A JVM is forked, writes visits through the journal's own transaction
 * discipline, prints and flushes an acknowledgement after each commit, and is then sent `SIGKILL`
 * with `destroyForcibly` — landing wherever the writer happens to be, usually inside a transaction,
 * which is the case worth testing. Not `exit()`: that runs shutdown hooks and flushes buffers, which
 * is precisely what a crash does not do, and a kill test built on it quietly tests the happy path.
 *
 * **What it cannot say.** The kernel, the filesystem and the drive all keep running through a
 * `SIGKILL`, so a journal that only ever reached the OS page cache passes this and would still lose
 * data to a pulled battery. That is why ADR-011 asks for two tests, and why a green run here must
 * never be reported as durability. `docs/runbooks/DURABILITY_KILL_TEST.md` puts the two in a table.
 */
class KillTest {

    private lateinit var dir: Path
    private lateinit var path: String

    @BeforeTest fun setUp() {
        dir = Files.createTempDirectory("thro-kill")
        path = dir.resolve("journal.sqlite").toString()
    }

    @AfterTest fun tearDown() {
        dir.toFile().deleteRecursively()
    }

    @Test fun nothingAcknowledgedIsLostWhenTheWriterIsKilled() {
        val process = ProcessBuilder(
            Path.of(System.getProperty("java.home"), "bin", "java").toString(),
            "-cp", System.getProperty("java.class.path"),
            "thro.journal.KillWriterKt",
            path,
        ).redirectErrorStream(true).start()

        // Read acknowledgements until the writer has committed enough to be worth killing. Each one
        // is printed and flushed AFTER its commit returned, so an acknowledgement is a claim that
        // the row is on disk — which is exactly the claim being tested.
        var lastAck = 0
        val reader = BufferedReader(InputStreamReader(process.inputStream))
        val deadline = System.nanoTime() + TimeUnit.SECONDS.toNanos(60)
        while (lastAck < ACKS_BEFORE_KILL && System.nanoTime() < deadline) {
            val line = reader.readLine() ?: break
            if (line.startsWith(ACK)) lastAck = line.removePrefix(ACK).trim().toInt()
        }
        assertTrue(lastAck >= ACKS_BEFORE_KILL, "the writer produced only $lastAck acknowledgement(s)")

        // SIGKILL. The writer gets no notice and runs no shutdown hook.
        process.destroyForcibly()
        assertTrue(process.waitFor(30, TimeUnit.SECONDS), "the killed writer did not exit")
        assertTrue(process.exitValue() != 0, "a killed process does not exit cleanly")

        val report = Kill.inspect(path)
        val verdict = Kill.verdict(report, lastAck)
        assertTrue(verdict.passed, "${verdict.line}\n  report: $report\n  lastAck: $lastAck")
        assertTrue(report.maxSeq >= lastAck, "the journal holds fewer rows than were acknowledged")
        assertEquals("ok", report.integrity)

        // And what survived is a journal, not just a file: it reopens under the configuration and
        // replays through the engine. A file that passes an integrity check and cannot be read by
        // the app is not a pass.
        Journal.open(path, DeviceId("kill-test")).use { j ->
            val m = j.matches().single()
            assertEquals(report.rowCount, j.entries(m.id).size)
            j.replay(m.id)
        }
    }

    /** The rule itself, at the boundaries, without needing a kill to reach each one. */
    @Test fun theVerdictIsOneDirectional() {
        val intact = Kill.Report(true, "ok", tableFound = true, rowCount = 5, maxSeq = 5, holes = emptyList())
        assertTrue(Kill.verdict(intact, lastAck = 5).passed)
        // More on disk than was seen acknowledged is fine: SIGKILL discards a buffered
        // acknowledgement for a write that did land.
        assertTrue(Kill.verdict(intact, lastAck = 3).passed)
        // Less is never fine.
        assertTrue(Kill.verdict(intact, lastAck = 6) is Kill.Verdict.Fail)
        // Nor is a hole, however few rows are missing.
        val holed = intact.copy(holes = listOf(3))
        assertTrue(Kill.verdict(holed, lastAck = 5) is Kill.Verdict.Fail)
        // A run that measured nothing is VOID, not PASS. A test that could not run is not a test
        // that passed, and reporting it as one is how a durability claim becomes fiction.
        val empty = Kill.Report(true, "ok", tableFound = true, rowCount = 0, maxSeq = 0, holes = emptyList())
        assertTrue(Kill.verdict(empty, lastAck = null) is Kill.Verdict.Void)
        val absent = Kill.Report(true, "ok", tableFound = false, rowCount = 0, maxSeq = 0, holes = emptyList())
        assertTrue(Kill.verdict(absent, lastAck = null) is Kill.Verdict.Void)
        assertTrue(Kill.verdict(absent, lastAck = 2) is Kill.Verdict.Fail)
        // A corrupt file fails on its own terms, before anything is counted.
        val corrupt = intact.copy(integrity = "row 3 missing from index")
        assertTrue(Kill.verdict(corrupt, lastAck = null) is Kill.Verdict.Fail)
        assertTrue(Kill.verdict(intact.copy(opened = false), lastAck = null) is Kill.Verdict.Fail)
    }

    private companion object {
        const val ACK = "KILLTEST-ACK"
        const val ACKS_BEFORE_KILL = 40
    }
}
