# ADR-011 — Deployment topology and environments

**Status:** Accepted · **Date:** 2026-09-03

## Decision

**One container image on a container platform-as-a-service, managed Postgres with point-in-time
recovery, and object storage. Single region, UK/EU. Infrastructure as code in the repository.**

Kubernetes is rejected outright: it is a full-time job for a one-person team. Serverless fits poorly
against long-lived event streams and JVM cold starts. A full cloud-provider setup brings an
identity, networking and load-balancer surface disproportionate to the problem.

UK/EU region because the product is unambiguously British and the data-protection questions point
there.

## Environments — four, no more

- **local** — containerised Postgres with deterministic seeded fixtures.
- **test** — an ephemeral database per CI run. **Never a shared test database**; that is the classic
  solo-team flake source.
- **staging** — the identical image, its own database, **synthetic data only, never a production
  clone**. The design export already carries realistic personal data, which is exactly what must not
  be copied around.
- **production** — managed Postgres, point-in-time recovery, and **a scheduled restore drill**.

Environment-suffixed application identifiers so all three install side by side on one device — which
is required to test two-device sync at all.

## Identifiers, fixed now because they are effectively permanent

- **The bundle identifier and Android application id must not contain the product name.** A rename is
  anticipated; changing an Android application id means a **new store listing with no migration
  path** — installs, reviews and ratings all lost. Use the company domain.
- **All identifiers ASCII.** The `Ø` cannot appear in identifiers, package names or URL schemes.
- **Public URL shapes are fixed now** — `/e/{eventId}`, `/m/{matchId}`, `/p/{playerHandle}` — because
  universal and app links make them permanent and the web presence must honour them.

## Security baseline

Secrets in the platform secret store, never in the repository or a shipped bundle — a shipped binary
is public, so anything in it is disclosed. **Secret scanning from the first commit**, since a leaked
key in history needs both rotation and a history rewrite. Per-module database roles with least
privilege, and **no update or delete grant on the evidence schema** — integrity and security in one
control. Card data never touches THRØ; the payment processor's hosted surface keeps it out of scope.

## What CI gates from day one

The scoring conformance corpus on every platform; engine property tests; **event-log replay producing
byte-identical projections**; the append-only grant assertion; idempotency (replay every command
three times, assert one event and identical responses including rejections); the **dart-inference
guard** (run the statistics suite against a corpus with zero dart rows and assert every dart-level
metric reports unavailable); the API contract diff; the token and contrast gates from ADR-010;
formatting, linting and static analysis; secret and dependency scanning; a money-type guard
forbidding floating point in payment and scoring paths; **the pseudonymisation gate** — assert that
every read model, export and public page can be regenerated from the pseudonymised source, which is
what makes the design's deletion promise structural rather than a matter of discipline; and voice
lints — no emoji in user-facing
strings, and all user-facing text in a central catalogue so the product can be renamed.

## Read-model rebuilds in production

ADR-004 tests rebuildability by truncating and replaying. **That is a test procedure, not a production
one** — a rebuild taking tens of minutes would be an outage of the organiser console.

Read models carry a `projection_version`. A rebuild writes a **new version alongside the live one**
and switches reads atomically when it completes; the old version is dropped after a hold period. No
truncation of a live read model, ever.

## The organiser console

Served by the same application and the same container image, so the console's version cannot drift
from the API it calls. No separate origin, which also avoids a second deployment pipeline and the
cross-origin, cookie-domain and content-security surface that comes with one.

## Tests that cannot run in CI

Two properties this architecture depends on are not testable by a build server, and an unowned manual
test is a test that runs once:

- **Power-cut durability** on both reference devices — kill the process mid-visit, and cut power
  mid-visit. **Every release candidate.**
- **Two-device offline sync**, including the fully-contested case. **Every release candidate**, using
  the environment-suffixed builds installed side by side.

Both have a written procedure and a named device inventory. A release candidate without them is not a
release candidate.

## Cost

Roughly $60–200 per month at launch. A cluster or a service fleet would be five to ten times that,
plus the operator's attention, which is the scarcer resource.

## Revisit trigger

Sustained load needing more than about four application instances; a second region for latency or
data residency; or platform pricing crossing roughly three times the equivalent raw-compute cost.
