package thro.api

import io.ktor.client.request.delete
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
import java.time.LocalDate
import java.util.Base64
import java.util.UUID
import kotlin.test.Test
import kotlin.test.assertTrue
import thro.api.http.Authenticator
import thro.api.http.Deps
import thro.api.http.thro
import thro.authz.ObjectRef
import thro.authz.ObjectType

/**
 * An organiser's contact email (PD-104): the one piece of contact information THRØ holds, for the one kind of person
 * who needs to be reachable — an adult who runs a league or a team. Never a player's, never a child's, never public,
 * and gone with the rest on erasure.
 */
class OrganiserContactTest {

    private val b64 = Base64.getUrlEncoder().withoutPadding()

    private fun jwt(key: PrivateKey, kid: String, claims: String): String {
        val h = b64.encodeToString("""{"alg":"RS256","kid":"$kid"}""".toByteArray())
        val p = b64.encodeToString(claims.toByteArray())
        val sig = Signature.getInstance("SHA256withRSA").run { initSign(key); update("$h.$p".toByteArray()); sign() }
        return "$h.$p." + b64.encodeToString(sig)
    }

    @Test
    fun `an adult who runs a league or team may give an email, the admins of its teams may read it, and erasure takes it`() {
        if (!TestDatabase.configured) {
            println("no database configured (set PGHOST) — organiser contact tests skipped")
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
        val clock = Instant.parse("2026-09-16T12:00:00Z")
        val clientId = "app.thro.darts"
        fun claims(sub: String) = """{"iss":"https://appleid.apple.com","aud":"$clientId","exp":${clock.epochSecond + 300},"iat":${clock.epochSecond},"sub":"$sub"}"""
        fun field(json: String, name: String): String? = Json.parseObject(json)[name]?.toString()
        fun stored(account: UUID): String? = c.prepareStatement("SELECT contact_email FROM identity.account WHERE account_id = ?")
            .use { ps -> ps.setObject(1, account); ps.executeQuery().use { rs -> rs.next(); rs.getString(1) } }

        testApplication {
            application {
                thro(Deps(connect = { TestDatabase.connect() }, authenticator = Authenticator.Bearer(now = { clock }), now = { clock },
                          providers = mapOf(Provider.APPLE to clientId), keys = keys))
            }
            val device = UUID.randomUUID()
            suspend fun post(path: String, body: String, token: String? = null): HttpResponse = client.post(path) {
                token?.let { header("Authorization", "Bearer $it") }; header("X-Thro-Device", device.toString()); setBody(body)
            }
            suspend fun put(path: String, body: String, token: String): HttpResponse = client.put(path) { header("Authorization", "Bearer $token"); setBody(body) }
            suspend fun get(path: String, token: String?): HttpResponse = client.get(path) { token?.let { header("Authorization", "Bearer $it") } }
            suspend fun signIn(sub: String) = post("/v1/auth/apple", """{"idToken":${thro.api.http.Contract.q(jwt(apple.private, "apple-1", claims(sub)))},"deviceId":"$device"}""").bodyAsText()

            // Lee runs a league; Ade runs a team in it; Zed runs nothing.
            val lee = signIn("001234.lee"); val leeToken = field(lee, "accessToken")!!
            val leeAccount = UUID.fromString(field(lee, "accountId")); val leePlayer = UUID.fromString(field(lee, "playerId"))
            val ade = signIn("001234.ade"); val adeToken = field(ade, "accessToken")!!; val adePlayer = UUID.fromString(field(ade, "playerId"))
            val zed = signIn("001234.zed"); val zedToken = field(zed, "accessToken")!!
            val orgs = Organisations(c)
            val league = orgs.createLeague("Teesside Thursday League")
            val season = orgs.openSeason(league, "2026/27", LocalDate.of(2026, 9, 1), LocalDate.of(2027, 5, 31))
            Relations(c).grant(leePlayer, "admin", ObjectRef(ObjectType.LEAGUE_SEASON, season.toString()))
            val riverside = orgs.createTeam("Riverside A", by = adePlayer)
            Relations(c).grant(adePlayer, "admin", ObjectRef(ObjectType.TEAM, riverside.toString()))
            val affiliation = orgs.affiliate(riverside, season, from = clock)

            // --- who may give one ---------------------------------------------------------------------------
            val unknownAge = put("/v1/me/profile", """{"contactEmail":"lee@example.org"}""", leeToken)
            check("an account whose age is not known cannot give an email", unknownAge.status.value == 403 && unknownAge.bodyAsText().contains("18 or over"))
            check("a new account's profile says it may not", field(get("/v1/me", leeToken).bodyAsText(), "organiser") == "false")
            put("/v1/me/profile", """{"ageBand":"adult"}""", leeToken)
            put("/v1/me/profile", """{"ageBand":"adult"}""", adeToken)
            put("/v1/me/profile", """{"ageBand":"adult"}""", zedToken)
            val nobody = put("/v1/me/profile", """{"contactEmail":"zed@example.org"}""", zedToken)
            check("an adult who runs no league and no team cannot give one, and is told what would let them",
                nobody.status.value == 403 && nobody.bodyAsText().contains("runs a league or a team"))
            check("a shape that is not an email is 400", put("/v1/me/profile", """{"contactEmail":"lee at example"}""", leeToken).status.value == 400)
            check("and one too long is 400", put("/v1/me/profile", """{"contactEmail":"${"a".repeat(250)}@example.org"}""", leeToken).status.value == 400)
            val given = put("/v1/me/profile", """{"contactEmail":"  Lee@Example.ORG "}""", leeToken)
            check("the league's organiser gives one, kept lower-case and trimmed, and the profile carries it",
                given.status.value == 200 && field(given.bodyAsText(), "contactEmail") == "lee@example.org" && field(given.bodyAsText(), "organiser") == "true"
                    && stored(leeAccount) == "lee@example.org")
            check("a team's admin may too", put("/v1/me/profile", """{"contactEmail":"ade@example.org"}""", adeToken).status.value == 200)

            // --- who may read it -------------------------------------------------------------------------------
            check("a season's organiser contact needs a principal", get("/v1/seasons/$season/organiser", null).status.value == 401)
            check("a stranger cannot read it", get("/v1/seasons/$season/organiser", zedToken).status.value == 403)
            check("nor a team still waiting to be let in", get("/v1/seasons/$season/organiser", adeToken).status.value == 403)
            orgs.acceptAffiliation(affiliation, clock)
            val contact = get("/v1/seasons/$season/organiser", adeToken)
            check("the admin of a team accepted into the season reads the organiser's email",
                contact.status.value == 200 && contact.bodyAsText().contains("lee@example.org"))
            check("and the organiser reads their own season's", get("/v1/seasons/$season/organiser", leeToken).status.value == 200)
            check("a season nobody has is a 404", get("/v1/seasons/${UUID.randomUUID()}/organiser", adeToken).status.value == 404)
            check("the public league front carries no email", !get("/v1/leagues", null).bodyAsText().contains("example.org"))

            // --- taking it away -----------------------------------------------------------------------------------
            val cleared = put("/v1/me/profile", """{"contactEmail":""}""", leeToken)
            check("an empty email takes it away", cleared.status.value == 200 && field(cleared.bodyAsText(), "contactEmail") == null && stored(leeAccount) == null)
            check("with none, the season's contact says so rather than inventing one", get("/v1/seasons/$season/organiser", adeToken).bodyAsText().contains("\"contacts\":[]"))
            put("/v1/me/profile", """{"contactEmail":"lee@example.org"}""", leeToken)
            check("erasing the account takes the email with everything else",
                client.delete("/v1/me") { header("Authorization", "Bearer $leeToken") }.status.value == 200 && stored(leeAccount) == null)
        }
        println("organiser contact: $passed checks passed")
    }
}
