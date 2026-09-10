package thro.api

import io.ktor.client.request.get
import io.ktor.client.request.header
import io.ktor.client.request.post
import io.ktor.client.request.put
import io.ktor.client.request.setBody
import io.ktor.client.statement.HttpResponse
import io.ktor.client.statement.bodyAsText
import io.ktor.server.testing.testApplication
import java.security.KeyPairGenerator
import java.security.PrivateKey
import java.security.Signature
import java.time.Instant
import java.util.Base64
import java.util.UUID
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue
import thro.api.http.Authenticator
import thro.api.http.Deps
import thro.api.http.thro
import thro.authz.ObjectRef
import thro.authz.ObjectType

/**
 * Accounts and sessions (PD-030, plan §12d). The test holds the provider's private key, so it can
 * mint ID tokens that verify and ID tokens that must not, and it reads the tables back to hold that
 * no secret was ever stored.
 *
 * Skipped cleanly when no database is configured, rather than passing silently.
 */
class AuthTest {

    private val b64 = Base64.getUrlEncoder().withoutPadding()

    private fun jwt(key: PrivateKey, kid: String, claims: String, alg: String = "RS256"): String {
        val h = b64.encodeToString("""{"alg":"$alg","kid":"$kid"}""".toByteArray())
        val p = b64.encodeToString(claims.toByteArray())
        val sig = Signature.getInstance("SHA256withRSA").run { initSign(key); update("$h.$p".toByteArray()); sign() }
        return "$h.$p." + b64.encodeToString(sig)
    }

    @Test
    fun `sign in with a provider yields THRØ's own session, rotated with reuse detection, and no secret is stored`() {
        if (!TestDatabase.configured) {
            println("no database configured (set PGHOST) — auth tests skipped")
            return
        }
        val c = TestDatabase.migrated()
        var passed = 0
        fun check(name: String, cond: Boolean) {
            assertTrue(cond, "FAILED: $name")
            println("  PASS  $name")
            passed++
        }
        val apple = KeyPairGenerator.getInstance("RSA").apply { initialize(2048) }.generateKeyPair()
        val other = KeyPairGenerator.getInstance("RSA").apply { initialize(2048) }.generateKeyPair()
        val keys = JwkSource { provider, kid -> if (provider == Provider.APPLE && kid == "apple-1") apple.public else null }
        var clock = Instant.parse("2026-09-12T10:00:00Z")
        val clientId = "app.thro.darts"
        val device = UUID.randomUUID()
        fun claims(sub: String = "001234.abc", iss: String = "https://appleid.apple.com", aud: String = clientId, exp: Long = clock.epochSecond + 300) =
            """{"iss":"$iss","aud":"$aud","exp":$exp,"iat":${clock.epochSecond},"sub":"$sub","email":"hidden@privaterelay.appleid.com","name":"Sam"}"""

        testApplication {
            application {
                thro(Deps(connect = { TestDatabase.connect() }, authenticator = Authenticator.Bearer({ TestDatabase.connect() }, now = { clock }), now = { clock },
                    providers = mapOf(Provider.APPLE to clientId), keys = keys))
            }
            suspend fun post(path: String, body: String, token: String? = null): HttpResponse = client.post(path) { token?.let { header("Authorization", "Bearer $it") }; header("X-Thro-Device", device.toString()); setBody(body) }
            suspend fun get(path: String, token: String?): HttpResponse = client.get(path) { token?.let { header("Authorization", "Bearer $it") } }
            fun field(json: String, name: String): String? = Json.parseObject(json)[name]?.toString()
            suspend fun signIn(idToken: String) = post("/v1/auth/apple", """{"idToken":${thro.api.http.Contract.q(idToken)},"deviceId":"$device"}""")

            // --- what is not a sign-in --------------------------------------------------------------
            val forged = signIn(jwt(other.private, "apple-1", claims()))
            check("a token signed by anyone but the provider is 401: signature does not verify", forged.status.value == 401 && forged.bodyAsText().contains("signature"))
            val wrongAud = signIn(jwt(apple.private, "apple-1", claims(aud = "someone.else")))
            check("a token for another app is 401: audience", wrongAud.status.value == 401 && wrongAud.bodyAsText().contains("audience"))
            val expired = signIn(jwt(apple.private, "apple-1", claims(exp = clock.epochSecond - 1)))
            check("an expired token is 401: expired", expired.status.value == 401 && expired.bodyAsText().contains("expired"))
            val wrongIss = signIn(jwt(apple.private, "apple-1", claims(iss = "https://accounts.google.com")))
            check("a Google-issued token presented as Apple's is 401: issuer", wrongIss.status.value == 401 && wrongIss.bodyAsText().contains("issuer"))
            val none = signIn(jwt(apple.private, "apple-1", claims(), alg = "none"))
            check("alg none is not an algorithm", none.status.value == 401)
            check("nothing was created by any of that", c.prepareStatement("SELECT count(*) FROM identity.credential").use { it.executeQuery().use { rs -> rs.next(); rs.getInt(1) == 0 } })
            val google = post("/v1/auth/google", """{"idToken":"x.y.z","deviceId":"$device"}""")
            check("a provider this server is not configured for is 503, and says so", google.status.value == 503 && google.bodyAsText().contains("not configured"))

            // --- the first sign-in ----------------------------------------------------------------------
            val first = signIn(jwt(apple.private, "apple-1", claims()))
            check("a verified token signs in: 200 with a session", first.status.value == 200 && field(first.bodyAsText(), "created") == "true")
            val body = first.bodyAsText()
            val accountId = UUID.fromString(field(body, "accountId")); val playerId = UUID.fromString(field(body, "playerId"))
            val access = field(body, "accessToken")!!; val refresh = field(body, "refreshToken")!!
            val bound = c.prepareStatement(
                """
                SELECT (SELECT count(*) FROM identity.credential WHERE account_id = ? AND kind = 'apple' AND subject = '001234.abc' AND revoked_at IS NULL),
                       (SELECT count(*) FROM identity.player_claim WHERE account_id = ? AND player_id = ? AND method = 'self_created' AND revoked_at IS NULL),
                       (SELECT consent_basis FROM identity.account WHERE account_id = ?),
                       (SELECT display_name FROM identity.account WHERE account_id = ?)
                """.trimIndent(),
            ).use { ps -> ps.setObject(1, accountId); ps.setObject(2, accountId); ps.setObject(3, playerId); ps.setObject(4, accountId); ps.setObject(5, accountId); ps.executeQuery().use { rs -> rs.next(); listOf(rs.getInt(1), rs.getInt(2), rs.getString(3), rs.getString(4)) } }
            check("it created the account, the player and the self_created claim, with the person's own consent recorded", bound[0] == 1 && bound[1] == 1 && bound[2] == "self")
            check("the name is a placeholder, not the token's name claim: the name is the person's to give", bound[3] == Accounts.PLACEHOLDER_NAME)
            val second = signIn(jwt(apple.private, "apple-1", claims()))
            check("the same subject signs in to the same account and creates nothing", second.status.value == 200 && field(second.bodyAsText(), "accountId") == accountId.toString() && field(second.bodyAsText(), "created") == "false")

            // --- the session is THRØ's own ----------------------------------------------------------
            val me = get("/v1/me", access)
            check("the access token names the account, and its live claim is the principal", me.status.value == 200 && field(me.bodyAsText(), "playerId") == playerId.toString() && field(me.bodyAsText(), "named") == "false")
            check("no principal is 401 on /v1/me", get("/v1/me", null).status.value == 401)
            check("a made-up bearer token is nobody", get("/v1/me", "not-a-token").status.value == 401)
            val orgs = Organisations(c)
            val team = orgs.createTeam("Riverside A", by = playerId)
            Relations(c).grant(playerId, "admin", ObjectRef(ObjectType.TEAM, team.toString()))
            val rename = post("/v1/commands", """{"type":"RenameTeam","commandId":"${UUID.randomUUID()}","teamId":"$team","to":"Riverside Reds","expectedVersion":1}""", access)
            check("the same token drives the command endpoint as that player", rename.status.value == 200)
            val named = client.put("/v1/me/profile") { header("Authorization", "Bearer $access"); setBody("""{"displayName":"Sam W"}""") }
            check("the person sets their own name", named.status.value == 200 && field(named.bodyAsText(), "displayName") == "Sam W" && field(named.bodyAsText(), "named") == "true")
            val stored = c.prepareStatement("SELECT count(*) FROM identity.access_token WHERE token_hash = ? UNION ALL SELECT count(*) FROM identity.refresh_token WHERE token_hash = ?")
                .use { ps -> ps.setBytes(1, Accounts(c).sha256(access)); ps.setBytes(2, Accounts(c).sha256(refresh)); ps.executeQuery().use { rs -> rs.next(); val a = rs.getInt(1); rs.next(); a to rs.getInt(1) } }
            val raw = c.prepareStatement("SELECT count(*) FROM identity.access_token WHERE token_hash = ?").use { ps -> ps.setBytes(1, access.toByteArray()); ps.executeQuery().use { rs -> rs.next(); rs.getInt(1) } }
            check("only the SHA-256 of a token is stored, never the token", stored == (1 to 1) && raw == 0)

            // --- rotation, reuse, expiry, logout ------------------------------------------------------
            val rotated = post("/v1/auth/refresh", """{"refreshToken":${thro.api.http.Contract.q(refresh)}}""")
            check("refresh rotates: a new pair", rotated.status.value == 200 && field(rotated.bodyAsText(), "refreshToken") != refresh)
            val access2 = field(rotated.bodyAsText(), "accessToken")!!; val refresh2 = field(rotated.bodyAsText(), "refreshToken")!!
            check("the new access token works", get("/v1/me", access2).status.value == 200)
            val reused = post("/v1/auth/refresh", """{"refreshToken":${thro.api.http.Contract.q(refresh)}}""")
            check("presenting the used refresh token is reuse: 401 and the whole family is revoked", reused.status.value == 401 && reused.bodyAsText().contains("already been used") && get("/v1/me", access2).status.value == 401)
            check("and the successor refresh token is dead with it", post("/v1/auth/refresh", """{"refreshToken":${thro.api.http.Contract.q(refresh2)}}""").status.value == 401)
            val fresh = signIn(jwt(apple.private, "apple-1", claims()))
            val access3 = field(fresh.bodyAsText(), "accessToken")!!
            clock = clock.plus(Accounts.ACCESS_TTL).plusSeconds(1)
            check("an access token expires on its own clock", get("/v1/me", access3).status.value == 401)
            val refresh3 = field(fresh.bodyAsText(), "refreshToken")!!
            val again = post("/v1/auth/refresh", """{"refreshToken":${thro.api.http.Contract.q(refresh3)}}""")
            val access4 = field(again.bodyAsText(), "accessToken")!!
            check("but its refresh token still rotates into a live one", again.status.value == 200 && get("/v1/me", access4).status.value == 200)
            check("logout revokes the family", post("/v1/auth/logout", "", access4).status.value == 200 && get("/v1/me", access4).status.value == 401)
            val families = c.prepareStatement("SELECT array_agg(revoked_reason ORDER BY created_at) FROM identity.session_family WHERE account_id = ?").use { ps -> ps.setObject(1, accountId); ps.executeQuery().use { rs -> rs.next(); (rs.getArray(1).array as Array<*>).toList() } }
            // Three sign-ins, three families: the first died of reuse, the second was never touched, the third logged out.
            check("every family's fate is recorded, in its words", families == listOf("refresh token reused", null, "logout"))
        }
        println("  $passed auth properties held")
        assertEquals(25, passed)
    }
}
