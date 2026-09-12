# Going live: the day the domain arrives

The free arrangement is for a handful of testers. This is the ordered list for turning it into the public
one, written so that **buying the domain is the switch** and not the start of a scavenger hunt.

Read [DEPLOY.md](DEPLOY.md) first if nothing is deployed yet. This document assumes the free arrangement is
already running: the API on Render as a web service, the pages on Render as a static site.

## What actually changes

Three files name THRØ's public host. They agree today and they **stop agreeing** the day a domain exists,
which is the whole reason this is written down.

| Where | Free arrangement | With `thro.uk` |
|---|---|---|
| `render.yaml` → `THRO_RP_ID` | `thro-api-staging.onrender.com` | **`thro.uk`** |
| `render.yaml` → `THRO_RP_ORIGINS` | absent (the code defaults to `https://<rp id>`) | `https://thro.uk,https://api.thro.uk` |
| `Info.plist` → `THROAPIBaseURL` | `https://thro-api-staging.onrender.com` | **`https://api.thro.uk`** |
| `ThroDarts.entitlements` → `webcredentials:` | `thro-api-staging.onrender.com` | **`thro.uk`** |
| `render.yaml` → the two rewrite destinations | the API service's own hostname | **unchanged** |

Two things in that table are easy to get wrong and both are silent.

**The app's host and the relying party are different names.** The app talks to `api.thro.uk`; the passkey is
bound to `thro.uk`. That is legal because WebAuthn lets an origin assert a relying party that is a
registrable-domain suffix of itself, and it is the reason owning a domain is worth anything here: `thro.uk`
and `api.thro.uk` share one relying party, so a passkey made on the website works in the app. Two
`*.onrender.com` names cannot do this — `onrender.com` is on the Public Suffix List, so they are two
different registrable domains (PD-058).

**The rewrites do not move.** They address the API *service*, not the public name. A find-and-replace across
the repo would drag them onto the public domain and produce a rewrite that points at itself.

Both mistakes are caught by a check, and the switch itself is a command:

```bash
python3 tools/host.py --set thro.uk
```

It rewrites all four values, refuses a name that cannot be a relying party, and prints what is left to do by
hand. `python3 tools/host.py` on its own checks the repo is in one consistent arrangement, and runs in CI on
every push, so a half-finished switch fails the build rather than reaching a tester.

## The order to do it in

1. **Register `thro.uk`.** Nominet, about £8–10 a year, any registrar (PD-057).
2. **Run the switch**, commit it, and let CI confirm all four values agree.
   ```bash
   python3 tools/host.py --set thro.uk
   ```
3. **In Render — the static site:** Settings → Custom Domains → add `thro.uk` and `www.thro.uk`.
4. **In Render — the API service:** Settings → Custom Domains → add `api.thro.uk`.
5. **At the registrar:** add the records Render shows. **A records only — Render is IPv4-only, so delete
   any AAAA record**, or the site answers for some people and not others, intermittently, which is the
   worst way to find out.
6. **In Render — the API service's environment:** set `THRO_RP_ID` to `thro.uk` and `THRO_RP_ORIGINS` to
   `https://thro.uk,https://api.thro.uk`. `render.yaml` carries these, but a service already created from a
   blueprint does not pick up an edited value without a sync — set them in the dashboard and confirm.
7. **Move the API off the free instance** ($7/mo, PD-057). A free instance sleeps after fifteen idle minutes
   and a sleeping server drops a live match stream (ADR-007). This is not optional at launch.
8. **Rebuild and ship the app** with the new `Info.plist` and entitlement.
9. **Check the association file is served from the domain**, because iOS only offers a passkey for a domain
   that serves it: `curl -s https://thro.uk/.well-known/apple-app-site-association | head`. It must come
   back as JSON with no extension and no redirect.

## Tell the testers first: passkeys do not survive this

**A passkey is bound to one relying party.** Every passkey registered while the relying party was
`thro-api-staging.onrender.com` stops working the moment it becomes `thro.uk`. This is WebAuthn working
correctly — a credential that followed a name change would be a credential that could be stolen by whoever
took the old name.

**Sign in with Apple is not domain-bound.** A native app's Sign in with Apple uses the bundle id
(`app.thro.darts`) as its audience, not a hostname, so an account reached that way survives the move
untouched.

So during the free period: **tell testers to sign in with Apple.** Then the domain switch costs them
nothing, and nobody is locked out of an account with a season in it. A tester who has used a passkey is not
locked out either — they sign in with Apple and register a new passkey — but only if the same account is
reachable both ways, so it is worth having them do both before the switch rather than after.

## What is deliberately not being done

**Serving the pages from the API service to get web sign-in working before the domain.** It would work — one
origin, one relying party — and it is rejected: the public pages would inherit the free instance's
spin-down, so the account-deletion page a Play reviewer opens could take a minute or time out. There is also
nobody to serve: not one league administrator has been named. See DEPLOY.md.
