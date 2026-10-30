package thro.api

import com.zaxxer.hikari.HikariConfig
import com.zaxxer.hikari.HikariDataSource
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

    /**
     * Connections a request borrows and gives back (PD-196). Opening one costs the API about 170 ms on
     * production — TCP, TLS and the password exchange, Frankfurt to London — before the first query, and every
     * request paid it. Only requests borrow: the live-match listener and the daily sweep hold their own.
     *
     * A connection carries session state between borrowers, and two pieces of it matter here: the module role
     * each request narrows itself to (ADR-011) and `thro.actor`, which names who did what on the audit record.
     * [giveBack] clears both, and a connection that cannot be cleared is thrown away rather than lent again.
     *
     * Small and idle-friendly: Neon suspends its compute after five idle minutes and Render the server after
     * fifteen, so nothing is kept warm on purpose, and a connection idle past four minutes is closed.
     */
    public class Pool(t: Target, size: Int = 8) : AutoCloseable {
        private val source = HikariDataSource(HikariConfig().apply {
            jdbcUrl = t.jdbcUrl; username = t.user; password = t.password
            poolName = "thro"
            maximumPoolSize = size
            minimumIdle = 0
            idleTimeout = 240_000
            maxLifetime = 600_000
            connectionTimeout = 10_000
        })

        public fun borrow(): Connection = source.connection

        public fun giveBack(c: Connection) {
            val clean = runCatching {
                // Out of any transaction first: a RESET inside one the pool then rolls back would be undone.
                if (!c.autoCommit) { c.rollback(); c.autoCommit = true }
                c.createStatement().use { it.execute("RESET ROLE; RESET ALL") }
            }.isSuccess
            if (!clean) source.evictConnection(c)
            c.close()
        }

        override fun close(): Unit = source.close()
    }

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
