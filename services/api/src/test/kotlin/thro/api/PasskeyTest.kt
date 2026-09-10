package thro.api

import io.ktor.client.request.get
import io.ktor.client.request.header
import io.ktor.client.request.post
import io.ktor.client.request.setBody
import io.ktor.client.statement.HttpResponse
import io.ktor.client.statement.bodyAsText
import io.ktor.server.testing.testApplication
import java.io.ByteArrayOutputStream
import java.nio.ByteBuffer
import java.security.KeyPair
import java.security.KeyPairGenerator
import java.security.MessageDigest
import java.security.Signature
import java.security.interfaces.ECPublicKey
import java.time.Instant
import java.util.Base64
import java.util.UUID
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue
import thro.api.http.Authenticator
import thro.api.http.Contract
import thro.api.http.Deps
import thro.api.http.thro

/**
 * Passkeys (PD-030's fallback, V025). The test is the authenticator: it holds a P-256 key, builds
 * the client data and authenticator data byte for byte, signs assertions, and then does each of
 * those wrong in turn. The relying party is `api.example`, the origins `https://api.example`.
 *
 * Skipped cleanly when no database is configured, rather than passing silently.
 */
class PasskeyTest {

    private val b64 = Base64.getUrlEncoder().withoutPadding()
    private val rpId = "api.example"

    // --- a minimal CBOR encoder, enough for attestation objects and COSE keys -------------------
    private fun cbor(v: Any?): ByteArray {
        val out = ByteArrayOutputStream()
        fun head(major: Int, n: Long) {
            when {
                n < 24 -> out.write((major shl 5) or n.toInt())
                n < 256 -> { out.write((major shl 5) or 24); out.write(n.toInt()) }
                n < 65536 -> { out.write((major shl 5) or 25); out.write((n shr 8).toInt()); out.write((n and 0xff).toInt()) }
                else -> { out.write((major shl 5) or 26); out.write(ByteBuffer.allocate(4).putInt(n.toInt()).array()) }
            }
        }
        fun enc(x: Any?) {
            when (x) {
                is Long -> if (x >= 0) head(0, x) else head(1, -1 - x)
                is Int -> enc(x.toLong())
                is ByteArray -> { head(2, x.size.toLong()); out.write(x) }
                is String -> { val b = x.toByteArray(); head(3, b.size.toLong()); out.write(b) }
                is List<*> -> { head(4, x.size.toLong()); x.forEach { enc(it) } }
                is Map<*, *> -> { head(5, x.size.toLong()); x.forEach { (k, v) -> enc(k); enc(v) } }
                else -> error("cannot encode $x")
            }
        }
        enc(v); return out.toByteArray()
    }

    private fun coseKey(kp: KeyPair): ByteArray {
        val pub = kp.public as ECPublicKey
        fun fixed(b: java.math.BigInteger) = b.toByteArray().let { if (it.size == 33) it.copyOfRange(1, 33) else if (it.size < 32) ByteArray(32 - it.size) + it else it }
        return cbor(linkedMapOf(1L to 2L, 3L to -7L, -1L to 1L, -2L to fixed(pub.w.affineX), -3L to fixed(pub.w.affineY)))
    }

    private fun authData(rp: String, flags: Int, count: Long, credId: ByteArray? = null, cose: ByteArray? = null): ByteArray {
        val out = ByteArrayOutputStream()
        out.write(MessageDigest.getInstance("SHA-256").digest(rp.toByteArray()))
        out.write(flags)
        out.write(ByteBuffer.allocate(4).putInt(count.toInt()).array())
        if (credId != null) {
            out.write(ByteArray(16)); out.write(credId.size shr 8); out.write(credId.size and 0xff); out.write(credId); out.write(cose!!)
        }
        return out.toByteArray()
    }

    private fun clientData(type: String, challenge: String, origin: String = "https://$rpId") =
        """{"type":"$type","challenge":"$challenge","origin":"$origin","crossOrigin":false}""".toByteArray()

    private fun sign(kp: KeyPair, authData: ByteArray, clientData: ByteArray): ByteArray =
        Signature.getInstance("SHA256withECDSA").run { initSign(kp.private); update(authData + MessageDigest.getInstance("SHA-256").digest(clientData)); sign() }

    @Test
    fun `a passkey is created, signs in, and every way of doing it wrong is refused`() {
        if (!TestDatabase.configured) {
            println("no database configured (set PGHOST) — passkey tests skipped")
            return
        }
        val c = TestDatabase.migrated()
        var passed = 0
        fun check(name: String, cond: Boolean) {
            assertTrue(cond, "FAILED: $name")
            println("  PASS  $name")
            passed++
        }
        var clock = Instant.parse("2026-09-12T10:00:00Z")
        val device = UUID.randomUUID()
        val kp = KeyPairGenerator.getInstance("EC").apply { initialize(256) }.generateKeyPair()
        val credId = ByteArray(16).also { java.security.SecureRandom().nextBytes(it) }
        val cose = coseKey(kp)
        val UP_UV_AT = 0x01 or 0x04 or 0x40; val UP_UV = 0x01 or 0x04

        testApplication {
            application {
                thro(Deps(connect = { TestDatabase.connect() }, authenticator = Authenticator.Bearer(now = { clock }), now = { clock },
                    relyingParty = RelyingParty(rpId, setOf("https://$rpId")), appleAppIds = listOf("TEAMID.app.example")))
            }
            suspend fun post(path: String, body: String, token: String? = null): HttpResponse = client.post(path) { token?.let { header("Authorization", "Bearer $it") }; setBody(body) }
            fun field(json: String, vararg path: String): Any? { var v: Any? = Json.parseObject(json); for (p in path) v = (v as Map<*, *>)[p]; return v }
            suspend fun registerOptions(token: String? = null): Pair<String, String> {
                val r = post("/v1/auth/passkey/register/options", """{"deviceId":"$device"}""", token); val b = r.bodyAsText()
                return field(b, "challengeId").toString() to field(b, "publicKey", "challenge").toString()
            }
            suspend fun register(challengeId: String, clientData: ByteArray, authData: ByteArray, id: ByteArray = credId, token: String? = null): HttpResponse =
                post("/v1/auth/passkey/register", """{"challengeId":"$challengeId","deviceId":"$device","credentialId":${Contract.q(b64.encodeToString(id))},"clientDataJSON":${Contract.q(b64.encodeToString(clientData))},"attestationObject":${Contract.q(b64.encodeToString(cbor(linkedMapOf("fmt" to "none", "attStmt" to linkedMapOf<Any, Any>(), "authData" to authData))))}}""", token)
            suspend fun assertOptions(): Pair<String, String> {
                val b = post("/v1/auth/passkey/options", """{"deviceId":"$device"}""").bodyAsText()
                return field(b, "challengeId").toString() to field(b, "publicKey", "challenge").toString()
            }
            suspend fun assert(challengeId: String, clientData: ByteArray, authData: ByteArray, signature: ByteArray, id: ByteArray = credId): HttpResponse =
                post("/v1/auth/passkey", """{"challengeId":"$challengeId","deviceId":"$device","credentialId":${Contract.q(b64.encodeToString(id))},"clientDataJSON":${Contract.q(b64.encodeToString(clientData))},"authenticatorData":${Contract.q(b64.encodeToString(authData))},"signature":${Contract.q(b64.encodeToString(signature))}}""")

            // --- registration ---------------------------------------------------------------------------
            val (ch1, chal1) = registerOptions()
            check("creation options carry a challenge and this relying party", chal1.isNotEmpty() && post("/v1/auth/passkey/register/options", """{"deviceId":"$device"}""").bodyAsText().contains("\"rp\":{\"id\":\"$rpId\""))
            val wrongOrigin = register(ch1, clientData("webauthn.create", chal1, origin = "https://evil.example"), authData(rpId, UP_UV_AT, 0, credId, cose))
            check("a registration from another origin is refused, and it spent the challenge", wrongOrigin.status.value == 401 && wrongOrigin.bodyAsText().contains("origin") &&
                register(ch1, clientData("webauthn.create", chal1), authData(rpId, UP_UV_AT, 0, credId, cose)).status.value == 401)
            val (ch2, chal2) = registerOptions()
            val noUv = register(ch2, clientData("webauthn.create", chal2), authData(rpId, 0x01 or 0x40, 0, credId, cose))
            check("a registration without user verification is refused", noUv.status.value == 401 && noUv.bodyAsText().contains("verification"))
            val (ch3, chal3) = registerOptions()
            val wrongRp = register(ch3, clientData("webauthn.create", chal3), authData("other.example", UP_UV_AT, 0, credId, cose))
            check("a registration for another relying party is refused", wrongRp.status.value == 401 && wrongRp.bodyAsText().contains("relying party"))
            val (ch4, chal4) = registerOptions()
            val created = register(ch4, clientData("webauthn.create", chal4), authData(rpId, UP_UV_AT, 0, credId, cose))
            check("a good registration creates an account and opens a session", created.status.value == 200 && field(created.bodyAsText(), "created") == true)
            val accountId = UUID.fromString(field(created.bodyAsText(), "accountId").toString())
            val stored = c.prepareStatement("SELECT sign_count, octet_length(public_key) FROM identity.credential WHERE account_id = ? AND kind = 'passkey'").use { ps -> ps.setObject(1, accountId); ps.executeQuery().use { rs -> rs.next(); rs.getLong(1) to rs.getInt(2) } }
            check("the COSE public key and the counter are stored", stored == (0L to cose.size))
            val (ch5, chal5) = registerOptions()
            check("the same passkey cannot be registered twice", register(ch5, clientData("webauthn.create", chal5), authData(rpId, UP_UV_AT, 0, credId, cose)).status.value == 401)

            // --- assertion ------------------------------------------------------------------------------
            val (a1, ac1) = assertOptions()
            val cd1 = clientData("webauthn.get", ac1); val ad1 = authData(rpId, UP_UV, 1)
            val signedIn = assert(a1, cd1, ad1, sign(kp, ad1, cd1))
            check("a signed assertion signs in to the passkey's account", signedIn.status.value == 200 && field(signedIn.bodyAsText(), "accountId").toString() == accountId.toString() && field(signedIn.bodyAsText(), "created") == false)
            val access = field(signedIn.bodyAsText(), "accessToken").toString()
            check("and the session works", client.get("/v1/me") { header("Authorization", "Bearer $access") }.status.value == 200)
            check("the counter moved on", c.prepareStatement("SELECT sign_count FROM identity.credential WHERE account_id = ?").use { ps -> ps.setObject(1, accountId); ps.executeQuery().use { rs -> rs.next(); rs.getLong(1) == 1L } })
            check("a spent challenge is refused", assert(a1, cd1, ad1, sign(kp, ad1, cd1)).status.value == 401)
            val (a2, ac2) = assertOptions()
            val cd2 = clientData("webauthn.get", ac2); val ad2 = authData(rpId, UP_UV, 2)
            val tampered = assert(a2, cd2, ad2, sign(kp, authData(rpId, UP_UV, 3), cd2))
            check("a signature over different authenticator data is refused", tampered.status.value == 401 && tampered.bodyAsText().contains("signature"))
            val (a3, ac3) = assertOptions()
            val cd3 = clientData("webauthn.get", ac3); val ad3 = authData(rpId, UP_UV, 1)
            val cloned = assert(a3, cd3, ad3, sign(kp, ad3, cd3))
            check("a counter that did not advance is refused — the sign of a cloned authenticator — and the stored counter is untouched",
                cloned.status.value == 401 && cloned.bodyAsText().contains("sign count") && c.prepareStatement("SELECT sign_count FROM identity.credential WHERE account_id = ?").use { ps -> ps.setObject(1, accountId); ps.executeQuery().use { rs -> rs.next(); rs.getLong(1) == 1L } })
            val other = KeyPairGenerator.getInstance("EC").apply { initialize(256) }.generateKeyPair()
            val (a4, ac4) = assertOptions()
            val cd4 = clientData("webauthn.get", ac4); val ad4 = authData(rpId, UP_UV, 5)
            check("another key's signature is refused", assert(a4, cd4, ad4, sign(other, ad4, cd4)).status.value == 401)
            val (a5, ac5) = assertOptions()
            check("an unknown credential id is refused", assert(a5, clientData("webauthn.get", ac5), authData(rpId, UP_UV, 6), ByteArray(64), id = ByteArray(16)).status.value == 401)
            val (a6, ac6) = assertOptions()
            clock = clock.plus(Accounts.CHALLENGE_TTL).plusSeconds(1)
            val cd6 = clientData("webauthn.get", ac6); val ad6 = authData(rpId, UP_UV, 7)
            check("a challenge older than five minutes is refused", assert(a6, cd6, ad6, sign(kp, ad6, cd6)).status.value == 401)

            // --- recovery is a second way in (PD-032) -------------------------------------------------
            val kp2 = KeyPairGenerator.getInstance("EC").apply { initialize(256) }.generateKeyPair()
            val cred2 = ByteArray(16).also { java.security.SecureRandom().nextBytes(it) }
            val (a7, ac7) = assertOptions()
            val cd7 = clientData("webauthn.get", ac7); val ad7 = authData(rpId, UP_UV, 8)
            val again = assert(a7, cd7, ad7, sign(kp, ad7, cd7)); val access2 = field(again.bodyAsText(), "accessToken").toString()
            val (ch8, chal8) = registerOptions(token = access2)
            val second = register(ch8, clientData("webauthn.create", chal8), authData(rpId, UP_UV_AT, 0, cred2, coseKey(kp2)), id = cred2, token = access2)
            check("with a session, a second passkey is added to the same account rather than making a new one",
                second.status.value == 200 && field(second.bodyAsText(), "accountId").toString() == accountId.toString() && field(second.bodyAsText(), "created") == false)
            val me = client.get("/v1/me") { header("Authorization", "Bearer $access2") }.bodyAsText()
            check("the profile says how many ways in the person has", field(me, "credentials") == 2L)
            val (ch9, _) = registerOptions(token = access2)
            val stolen = register(ch9, clientData("webauthn.create", "x"), authData(rpId, UP_UV_AT, 0, cred2, coseKey(kp2)), id = cred2)
            check("a challenge issued to an account cannot be finished by an anonymous caller", stolen.status.value == 401 && stolen.bodyAsText().contains("another account"))

            // --- the association file -----------------------------------------------------------------
            val aasa = client.get("/.well-known/apple-app-site-association")
            check("this host tells iOS which app may use its passkeys", aasa.status.value == 200 && aasa.bodyAsText() == """{"webcredentials":{"apps":["TEAMID.app.example"]}}""")
        }
        println("  $passed passkey properties held")
        assertEquals(20, passed)
    }
}
