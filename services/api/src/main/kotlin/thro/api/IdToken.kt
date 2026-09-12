package thro.api

import java.math.BigInteger
import java.net.URI
import java.net.http.HttpClient
import java.net.http.HttpRequest
import java.net.http.HttpResponse
import java.security.KeyFactory
import java.security.PublicKey
import java.security.Signature
import java.security.spec.RSAPublicKeySpec
import java.time.Duration
import java.time.Instant
import java.util.Base64
import java.util.concurrent.ConcurrentHashMap

/**
 * Verifying a Sign in with Apple or Google ID token (PD-030). An ID token is a JWT the provider
 * signed; THRØ checks the signature against the provider's published keys, the issuer, the
 * audience and the expiry, and takes from it exactly one fact: the provider's subject for this
 * person. **Nothing else is read at all** (PD-063). The token carries a name and often an email; both were
 * parsed into `Claims` and never looked at by anything, which is a copy of somebody's email address made
 * for no reason and then written down in a privacy policy. THRØ's own words to the player are "THRØ has no
 * email or phone", and that is now true of the code and not only of the screen.
 *
 * No library: RS256 is `SHA256withRSA` over `header.payload`, and the JWKS is an RSA modulus and
 * exponent. The key source is an interface so a test can sign tokens with a key it holds.
 */
public enum class Provider(public val issuers: Set<String>, public val jwks: String) {
    APPLE(setOf("https://appleid.apple.com"), "https://appleid.apple.com/auth/keys"),
    GOOGLE(setOf("https://accounts.google.com", "accounts.google.com"), "https://www.googleapis.com/oauth2/v3/certs"),
}

public fun interface JwkSource {
    /** The provider's public key with this `kid`, or null when it publishes none. */
    public fun publicKey(provider: Provider, kid: String): PublicKey?
}

public class IdTokenVerifier(private val keys: JwkSource, private val now: () -> Instant = { Instant.now() }) {

    /// The one fact taken from a verified token. There is deliberately nothing else here: a field that
    /// holds personal data nobody reads is personal data THRØ has to declare, defend and delete.
    public data class Claims(val subject: String, val issuer: String)

    public sealed interface Result {
        public data class Verified(val claims: Claims) : Result
        public data class Rejected(val why: String) : Result
    }

    /** Sign-ins that fail because the provider's keys could not be fetched are a 503, not a 401. */
    public class KeysUnavailable(message: String) : IllegalStateException(message)

    /**
     * [nonce] is what the client generated for this sign-in, when it did. A token carrying a nonce
     * must match it (Apple sends the SHA-256 of the client's value, Google the value itself); a
     * caller who supplies one for a token that carries none is refused too. Without a nonce a
     * captured ID token could open a session anywhere within its validity, so the clients send one.
     */
    public fun verify(token: String, provider: Provider, clientId: String, nonce: String? = null): Result {
        val parts = token.split('.')
        if (parts.size != 3) return Result.Rejected("not a JWT")
        val header = try { Json.parseObject(String(b64(parts[0]), Charsets.UTF_8)) } catch (e: Exception) { return Result.Rejected("header unreadable") }
        val payload = try { Json.parseObject(String(b64(parts[1]), Charsets.UTF_8)) } catch (e: Exception) { return Result.Rejected("payload unreadable") }
        if (header["alg"] != "RS256") return Result.Rejected("algorithm ${header["alg"]} is not accepted")
        val kid = header["kid"] as? String ?: return Result.Rejected("no key id")
        val key = keys.publicKey(provider, kid) ?: return Result.Rejected("the provider publishes no key $kid")
        val signed = try {
            Signature.getInstance("SHA256withRSA").run {
                initVerify(key); update((parts[0] + "." + parts[1]).toByteArray(Charsets.US_ASCII)); verify(b64(parts[2]))
            }
        } catch (e: Exception) { false }
        if (!signed) return Result.Rejected("signature does not verify")
        val iss = payload["iss"] as? String
        if (iss !in provider.issuers) return Result.Rejected("issuer $iss is not ${provider.name.lowercase()}")
        val aud = when (val a = payload["aud"]) { is String -> listOf(a); is List<*> -> a.map { it.toString() }; else -> emptyList() }
        if (clientId !in aud) return Result.Rejected("audience is not this app")
        val exp = (payload["exp"] as? Number)?.toLong() ?: return Result.Rejected("no expiry")
        if (Instant.ofEpochSecond(exp).plus(LEEWAY).isBefore(now())) return Result.Rejected("expired")
        (payload["iat"] as? Number)?.toLong()?.let { iat ->
            if (Instant.ofEpochSecond(iat).minus(LEEWAY).isAfter(now())) return Result.Rejected("issued in the future")
        }
        val tokenNonce = payload["nonce"] as? String
        when {
            tokenNonce != null && nonce == null -> return Result.Rejected("the token carries a nonce and the request did not say which")
            tokenNonce != null && tokenNonce != nonce && tokenNonce != sha256Hex(nonce!!) -> return Result.Rejected("nonce mismatch")
            tokenNonce == null && nonce != null -> return Result.Rejected("the request named a nonce and the token carries none")
        }
        val sub = payload["sub"] as? String ?: return Result.Rejected("no subject")
        return Result.Verified(Claims(sub, iss!!))
    }

    private fun b64(s: String): ByteArray = Base64.getUrlDecoder().decode(s)

    private fun sha256Hex(s: String): String =
        java.security.MessageDigest.getInstance("SHA-256").digest(s.toByteArray(Charsets.UTF_8)).joinToString("") { "%02x".format(it) }

    public companion object {
        /** Clock skew tolerated on exp and iat. A server a few seconds fast must not refuse every sign-in. */
        public val LEEWAY: Duration = Duration.ofSeconds(60)
    }
}

/**
 * The providers' published keys, fetched over HTTPS and kept for an hour. An unknown `kid`
 * refetches at most once a minute per provider, so a stream of tokens with invented key ids cannot
 * make THRØ call Apple once per request; a fetch that fails, returns anything but 200, or returns
 * more than a megabyte leaves the last good keys in place and surfaces as [IdTokenVerifier.KeysUnavailable]
 * when there are none. The fetcher is injectable so a test can count the calls.
 */
public class HttpJwkSource(
    private val fetcher: (Provider) -> String = HttpJwkSource::overHttps,
    private val now: () -> Instant = { Instant.now() },
) : JwkSource {
    private class State(var at: Instant?, var keys: Map<String, PublicKey>)
    private val states = ConcurrentHashMap<Provider, State>()

    override fun publicKey(provider: Provider, kid: String): PublicKey? {
        val st = states.computeIfAbsent(provider) { State(null, emptyMap()) }
        synchronized(st) {
            val fresh = st.at != null && Duration.between(st.at, now()) < Duration.ofHours(1)
            if (fresh && kid in st.keys) return st.keys[kid]
            val recently = st.at != null && Duration.between(st.at, now()) < Duration.ofMinutes(1)
            if (recently) return st.keys[kid]   // an unknown kid does not earn another fetch this minute
            try {
                st.keys = parse(fetcher(provider)); st.at = now()
            } catch (e: Exception) {
                if (st.keys.isEmpty()) throw IdTokenVerifier.KeysUnavailable("${provider.name.lowercase()} keys unavailable: ${e.message}")
                st.at = now()   // keep the last good set; try again in a minute
            }
            return st.keys[kid]
        }
    }

    private fun parse(body: String): Map<String, PublicKey> {
        require(body.length <= 1_000_000) { "key set over a megabyte" }
        val keys = (Json.parseObject(body)["keys"] as? List<*>) ?: throw IllegalArgumentException("no keys array")
        return keys.mapNotNull { k ->
            val m = k as? Map<*, *> ?: return@mapNotNull null
            if (m["kty"] != "RSA") return@mapNotNull null
            val kid = m["kid"] as? String ?: return@mapNotNull null
            val n = m["n"] as? String ?: return@mapNotNull null
            val e = m["e"] as? String ?: return@mapNotNull null
            kid to rsa(n, e)
        }.toMap()
    }

    public companion object {
        private val client: HttpClient by lazy { HttpClient.newBuilder().connectTimeout(Duration.ofSeconds(5)).build() }

        public fun overHttps(provider: Provider): String {
            val r = client.send(HttpRequest.newBuilder(URI.create(provider.jwks)).timeout(Duration.ofSeconds(5)).GET().build(), HttpResponse.BodyHandlers.ofString())
            check(r.statusCode() == 200) { "HTTP ${r.statusCode()} from ${provider.jwks}" }
            return r.body()
        }

        public fun rsa(n: String, e: String): PublicKey {
            val dec = Base64.getUrlDecoder()
            return KeyFactory.getInstance("RSA").generatePublic(RSAPublicKeySpec(BigInteger(1, dec.decode(n)), BigInteger(1, dec.decode(e))))
        }
    }
}
