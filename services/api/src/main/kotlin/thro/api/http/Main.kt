package thro.api.http

import io.ktor.server.cio.CIO
import io.ktor.server.engine.embeddedServer
import java.sql.Connection
import java.sql.DriverManager

/**
 * `gradle -p services/api serve`. Refuses to start without an authenticator, and the only one that
 * exists is the development one (THRO_DEV_AUTH=1). Migrations are a deploy step (ADR-013), not a
 * boot step: a database behind the code is reported by /healthz as 503 and served nowhere else.
 */
public fun main() {
    val env: (String) -> String? = { System.getenv(it)?.takeIf { v -> v.isNotBlank() } }
    val authenticator = Authenticator.Dev.ifEnabled(env)
        ?: error(
            "no authenticator: the production scheme is founder decision FB-1 (execution plan §9). " +
                "For development only, set ${Authenticator.Dev.VARIABLE}=1 to trust the ${Authenticator.Dev.HEADER} header.",
        )
    System.err.println("WARNING: development authenticator enabled — any caller naming a UUID in ${Authenticator.Dev.HEADER} is that person. Never in a deployment.")
    val connect: () -> Connection = {
        DriverManager.getConnection(
            "jdbc:postgresql://${env("PGHOST") ?: "localhost"}:${env("PGPORT") ?: "5432"}/${env("PGDATABASE") ?: "postgres"}",
            env("PGUSER") ?: "postgres", "",
        )
    }
    val port = env("PORT")?.toIntOrNull() ?: 8080
    embeddedServer(CIO, port = port) { thro(Deps(connect, authenticator)) }.start(wait = true)
}
