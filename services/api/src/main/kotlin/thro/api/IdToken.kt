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
 * person. Nothing else in the token is trusted for anything — a name or email claim is a hint the
 * person may accept on a screen, never a fact THRØ writes on its own.
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

    public data class Claims(val subject: String, val issuer: String, val nameHint: String?, val emailHint: String?)

    public sealed interface Result {
        public data class Verified(val claims: Claims) : Result
        public data class Rejected(val why: String) : Result
    }

    public fun verify(token: String, provider: Provider, clientId: String): Result {
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
        if (Instant.ofEpochSecond(exp).isBefore(now())) return Result.Rejected("expired")
        val sub = payload["sub"] as? String ?: return Result.Rejected("no subject")
        val name = (payload["name"] as? String) ?: (payload["given_name"] as? String)
        return Result.Verified(Claims(sub, iss!!, name, payload["email"] as? String))
    }

    private fun b64(s: String): ByteArray = Base64.getUrlDecoder().decode(s)
}

/** The providers' published keys, fetched over HTTPS and kept for an hour; a missing kid refetches once. */
public class HttpJwkSource(private val client: HttpClient = HttpClient.newHttpClient(), private val now: () -> Instant = { Instant.now() }) : JwkSource {
    private data class Cached(val at: Instant, val keys: Map<String, PublicKey>)
    private val cache = ConcurrentHashMap<Provider, Cached>()

    override fun publicKey(provider: Provider, kid: String): PublicKey? {
        val cached = cache[provider]
        if (cached != null && Duration.between(cached.at, now()) < Duration.ofHours(1) && kid in cached.keys) return cached.keys[kid]
        val fresh = fetch(provider)
        cache[provider] = Cached(now(), fresh)
        return fresh[kid]
    }

    private fun fetch(provider: Provider): Map<String, PublicKey> {
        val body = client.send(HttpRequest.newBuilder(URI.create(provider.jwks)).timeout(Duration.ofSeconds(5)).GET().build(), HttpResponse.BodyHandlers.ofString()).body()
        val keys = (Json.parseObject(body)["keys"] as? List<*>).orEmpty()
        return keys.mapNotNull { k ->
            val m = k as? Map<*, *> ?: return@mapNotNull null
            if (m["kty"] != "RSA") return@mapNotNull null
            val kid = m["kid"] as? String ?: return@mapNotNull null
            kid to rsa(m["n"] as String, m["e"] as String)
        }.toMap()
    }

    public companion object {
        public fun rsa(n: String, e: String): PublicKey {
            val dec = Base64.getUrlDecoder()
            return KeyFactory.getInstance("RSA").generatePublic(RSAPublicKeySpec(BigInteger(1, dec.decode(n)), BigInteger(1, dec.decode(e))))
        }
    }
}
