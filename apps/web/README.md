# THRØ on the web

Three pages and no build step: the leagues THRØ knows, a league season's table, and how to delete an
account. It is a static site over the public API.

| Page | What it is |
|---|---|
| `index.html` | The leagues, searchable by name or town. A league with a season links to its table |
| `table.html?season=<uuid>` | That season's table, as `GET /v1/seasons/{id}/standings` computes it |
| `fixtures.html?season=<uuid>` | That season's fixtures, played and still to play, from `GET /v1/seasons/{id}/fixtures`. A result says how it was arrived at: scored on THRØ, or the league's word |
| `organiser.html?season=<uuid>` | **Running a league.** Sign in with a passkey, then type the week's results. Only an administrator of that season may save one (PD-053); everybody else is refused politely, because nothing on this page can grant the relation |
| `delete-account.html` | Static. Google Play requires a web URL for account deletion before an Android app may ship, and it says what the app says: what goes, what stays, and why |

## Why it looks like THRØ without a design system in it

`tokens.css` is the generated token file, copied from `packages/design-tokens/generated/`, and
`tools/check_web_tokens.py` fails the build if the copy drifts. A static host serves a directory and will
not follow a link out of one, so a copy is the only shape available — and an unguarded copy is how a brand
quietly forks. Everything in `thro.css` is arrangement; no colour, radius or spacing is invented here.

## Why there is no framework

The pages need the tokens, one fetch and a little DOM. A dependency would have to earn itself against
that, and none can yet. If one ever does, this README is where the reason goes.

## The API is on the same origin

`thro.js` calls `/v1/...` with no host, so a deployment puts the pages and the API behind one origin —
Cloudflare in front, routing `/v1/*` to the API (PD-051) — and the browser never makes a cross-origin
request. No CORS, no preflight, no second host to configure, and no credentials in a query string.
`?api=https://…` overrides it for looking at another server.

## Running it

```bash
PGHOST=localhost THRO_DEV_AUTH=1 gradle -p services/api serve   # one terminal
python3 apps/web/serve.py                                       # another; http://localhost:8899
```

`serve.py` serves the directory and proxies `/v1` to the API, so what you look at in development is
arranged the way the real thing is rather than in a way that only works locally.

## Signing in

A passkey, not an OAuth redirect. The API already speaks WebAuthn (PD-030), and a redirect flow on a static
site means a client id, a callback page and a third party in the round trip; a passkey needs none of those.
The session lives in `sessionStorage` and goes when the tab closes, which is the right default for somebody
entering results on a shared laptop in a pub back room.

**What is verified, and what is not.** The handshake's first half is proven end to end — the options call
returns a challenge and the relying-party id through the same origin. The ceremony itself needs a human with
a device, so the signed-in view has not been seen in a browser. The server side behind it *is* proven: a
result posted by somebody who does not administer the season is a 403, the same post after they are named is
a 200 that comes back `"kind":"declared"` because no match was scored, and a second result on the same
fixture is a 409. That is the whole authority model and PD-055's rule, tested through this proxy.

## Not built

Correcting a result already in — the API supersedes, this page does not offer it yet. The privacy policy and
terms. And anything about a team or a player: this is a league's own surface, not an account's.
