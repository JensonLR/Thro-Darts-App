# Links: the file a domain has to serve

THRØ's link grammar was fixed by **ADR-011** before there was anything to serve it, and the app's
parser has read `https://` paths since it was written — `ThroRoute(url:)` treats the path as the
contract and the scheme as incidental, so adopting universal links is a hosting decision rather than
a code change. This directory holds the one file that hosting needs.

## What is here, and what is deliberately not

- **`.well-known/apple-app-site-association`** — the association file, listing every path this build
  can actually read. `tools/check_aasa.py` holds it against `ThroRoute`'s own parser on every push:
  a path advertised here that the app cannot parse is a link that opens THRØ and then does nothing,
  which looks exactly like the app being broken.

- **The `applinks` entry is there since PD-117 (17 September 2026)**: `applinks:thro.uk`, beside the
  `webcredentials:` line passkeys need. The API serves the association file at `thro.uk`, with `/link/*`
  — a screen's sign-in code — as the first path that opens the app from a link, and this committed file
  keeps every path the parser reads, held to the parser by `tools/check_aasa.py`. Adding the entry
  before the domain existed would have made iOS ask Apple's CDN for a file that was not there, after
  which the app silently never handles a link; that is why it waited for the domain.

## What turning this on took, once there was a domain

1. Buy the domain and serve this file at `https://<domain>/.well-known/apple-app-site-association`
   over **HTTPS with a valid certificate**, `Content-Type: application/json`, **no redirect** and
   **no `.json` extension** on the filename.
2. In Xcode, on the **ThroDarts** target, *Signing & Capabilities* → **+ Capability** →
   **Associated Domains**, and add `applinks:<domain>`.
3. Nothing else. `ThroRootView` already routes an incoming `URL` through `ThroRouter`, and
   `RoutingTests` already holds that `thro://m/7F2A` and `https://any.host/m/7F2A` name the same
   place.

## Two facts worth knowing before relying on it

- **The file is fetched by an Apple CDN, not by the phone from the server.** Apple picks up a change
  within about 24 hours and installed apps re-check roughly weekly, so this is not something to
  iterate on in an afternoon. Get it right before shipping it.
- **A link into a phone's own data is a link to nothing on anybody else's.** `/m/{matchId}` names a
  match in *this* device's journal. Until there is a server, a shared match link opens the app on
  the sender's phone and opens nothing on the recipient's — which is why the share card carries no
  link at all, and why the web side of these paths has nothing to serve yet beyond this file.
