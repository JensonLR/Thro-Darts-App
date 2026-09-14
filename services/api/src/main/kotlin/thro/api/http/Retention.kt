package thro.api.http

import java.sql.Connection
import java.time.Duration
import kotlin.concurrent.thread

/**
 * Forgetting what is no longer needed (PD-087).
 *
 * The rule lives in SQL — `safety.forget_decided`, whose body is in migration V044 — because that is where
 * the guarantee it has to respect lives: nobody may delete a report, and the only exception is a function
 * applying one rule to all of them at once. This is only the thing that calls it.
 *
 * **On a schedule and not on a request.** A retention sweep that ran when somebody happened to open the
 * moderation queue would run often on a busy week and never on a quiet one, which is not a retention
 * period. Daily, from the server's own clock, whether anybody is looking or not.
 */
public object Retention {

    /** How long a decided report is kept. The founder's number, 12 September 2026. */
    public const val KEEP: String = "2 years"

    private val EVERY: Duration = Duration.ofHours(24)

    /**
     * Starts the sweep, now and then daily. Returns immediately.
     *
     * A failure is reported and the loop continues: a database that is behind the code, or briefly away,
     * must not take the server down — and tomorrow's sweep does the same work, because the rule is about
     * what is in the table and not about what happened last time.
     */
    public fun everyDay(connect: () -> Connection, every: Duration = EVERY, keep: String = KEEP) {
        thread(isDaemon = true, name = "thro-retention") {
            while (true) {
                runCatching { connect().use { sweep(it, keep) } }
                    .onSuccess { gone -> if (gone > 0) System.err.println("retention: forgot $gone decided report(s)") }
                    .onFailure { System.err.println("retention: could not sweep — ${it.message}") }
                Thread.sleep(every.toMillis())
            }
        }
    }

    /**
     * One sweep, on a connection the caller owns. Returns how many reports were forgotten.
     *
     * **It does not close the connection.** The first version took the factory and closed what it opened,
     * which is right for the loop above and wrong for everybody else: a test handed it a live connection
     * and got it back closed. Opening and closing belongs to whoever is scheduling, not to the work.
     */
    public fun sweep(c: Connection, keep: String = KEEP): Int =
        c.prepareStatement("SELECT safety.forget_decided(?::interval)").use { s ->
            s.setString(1, keep)
            s.executeQuery().use { rs -> if (rs.next()) rs.getInt(1) else 0 }
        }
}
