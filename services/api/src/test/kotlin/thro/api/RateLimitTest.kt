package thro.api

import java.time.Instant
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNull
import kotlin.test.assertTrue
import thro.api.http.RateLimiter

/** The allowance for a stranger: a bucket per key, refilled by the clock, never by a different key. */
class RateLimitTest {
    @Test
    fun `thirty a minute per key, the wait is honest, and one key cannot spend another's`() {
        var clock = Instant.parse("2026-09-12T10:00:00Z")
        val l = RateLimiter(capacity = 5, refillPerMinute = 5, now = { clock })
        repeat(5) { assertNull(l.take("a:1.2.3.4"), "attempt ${it + 1} of 5 is allowed") }
        val wait = l.take("a:1.2.3.4")
        assertEquals(12, wait, "the sixth must wait one refill: 60 / 5 seconds")
        assertNull(l.take("a:5.6.7.8"), "another address has its own bucket")
        clock = clock.plusSeconds(12)
        assertNull(l.take("a:1.2.3.4"), "after the wait, one more is allowed")
        assertTrue((l.take("a:1.2.3.4") ?: 0) > 0, "and no more until the next refill")
        clock = clock.plusSeconds(600)
        repeat(5) { assertNull(l.take("a:1.2.3.4")) }
        println("  PASS  a stranger's allowance refills by the clock and is never borrowed from another key")
    }
}
