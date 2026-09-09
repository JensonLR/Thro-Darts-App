package thro.api.http

/**
 * The contract, once. Every route the server mounts is an [Endpoint] here, and `/openapi.json` is
 * rendered from this list — so the document cannot describe a route that is not served, and the
 * server cannot serve a route the document does not describe (the server refuses to start if a
 * handler is missing for an endpoint, or present for none). ADR-001's mitigation — a machine-checked
 * contract rather than a hand-maintained one — without a schema plugin: the registry is the schema.
 *
 * The committed copy at `services/api/openapi.json` is held equal to the served document by test,
 * so a change to the contract is a change to a reviewed file.
 */
public data class Endpoint(
    val id: String,
    val method: String,
    val path: String,
    val summary: String,
    val description: String,
    val authenticated: Boolean,
    val request: Schema? = null,
    val responses: Map<Int, String>,
    val query: List<Pair<String, String>> = emptyList(),
)

/** A JSON schema fragment, written by hand and rendered verbatim. */
public data class Schema(val json: String)

public object Contract {

    public const val VERSION: String = "0.1.0"

    private val commandEnvelope = Schema(
        """
        {"type":"object","required":["type","commandId"],
         "description":"One command. `type` selects the shape; the caller's identity is the authenticated principal and is never read from the body; the device is the X-Thro-Device header.",
         "properties":{
           "type":{"type":"string","enum":["RecordVisit","RenameTeam","RearrangeFixture","SetAvailability","NameLineup"]},
           "commandId":{"type":"string","format":"uuid","description":"Idempotency key per device: a replay returns the stored response verbatim."},
           "matchId":{"type":"string","format":"uuid"},
           "deviceSeq":{"type":"integer","description":"RecordVisit: the device's gapless sequence for this match."},
           "player":{"type":"string","enum":["home","away"],"description":"RecordVisit: the seat that threw."},
           "visitTotal":{"type":"integer"},"dartsUsed":{"type":["integer","null"]},"dartsAtDouble":{"type":["integer","null"]},
           "occurredAt":{"type":"string","format":"date-time"},"occurredTz":{"type":"string"},
           "clientEffect":{"type":["string","null"]},"engineVersion":{"type":"string"},
           "teamId":{"type":"string","format":"uuid"},"to":{"type":"string","description":"RenameTeam: the new name. RearrangeFixture: the new date-time."},
           "fixtureId":{"type":"string","format":"uuid"},"venueId":{"type":["string","null"],"format":"uuid"},
           "playerId":{"type":"string","format":"uuid"},"status":{"type":"string","enum":["available","unavailable","maybe"]},
           "players":{"type":"array","items":{"type":"string","format":"uuid"},"description":"NameLineup: the side in slot order."},
           "expectedVersion":{"type":"integer","description":"The row version the author last saw; 0 when the row does not exist yet. A different current version is a 409 with the current row."}
         }}
        """.trimIndent(),
    )

    public val endpoints: List<Endpoint> = listOf(
        Endpoint(
            id = "health", method = "GET", path = "/healthz", authenticated = false,
            summary = "Liveness, and the schema version the database stands at",
            description = "Unauthenticated. Reports the migration ledger's current version; a database the code cannot serve is a 503.",
            responses = mapOf(200 to "ok, with schemaVersion", 503 to "database unreachable or behind the code"),
        ),
        Endpoint(
            id = "openapi", method = "GET", path = "/openapi.json", authenticated = false,
            summary = "This document", description = "Rendered from the same registry the routes are mounted from.",
            responses = mapOf(200 to "OpenAPI 3.1 document"),
        ),
        Endpoint(
            id = "commands", method = "POST", path = "/v1/commands", authenticated = true,
            summary = "The one command endpoint (ADR-007)",
            description = "Every client-to-server state change, online or from a queue. Identity comes from the principal, the device from X-Thro-Device. Applied is 200; a replay returns what it returned; stale is 409 with the current row; a refusal is 422 in the store's words; a sequence gap is 409; a match the caller is not in is 404.",
            request = commandEnvelope,
            responses = mapOf(200 to "applied, or a replay of an earlier answer", 400 to "malformed", 401 to "no principal", 404 to "not this match, or not in it", 409 to "stale version, or sequence gap", 413 to "body over 64 KiB", 422 to "refused"),
        ),
        Endpoint(
            id = "me.inbox", method = "GET", path = "/v1/me/inbox", authenticated = true,
            summary = "The caller's own Secretary tasks, by section",
            description = "Tasks whose subject is the caller: consent, claims, anything the Secretary needs from them.",
            responses = mapOf(200 to "sections of tasks", 401 to "no principal"),
        ),
        Endpoint(
            id = "team.inbox", method = "GET", path = "/v1/teams/{teamId}/inbox", authenticated = true,
            summary = "A team's Secretary inbox, for those who run it",
            description = "Requires team.manage on the team (admin or captain). Anyone else is 403, and the refusal is on the audit record.",
            responses = mapOf(200 to "sections of tasks", 401 to "no principal", 403 to "you do not run this team"),
        ),
        Endpoint(
            id = "me.discovery", method = "GET", path = "/v1/me/discovery", authenticated = true,
            summary = "Darts the caller can play, and why each card is there",
            description = "The discovery read model for the caller between from and to. Every card carries its reasons; nothing is called eligible that THRØ cannot check.",
            query = listOf("from" to "date-time, default now", "to" to "date-time, default from + 60 days", "locality" to "the caller's team's locality, optional"),
            responses = mapOf(200 to "sections of cards", 400 to "malformed dates", 401 to "no principal"),
        ),
    )

    /** OpenAPI 3.1, rendered by hand from [endpoints]. Deterministic: the same registry, the same bytes. */
    public fun openApi(): String {
        val paths = endpoints.groupBy { it.path }.entries.sortedBy { it.key }.joinToString(",\n") { (path, eps) ->
            val ops = eps.sortedBy { it.method }.joinToString(",\n") { e ->
                val params = (Regex("\\{(\\w+)}").findAll(path).map { it.groupValues[1] }.map { name ->
                    """{"name":${q(name)},"in":"path","required":true,"schema":{"type":"string","format":"uuid"}}"""
                } + e.query.map { (name, desc) -> """{"name":${q(name)},"in":"query","required":false,"description":${q(desc)},"schema":{"type":"string"}}""" }).toList()
                val security = if (e.authenticated) ""","security":[{"principal":[]}]""" else ""
                val body = e.request?.let { ""","requestBody":{"required":true,"content":{"application/json":{"schema":${it.json}}}}""" } ?: ""
                val responses = e.responses.entries.sortedBy { it.key }.joinToString(",") { (code, desc) -> """"$code":{"description":${q(desc)}}""" }
                """    "${e.method.lowercase()}":{"operationId":${q(e.id)},"summary":${q(e.summary)},"description":${q(e.description)},"parameters":[${params.joinToString(",")}]$security$body,"responses":{$responses}}"""
            }
            """  ${q(path)}:{
$ops
  }"""
        }
        return """{
"openapi":"3.1.0",
"info":{"title":"THRØ API","version":"$VERSION","description":"Routes over the command handlers. One command endpoint (ADR-007); identity from the principal, never the body (ADR-008); every relationship decision recorded."},
"components":{"securitySchemes":{"principal":{"type":"apiKey","in":"header","name":"${Authenticator.Dev.HEADER}","description":"Development authenticator only (THRO_DEV_AUTH=1). The production scheme is founder decision FB-1 and replaces this entry."}}},
"paths":{
$paths
}
}
"""
    }

    internal fun q(s: String): String {
        val b = StringBuilder(s.length + 2).append('"')
        for (ch in s) when {
            ch == '\\' -> b.append("\\\\")
            ch == '"' -> b.append("\\\"")
            ch == '\n' -> b.append("\\n")
            ch == '\r' -> b.append("\\r")
            ch == '\t' -> b.append("\\t")
            ch < ' ' -> b.append("\\u%04x".format(ch.code))
            else -> b.append(ch)
        }
        return b.append('"').toString()
    }
}
