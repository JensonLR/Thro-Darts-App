# thro-journal — ADR-006's on-device journal, Android's half

Gate 5 has read *"on-device journal built on iOS … Android not started"* since the journal shipped.
This is the other half, and it is deliberately **the same journal** rather than a second one: the
same schema, the same append-only triggers, the same gapless per-device sequence, the same replay
through the engine, the same refusal to interpret a row a later build wrote.

```bash
gradle test          # 39 tests
python3 ../../tools/check_journal_parity.py
```

## Why a second implementation is not a second design

ADR-002 argues that the domain is one domain rendered on several platforms. For the **engine** that
claim is held by 258,516 exhaustive transitions run against both implementations. For the **journal**
it was held by nothing at all — two files, written weeks apart in two languages, whose agreement was
a matter of care.

A journal is a file, and a file outlives the process that wrote it. What has to agree is what is
written down, so `tools/check_journal_parity.py` compares exactly that on every push:

- the columns of `local_match` and `journal`, **in order**, because both readers address columns by
  index;
- both append-only triggers, verbatim once whitespace is normalised, including PD-026's narrowing of
  the delete to a single named purge;
- the stored vocabulary — the `kind` and `seat` words — which Kotlin's upper-case enum cases must
  serialise to.

If one platform wrote `retirement` and the other `RETIREMENT`, every ending would read back as a row
the other build cannot interpret. Both readers **refuse** such a row rather than guess, which is
right, and which is also why the failure would be silent, total and found by a player rather than by
a test.

## What this package does not claim

**It is not Android's SQLite — and the Android client does not use Android's SQLite either.** These
tests run on `org.xerial:sqlite-jdbc`, a JVM build; Android ships its own behind
`android.database.sqlite`, with its own version and its own defaults. The obvious reading of that
sentence, when it was written, was that an Android client would need a second implementation.

**It does not.** The `sqlite-jdbc` JAR ships Android natives, so as of 12 September 2026 (PD-082) the
Compose client runs *this* package, against *this* SQLite build: the same schema, the same
append-only triggers, the same replay, the same `DurabilityConfiguration`. Verified on an emulator,
which reported `journal_mode wal · synchronous 2` back from the phone.

Two things it took, and neither is obvious. The `.so` has to be in the **APK's own `lib/`
directory** — Android will not `dlopen` from an app's writable storage, so the driver's habit of
extracting to a temp folder fails with *dlopen failed: library "libsqlitejdbc.so" not found*; the
Android build lifts the natives out of the resolved JAR at build time, which also makes it impossible
for the driver and its native library to be different versions. And `org.sqlite.lib.path` has to be
set to `applicationInfo.nativeLibraryDir` before the first connection.

What is proved here is still the schema, the triggers, the replay and the API — the parts that are
the domain. How a device's storage behaves is not proved by a JVM, and is not proved by an emulator
either.

**No durability number is claimed.** `ThroJournal` on iOS sets four pragmas: WAL, `synchronous=FULL`,
`fullfsync` and `checkpoint_fullfsync`. The last two are Apple's `F_FULLSYNC`, which pushes data past
the drive's write cache; ADR-006 measured them on an iPhone 14 Pro Max at P95 1.64 ms against a 20 ms
budget.

**Android has no equivalent barrier, and setting the pragma there would prove nothing.** SQLite
accepts `PRAGMA fullfsync` on every platform and stores the value, so reading it back returns 1 while
nothing has happened to the hardware — a verification that always passes, which is worse than no
verification. So `DurabilityConfiguration` here asks for the two pragmas that mean something
everywhere and reads **both** back, and a test holds it to exactly those two so the shape of that
decision cannot be quietly widened into a claim.

The equivalent measurement on a real Android device is **outstanding**, in the same way OD-020's
watch measurement is. Until somebody takes it, nothing in this repository says how much of a
committed visit survives a battery being pulled on Android.

## What is here, and what an Android client still needs

Here: matches, the append path with its transaction, retraction (PD-004), attestation (PD-011),
endings (PD-016), the shelf and the one delete (PD-026), replay with per-seat leg ordinals, the
device identity the journal keeps even when the caller forgets it, and the idempotency the server
has always had — **a replay returns the stored response**, on both platforms, checked before the
ending so a retry of a visit that landed is never refused on the ground that the match has since
been retired.

Still to come, and none of it started: the club book, images, the export, and an Android UI. The
iOS client's `ThroPlay` and `ThroApp` have no counterpart, and this package deliberately says
nothing about what one should look like — the design system's Kotlin tokens exist
(`packages/design-tokens/generated/ThroTokens.kt`), and the screens are a separate question.
