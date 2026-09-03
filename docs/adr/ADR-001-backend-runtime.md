# ADR-001 — Backend runtime and language

**Status:** Accepted · **Date:** 2026-09-03

## Context

Greenfield. The operating team is one founder plus AI agents, so operational simplicity and
*verifiable* agent output are first-class requirements, not afterthoughts. The domain is rules-heavy:
a leg is a closed algebra of states, and the scoring rules must produce identical results on iOS,
Android and server validation.

No prototype exists, so nothing is inherited. The brief explicitly forbids adopting a stack because
a prototype used it.

## Options

Scored against correctness for a closed rules domain, solo-operator productivity, agent output that
the toolchain can catch mistakes in, ecosystem, testing, observability, operational burden, cost,
scaling, and code-sharing with native clients.

- **TypeScript/Node** — best single-language story (server plus the organiser web console) and the
  largest agent training corpus. But `number` is IEEE-754 and `JSON.parse` yields floats by default,
  so every money and score boundary needs a guard against a constraint we are told never to violate.
  No structural sharing with native clients.
- **Go** — the best pure operations story. But no sum types and no exhaustiveness checking, and the
  zero value makes an invalid leg state silently constructible. Wrong tool for a closed algebra.
- **Kotlin/JVM** — sealed interfaces, data classes and exhaustive `when` give a compiler-checked
  total state machine. Strong testing and observability. Heavier operationally than Go.
- **Elixir** — wins realtime outright, but realtime here is hundreds of concurrent viewers per event,
  not millions, so its strength is not the binding constraint; and it pays with a dynamically typed
  rules engine.
- **C#/.NET** — close behind Kotlin on correctness; loses on native sharing.

## Decision

**Kotlin/JVM, with Ktor and typed SQL (jOOQ), wired by explicit constructors rather than a DI
container.**

## Rationale

Two properties dominate and Kotlin is the only candidate strong in both: a **compiler-checked total
state machine** for the competitive domain, and the ability to **keep ADR-002 open**. If the shared
scoring core turns out to be the right answer, the server already speaks the language; if three
native implementations win instead, Kotlin remains an excellent rules-domain server. It is the
option-preserving choice, which matters because ADR-002 is deliberately undecided.

Typed SQL over an ORM because the competitive graph — brackets, tables, head-to-head, rating
histories — is genuinely relational and we want the compiler checking queries against the real
schema. No DI framework because agent productivity must be measured as *verifiable* output, and
explicit constructor wiring is compile-checked where a runtime proxy graph is not.

## The strongest argument against

THRØ needs a data-dense organiser back-office — nine screens built around tables, disputes, draw
management and check-in. That is a web application, and it may be the larger half of the engineering
surface. A Kotlin backend forces a second language and toolchain on a one-person team for that
surface, where TypeScript would have unified it.

**This is accepted with a mandatory mitigation, not waved away:** the organiser client's types and
API surface are generated from an OpenAPI schema emitted by the server, and the generation is gated
in CI, so the contract is machine-checked rather than hand-maintained. Secondary costs: the JVM's
memory footprint makes the cheapest hosting tier awkward, and the agent training corpus for this
framework combination is thinner than for Node — expect more correction on plumbing, though not on
domain code, where Kotlin is the strongest verified language available.

## Consequences

- Domain code is exceptionally auditable, which the brief requires of competitive logic.
- One extra language for the organiser web console, with a generated contract to hold it honest.
- Modest hosting cost increase versus a static-binary runtime.

## Revisit trigger

Organiser web work exceeds ~50% of commits for two consecutive quarters; **or** the agent-correction
rate on server plumbing is materially worse than on the mobile clients; **or** hosting cost per
instance becomes a genuine constraint.
