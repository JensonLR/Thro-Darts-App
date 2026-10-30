package thro.api

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue

/**
 * A borrowed connection comes back as a fresh one would (PD-196). The pool holds a single connection here, so the
 * second borrower is handed the very connection the first one dirtied: the role a request narrowed itself to, the
 * actor it named on the audit record, and a transaction it left open or broken are all gone.
 */
class PoolTest {
    private fun target() = Db.target({ System.getenv(it)?.takeIf { v -> v.isNotBlank() } })

    private fun one(c: java.sql.Connection, sql: String): String? =
        c.createStatement().use { st -> st.executeQuery(sql).use { rs -> rs.next(); rs.getString(1) } }

    @Test
    fun `the next borrower finds no role, no actor and no transaction`() {
        if (!TestDatabase.configured) return
        TestDatabase.migrated().close()
        Db.Pool(target(), size = 1).use { pool ->
            val login = pool.borrow().let { c -> one(c, "SELECT current_user").also { pool.giveBack(c) } }

            val first = pool.borrow()
            first.createStatement().use { it.execute("SET ROLE app_read") }
            first.createStatement().use { it.execute("SELECT set_config('thro.actor', '00000000-0000-0000-0000-000000000001', false)") }
            assertEquals("app_read", one(first, "SELECT current_user"))
            pool.giveBack(first)

            pool.borrow().let { c ->
                assertEquals(login, one(c, "SELECT current_user"), "the role went back with the connection")
                assertEquals("", one(c, "SELECT current_setting('thro.actor', true)").orEmpty(), "and so did the actor")
                pool.giveBack(c)
            }

            // A request that failed half-way through a transaction.
            pool.borrow().let { c ->
                c.autoCommit = false
                c.createStatement().use { it.execute("CREATE TEMP TABLE pool_probe (x int)") }
                runCatching { c.createStatement().use { it.execute("SELECT 1/0") } }
                pool.giveBack(c)
            }
            pool.borrow().let { c ->
                assertTrue(c.autoCommit, "handed out in autocommit, as a new connection is")
                assertEquals("1", one(c, "SELECT 1"), "and usable: the broken transaction was rolled back")
                assertEquals(null, one(c, "SELECT to_regclass('pool_probe')::text"), "with nothing it made left standing")
                pool.giveBack(c)
            }
        }
    }
}
