package thro.api

import java.sql.DriverManager

/**
 * The deploy step ADR-013 requires: bring the database to this image's version, then exit.
 * Runs before the new image serves a request (Fly's release command). Connects as the deploy
 * user — which must be `thro_owner` or a member of it, because every migration does `SET ROLE
 * thro_owner` — and never as an application role. Refuses a ledgerless, edited or ahead database
 * with the reason, so a wrong deploy stops here rather than at the first request.
 */
public fun main() {
    val env: (String) -> String? = { System.getenv(it)?.takeIf { v -> v.isNotBlank() } }
    val url = "jdbc:postgresql://${env("PGHOST") ?: "localhost"}:${env("PGPORT") ?: "5432"}/${env("PGDATABASE") ?: "postgres"}" +
        (if (env("PGSSLMODE") != null) "?sslmode=${env("PGSSLMODE")}" else "")
    DriverManager.getConnection(url, env("PGUSER") ?: "postgres", env("PGPASSWORD") ?: "").use { c ->
        val before = Migrations.currentVersion(c)
        val applied = Migrations.apply(c)
        val after = Migrations.currentVersion(c)
        if (applied.isEmpty()) println("schema already at V${"%03d".format(after)}; nothing applied")
        else println("migrated V${before?.let { "%03d".format(it) } ?: "---"} -> V${"%03d".format(after)}: " + applied.joinToString { it.file })
    }
}
