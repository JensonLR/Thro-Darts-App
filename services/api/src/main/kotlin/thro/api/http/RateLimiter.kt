package thro.api.http

import java.time.Instant
import java.util.concurrent.ConcurrentHashMap

/**
 * A token bucket per key, for the routes a stranger may call without a principal: sign-in,
 * refresh, passkey ceremonies. Not a defence against a determined flood — a single instance's
 * memory cannot be — but the difference between an attacker trying a thousand tokens a second
 * and thirty a minute, which is what the JWKS throttle, the challenge table and the database
 * were sized for.
 *
 * Keys are the client address and, where a body names one, the device id, so one address
 * cannot spend every device's allowance and one device cannot spend every address's. Buckets
 * that have been full for a while are dropped, so a scan of a million addresses does not grow
 * memory without bound.
 */
public class RateLimiter(
    private val capacity: Int = 30,
    private val refillPerMinute: Int = 30,
    private val now: () -> Instant = { Instant.now() },
) {
    private class Bucket(var tokens: Double, var at: Instant)

    private val buckets = ConcurrentHashMap<String, Bucket>()

    /** Null when the request may proceed; otherwise the seconds to wait. */
    public fun take(key: String): Int? {
        val t = now()
        var wait: Int? = null
        buckets.compute(key) { _, old ->
            val b = old ?: Bucket(capacity.toDouble(), t)
            val elapsed = (t.toEpochMilli() - b.at.toEpochMilli()).coerceAtLeast(0) / 60_000.0
            b.tokens = (b.tokens + elapsed * refillPerMinute).coerceAtMost(capacity.toDouble())
            b.at = t
            if (b.tokens >= 1.0) { b.tokens -= 1.0; wait = null } else {
                wait = kotlin.math.ceil((1.0 - b.tokens) / refillPerMinute * 60).toInt().coerceAtLeast(1)
            }
            b
        }
        if (buckets.size > 100_000) sweep(t)
        return wait
    }

    private fun sweep(t: Instant) {
        val stale = t.minusSeconds(600)
        buckets.entries.removeIf { it.value.at.isBefore(stale) }
    }
}
