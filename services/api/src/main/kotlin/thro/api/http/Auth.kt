package thro.api.http

import java.sql.Connection
import java.util.UUID
import thro.api.Accounts

/**
 * Who is calling. A principal is a THRØ ID — the subject every authorization rule and every command
 * handler already speaks. When accounts arrive (FB-1) the authenticator that produces one resolves
 * an account to its live `identity.player_claim` here, and nothing below this line changes.
 */
public data class Principal(val subject: UUID, val accountId: UUID? = null)

/**
 * Turns a request into a [Principal], or nothing. The production authenticator — passkeys,
 * short-lived access tokens, rotating refresh tokens (ADR-008) — is founder decision FB-1 and does
 * not exist. The server refuses to start without one; the only one that exists is [Dev].
 */
public fun interface Authenticator {
    /** [connection] is the request's own; an authenticator that needs the store opens nothing else. */
    public fun authenticate(header: (String) -> String?, connection: () -> Connection): Principal?

    /**
     * The production authenticator (PD-030): `Authorization: Bearer <access token>`. The token is
     * opaque and looked up server-side; it names an account whose live claim is the principal.
     * Unknown, expired and revoked tokens are simply nobody.
     */
    public class Bearer(private val now: () -> java.time.Instant = { java.time.Instant.now() }) : Authenticator {
        override fun authenticate(header: (String) -> String?, connection: () -> Connection): Principal? {
            val raw = header("Authorization")?.trim() ?: return null
            if (!raw.startsWith("Bearer ", ignoreCase = true)) return null
            val token = raw.substring(7).trim()
            if (token.isEmpty() || token.length > 128) return null
            return Accounts(connection(), now).resolve(token)?.let { (account, player) -> Principal(player, account) }
        }
    }

    /**
     * Development only. Trusts an `X-Thro-Dev-Subject` header carrying a UUID, which is to say it
     * trusts anyone who can reach the port. It cannot be constructed unless the environment says
     * `THRO_DEV_AUTH=1`, it says so on every start, and nothing in a deployment manifest may set
     * that variable. It exists so the HTTP layer can be built and tested before FB-1 is decided,
     * not so that a server can be run without deciding it.
     */
    public class Dev internal constructor() : Authenticator {
        /**
         * **Names an account when the subject is one** (PD-166). This returned `Principal(subject)` with
         * `accountId` always null, and both `withAccount` and `withModerator` refuse a principal with no account
         * behind it — so every account-shaped route answered 403 to every local request, the moderation queue
         * among them. That is why the moderation page is recorded as never looked at in a browser: the documented
         * recipe could not reach it, which is a different thing from nobody having bothered.
         *
         * A subject that is not an account still gets a principal with no account, because a player who has never
         * signed in is exactly that, and the routes that refuse one should go on refusing it. This reads the
         * request's own connection and opens nothing else.
         */
        override fun authenticate(header: (String) -> String?, connection: () -> Connection): Principal? =
            header(HEADER)?.let { runCatching { UUID.fromString(it.trim()) }.getOrNull() }?.let { subject ->
                val isAccount = runCatching {
                    connection().prepareStatement("SELECT 1 FROM identity.account WHERE account_id = ?").use { ps ->
                        ps.setObject(1, subject); ps.executeQuery().use { it.next() }
                    }
                }.getOrDefault(false)
                Principal(subject, if (isAccount) subject else null)
            }

        public companion object {
            public const val HEADER: String = "X-Thro-Dev-Subject"
            public const val VARIABLE: String = "THRO_DEV_AUTH"

            /**
             * The dev authenticator, only when [env] says so and the database is on this machine;
             * null otherwise. A development authenticator pointed at a remote database is a
             * deployment with the door open, whatever the variable says.
             */
            public fun ifEnabled(env: (String) -> String?): Dev? {
                if (env(VARIABLE) != "1") return null
                val host = env("PGHOST") ?: "localhost"
                check(host == "localhost" || host == "127.0.0.1" || host == "::1") {
                    "$VARIABLE=1 with PGHOST=$host: the development authenticator is refused against a database that is not on this machine"
                }
                return Dev()
            }
        }
    }
}
