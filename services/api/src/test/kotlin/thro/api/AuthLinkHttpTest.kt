package thro.api

import io.ktor.client.request.get
import io.ktor.client.request.header
import io.ktor.client.request.post
import io.ktor.client.request.setBody
import io.ktor.client.statement.HttpResponse
import io.ktor.client.statement.bodyAsText
import io.ktor.server.testing.testApplication
import java.time.Instant
import java.util.UUID
import kotlin.test.Test
import kotlin.test.assertTrue
import thro.api.http.Authenticator
import thro.api.http.Deps
import thro.api.http.thro

/**
 * A screen signs in by the phone that holds the account (PD-114): the screen asks for a code, the signed-in phone
 * approves it, and the screen collects a session of its own — once, on the device that asked, before the code
 * expires. Nothing here is a password, and nothing here lets a phone that is not signed in do anything.
 */
class AuthLinkHttpTest {

    @Test
    fun `a screen shows a code, the phone approves it, and the screen is signed in`() {
        if (!TestDatabase.configured) {
            println("no database configured (set PGHOST) — auth link HTTP tests skipped")
            return
        }
        val c = TestDatabase.migrated()
        val accounts = Accounts(c)
        var passed = 0
        fun check(name: String, cond: Boolean) {
            assertTrue(cond, "FAILED: $name")
            println("  PASS  $name")
            passed++
        }
        val phone = UUID.randomUUID()
        val screen = UUID.randomUUID()
        val jenson = accounts.signIn("apple", "006.jenson", phone)
        accounts.setDisplayName(jenson.accountId, "Jenson R.")
        var clock = Instant.parse("2026-09-16T12:00:00Z")

        testApplication {
            // Real sessions, not the development principal: approving a screen is an account's act.
            application { thro(Deps(connect = { TestDatabase.connect() }, authenticator = Authenticator.Bearer(now = { clock }), now = { clock })) }
            suspend fun post(path: String, body: String, bearer: String? = null): HttpResponse = client.post(path) {
                bearer?.let { header("Authorization", "Bearer $it") }; header("X-Thro-Device", phone.toString()); setBody(body)
            }
            suspend fun get(path: String, bearer: String? = null): HttpResponse = client.get(path) { bearer?.let { header("Authorization", "Bearer $it") } }
            fun field(text: String, key: String) = Regex("\"$key\":\"([^\"]+)\"").find(text)?.groupValues?.get(1)

            // --- the screen asks ------------------------------------------------------------------------------------
            check("a screen names its device", post("/v1/auth/link", "{}").status.value == 400)
            val asked = post("/v1/auth/link", """{"deviceId":"$screen"}""")
            val body = asked.bodyAsText()
            val linkId = field(body, "linkId"); val code = field(body, "code")
            check("the screen is given a link and a six-character code that expires", asked.status.value == 200 && linkId != null && code != null && code.length == 6 && body.contains("\"expiresAt\":\"2026-09-16T12:05:00Z\""))
            check("the code has no look-alikes", code!!.all { it in "ABCDEFGHJKLMNPQRSTUVWXYZ23456789" })
            val waiting = get("/v1/auth/link/$linkId?deviceId=$screen")
            check("until the phone speaks, the screen waits", waiting.status.value == 202 && waiting.bodyAsText().contains("\"state\":\"waiting\""))
            check("another device cannot collect it", get("/v1/auth/link/$linkId?deviceId=${UUID.randomUUID()}").status.value == 404)

            // --- the phone approves --------------------------------------------------------------------------------
            check("approving needs a signed-in phone", post("/v1/auth/link/$code/approve", "{}").status.value == 401)
            check("a code THRØ does not have is a 404", post("/v1/auth/link/ZZZZZZ/approve", "{}", jenson.accessToken).status.value == 404)
            check("the code is read however it is typed", post("/v1/auth/link/${code.lowercase()}/approve", "{}", jenson.accessToken).status.value == 200)
            check("approving twice is a 409", post("/v1/auth/link/$code/approve", "{}", jenson.accessToken).status.value == 409)

            // --- the screen collects its session, once --------------------------------------------------------------
            val collected = get("/v1/auth/link/$linkId?deviceId=$screen")
            val token = field(collected.bodyAsText(), "accessToken")
            check("the screen is signed in as the phone's account", collected.status.value == 200 && collected.bodyAsText().contains("\"accountId\":\"${jenson.accountId}\"") && token != null)
            check("and the session is real", client.get("/v1/me") { header("Authorization", "Bearer $token") }.bodyAsText().contains("Jenson R."))
            check("collected once: the link is spent", get("/v1/auth/link/$linkId?deviceId=$screen").status.value == 410)
            check("a spent code cannot be approved again", post("/v1/auth/link/$code/approve", "{}", jenson.accessToken).status.value == 404)

            // --- a code that was never approved dies in five minutes ---------------------------------------------------
            val second = post("/v1/auth/link", """{"deviceId":"$screen"}""").bodyAsText()
            val secondCode = field(second, "code")!!; val secondLink = field(second, "linkId")!!
            clock = Instant.parse("2026-09-16T12:06:00Z")
            check("after five minutes the phone finds nothing to approve", post("/v1/auth/link/$secondCode/approve", "{}", jenson.accessToken).status.value == 404)
            check("and the screen is told to ask again", get("/v1/auth/link/$secondLink?deviceId=$screen").status.value == 410)
        }
        println("auth link over HTTP: $passed checks passed")
    }
}
