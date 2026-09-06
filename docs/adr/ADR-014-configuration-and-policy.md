# ADR-014 — Configuration and policy versioning

**Status:** Accepted · **Date:** 2026-09-03

## Context

Several decisions are described elsewhere as "configurable", and that word was doing a great deal of
unexamined work. Hostile review noticed that between them they amount to a versioned-policy
subsystem that no record defined:

- **PD-001 / B1** — whether the client prompts for `darts_used` and `darts_at_double`, and which
  statistics are shown.
- **PD-002 / B2** — the rating eligibility rule.
- **ADR-009** — which rating model is published, and the scale epoch.
- **ADR-012** — per-competition tie-break chains and per-round format overrides.
- **ADR-008** — the policy version recorded against every authorization decision.
- **ADR-004** — `rules_version` pinned to every event.

The claim that B1 and B2 need "no migration" was true of the schema and **incomplete about the
system**: both answers also require behaviour changes to reach native clients that ship on store
timelines.

## Decision

**Three distinct kinds of configuration, deliberately not unified.**

### 1 — Competition policy (data, not configuration)

Tie-break chains, format definitions, in and out rules, per-round overrides. These are **rows owned
by the `competition` module**, versioned, and **pinned by identifier onto the match at open**
(`rules_version`). A match is scored under the rules it started with, permanently, even if the
competition's policy changes mid-season.

Correctness depends on this: a correction replayed two seasons later must replay under the rules that
applied then, not today's.

### 2 — Platform policy (server-evaluated)

Rating eligibility, quarantine thresholds, publication gates. **Evaluated server-side only**, so a
change takes effect without a client release. Every policy carries a version, and **the version is
recorded on every decision it produces** — which is what makes an eligibility change auditable and a
rating recomputation reproducible.

This is why PD-002 is genuinely reversible: lowering the eligibility floor is a policy version bump
plus a recomputation, with the old decisions still explaining themselves under the old version.

### 3 — Client capability flags (remote, but bounded)

Whether the keypad prompts for `darts_used`; whether a statistic is rendered; whether a surface is
enabled. Fetched at launch and cached, with a **compiled-in default** so a client with no network
behaves correctly — non-negotiable, given that scoring must work offline.

**Deliberate limits.** Flags may gate *presentation and capture*, never *rules*. A flag must never
change how a leg is scored — that is `rules_version`'s job, and mixing them would make two clients
disagree about a result. Flags are removed once a rollout completes; a flag older than two releases
is a defect, not a feature.

## What this makes honest

"B1 and B2 are reachable without migration" is now precise:

| | Schema | Server behaviour | Client behaviour |
|---|---|---|---|
| **B1** — capture `darts_used` | already nullable, no change | statistics basis is computed | **needs a client release** to prompt |
| **B1** — which statistics shown | none | none | flag, no release |
| **B2** — eligibility floor | none | policy version bump + recomputation | none |

So B2 is fully reversible at runtime. **B1's capture half requires a client release** — which is
cheap if the field and the flag exist from the start, and a migration if they do not. That is the
actual argument for putting `darts_used` in schema v1, and it is now stated correctly.

## Revisit trigger

The first time a policy change needs to apply retroactively to already-decided outcomes — which the
versioning permits but the product may not want, and that is a product decision rather than a
technical one.
