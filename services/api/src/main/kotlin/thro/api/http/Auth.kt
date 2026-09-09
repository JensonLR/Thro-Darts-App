package thro.api.http

import java.util.UUID

/**
 * Who is calling. A principal is a THRØ ID — the subject every authorization rule and every command
 * handler already speaks. When accounts arrive (FB-1) the authenticator that produces one resolves
 * an account to its live `identity.player_claim` here, and nothing below this line changes.
 */
public data class Principal(val subject: UUID)

/**
 * Turns a request into a [Principal], or nothing. The production authenticator — passkeys,
 * short-lived access tokens, rotating refresh tokens (ADR-008) — is founder decision FB-1 and does
 * not exist. The server refuses to start without one; the only one that exists is [Dev].
 */
public fun interface Authenticator {
    public fun authenticate(header: (String) -> String?): Principal?

    /**
     * Development only. Trusts an `X-Thro-Dev-Subject` header carrying a UUID, which is to say it
     * trusts anyone who can reach the port. It cannot be constructed unless the environment says
     * `THRO_DEV_AUTH=1`, it says so on every start, and nothing in a deployment manifest may set
     * that variable. It exists so the HTTP layer can be built and tested before FB-1 is decided,
     * not so that a server can be run without deciding it.
     */
    public class Dev internal constructor() : Authenticator {
        override fun authenticate(header: (String) -> String?): Principal? =
            header(HEADER)?.let { runCatching { UUID.fromString(it.trim()) }.getOrNull() }?.let { Principal(it) }

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
