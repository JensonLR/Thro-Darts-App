# The change record

This is the full account of how THRØ's foundation was built: what was decided, what was verified,
and every defect found along the way — including the ones that were mine.

**It lives here rather than in the pull request description** because that description reached
64,173 bytes of GitHub's 65,536-byte limit on 2026-09-07 and would have broken on the next round of
work. Nothing was cut in the move. A record that has to be shortened to fit somewhere is a record
that will be shortened again, and the first thing to go is always the part about what went wrong.

The pull request keeps the summary and the evidence table and links here.

## What this is

The repository was empty at the start — no branches, no commits, no prior code. The approved Claude Design system was recovered from the founder's published export and is committed under `docs/design/` with a provenance record.

The build follows a gated process where each gate is attacked by a hostile critic before it closes. **Gate 0 and Gate 1 were both rejected on first pass and corrected rather than defended** — in Gate 1's case after the defect was reproduced against a live PostgreSQL.

## Playable

`PGHOST=localhost gradle -p services/api run` starts a playtest harness — the real engine and the real command path behind a browser — and the README command was run as written. It is **not the product**: online only, no accounts, no rating, and it says so at the top of every screen. It is also the one thing in this repository that speaks HTTP.

A leg played in it shows a 3-dart average of 115.62 (501×3/13), a first nine of 153.67 (461×3/9) and a checkout of 25% (1 of 4). Leave the prompts blank and the same leg reports 12.5–33.33% as a range instead.

## The iOS client

`packages/client-ios` is four packages — `ThroDesign` (the approved components as SwiftUI, Lucide glyphs drawn from the export's own path data), `ThroJournal` (the ADR-006 journal), `ThroPlay` (setup, ready, scoring, result, with PD-001's two questions asked exactly when they apply) and `ThroApp` (Home, the tabs, Settings, the opening, and the club, league and profile screens on the Discover tab) — plus an Xcode app at `apps/ios/ThroDarts.xcodeproj` that mounts them. It scores a match between two people on one phone and keeps it there. It talks to nothing: the package graph has no network target, which is how LATENCY_BUDGETS.md's structural requirement is enforced. Every visit is committed to the journal before the screen updates. Portrait-only, as every screen in the export is drawn, and it holds the screen awake while scoring unless the player turns that off.

**It has run on the founder's phone three times, setup to result**, and each run produced findings that were fixed and confirmed on the next; the opening was watched there six further times, once per version, the seventh not yet. Founder decisions followed and are recorded in `docs/product/DECISIONS.md`: **PD-003** appearance is the player's choice; **PD-004** a mis-keyed visit is undone by a retraction, never an edit; **PD-005** a bust or won leg is announced to both players and holds the keypad; **PD-006** the mark is the app icon and the two type families are embedded under the OFL; **PD-007** the app opens on the throw; **PD-008** under double-in a visit records what counted, from the opening dart; **PD-009** a club has a public front and a private inside, announcements only, and the official keeps the fixture list; **PD-010** the club and profile screens are designed from the approved system rather than invented; **PD-011** both players confirm the result on the phone; **PD-012** local first, with the claim path designed now; **PD-013** the app shows one checkout route and says which rule picked it; **PD-014** what happens to an image somebody supplies; **PD-015** four design commissions come off the B3 list; **PD-016** a match may be retired or abandoned and the player picks; **PD-017** an export the player controls and the phone's own backup; **PD-018** a descriptive form figure that is never called a rating.

### PD-007, the opening — seventh version

One shot, **4.86 seconds**, once per cold launch, a tap skips it in a fifth of a second, still and silent under Reduce Motion.

The founder's sixth look: *"maybe half a second shorter at the end. the creation of the O with line through logo needs work as you can see breakage at the bottom right & doesnt feel very dynamic or cinematic or engaging, need a fresh idea."*

**The breakage was structural, not a tuning error.** Two chalk strokes ran out from the dart's crossings at 135° and 315° and met at 45° and 225°, and a stroke thins to a point where it leads — so the ring closed on two hairline pinches that never filled. The bottom-right one is the one they saw. Two tapered ends cannot meet in a whole ring, so no amount of overlap would have fixed it.

**The fresh idea: the ring is not drawn at all.** The strike sends a shock out through the board, and it is not round — it is stretched along the dart's own line, so it reaches the mark's radius first exactly where the dart crosses it and last square to that. Where it crosses, the chalk is **set**, at full width, on the frame it arrives. The ring lights up from the dart's line and races round both ways until two lit fronts merge. Nothing tapers anywhere, so the fronts can only overlap and 45° cannot break again — and a test holds the band at full width along its whole length, so nothing can put a taper back.

Three things came with it:

- The shock leaves the point on the frame of the thud and reaches the ring exactly as the ring's segment begins, so the 0.38 s between the hit and the mark — previously the emptiest stretch in the film — is now the shock travelling.
- It is seen as what it throws: **chalk off the board**, riding the same front that sets the ring, so the dust arriving and the chalk lighting are one event. Dust rather than a drawn wave, because a stroked ring at these radii traces the dart's own barrel and reads as an outline round it; and only outside 0.72 of the ring's radius, because closer in it reads as bristles on the dart. Both were built, rendered, looked at, and rejected.
- The ring becoming whole **lands as light** — a flare around the whole ring, gone in a sixth of a second. That is the difference between a mark appearing and a mark being made.

**The timing.** The half second comes out of the hold and nothing else — every other cut is where it was — so the tagline still has **0.87 s** of stillness, two thirds again what the fifth version gave it, which was the version the founder could not read. The ceiling in the test is the founder's number in both directions and is back under five seconds.

Built and judged first in a line-for-line browser port of the frame function, rendered at 430×932. The mark in the repository is a geometric reconstruction measured from the supplied artwork and is **untouched**.

## Double-in (PD-008), and two defects it found

The founder: *"yes want double in option as theres leagues & tournaments that are double in."*

**OD-015 is closed.** What a visit records while the player has not opened is the score **from the opening dart onward**; zero means they did not open. That is what the scorer calls at the oche, and it costs no statistic — a visit is three darts whether it opened or not, so the 3-dart average is untouched and a visit that did not open correctly drags it down. A non-zero total no opening sequence can make is refused under its own reason, because 180 is a perfectly possible visit and an impossible opening.

The table is enumerated from the dartboard, and enumeration corrected two things that looked obvious: **the bull opens**, so the largest double-in opening total is D25+T20+T20 = **170** and not 160; and **41 is openable** (D1, then 19 and 20).

Two defects found on the way, both older than the change:

- **The generated checkout table was built from a hardcoded floor of 2**, so 1 was missing from the straight-out set. A single 1 finishes a straight-out leg, so both engines would have busted a player who did. The floor is now the rule's own, carried from the spec.
- That was invisible because **the exhaustive transition table only ever covered double-out**, from a remaining of 2. It now covers all three out-rules from a remaining of 1: 86,172 → **258,516**, and they pass.

Also asserted in both engines and the spec: **opening totals and checkout totals are the same set for every rule.** A checkout is free darts then a finisher; an opening is an opener then free darts; the segment sets are the same and addition commutes. Worth holding because it fails if either table is wrong.

## Clubs, leagues and tournaments

The founder: *"want to allow leagues & clubs & tournaments to customise as well as player profiles… become a hub for them to communicate with member and arrange things."*

`packages/organisation` is the part engineering can build without inventing product. Two of it are guarantees rather than features.

**A club cannot make the app unreadable.** The text that sits *on* an accent is chosen, not configured — whichever of the brand's two neutrals reads better against it — and the accent is only used *as* text where it passes there too. That turned out to be a stronger promise than refusing bad colours: because the brand's neutrals sit **17.4:1 apart**, near the ends of the luminance range, the worst any colour can do against the better of them is **4.17:1**, above the 3:1 floor. A sweep of the colour cube proves it. The refusal stays as a guard on the *palette*, and the test asserts the headroom, so the day the neutrals move towards each other is the day a test says so rather than the day a club sees an unreadable page.

**An app shipped with no answer cannot message a child.** Announcements are broadcast, from an official or admin, to a membership, with an author on the record and no private channel anywhere. `CommunicationPolicy` starts undecided, and while it does every member whose band is `MINOR` **or `UNKNOWN`** is withheld with the reason recorded — unknown treated exactly as minor, because the thing not known is whether this is a child. **Member-to-member messaging is not built, not stubbed and not behind a flag**: it is absent, because the controls it needs would determine its data model and building the model first would prejudge them. The founder closed OD-017 the same way: **announcements only**, and messaging is not to be built until they have taken safeguarding advice.

The founder answered three of the four decisions this waited on, recorded as **PD-009**:

- **A public front, a private inside.** A club's name, badge, kind and published fixtures are public; members, results and announcements are members-only; and a member recorded as a minor is never listed to anyone but an admin. That last one is not a setting — it is the visibility filter itself, asserted in the Kotlin domain and again in the client.
- **Announcements only, for now.** Broadcast, from an official, with an author on the record.
- **The official's list.** An official schedules, moves and cancels a fixture; agreeing one happens off the app. Propose-and-accept is deferred, not refused — and `Fixture` is deliberately thin, carrying **no result**, because a result comes from a scored match and a fixture that could assert one would be a second, unverified source of truth.

**OD-019** — what happens to an image somebody uploads — came back the same week as **PD-014**, and a club can have a badge now. See *Images* below.

### Three kinds, three screens (PD-019, PD-020, PD-021)

The founder, looking at the built screens: *"screen view for club league & tournament are all the
same, this seems wrong, lazy & ugly, really think about what should be visible for each admin style."*

Right about the screens, and right about the cause. One screen had been drawn and the word at the top
changed, because **nobody had decided what the other two are**. Deciding that came first, and all
three answers were the founder's:

- **PD-019 — a league is made of teams.** Its roster is teams, its fixtures are team v team, its
  table's rows are teams. Its *members* are the people who run it, which is a different list from its
  competitors — and showing one under the other's name is precisely what made the three pages one
  page.
- **PD-020 — a result comes from two places and always says which.** A match scored in THRØ carries
  every visit and every dart. An official's word carries their word. **Both count for the table**,
  because a league that only worked when every player used THRØ is not a product, it is a demand —
  and they are never averaged, never merged, and never drawn the same way. Only the first may ever
  inform a rating.
- **PD-021 — a tournament is one of four shapes**, chosen when it is made and never after: knockout
  with byes, groups then knockout, round robin, double elimination. All four at once, deliberately: a
  shape added later is not a feature bolted on, it is a second design of the same screens.

What each admin now sees is different because what each thing *is* is different: a club leads with
its next fixture, a league with **the results nobody has entered yet** — the one thing only the
person looking at the page can fix — and a tournament with its shape and what that shape means for
the field it actually has.

**The guarantee is in the database, not in the views.** `fixture_result` carries a CHECK that refuses
a scored result with no match to point at and an official's word with nobody's name on it. A result
whose provenance cannot be shown is the one thing PD-020 says must never reach a table, so it is
unwritable rather than something every screen has to remember to ask. The read drops one anyway if it
finds one, and the store's mapping drops it a third time — the same answer three times, in the same
direction.

**The table is derived, never stored**, so a standing cannot come to disagree with the fixtures under
it, and every row carries how many of its results were evidenced. What a win is worth is the
league's, not THRØ's: stored, shown, editable, defaulted to the common 2 and 1 — and **OD-022** asks
the founder the question underneath it, which is whether a result's *unit* needs declaring before two
leagues ever sit next to each other, because a stored `3–1` with no unit on it cannot be
reinterpreted later.

**What is not built, said rather than implied:** the tournament draw. Rounds and slots against
fixtures is the next thing. The page holds the shape, the entrants, and the arithmetic — matches to
play, byes to give, who gets them and why — and says on the screen where it stops, because half a
bracket looks broken and reads as a bug.

### The screens (PD-010)

The founder: *"id want you to use the design system & /design to build the screens."*

`docs/design/DESIGN_UNSPECIFIED.md` forbids engineering from inventing screens the export does not draw. **PD-010 is the founder lifting that for one named set**, on four conditions: tokens only; approved components first; anything genuinely missing drawn in the system's own idiom and recorded in `DESIGN_INVENTORY.md` as engineering-drawn rather than exported; and the canvas as the review surface, so a design decision is taken by looking rather than by reading a diff. It does not extend to any other unspecified screen — B3 still stands for those.

Seven screens were drawn on a canvas first and then built: the clubs list, a club's public front, its members-only inside, the member list, the fixture list, the announcement composer and a player profile. They are assembled from components that already existed — `PlayerIdentity`, `Tag`, `ThroButton`, `ThroTextField`, `EmptyState`, `Eyebrow` — plus four Lucide glyphs (`lock`, `shield`, `calendar`, `search`) ported from the export's own path data, which were already in the approved icon set and simply had not been needed yet. **One new component was drawn: `Badge`**, because the system had no mark for an *organisation*. It is recorded in `DESIGN_INVENTORY.md` as engineering-drawn, and it is for organisations only — a person already has a mark in the system (`PlayerIdentity` draws it), and my first attempt invented a second one before that was caught.

### And they are reachable, reading a real store

Screens nobody can reach are not a feature. The **Discover tab is the Clubs tab**, and it reads
`ClubBook` — a second SQLite database beside the journal, holding the clubs a person starts, their
rosters and their fixture lists.

**Separate from the journal on purpose.** The journal's whole story is that nothing in it is ever
edited, and two triggers enforce it. A roster is the opposite kind of thing: a member leaves, a
fixture is postponed, a name typed wrong is fixed. Mixing them would leave the journal's guarantee
true of only *some* of its tables, which is the kind of qualification nobody remembers a year later.
Two files, two rules. It keeps the **measured durability configuration** all the same, because there
is no reason to write a captain's roster less carefully than a leg — and because the same open path
then verifies both. ADR-006 records it.

What is real here and what is not, stated rather than implied:

- **Real**: a club you start, its roster, its fixture list. Yours, on this phone, and it survives
  being closed. A fixture can be postponed, played or cancelled — and once it is played or cancelled
  it does not move again, the same rule the Kotlin domain states, kept in the client so it cannot
  offer a move the domain would refuse.
- **Not real**: joining somebody else's club, and sending an announcement. Both need a server and an
  identity. So the Clubs tab now offers **"Start a club"**, which works, instead of "Search for a
  club", which cannot — a button that cannot do what it says is worse than no button. And the
  composer's send is **refused with its reason** rather than silently doing nothing; the screen is
  still reachable because everything it says about who *would* be reached is true today, and that is
  the part an official most needs to see.

The mapping supplies `yourRole = .admin`, and that is a fact rather than a shortcut: a club in this
book is one the keeper of this phone started, and nobody else can see or change it. `Club` carries
the role as a value precisely so that the day a server says otherwise, that is the only line that
changes. When sync exists this book becomes the device's side of the reconciliation ADR-006 already
specifies — a phone and a server are the same problem as two phones.

**A member's row opens their page**, which is where the profile screen earns its place. Its figures
were dashes with reasons when this was first built, because nothing on the device was attributed to
anybody; **PD-012 changed that**, and they are now computed from that person's own matches. Where one
still cannot be supported it remains a dash with the reason — never a zero, which would read as
*they are bad at darts*.

Two things those screens do are guarantees rather than layout:

- **The composer says who it will not reach, and why**, before anything is sent — *2 members are not reached: 1 recorded as under 18, 1 whose age is not established*. An app that silently drops recipients is worse than one that refuses to send.
- **The client's authority table is the domain's.** A test asserts the Swift answers for *may announce*, *may manage fixtures* and *may manage members* match the Kotlin `Permissions` table role for role, so a screen cannot drift into offering a button the domain would refuse.

**Installing without the Mac.** `.github/workflows/testflight.yml` puts a build on the phone through TestFlight: an unsigned archive on the macOS runner, signed at export by Xcode's automatic signing with an App Store Connect API key, uploaded with the run number as the build number. It runs only when asked, never on a push, refuses without the three secrets, and **refuses a fork's head** — the job builds a checkout with the signing key on disk, so the code it builds has to be code this repository owns. `docs/runbooks/TESTFLIGHT.md` walks the founder through what to set up. **It has not been run against a real key**, so the first run is the test of it.

## Apple Watch (OD-020)

The founder: *"also interested in watch options."* There are three, and **which of them THRØ can honestly build is decided by a rule this repository already keeps** rather than by taste: every visit is committed to the journal *before* the screen updates, and if the commit fails the screen says *Not saved, so not scored*.

- **A — a glance, and nothing more.** The watch shows what the phone is scoring; no input. Keeps the rule trivially, because nothing is recorded on the wrist. Small, safe, and not what most people mean by a watch app.
- **B — scoring from the wrist.** It needs the watch's **own journal**, not a message to the phone: `WatchConnectivity` is best-effort by design, so "the watch takes the entry and the phone stores it" would show a score that is not yet saved — precisely what the rule exists to prevent. Most of the architecture is already there: the engine is Swift and dependency-free, the journal is SQLite and so is watchOS, and the two-device reconciliation this needs is **already built and tested**, because a watch and a phone are two devices with their own streams.
- **C — the watch as the corroborating second device.** The one that is uniquely THRØ's rather than a scoring app's, and the one that makes a rated match possible in a pub without two phones at the oche. Blocked twice: identity (**B4**) and the sync path, and neither is close.

**The one thing missing for B is a measurement.** ADR-006's durability figures were taken on a phone; a watch has a different chip, a different flash controller and a much tighter power budget, so `synchronous=FULL` with `fullfsync` may well cost more than the 20 ms budget there. That is measurable rather than arguable, and the answer might be **no** — in which case the honest outcome is A, and knowing it is worth the probe. `packages/durability-probe` can now target watchOS, which it could not do at all before this branch. **The run still needs a watch**, and no watch interface is designed until it has happened.

## Eight decisions, and what each one cost

The founder asked for options on everything blocking engineering, twice. Sixteen questions were put;
sixteen came back; **eight became work**.

### The result is confirmed by both players, on the one phone (PD-011)

`DESIGN_UNSPECIFIED.md` called participant attestation **the single highest-value missing item**:
PD-002 says one player's word never moves a rating, and the participant app had no way for the
second player to say anything at all. Both players stand at the same phone, so it was buildable.

Each is asked in turn, by name, so the phone gets handed to the right hand. Both agree →
`participant-confirmed`. Either refuses → `disputed`, and a refusal outranks the other's agreement,
because a result one competitor does not accept is disputed whatever the other said.

**Both are asked, not one.** The trust model lets the player who *entered* a result count as one of
its backers, so ordinarily only the opponent need confirm. On a single phone nothing records who was
keeping score, so a confirmation from whoever happened to be holding it is one person's word twice.

**What it is honest about is the point of it.** Two people at one phone is the *weakest* form of
participant-confirmed: an assertion by somebody standing there, under names typed at setup rather
than accounts, with no independent second record. Every screen that shows the label says so in
words. It is still the difference between one person's word and two, which is what PD-002 asks for.

A refusal deletes nothing. And **an agreement does not survive the result changing under it**: a
visit or an undo written afterwards makes it stale, so the label drops back rather than claiming an
agreement nobody gave to this version of the result.

### Local first, with the claim path designed now (PD-012, ADR-016)

The failure this prevents is the one nobody notices until it happens: a first cohort plays a season,
accounts arrive, and none of it can be carried over, because nothing recorded *whose* those matches
were. Free text cannot be claimed — "Jenson", "jenson" and "Jenson L" are three strings and one
player, and a claim that had to guess would either lose matches or steal them.

So the device keeps a **book of the people who play on it**, and a match records who each of its two
names referred to. ADR-016 states the rest: a claim is one person attaching all their matches at
once; the other seat stays theirs to claim; **a claimed local history is attributable and never
verified**, because a local journal lives in a file its owner can edit; and a digest at claim time
makes later tampering visible without pretending to prove what was true when the rows were written.

It is the better product today regardless — match setup offers the people it knows as a row of taps
— and it makes the **profile screen real**: a person's visits pool across every match they played
here, through the same audited honesty layer a single match's figures use.

Three refusals hold that honest. **Checkout percentage is not pooled across out-rules**, because
whether a visit began on a finish depends on the rule. **Legs are renumbered when pooled**, because
leg 1 of one match and leg 1 of another are different legs — merging them would put six visits in a
first-nine average, the same class of defect as sharing visit ordinals between competitors, already
made once here. And **nothing guesses who an old match belonged to**.

### One checkout route, and the line under it (PD-013)

Told that most finishes have several legal routes and that showing one asserts a preference rather
than a fact, the founder chose to show the conventional route always. THRØ takes a position.

**The preference is written as a rule**, in `packages/domain-spec/generate.py`, so anybody can read
what THRØ prefers and disagree with it specifically rather than with a table somebody typed. Derived,
it produces the conventional chart where people look it up: 170 = T20 T20 Bull, 160 = T20 T20 D20,
141 = T20 T19 D12, 100 = T20 D20, 90 = T18 D18, 81 = T19 D12, 60 = 20 D20, 41 = 9 D16.

**The fact is checked, three times over.** Whether a route is a legal finish of exactly that number
under exactly that match's out-rule is arithmetic, so the spec validator, the Kotlin engine and the
Swift engine each hold every route in every rule to it. 449 property checks became 2,988.

Nothing was invented: **`CheckoutCard` already draws a route** and had simply never been given one.
The engine is untouched — a route is a display, not a rule.

### Images: four answers, and a fifth nobody asked for (PD-014, closing OD-019)

The founder chose to decide the moderation questions rather than defer images. Automated screening
plus report-and-remove; **nobody under 18, or of unestablished age, has a picture at all**; deletion
stops it being served at once and the bytes go within thirty days; the uploader warrants the right
and THRØ removes on notice. Which of those shapes is *legally* available is a question for a
solicitor, and they are recorded as product intent rather than as legal conclusions.

The fifth was engineering's: **every image is decoded and written out again and carries nothing it
came with.** A phone photograph carries the place it was taken. It is done with ImageIO and an
explicitly empty property dictionary, so metadata is dropped by construction — and the test does not
describe that, it performs it: a real JPEG is built with GPS and a planted comment, put through the
intake, and the bytes are searched to prove the comment appears nowhere in the output.

**The safeguarding refusal is at the write, not the render**, so there is no image of a child in the
file to leak whatever any screen later decides to draw — and the read goes through the policy too,
so a picture already on file for somebody whose age stops saying adult is not handed over.

A club can have a badge today: picked, resized, stripped, stored on the device, drawn wherever the
initials would be, and swept off disk when nothing points at it. **Nothing has left the phone**, and
the screen says so rather than implying an image has been checked when nothing has checked it.

**Since 2026-09-07 a member can have a picture too, and all of it is reachable.** One control does
both — the same picker for a club's badge and a person's picture — and a person's mark is the circle
`PlayerIdentity` has always drawn, extracted so it can be shown at any size rather than a second
person-mark drawn beside the first. It **refuses before it offers**: where PD-014 says no picture
there is no picker, only the reason, and the reason is asked of `ImagePolicy` rather than restated,
so the screen cannot drift into offering what the book will throw on. The two refusals are different
sentences because they are different facts — an age that was never recorded can be recorded; being
under 18 is not a setting.

**A person on this phone still has none, and that is the rule rather than a gap.** The `person` table
holds a name; nowhere asks an age; an unknown age means no picture. Their page says which rule and
why. Recording an age for somebody whose name was typed at an oche is a product decision and is now
**OD-021** — engineering's reading is that the person in the photograph is the one who should be
asked, which arrives with accounts (B4).

The honest part of this entry is the last: none of the badge half worked before that date. The picker
existed inside a screen `ClubRoute` had no case for. See *Corrections to my own work*.

### A match that will not finish: two endings, and the player picks (PD-016)

Somebody leaves, the pub shuts, a player is injured. The app had no answer at all: a half-played
match sat on Home for ever.

**They are two different things and the app does not choose between them.** A retirement is a
concession — the other player wins, which is how darts has always handled a walk-off, and it counts.
An abandonment has no winner and none is invented. Collapsing them into one word would force exactly
one of two errors: inventing a winner where there was none, or throwing away a real one.

**The darts are real either way.** Every visit thrown is kept and counts towards both players'
figures. Only the *result* differs — and a person's history counts abandoned and retired matches
apart from matches played out, because "played 12" meaning "nine played out and three walked away
from" is a different claim to the one it looks like.

**An ending is final.** No more visits, no retractions, no second ending, all refused by the journal.
That departs from PD-004 on purpose: a visit is a transcription and an ending is a declaration, taken
behind a confirmation that spells out its consequence and says outright that it cannot be undone. If
an ending could be undone the match could un-end, and "the result" would be a claim that moves —
which is precisely what PD-011's attestation exists to pin down.

**An ending makes an earlier agreement stale**, by the rule a visit or a retraction already triggers:
retiring after both players confirmed a scoreline would hand the match to somebody neither of them
agreed had won it.

**An abandoned match is never labelled.** No result means nothing to confirm and nothing to dispute:
no verification badge, no attestation flow. "Self-reported" on a match nobody claimed to have won
would be attesting to a claim that was never made.

No schema change was needed — `kind` is already free text, and the guard added with PD-011 means an
older build reads these rows as `unknown` and refuses to replay rather than scoring them as visits.

One defect found on the way: **the Result screen reopened a match whenever the engine said it was
incomplete.** The engine never says a retired match is complete, so a perfectly ended match would
have bounced straight back to the keypad.

An abandonment has no seat and the column will not take a null, so `home` goes in as a placeholder.
`abandonmentIgnoresTheSeatItStores` **proves it is inert** by reading the same rows back with the
other seat and getting the same ending — a comment saying "never read" is not a guarantee.

### How far a figure can be trusted, drawn (PD-015)

`DESIGN_UNSPECIFIED` listed four things engineering could draw under PD-010's terms and the founder
released all four.

**The `Stat` variant** closes item 9. The export draws one kind of statistic — a confident number —
and the honesty layer produces three, and until now **all three were drawn identically**: `58.4`,
`58.4–61.2` and an em dash at the same weight, the same colour and the same size. The one thing the
honesty layer exists to communicate was the one thing the screen did not show. The basis now travels
from `Stat` through `StatLine` to `StatItem`, where it had been thrown away — and the guarantee is
in the type rather than the drawing: **`range` and `unavailable` take the reason as a non-optional
argument**, so it is not possible to put a dash on a screen without saying why. Colour is not
available to a screen reader, so the basis is spoken too: *"between 30% and 50%"*, *"not available"*,
never a dash read out as a dash.

**Pressed, focus and keypad haptics** close item 2 for the client. Every control was
`.buttonStyle(.plain)` — SwiftUI for *do nothing at all* — on the surface a player touches sixty
times a leg. A press now goes in by exactly the inverse of the design's own impact scale, over the
shortest duration the design defines; the scale is withdrawn under Reduce Motion and the surface
change is kept, because that setting means what it says. The focus ring is drawn *outside* the
control's border, so it never overlaps an error border and the contrast problem the item names does
not arise. Four haptics for four events, and **the two that mean *something went wrong* and
*something went right* are deliberately not the same sensation** — a bust and a won leg are what a
player needs to know while looking at the board rather than at the phone. Off is offered in Settings;
default on.

**The Dynamic Type contract** closes item 1, and it accepts a real limit rather than hiding one. The
app already scaled — every type role carries a `relativeTo:` style — but nothing stated what happens
at the accessibility sizes. Reading screens go to `.accessibility5` and scroll. **The scoring screen
stops at `.accessibility1`**, because it must fit without scrolling and holds a keypad already at the
minimum touch target. A player who needs the largest text does not get it there. The alternative on
that screen is a keypad that moves under the thumb mid-visit, and the thing that would serve them
properly is a scoring screen that *reflows* — which is a design commission, not something to invent
here. It is written down in `docs/design/DYNAMIC_TYPE.md` so it can be revisited deliberately.

### What a lost phone loses (PD-017)

PD-012 put everything on the phone, so a lost, broken or wiped phone loses every match ever played on
it — and the app did not even warn about it. The founder chose both remedies.

**The backup.** Application Support is backed up by iOS unless something excludes it, so on paper
there was nothing to do — which is exactly the situation this repository was caught by when the
durability probe measured a configuration SQLite had refused because nobody read the pragmas back.
The flag is now set explicitly and **read back**, and Settings says what was found rather than what
was asked for. A journal is the only copy of what was thrown, so Apple's guidance to exclude
*regenerable* data does not apply to it, and including it is a decision rather than the absence of
one. A future change that excluded the container is noticed here rather than on somebody's new phone.

**The export.** One JSON file: every match, every journal row as written, every person, every club.
**Every row, including the struck ones** — an export that dropped a retraction would be a tidier
record of a different match, and the whole point of an append-only journal is that the corrections
are in it. Nothing is sent anywhere; the player chooses where it goes.

A digest over the content detects a file that changed between the phone and wherever it ended up. It
**proves nothing about who wrote the rows**: this device computed it over a file this device's owner
can edit, so a forger recomputes it. ADR-016 already says a claimed local history is attributable and
never verified; this claim is no larger.

**There is deliberately no importer, and a test asserts the absence.** Merging two append-only
journals with their own gapless per-device sequences is the reconciliation ADR-006 specifies for
sync, and sync is not built; an import that pretended to do it would produce a journal whose sequence
lies about what this device wrote.

Image bytes are not in the file. It names the assets the phone holds instead, because an incomplete
export that says so is not the same thing as one that does not.

### Form, and what it is not (PD-018)

OD-001 leaves the rating model open because no model here has been validated against real matches,
which left a profile with nothing on it saying how somebody has been playing. The founder chose to
fix that without touching OD-001.

**Recent form is a description, never a rating.** A three-dart average over the most recent completed
legs, computed by the same audited `Statistics.threeDartAverage` a single match uses, through the
same honesty layer. Nothing seeds a rating from it and nothing on a profile is called one.

Four choices in it, each with a reason rather than a number picked to feel right. **The window is
legs**, not matches or days: a match runs from three legs to twenty-one, so "your last five matches"
is not a fixed amount of darts, and a player who plays monthly would have no form at all under a time
window. **Below three completed legs there is no figure**, only a note saying how many more are
needed — one leg is a performance, and a best of three is the shortest thing anybody in darts calls a
match; that floor is a stated position, not a statistical result, and it is the number to argue with.
**A leg counts only when somebody has won it**, because a leg still being thrown would move the
figure between visits of it. And **the window travels with the figure**, because "58.4" is a claim
and "58.4 over your last ten legs" is a description.

Added to the Kotlin first and ported to Swift case for case, so both implementations are held to the
same twenty-five assertions rather than the Swift drifting into a private extension of an audited
layer.

**One latent defect found by writing it.** The pooled history numbered legs **newest first**, because
`matches()` returns newest first. Nothing had noticed, because every pooled figure before this —
averages, first nine, best leg — is order-independent. The form figure takes the highest ordinals as
the recent ones, so under that numbering it would have described a player's oldest darts as their
current form. Reversed, documented, and held by a test, since nothing else would ever have caught it.

## Nothing here is a convention

Each competitive property is asserted by something that fails when it is removed.

- **Who is playing comes from the store, never the request.** ADR-008 names cross-match evidence injection as the highest-value attack. The tests mount the attack rather than describing it, and a foreign key refuses evidence for a match that does not exist.
- **A module may append only to streams it owns**, enforced by a trigger.
- **An official cannot correct or adjudicate a match they are playing in.** In darts the same people organise and play, so this is the ordinary case.
- **Evidence is never destroyed for an authorization reason.** A revoked scorer's visit is still written, flagged, and routed to review.
- **The audit chain is computed by the database**, and cannot be read by the roles that write to it.
- **One player's word never moves a rating** (PD-002), and **no unvalidated rating model can be published**.
- **A dispute suspends belief without destroying anything**, and quarantine suspends eligibility while leaving the verification label byte-identical.
- **Personal data lives in one schema**; match, trust and rating cannot read it. Age is a parameter of every authorization decision.
- **The on-device journal runs only under the configuration that was measured**, read back on open. **And it owns its device identity** — written once into the journal file, read back for ever after, so a lost `UserDefaults` cannot restart `device_seq` and make one device arrive at the server as two. Opening the journal now writes that identity back to the caller, so nothing else on the device is left holding the one the journal refused.
- **A mis-keyed visit is corrected, never edited** (PD-004).
- **A weight is a named face, not a guess**, held to the shipped binaries on every push (PD-006).
- **Nothing scores until a player opens** (PD-008). `MatchState.opened`, per player and per leg; a bust reverts the score but never the opening, because the double was thrown and it landed.
- **A rule table's floor is the rule's own**, not the constant 2 — a single 1 finishes a straight-out leg, and both engines used to bust it.
- **A club cannot make the app unreadable**, and the guarantee is a proof rather than a promise: no colour in the cube falls below the contrast floor against the better of the brand's two neutrals.
- **An announcement reaches nobody whose age is minor or unknown** until the safeguarding question is answered, enforced in the delivery calculation rather than documented.
- **An age band that cannot be read is *unknown*, never *adult*.** The permissive fallback is the one that lists a child and messages them, so the restrictive one is taken twice — once in the club book's read, once in the mapping to the screens — and a test holds each.
- **A fixture that is played or cancelled never moves again**, in the client as well as the domain, so the app cannot offer a move that would be refused.
- **Reference data does not live in the evidence journal.** A roster is edited; a journal never is. Two databases, so the journal's guarantee needs no qualification.
- **A row kind this build cannot read is refused, never scored.** It used to fall back to *visit*, so a row written by a later build would have entered the match as a nil-scoring throw and changed every statistic derived from it.
- **An agreement covers the result it was given to.** A visit or an undo written after it makes it stale, and the label drops back rather than claiming an agreement nobody gave to this version.
- **Nobody under 18, or of unestablished age, has a picture** — refused at the write, so there is no image of a child in the file to leak, and refused again at the read.
- **An image carries nothing it came with.** Decoded and written out again, always, so the place a photograph was taken is not published with it.
- **A checkout percentage is never pooled across out-rules**, because whether a visit began on a finish depends on the rule.
- **A checkout route is a legal finish of the number it is shown for**, under that match's own out-rule, checked for every route in every rule in three independent places.
- **Statistics are replayed under the match's own format**, not a fixed one — with no default parameter, because a default is how that went wrong.
- **Home never hides a match it cannot read.** A journal row that will not replay leaves the match on the list saying so, rather than vanishing.
- **No check can pass without checking.** The database suites fail rather than skip when a run declares it must have a database; both engines fail rather than skip when the exhaustive table is missing; the contrast gate treats an unresolvable pair as a breach.
- **A match ends once.** A retirement or an abandonment is final: no further visit, no retraction, no second ending. An ending that could be undone would let the match un-end, and the result would be a claim that moves.
- **An abandoned match is never labelled.** No result means nothing to confirm and nothing to dispute; a self-reported badge there would attest to a claim nobody made.
- **A dash cannot reach a screen without its reason.** `range` and `unavailable` take the explanation as a required argument, so a figure that is not a fact cannot be drawn as one by omission.
- **A form figure is never called a rating**, and nothing seeds a rating from it.
- **A person's legs are numbered oldest first.** Nothing else would have caught it, because every pooled figure before the form figure was order-independent.
- **The backup flag is read back**, like the durability pragmas — a default that nothing states and nothing checks is a default that changes.
- **There is no importer.** Merging two append-only journals is the reconciliation sync specifies, and one that pretended to do it would produce a journal whose sequence lies.
- **The README's test counts are the tests that exist**, checked in CI. They had drifted three times, each found by a person afterwards.
- **No secret is ever in the repository.** The TestFlight workflow reads its key from repository secrets, refuses without them, removes the key file in an `always()` step, and every workflow states `permissions: contents: read`.

## Capturing darts at a double

An earlier version of this branch asked for the dart count **only on a visit that won a leg**, and concluded that checkout percentage was permanently uncomputable. The founder corrected it: a player who is on a finish and *misses* has still thrown darts at a double.

That correction was load-bearing. Asking only on a successful checkout records every hit and no miss, so the figure was not merely uncomputable — it would have been **biased upward**. The trigger is now "the visit began on a checkout number", verified by enumeration to be exactly equivalent to "a double could have been thrown at during this visit". "Not sure" is recorded as unknown, never zero.

## Defects found in the approved design

Sample data and screens were checked rather than trusted, and four arithmetic impossibilities were found:

- **The organiser dispute evidence table contains dart counts no dartboard can produce.** Leg 6 implies a one-dart finish of 48; leg 9 a one-dart finish of 64. Leg 9 is the disputed leg the ruling turns on.
- **Bye arithmetic is wrong** — 74 entrants described as "Round of 64 with 10 byes"; the real bye figure is 54.
- The bust screen uses a remaining of 186, where bust is mathematically impossible.
- A Round of 64 is shown with 41 matches; it has 32.

Also: `TurnIndicator` renders fabricated mid-visit dart progress, and four scoring components default to dark while painting no background — chalk on chalk at 1.00:1, working only by CSS cascade, which does not exist on either native platform.

And one the domain exposed: `thro-recorded` describes **how** a result was captured while `participant-confirmed` describes **who attested** to it. The domain models the two axes separately (OD-014).

## Corrections to my own work

The full list is long and every entry is in the git history. The ones that mattered most:

- The first event schema **could not store the two-device corroboration case the trust model is built on**. Proved against a live Postgres, then fixed.
- **I wrote a schema assertion constructed to pass either way.** Replaced by four that each fail if the control is removed. Two authorization assertions were malformed, one of which (`assertFalse(x && false)`) could never fail.
- The upper bound on checkout percentage could report **200%**. Visit ordinals were shared across both competitors. `doublesAttempted` reported EXACT when it could only mean *recorded*.
- The durability probe's `PRAGMA` calls were never read back, so a configuration SQLite refused would have been measured as if in force.
- Every motion token had been generated as zero: the generator's scan of `:root` also matched the `:root` inside the reduced-motion block.
- **The Kotlin engine's 86,000 exhaustive transitions never ran in CI.** The table is generated, not committed, and the engine job never generated it — so "on two independent implementations" was true of one of them.
- **Nine database suites skipped silently on an empty `PGHOST`**, and nothing asserted they had run. When the guard for that was added it did not work either: Gradle test tasks do not inherit the environment and the build forwarded four variables where the tests read five. Both fixed and verified in both directions.
- **The contrast gate silently dropped eight pairs it could not resolve** — four status colours have no `-surface` token of their own — and its exceptions recorded ratios in prose that nothing checked. Three of those recorded ratios were wrong.
- **Statistics were replayed under a hardcoded 501/double-out** while the scoreboard used the match's stored format, which is the precise failure the comment above the shared format was written to prevent.
- **Home dropped any match whose journal rows would not replay.** The journal refuses to replay a corrupt row on purpose; the app answered by hiding the match.
- **Seven documents had drifted from the code** — test counts, decided decisions still listed as open, a corpus layout that was never built, a clone path that contradicted the current runbook.
- **The counts drifted again, including in this description.** The README said fifteen journal tests where there are sixteen and 132 command-path properties where there are 169; a type-face row of four stood for a package of twenty-two; and the sixteen tests that hold the opening and the app shell had no row at all. Recounted against the sources and corrected. This description claimed the app had been run on the founder's phone **eight times, setup to result** — three are evidenced; the other five were viewings of the opening, one per version. Both now say which they are, and so does the README.
- **Two of the image tests were wrong, and one predicate was — twice.** The digest test asserted that a 600 px and an 800 px photograph of the same flat colour are different assets; they re-encode to identical bytes, so they are one, and the content-addressed id saying so is the id working. And "carries metadata" first counted the TIFF block and then the EXIF block that a JPEG encoder writes for itself, which made the predicate mean "was written by an encoder" — true of every JPEG, and worthless in the direction that matters. Narrowing a predicate twice is how a test quietly stops testing anything, so the test no longer relies on it: it plants a comment in the original, proves it is in the original's bytes, and proves the string appears nowhere in the output.
- **A defaulted field made an existing assertion weaker without touching it.** `StatLine` gained a confidence for PD-015 with a default of `.exact`, and an equality assertion written months earlier silently began claiming a range was a fact. CI caught it, and the expectation now names the confidence on every line — which is what it should have done to begin with.
- **I wrote a Kotlin test with no `@Test` on it**, which is a test that never runs. Caught by reading the file back before pushing, and it is why the count checker below counts Kotlin's annotations rather than its function names.
- **The README's counts drifted twice more in this round alone**, in the very commit that was correcting them: 27 design tests where there are 29, and 56 journal tests where there are 64. Both were mine, both were guesses at arithmetic I could have run. `tools/check_test_counts.py` now counts the declarations per target, holds the README's stated number to them, and runs in CI — and it was perturbed by one to prove it fails, because a check that cannot fail is not a check.
- **I built seven screens and wired none of them to anything.** The club, league and profile screens compiled, were tested, were published on a canvas — and no code in the app constructed a single one of them; the Discover tab still said *not in this build*. A design commission that ends at the compiler is not delivered, and the round was not finished when I said the screens were built.
- **I did it again with the club editor, and this time the documents described it as though you could open it.** `EditClubScreen` — the name, the colour, the badge, and deleting a club — was written and documented, and `ClubRoute` had no case for it. Nothing constructed it, `ClubScreen.onEdit` was never passed, and `ClubScreen.badge:` was never given the club's own badge either. So on a phone: no club, league or tournament could be renamed, recoloured, badged or deleted, and its page showed initials while its badge sat in the store. `ClubStore.setAvatar` was the same shape — public, two tests, no caller — which made the founder's *"no option for profile pictures for players, clubs, leagues or tournaments yet"* right on all four counts, when I had first written it down as half right. The runbook meanwhile said *"an admin taps Edit on their club"*. **Every test was green and every one was honest**: no test in this repository constructs a screen, so the suite is shaped to miss exactly this. `tools/check_screens_reachable.py` now fails a build on a screen nothing constructs or a route case nothing assigns; it was run against the previous commit to prove it names `EditClubScreen`, and perturbed to prove the route half fires too.
- **The design inventory recorded a decision the code had already reversed.** It said the club accent *"is a hex field, not a swatch palette"* and gave the reasoning, three days after the founder asked for a better picker and I replaced it with thirteen swatches and a colour well. Both are defensible; keeping the old reasoning on the record while shipping the opposite is not. The entry now says what changed, what the original argument got wrong (a club's colour is content, like its name, not a design token), and what makes the change safe — which is the cube sweep, and is the one part that did not change.
- **The runbook's test counts were a hundred short.** It said 89 tests where there are 189, and its table said "forty-six", "thirty-six", "thirty-one" for targets holding 67, 45 and 41. `tools/check_test_counts.py` had held the README to its sources since the last time this happened and nothing held anything else, so the drift moved to the document nobody was checking. It now holds twenty-five stated counts across both documents, including the sub-counts that must sum to their totals, and it fails both when a number is wrong **and** when a sentence is reworded so its number disappears — because a check that silently stops checking looks exactly like a check that passes.
- **The journal read its match rows with `SELECT *`.** That worked for exactly as long as the table never changed — and adding `in_rule` for double-in is precisely the change that shifts a column index, so the read would have started returning the wrong field for every match already on the device. Named columns now, in one constant both reads share.
- **My first club badge invented a mark for a person** — a green-tinted circle — when the system already draws one. The canvas and the Swift were both corrected and `Badge` is organisations only. A design system you have already extracted is the first place to look, not the last.
- **The contrast refusal I wrote for club branding could never fire.** With the brand's two neutrals 17.4:1 apart, the worst any colour in the cube does against the better of them is 4.17:1, above the floor. Rather than write a test that asserts a refusal which cannot happen, the refusal is documented as a guard on the *palette* and the headroom is asserted by sweeping the cube.
- **I guessed the palette's hex values rather than reading them**, and three of the five were wrong. The test now parses the generated `ThroTokens.kt`, so a guess cannot pass again.
- Across seven versions of the opening, in order: a chalk wedge with two right-angle corners; a Reduce Motion path that still animated four effects; letters that lost the face's kerning and an R that only ever reached 87%; lit cuts drawn as blobs on the dart's body; a tracking shot that framed a point ahead of the dart so its tail was off-screen throughout; a camera roll that made the dart change angle mid-flight, which the founder called and which is withdrawn; a flight with no flight in it; and a ring whose two strokes each thinned to a point where they met, so it closed on two pinches that never filled.

