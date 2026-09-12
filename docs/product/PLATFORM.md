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

**Fly London is the cheaper platform at every size** and the only true London one; if this were a fresh
choice it would be Fly, with `auto_stop_machines = off` so its proxy does not stop the machine under an
idle-looking stream.

**It is not a fresh choice, and PD-057 revises this.** The API already runs on Render, the founder asked to
stay there, and Frankfurt against London is tens of milliseconds for an app whose slowest step is a person
throwing three darts. One platform and one dashboard is worth more than that to a single developer. The
change actually worth making is **off the free instance** — it sleeps after fifteen idle minutes and a
sleeping server drops a live match stream — at $7 a month. Revisit Fly at about a thousand players, where
Render's curve turns: roughly $25 against $7, and $39 against $14 at ten thousand.

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
| API (Render Starter — PD-057) | $7 | $25.75 | $39.25 |
| Database | $0 (Neon free) | $25 (Supabase Pro) | $32 |
| CI | $0 | $0 | $0 |
| Everything else | $0 | ~$0.30 | ~$68 |
| Apple Developer Program | $8.25 | $8.25 | $8.25 |
| **Total** | **~$15/mo** | **~$59/mo** | **~$168/mo** |

Staying on Render costs about **$19 a month more at a thousand players and $25 more at ten thousand** than
Fly would. That is the price of one platform instead of two, and it is worth paying now and not at ten
thousand — which is why PD-057 sets the revisit at the first of those numbers rather than leaving it open.

At 10k the alternative to all of it is Hetzner with self-managed Postgres at about $45 — roughly $120 cheaper
and four to eight hours a month of the founder's time, in Germany rather than London. Pay the $120.

## The surfaces THRØ runs on

| Surface | Today | What it would take |
| --- | --- | --- |
| **iPhone** | Shipping | — |
| **iPad** | Same binary; the layout pass is done to 43 call sites (PD-052), the tab bar and empty states are fixed, and it has been looked at on a device | Two columns where a screen earns them (a list beside the map), and what a tall screen does with genuinely spare room |
| **Apple Watch** | **A watch app, shipping** (PD-078): the leg at a glance, fed from the phone over WatchConnectivity, and the Live Activity still reaches the Smart Stack on its own | Scoring *from* the wrist — a different thing, because a watch that scores is a second writer to the journal and needs events, not a projection. The engine is pure Swift and already builds for watchOS, so the rules come free; the sync does not |
| **TV / monitor** | Two things, and they are different. A phone drives an external display at room size (`ThroExternalScene`), by cable or AirPlay, and that is where the **live board** is. And an **Apple TV app** (PD-079) shows the league's table, fixtures and results all evening with no phone involved, from the public routes, signing in to nothing | The live board on the Apple TV itself, which needs either a sign-in on a television or a public match stream — the second is a safeguarding decision and not a plumbing one. And an Apple TV registered to the team before a device build can sign — the layered icon and top-shelf artwork are done, generated from the phone's mark by `tools/make_tv_artwork.swift` |
| **Android** | **Started** (PD-081): a Compose client on the brand board, showing a checkout derived at runtime by the shared Kotlin engine. The toolchain, the composite builds and the generated tokens all reach it, and CI builds it on Linux every push | Everything above the floor: the scoring screen, the keypad, the journal on the phone — `sqlite-jdbc` ships Android natives, so it can be the same journal rather than a second one — and the chalk grain the board has on iOS |
| **Wear OS** | — | Follows the Android client, same shape as the watch app |
| **Android TV / Chromecast** | — | Follows the Android client; the tvOS layout ports |
| **Web** | Built (PD-056): the leagues, a season's table, its fixtures, and the account-deletion page Play requires. Static, on Render, `/v1` rewritten to the API so it is one origin | Sign-in, and with it the organiser's own surface — entering results from a laptop, which the PD-053 routes already allow |

**The order, as revised on 12 September 2026 (PD-064).** iPhone and iPad first, then the **web** — live
since that morning — and then, instead of Android: **finish what exists**, because nobody has used any of it
yet and a second platform doubles the surface nobody has looked at. Then **the rest of Apple** — the watch, done that
same day, and then tvOS, both done that week — which share the tokens, the pure Swift engine and the whole client and are new
surfaces on a known stack. Then **Android**, which is a second implementation of everything, and Wear OS behind it. The
**rating** stays last, not because it is least wanted but because OD-001 cannot close without real matches.

Android is half the market and it waits; the deletion URL that unblocked Play is live and does not expire.
The previous order put Android second, and the reasons for that — the market, the store fees — are still
true. What changed is that three faults were found in shipped code by looking at it, none of which had a
failing test, and all of which would have been duplicated onto a second platform.
