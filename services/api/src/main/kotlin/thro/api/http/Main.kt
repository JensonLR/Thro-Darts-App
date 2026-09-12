package thro.api.http

import io.ktor.server.cio.CIO
import io.ktor.server.engine.embeddedServer
import java.sql.Connection
import java.util.UUID
import thro.api.Db
import thro.api.HttpJwkSource
import thro.api.Provider
import thro.api.RelyingParty

/**
 * `gradle -p services/api serve`. Refuses to start without an authenticator, and the only one that
 * exists is the development one (THRO_DEV_AUTH=1). Migrations are a deploy step (ADR-013), not a
 * boot step: a database behind the code is reported by /healthz as 503 and served nowhere else.
 */
public fun main() {
    val env: (String) -> String? = { System.getenv(it)?.takeIf { v -> v.isNotBlank() } }
    val target = Db.target(env)
    val connect: () -> Connection = { Db.connect(target) }
    // Passkeys (PD-030's fallback): the relying party is this server's public host. On Fly that is
    // <app>.fly.dev until a domain is attached; THRO_RP_ID overrides it, THRO_RP_ORIGINS lists the
    // origins allowed to sign (default https://<rp id>).
    val rpId = env("THRO_RP_ID") ?: env("FLY_APP_NAME")?.let { "$it.fly.dev" }
    val rp = rpId?.let { RelyingParty(it, (env("THRO_RP_ORIGINS")?.split(",")?.map(String::trim)?.toSet() ?: setOf("https://$it"))) }
    val appleAppIds = env("THRO_APPLE_APP_IDS")?.split(",")?.map(String::trim).orEmpty()
    // PD-030: Sign in with Apple and Google, each configured by THRØ's client id at that provider.
    val providers = buildMap {
        env("THRO_APPLE_CLIENT_ID")?.let { put(Provider.APPLE, it) }
        env("THRO_GOOGLE_CLIENT_ID")?.let { put(Provider.GOOGLE, it) }
    }
    val dev = Authenticator.Dev.ifEnabled(env)
    val authenticator = when {
        dev != null -> {
            System.err.println("WARNING: development authenticator enabled — any caller naming a UUID in ${Authenticator.Dev.HEADER} is that person. Never in a deployment.")
            dev
        }
        providers.isNotEmpty() -> Authenticator.Bearer()
        else -> error(
            "no authenticator: set THRO_APPLE_CLIENT_ID and/or THRO_GOOGLE_CLIENT_ID for Sign in with Apple/Google (PD-030), " +
                "or, for development only, ${Authenticator.Dev.VARIABLE}=1 to trust the ${Authenticator.Dev.HEADER} header.",
        )
    }
    if (providers.isEmpty()) System.err.println("note: no sign-in provider configured; /v1/auth/apple and /v1/auth/google answer 503")
    if (rp == null) System.err.println("note: no relying party (THRO_RP_ID or FLY_APP_NAME); passkey routes answer 503")
    else System.err.println("passkeys: relying party ${rp.id}, origins ${rp.origins}")
    // PD-050: the people who answer the moderation queue, named here as a comma-separated list of account
    // ids. Not a table: THRØ has no staff role, and a list in the database is a list a session could grow.
    // A name that is not a uuid is dropped rather than guessed at, and said so below.
    val named = env("THRO_MODERATORS")?.split(",")?.map(String::trim)?.filter { it.isNotEmpty() }.orEmpty()
    val moderators = named.mapNotNull { runCatching { UUID.fromString(it) }.getOrNull() }.toSet()
    if (moderators.size != named.size) System.err.println("WARNING: ${named.size - moderators.size} entry in THRO_MODERATORS is not an account id and was ignored.")
    if (moderators.isEmpty()) System.err.println("note: no moderators (THRO_MODERATORS); /v1/reports answers 403 to everyone, so nobody can answer a report on this server.")
    val port = env("PORT")?.toIntOrNull() ?: 8080
    embeddedServer(CIO, port = port) { thro(Deps(connect, authenticator, providers = providers, keys = HttpJwkSource(), relyingParty = rp, appleAppIds = appleAppIds, moderators = moderators)) }.start(wait = true)
}
