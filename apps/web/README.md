# THRØ on the web

Three pages and no build step: the leagues THRØ knows, a league season's table, and how to delete an
account. It is a static site over the public API.

| Page | What it is |
|---|---|
| `index.html` | The leagues, searchable by name or town. A league with a season links to its table |
| `table.html?season=<uuid>` | That season's table, as `GET /v1/seasons/{id}/standings` computes it |
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

## Not built

Signing in, the organiser's own surface (entering results from a laptop, which the routes behind
PD-053 already allow), the privacy policy and terms, and anything that writes. This is the public face
and the one page a store requires; everything that writes still needs an account, and an account on the
web needs sign-in that does not exist here yet.
