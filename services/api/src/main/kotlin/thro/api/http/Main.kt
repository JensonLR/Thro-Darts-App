package thro.api.http

import io.ktor.server.cio.CIO
import io.ktor.server.engine.embeddedServer
import java.sql.Connection
import java.sql.DriverManager
import thro.api.HttpJwkSource
import thro.api.Provider

/**
 * `gradle -p services/api serve`. Refuses to start without an authenticator, and the only one that
 * exists is the development one (THRO_DEV_AUTH=1). Migrations are a deploy step (ADR-013), not a
 * boot step: a database behind the code is reported by /healthz as 503 and served nowhere else.
 */
public fun main() {
    val env: (String) -> String? = { System.getenv(it)?.takeIf { v -> v.isNotBlank() } }
    val connect: () -> Connection = {
        DriverManager.getConnection(
            "jdbc:postgresql://${env("PGHOST") ?: "localhost"}:${env("PGPORT") ?: "5432"}/${env("PGDATABASE") ?: "postgres"}",
            env("PGUSER") ?: "postgres", env("PGPASSWORD") ?: "",
        )
    }
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
    if (providers.isEmpty()) System.err.println("note: no sign-in provider configured; /v1/auth/* answer 503")
    val port = env("PORT")?.toIntOrNull() ?: 8080
    embeddedServer(CIO, port = port) { thro(Deps(connect, authenticator, providers = providers, keys = HttpJwkSource())) }.start(wait = true)
}
