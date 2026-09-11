# Where THRØ runs, and what it costs

Researched 11 September 2026, prices in USD unless marked. Two questions the founder asked: what Cloudflare
would cost, and what the best arrangement is for iOS, Android, web — and, added the same night, Apple Watch,
TV and their Android equivalents.

## Cloudflare, plainly

**Cloudflare cannot run THRØ's API, and no amount of money changes that.** Workers is a V8 isolate runtime
that runs JavaScript and WebAssembly only — no JVM, no JDBC, no Ktor engine. Hyperdrive's connection string
is reachable only from inside a Worker, so a JVM on another host cannot use it. D1 and Durable Objects are
Worker-only too. Cloudflare Containers *can* run a JVM, but they need Workers Paid and a Worker in front,
which is a rewrite wearing a hosting bill.

What Cloudflare is genuinely worth, today, is the edge in front of whatever runs the API:

| Piece | What it does for THRØ | Cost |
| --- | --- | --- |
| DNS, CDN, free WAF ruleset, Turnstile | The front door, and bot pressure absorbed before it reaches a £6 server | **$0** |
| Tunnel | The origin never needs a public IP | **$0** |
| R2 | Player pictures and share cards later; 10 GB free, **no egress charge** | **$0** now, ~$0.015/GB-mo after |
| Pro plan | Managed WAF and OWASP rulesets | $25/mo ($20 annual) — **worth it at launch, not before** |

**The one thing this would normally cost us is already built.** Behind Cloudflare a live match stream must
heartbeat and must resume, or the proxy read timeout (100 seconds by default, then a 524) cuts it mid-leg.
THRØ's stream pings every 15 seconds and resumes from `Last-Event-ID` — [Streams.kt](services/api/src/main/kotlin/thro/api/http/Streams.kt),
proven by `StreamTest` — and Tunnels only buffer a stream when the response is not `text/event-stream`, which
this one is. What to hold onto: the client calls a stream stale after 45 seconds, and that number must stay
above the ping and below the proxy timeout. Both margins are currently wide.

## Hosting the API

The API is a JVM holding long-lived SSE connections, which rules out several otherwise-obvious hosts: Cloud
Run bills an open stream as active time and caps it at an hour, Railway cuts connections at 15 minutes, App
Runner is closed to new customers, and **Render's free tier spins down and kills streams** — which is what
staging does today.

| Host | Region | Idle | 1k MAU | 10k MAU |
| --- | --- | --- | --- | --- |
| **Fly.io** | **London** | $6.46 | $6.66 | $14.14 |
| Hetzner CX23 | Germany/Finland | €5.49 | €5.49 | €5.49 |
| Lightsail | London | $7 | $7 | $12 |
| Render (paid) | Frankfurt only | $7 | $25.75 | $39.25 |

**Move to Fly London.** It is the only true London platform-as-a-service of the three, it is cheaper than
Render at every size, and it has the 1 GB tier Render lacks. One caution: set `auto_stop_machines = off`, or
Fly's proxy stops the machine under an idle-looking stream.

## The database

THRØ's connection pool holds connections open, so **scale-to-zero pricing never applies to us** — every
usage-based quote must be read as 730 hours a month.

| Option | 1k MAU | 10k MAU | Backups |
| --- | --- | --- | --- |
| **Supabase Pro** | **$25 flat** | ~$32 | Daily, 7 days; point-in-time is +$100 |
| Neon Launch | ~$40 | ~$124 | 7-day point-in-time |
| RDS t4g, London | ~$16 | ~$33 | Real point-in-time; double for multi-AZ |
| Hetzner, self-managed | ~€12 | ~€16 | Yours to build, 4–8 hours a month |

Neon's free tier is right for now and its paid curve is the wrong shape for us, because we pay always-on
rates on a platform whose discount is suspension. **Stay on Neon free until launch, then move to Supabase
Pro** — or pin Neon at 0.25 compute units with suspension off, and accept ~$40.

## Deployment and automation

**GitHub cut runner prices about 39% on 1 January 2026 and removed the 10× macOS multiplier.** macOS minutes
are now $0.062, and the 2,000 free monthly minutes buy 2,000 macOS minutes — so thirty iOS builds a month,
even at forty minutes each, cost **nothing**. Xcode Cloud (25 hours free, then $49.99 per 100) is the
fallback. Scheduled jobs: GitHub Actions and Cloudflare Cron Triggers are free; Render charges $1 a month per
cron job.

Everything else, at 1k and 10k users: push notifications direct to APNs from Ktor ($0), email through SES
($0.30 → $3), Sentry EU (free → $26), PostHog EU (free → ~$25, and sample mobile session replay or it is the
one line that runs away), UptimeRobot and a status page ($0).

## What it costs, all in

| | Now | Launch / 1k MAU | 10k MAU |
| --- | --- | --- | --- |
| Edge (Cloudflare) | $0 | $0 | $20 |
| API (Fly London) | $6.46 | $6.66 | $14 |
| Database | $0 (Neon free) | $25 (Supabase Pro) | $32 |
| CI | $0 | $0 | $0 |
| Everything else | $0 | ~$0.30 | ~$68 |
| Apple Developer Program | $8.25 | $8.25 | $8.25 |
| **Total** | **~$15/mo** | **~$40/mo** | **~$142/mo** |

At 10k the alternative is Hetzner with self-managed Postgres at about $45 — about $100 cheaper and four to
eight hours a month of the founder's time, in Germany rather than London. Pay the $100.

## The surfaces THRØ runs on

| Surface | Today | What it would take |
| --- | --- | --- |
| **iPhone** | Shipping | — |
| **iPad** | Same binary, and the layout pass has begun (PD-052): a readable column rather than a phone screen pulled apart, on ten screens of forty-three so far | Two-column layouts where the screen earns them (a list beside the map); the 33 screens the audit found still stretching |
| **Apple Watch** | The Live Activity reaches the Smart Stack; there is **no watch app** | A watchOS target: the scoreboard at a glance, then scoring from the wrist over WatchConnectivity. The engine is pure Swift and already shared, so the rules come free |
| **TV / monitor** | An external display shows the board at room size (`ThroExternalScene`), by cable or AirPlay | A tvOS target for a venue: the board, the fixture, the league table, with no keypad. Same design tokens |
| **Android** | Nothing yet; the design tokens already generate Kotlin | A Compose client. ADR-002 keeps a Kotlin scoring engine structurally parallel to the Swift one, which is the hard half already done |
| **Wear OS** | — | Follows the Android client, same shape as the watch app |
| **Android TV / Chromecast** | — | Follows the Android client; the tvOS layout ports |
| **Web** | Nothing yet | Needed sooner than it looks: Google Play requires a **web account-deletion URL**, and the organiser subscription is best sold on the web (see MONEY.md) |

The order that serves the product: finish iPhone and iPad, then the **web** (because two commitments already
depend on it), then **Android** (the second half of the market and cheaper store fees), then the **watch**
(the most-wanted extra for a player at the oche), then **TV** for venues.
