package thro.api

import java.io.ByteArrayOutputStream
import java.net.URI
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
            // rawUserInfo, decoded exactly once: URI.userInfo has already decoded, and URLDecoder would
            // decode again and turn a '+' into a space — a password with either would fail at boot.
            val userInfo = u.rawUserInfo?.split(":", limit = 2)?.map(::percentDecode) ?: emptyList()
            val query = u.rawQuery?.let { "?$it" } ?: (env("PGSSLMODE")?.let { "?sslmode=$it" } ?: "")
            return Target(
                "jdbc:postgresql://${u.host}:${if (u.port > 0) u.port else 5432}${u.path}$query",
                userInfo.getOrNull(0) ?: "postgres",
                userInfo.getOrNull(1) ?: "",
            )
        }
        val ssl = env("PGSSLMODE")?.let { "?sslmode=$it" } ?: ""
        return Target(
            "jdbc:postgresql://${env("PGHOST") ?: "localhost"}:${env("PGPORT") ?: "5432"}/${env("PGDATABASE") ?: "postgres"}$ssl",
            env("PGUSER") ?: "postgres", env("PGPASSWORD") ?: "",
        )
    }

    public fun connect(t: Target): Connection = DriverManager.getConnection(t.jdbcUrl, t.user, t.password)

    internal fun percentDecode(s: String): String {
        val out = ByteArrayOutputStream()
        var i = 0
        while (i < s.length) {
            if (s[i] == '%' && i + 2 < s.length + 0 && i + 2 <= s.length - 1) { out.write(s.substring(i + 1, i + 3).toInt(16)); i += 3 }
            else { out.write(s[i].toString().toByteArray(Charsets.UTF_8)); i++ }
        }
        return String(out.toByteArray(), Charsets.UTF_8)
    }
}
