package thro.api.http

import java.sql.Connection
import java.util.UUID
import java.util.concurrent.ConcurrentHashMap
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.channels.Channel
import kotlinx.coroutines.withTimeoutOrNull
import org.postgresql.PGConnection

/**
 * ADR-007's internal fan-out: one connection LISTENing on `thro_match` (V036), waking the streams of
 * the match each notification names.
 *
 * **A hint to re-read, never the transport of truth.** A woken stream reads the log exactly as a
 * polling one does, and a stream that is never woken still polls — so a notifier that is down,
 * reconnecting or simply wrong costs latency and nothing else. That is the whole of its contract, and
 * why nothing it carries is ever sent to a watcher: the notification holds a match id and no event.
 *
 * **It holds its connection only while somebody is watching.** A connection held open all day would
 * keep a database that sleeps when idle — Neon's free compute — awake for nobody. The first stream
 * opens it, and it closes a little after the last one goes.
 *
 * **A watch begins once somebody is listening.** The first version started the listener and returned
 * at once, and the stream read the log straight away — so a visit that committed in the few
 * milliseconds before the new connection had said LISTEN was announced to nobody, and its watcher sat
 * out the poll. The latency test caught it on its second run. [watch] now returns when the listener is
 * listening, so a read made after it cannot miss a commit: anything later is announced to a connection
 * already listening. The wait is bounded, because a database slow to answer is the poll's to carry.
 */
internal class MatchNotifier(private val connect: () -> Connection) {
    private val watchers = ConcurrentHashMap<UUID, MutableSet<Channel<Unit>>>()
    private val lock = Any()
    @Volatile private var running = true
    private var thread: Thread? = null
    /** Complete while the listener is LISTENing; a fresh, incomplete one whenever it is not. */
    @Volatile private var listening = CompletableDeferred<Unit>()

    /**
     * A wake-up line for one stream of [matchId], handed back once the listener is listening. Give it
     * back with [unwatch] when the stream ends.
     */
    suspend fun watch(matchId: UUID): Channel<Unit> {
        val line = Channel<Unit>(Channel.CONFLATED)
        watchers.computeIfAbsent(matchId) { ConcurrentHashMap.newKeySet() }.add(line)
        synchronized(lock) { if (thread == null && running) start() }
        withTimeoutOrNull(READY_WAIT_MS) { listening.await() }
        return line
    }

    fun unwatch(matchId: UUID, line: Channel<Unit>) {
        watchers[matchId]?.let { set -> set.remove(line); if (set.isEmpty()) watchers.remove(matchId, set) }
        line.close()
    }

    /** The server is stopping. The listener sees this within a second and closes its connection. */
    fun stop() {
        running = false
    }

    private fun start() {
        thread = Thread({ listen() }, "thro-match-notifier").apply { isDaemon = true; start() }
    }

    private fun listen() {
        var backoff = FIRST_BACKOFF_MS
        var idleSince = 0L
        try {
            while (running) {
                try {
                    connect().use { c ->
                        c.autoCommit = true
                        // The least role that can LISTEN, which is any of them: it reads nothing.
                        c.createStatement().use { st -> st.execute("SET ROLE " + DbRole.READ.sql); st.execute("LISTEN thro_match") }
                        val pg = c.unwrap(PGConnection::class.java)
                        backoff = FIRST_BACKOFF_MS
                        listening.complete(Unit)
                        try {
                            while (running) {
                                for (n in pg.getNotifications(WAIT_MS) ?: emptyArray()) {
                                    val matchId = runCatching { UUID.fromString(n.parameter) }.getOrNull() ?: continue
                                    watchers[matchId]?.forEach { it.trySend(Unit) }
                                }
                                if (watchers.isEmpty()) {
                                    if (idleSince == 0L) idleSince = System.currentTimeMillis()
                                    else if (System.currentTimeMillis() - idleSince > LINGER_MS) return
                                } else {
                                    idleSince = 0L
                                }
                            }
                        } finally {
                            // Not listening from here: a watch that begins now waits for the next connection.
                            listening = CompletableDeferred()
                        }
                    }
                } catch (e: InterruptedException) {
                    return
                } catch (e: Exception) {
                    // The database went, or the connection did. Streams are polling meanwhile, so this
                    // is late rather than lost; try again, less eagerly each time.
                    if (!running) return
                    Thread.sleep(backoff)
                    backoff = (backoff * 2).coerceAtMost(MAX_BACKOFF_MS)
                }
            }
        } finally {
            // A stream that started watching while this was deciding to stop would otherwise have
            // nobody listening for it until the next one arrived.
            synchronized(lock) {
                thread = null
                if (running && watchers.isNotEmpty()) start()
            }
        }
    }

    private companion object {
        const val WAIT_MS = 1_000
        const val LINGER_MS = 30_000L
        const val FIRST_BACKOFF_MS = 250L
        const val MAX_BACKOFF_MS = 10_000L
        /** The longest a watch waits for the listener before its stream reads anyway, the poll beneath it. */
        const val READY_WAIT_MS = 2_000L
    }
}
