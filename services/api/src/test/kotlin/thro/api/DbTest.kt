package thro.api

import kotlin.test.Test
import kotlin.test.assertEquals

/** How the server finds its database from what a platform sets, decoded exactly once. */
class DbTest {
    @Test
    fun `DATABASE_URL is honoured, its credentials decoded once, and its own sslmode wins`() {
        val env = mapOf(
            "DATABASE_URL" to "postgres://thro_api_staging:a%2Bb%25c@top2.nearest.of.thro-db-staging.internal:5432/thro_api_staging?sslmode=disable",
            "PGSSLMODE" to "require",
        )
        val t = Db.target(env = { env[it] })
        assertEquals("jdbc:postgresql://top2.nearest.of.thro-db-staging.internal:5432/thro_api_staging?sslmode=disable", t.jdbcUrl)
        assertEquals("thro_api_staging", t.user)
        assertEquals("a+b%c", t.password)
        val plain = Db.target(env = { mapOf("PGHOST" to "db.example", "PGUSER" to "u", "PGPASSWORD" to "p w", "PGSSLMODE" to "require")[it] })
        assertEquals("jdbc:postgresql://db.example:5432/postgres?sslmode=require", plain.jdbcUrl)
        assertEquals("p w", plain.password)
        val migrate = Db.target({ mapOf("MIGRATE_DATABASE_URL" to "postgres://postgres:s3cret@thro-db-staging.flycast:5432/thro_api_staging?sslmode=disable", "DATABASE_URL" to "postgres://x:y@z/zz")[it] }, urlVariable = "MIGRATE_DATABASE_URL")
        assertEquals("postgres", migrate.user)
        println("  PASS  the database target is read from the platform's URL, decoded once")
    }
}
