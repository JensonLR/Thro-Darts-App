package thro.api

import io.ktor.client.request.get
import io.ktor.client.request.header
import io.ktor.client.request.post
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
import kotlin.test.assertTrue
import thro.api.http.Authenticator
import thro.api.http.Deps
import thro.api.http.thro

/**
 * The moderation queue over the wire, as a moderator with a real account (PD-101, PD-103). `HttpTest` holds that the
 * queue refuses strangers and the development principal; this holds that a named moderator, signed in the way a person
 * is, reads it by name and that a decision reaches the person it is about.
 */
class ModerationHttpTest {

    private val b64 = Base64.getUrlEncoder().withoutPadding()

    private fun jwt(key: PrivateKey, kid: String, claims: String): String {
        val h = b64.encodeToString("""{"alg":"RS256","kid":"$kid"}""".toByteArray())
        val p = b64.encodeToString(claims.toByteArray())
        val sig = Signature.getInstance("SHA256withRSA").run { initSign(key); update("$h.$p".toByteArray()); sign() }
        return "$h.$p." + b64.encodeToString(sig)
    }

    @Test
    fun `a named moderator works the queue by name, and a suspension reaches the person`() {
        if (!TestDatabase.configured) {
            println("no database configured (set PGHOST) — moderation HTTP tests skipped")
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
        val keys = JwkSource { provider, kid -> if (provider == Provider.APPLE && kid == "apple-1") apple.public else null }
        var clock = Instant.parse("2026-09-16T10:00:00Z")
        val clientId = "app.thro.darts"
        fun claims(sub: String) = """{"iss":"https://appleid.apple.com","aud":"$clientId","exp":${clock.epochSecond + 300},"iat":${clock.epochSecond},"sub":"$sub"}"""
        fun field(json: String, name: String): String? = Json.parseObject(json)[name]?.toString()

        // The moderator is named by account id at boot, so their account exists before the server does — made the way a
        // person's is, by a first sign-in, so it holds the player and the claim a principal needs.
        val moderator = Accounts(c, now = { clock }).signIn("apple", "001234.ann", UUID.randomUUID()).accountId

        testApplication {
            application {
                thro(Deps(connect = { TestDatabase.connect() }, authenticator = Authenticator.Bearer(now = { clock }), now = { clock },
                          providers = mapOf(Provider.APPLE to clientId), keys = keys, moderators = setOf(moderator)))
            }
            val device = UUID.randomUUID()
            suspend fun post(path: String, body: String, token: String? = null): HttpResponse = client.post(path) {
                token?.let { header("Authorization", "Bearer $it") }; header("X-Thro-Device", device.toString()); setBody(body)
            }
            suspend fun get(path: String, token: String?): HttpResponse = client.get(path) { token?.let { header("Authorization", "Bearer $it") } }
            suspend fun signIn(sub: String) = post("/v1/auth/apple", """{"idToken":${thro.api.http.Contract.q(jwt(apple.private, "apple-1", claims(sub)))},"deviceId":"$device"}""")

            val rude = signIn("001234.rude").bodyAsText()
            val rudeToken = field(rude, "accessToken")!!
            val rudeAccount = UUID.fromString(field(rude, "accountId"))
            check("a person signs in and is somebody", get("/v1/me", rudeToken).status.value == 200)
            check("and is not a moderator: the queue is 403", get("/v1/reports", rudeToken).status.value == 403)

            val ann = signIn("001234.ann").bodyAsText()
            check("the moderator signs in to the account named at boot", field(ann, "accountId") == moderator.toString())
            val annToken = field(ann, "accessToken")!!
            post("/v1/me/terms", "{}", annToken)
            val reported = post("/v1/reports", """{"subjectKind":"account","subjectId":"$rudeAccount","reason":"Threats after the match."}""", annToken)
            check("a report is raised over the wire", reported.status.value == 200)
            val reportId = field(reported.bodyAsText(), "reportId")!!

            val queue = get("/v1/reports", annToken)
            val text = queue.bodyAsText()
            check("the named moderator reads the queue", queue.status.value == 200 && text.contains(reportId))
            check("and each report carries the name somebody read, and what was said",
                text.contains("\"subject\":\"${Accounts.PLACEHOLDER_NAME}\"") && text.contains("Threats after the match."))
            val bad = post("/v1/reports/$reportId/decisions", """{"outcome":"vanish","note":"gone"}""", annToken)
            check("an answer a report cannot have is refused in words", bad.status.value == 400 && bad.bodyAsText().contains("not one of the answers"))
            val suspended = post("/v1/reports/$reportId/decisions", """{"outcome":"account_suspended","note":"Threats, after a warning."}""", annToken)
            check("the moderator suspends the account", suspended.status.value == 200)
            clock = clock.plusSeconds(1)
            check("and the person's session is dead on their next request", get("/v1/me", rudeToken).status.value == 401)
            val refused = signIn("001234.rude")
            check("and they cannot sign in again, and are told why", refused.status.value == 403 && refused.bodyAsText().contains("suspended"))
            val back = post("/v1/reports/$reportId/decisions", """{"outcome":"reinstated","note":"Apologised."}""", annToken)
            check("reinstating is a decision too", back.status.value == 200)
            check("and they sign in again", signIn("001234.rude").status.value == 200)
            check("the queue says the report was answered twice", get("/v1/reports", annToken).bodyAsText().contains("\"decisions\":2"))
        }
        println("moderation over HTTP: $passed checks passed")
    }
}
