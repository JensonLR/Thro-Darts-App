package thro.api

import java.net.URI
import java.net.URLDecoder
import java.sql.Connection
import java.sql.DriverManager

/**
 * How the server and the migration step find the database. Either `DATABASE_URL` in the form a
 * platform sets it (`postgres://user:password@host:port/db?sslmode=require`), or the PG* variables.
 * Nothing here is ever logged.
 */
public object Db {
    public data class Target(val jdbcUrl: String, val user: String, val password: String)

    public fun target(env: (String) -> String?, urlVariable: String = "DATABASE_URL"): Target {
        env(urlVariable)?.let { raw ->
            val u = URI(raw)
            val userInfo = u.userInfo?.split(":", limit = 2) ?: emptyList()
            val query = u.rawQuery?.let { "?$it" } ?: (env("PGSSLMODE")?.let { "?sslmode=$it" } ?: "")
            return Target(
                "jdbc:postgresql://${u.host}:${if (u.port > 0) u.port else 5432}${u.path}$query",
                userInfo.getOrNull(0)?.let { URLDecoder.decode(it, "UTF-8") } ?: "postgres",
                userInfo.getOrNull(1)?.let { URLDecoder.decode(it, "UTF-8") } ?: "",
            )
        }
        val ssl = env("PGSSLMODE")?.let { "?sslmode=$it" } ?: ""
        return Target(
            "jdbc:postgresql://${env("PGHOST") ?: "localhost"}:${env("PGPORT") ?: "5432"}/${env("PGDATABASE") ?: "postgres"}$ssl",
            env("PGUSER") ?: "postgres", env("PGPASSWORD") ?: "",
        )
    }

    public fun connect(t: Target): Connection = DriverManager.getConnection(t.jdbcUrl, t.user, t.password)
}
