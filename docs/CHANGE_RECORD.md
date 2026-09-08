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

**The knockout draws itself** (PD-021). Rounds and slots sit on a fixture; the bracket is derived
from the entry order and whatever has been played, never stored, so it cannot come to disagree with
the results under it. Byes go to the entrants who went in first, because THRØ has no rating to seed
on (OD-001) and the page says so rather than implying a ranking put anybody anywhere — **and a bye is
not a win**: it has no fixture, and appears in no record of results. Each round is created as
fixtures once both its sides are known, so a round nobody can play yet is not conjured into one.

Ten tests hold it, and they assert identities rather than one worked example, because a plausible
bracket is the worst kind of wrong: the seed order is a permutation of the bracket whose round-one
pairs all sum to *size + 1* — which is what makes the top seed meet the bottom one — and the top two
seeds are never in the same half, for every bracket size to 256. Then a whole eight-entrant
tournament is played through and the bottom seed comes out of it.

One thing the draw has to catch that the result screen cannot: **a knockout match cannot end level.**
The result screen accepts a draw because a league fixture may legitimately be one, so the tournament
names it as a problem and advances nobody, rather than quietly producing a round with no winner.

**Double elimination and groups followed the same week, so all four shapes draw themselves.**

The losers' bracket is the part that looks right and is not, and three things about it would have been
plausibly wrong. The **drop-in is reversed**, so somebody is not put straight back against the player
who has just knocked them out. An **unplayed winners' match produces a loser who is coming**, not a
bye — collapsing those two would draw a whole losers' round as walkovers and advance the wrong people.
And **two entrants have no losers' side at all**, so the grand final's challenger is the loser of the
winners' final; a bracket built for eight gets that wrong by reaching for a round that is not there.
The property the format is *defined* by is checked by playing whole tournaments out and counting:
every entrant but the champion lost exactly twice.

Groups needed two numbers THRØ does not get to pick — how many groups, and how many go through — so it
asks, and a tournament that has not been told says so instead of showing a bracket nobody chose. The
entrants are dealt **snake-wise**, because straight dealing puts the strongest into the earliest
groups. The knockout **waits** for every group to finish, because a bracket built from a half-played
table shows people through who are not.

And the part that had to be proved rather than eyeballed: seeding that knockout from the group tables.
Ordering the qualifiers position-major is right *almost* always — and I checked instead of assuming.
It is wrong at three groups with two through, where the bracket pairs the second group's winner
against its own runner-up, and at five groups with three. So the order is repaired, and the test
asserts the strong property — **nobody is drawn against their own group in the first round** — across
all fifteen setups from two to six groups and one to three through, with a second test naming the two
cases the repair exists for.

**What a result is counted in** was the other half of this (PD-022). `3–1` on its own does not mean
anything, so a league declares legs, matches or points when it is made, and the unit travels with the
numbers — the table's note, the screen reader's "leg difference", the boxes on the result screen. It
can be changed while the league has no results and **not after**, because changing it later would
turn every number already entered into a claim about something else; the store refuses it and the
refusal says how many results are in the way. A league made before the question was asked has no
unit, nil is a real answer, and nothing invents one for it.

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

## The controls did not react, and the screens had nothing to say

The founder, from a build on their phone:

> *"Buttons need to be more reactive sometimes when i press close to them they dont react and have to
> be exactly direct on them. undo last visit shouldn't be on results page as thats when its all done.
> option to delete or achive games. home page feels very bare & basic, all screens feel bare & basic
> ... all screens & features & unveilings or reveals including intro must be incredibly beautiful,
> clean, dynamic & fluid, no clunkyness or generic slop anywhere"*

### Two defects in one sentence

*Press close to them and they don't react* and *have to be exactly direct on them* are not one
complaint, they are two, and they had the same cause. **`.buttonStyle(.plain)` was on 32 controls.**
It is SwiftUI's way of saying *do nothing at all*: no pressed appearance, and a hit area exactly the
size of the ink the label happens to draw. `ThroPressStyle`, built for PD-015 precisely so that a
control would acknowledge a touch, was on **three** — the keypad, its enter key, and the accent
swatches.

So *See all* was a target about 50 by 17 points, in an app whose own design system defines 44 as the
minimum and uses it for icons; and none of the 32 moved, dimmed or changed under a finger.

Every one of them is now a `ThroPressStyle` with a real target. Three general fixes rather than 32
local ones:

- **`ThroTextButton`** — a worded action (*See all*, *Edit*, *Announce*, *Use THRØ's*), at least 44
  by 44 with `contentShape`, and aligned so the *words* stay where they were and the target grows
  inward. That is why it needs no negative inset, which is what broke the club page's top bar twice.
- **`throRowTapTarget()`** — a whole row is the button, gaps included. Without it a finger landing
  between a badge and a name lands on nothing.
- **`ThroPressStyle(scales:)`** — a key or a chip travels under the finger, because that is the
  sensation of pressing something; **a full-width row does not**, because scaling a row shrinks it
  away from the finger touching it, which reads as flinching rather than as a press landing.

`ThroButton` itself — the primary button of the whole application, on every screen — was one of the
32.

**Nothing in the repository was going to catch this.** No test here constructs a screen, and a hit
area is not something a unit test can see. `tools/check_controls_react.py` checks the source on every
push: no `.buttonStyle(.plain)` anywhere; every `Button` carries a style; every `Button`'s label
reaches a tap target. It reads a `Button`'s full modifier chain by indentation rather than by a fixed
window of lines, because a row's label is thirty lines and a chevron's is three, and a guessed number
either misses a real defect or invents one. The system's own dialog buttons are exempt by a rule that
is itself checked: `Button("Title") { … }` — the title-and-action form — is reserved for
`.confirmationDialog` and `.alert`, and a file using it while presenting no dialog fails.

It found two live defects the moment it ran that were not in the founder's list: the back chevron on
**every** club, league, tournament and profile page had a 44-point frame with no `contentShape`, so
three quarters of it did nothing — on the very control the founder had complained about the round
before — and it had no pressed state either.

### Undo, and where it belongs (PD-025)

The result screen now has two actions and both of them finish. The founder is right that the moment a
match becomes a record is the wrong moment to offer to unpick it — and PD-004's argument for undo,
*the mis-key that ends a match is the one that most needs undoing*, is answered by the confirm step
**before** that screen, not by a third button on it.

One case keeps it and moves it. Where a result is disputed the screen already says *"Undo the visit
that is wrong and confirm again."* A screen that gives an instruction and no way to follow it is
worse than either, so the control now sits directly under that sentence.

### The shelf, and the one delete (PD-026)

*Delete or archive* is two asks and only one of them was difficult.

**Archiving** takes a match off Home and out of nothing else — journal, export, history and every
figure still have it, because it happened. It is a column, it is reversible, and it is the right
answer for almost everybody who wants a match off their screen.

**Deleting** collided with `journal_append_only_delete`, which aborted every delete unconditionally.
The temptation was to weaken it quietly. What settles it is a distinction the trigger was not making:
append-only exists so that **what a visit says cannot be changed**; it does not exist to make a person
keep a match they never wanted recorded. A journal that will not let you edit a visit is honest. A
journal that will not let you throw away a match you started by mistake is stubborn — and in the
United Kingdom it is also a person being refused erasure of their own record.

So the rule is narrowed and the narrowing is held by tests. The **update** trigger is untouched and
unconditional. The **delete** trigger now aborts unless the row belongs to the match a purge is
currently naming, a key only `deleteMatch` sets, inside its own transaction, cleared in the same
transaction — so a crash mid-purge rolls the key back with the rows. A bare `DELETE FROM journal`
still aborts. A delete of another match's rows *during* a purge still aborts. Both are asserted, as is
that a journal written before any of this has the old trigger **replaced** rather than left beside the
new one.

One delete is refused outright, and it is not about tidiness: **a league result scored in THRØ cites
its match by id**, and that citation is the whole of its provenance. Deleting the match would leave a
table resting on evidence nobody could produce. The refusal says so, counts the fixtures, and offers
the shelf.

The warning before a delete names the two players, the date, the visits, and the thing the person
cannot know from the row — *an export or a backup written before now still has it, and nothing this
app can do reaches those.* Not "this cannot be undone", which every app says and nobody reads.

### Bare and basic (PD-027)

**The Live tab said "not built", and that was nearly true and not true enough.** You cannot watch
somebody else's match on a phone with no network, and this build still says so. But *nothing live*
was never right: a match in progress on this device is the most live thing THRØ has, and a fixture
somebody played that nobody has entered a result for is the one row an official actually has to act
on. Live now shows both, across every club on the phone, from the journal and the club book, with
the honest sentence at the bottom where an absence belongs. Nothing is scheduled, predicted or
invented — including the ordering, which is the order an official typed the fixtures in, because
`Fixture.when` is a line of text somebody wrote and not a date this app can sort by. Saying that is
better than sorting text and calling it a diary.

`NotBuiltScreen` was then reachable from nothing, and `tools/check_screens_reachable.py` said so on
the next run. It is deleted rather than kept for later — which is the rule that checker exists for.


Home was a system title bar, a list of rows and a button: everything on it was reachable from it and
nothing on it was known by it. It now answers three questions before a finger moves, in the order
they matter — *is there a match I walked away from*, *what have I been throwing*, *what happened
lately*.

The masthead is the mark on the board's own dark surface rather than a large title in a system bar,
because a large title bar is what every app on the phone opens with. The match still going is the
largest object on the screen when there is one; it used to be a row among thirty finished ones,
marked by a small blue tag. The last seven days are figures from the **audited** honesty layer — the
same `Statistics` functions the result screen uses — so a new phone shows three dashes and says why.
Filling that strip with zeroes was the one thing that could not be done: a number without its sample
is a claim rather than a description.

**A defect written and caught before it shipped.** Pooling a whole device's visits under one leg
ordinal per match would have handed `bestLegInVisits` a leg containing *both* players' darts, and the
first screen of the app would have reported every 15-visit leg as a 30-visit one. Each seat of each
match gets its own block of ordinals; a test plays a five-visit leg and asserts the answer is three.

**And the first version of that masthead was invisible.** I reached for `throChalkSunken` as "the
board's own dark surface" and put `throChalk` text on it: **1.08:1**. The `thro*` tokens are the raw
brand palette and are not appearance-aware — `chalk` is the near-white and `ink` is the dark — and I
had them the wrong way round. Nothing would have caught it: the design system's contrast gate checks
token *pairs* it has been told about, and this was a pairing no pair covered.

The masthead is the **brand field** now, so Home opens on the same green the opening's first frame
is: `colorBackgroundBrand` with **`throChalk` rather than `colorTextInverse`**, because
`colorTextInverse` is *ink* in dark mode and lands at 1.99:1 on the brand surface — one of the
design's 21 recorded exceptions, and the trap the appearance-aware name walks you into. Chalk
measures 11.24:1 light and 8.75:1 dark. **The pair is now in `PAIRS_TEXT`**, so the gate covers it
on every push and the next person reaching for the token that reads like the right one is stopped by
a check rather than by a screenshot.

The general rule came out of it too: `check_tokens_exist.py` now fails on **any raw pigment painted
as a surface** in `ThroApp` or `ThroPlay`. The `thro*` tokens are the pigments the appearance-aware
tokens are mixed from and they do not flip, so a screen painted with one is right in one mode and
wrong in the other. `ThroDesign` may use them — mixing the semantics out of them is its job — and so
may the opening, which paints the launch field before any of this applies.

**And the first version of that check did not check.** It knew `.background(ThroColor.x)` and not
`.background { ThroColor.x }` — and a `Color` *is* a view in SwiftUI, so the shape the defect
actually had was the shape it could not see. Putting the defect back and watching the check pass is
the only way to find that out; it now knows both, and putting the defect back fails it.

**Inside a match, the two reveals were cuts.** A bust and a won leg — the two things PD-005 exists
to announce — put a card on the screen on one frame and took it off on the next. The scrim fades
now and the card lands on `motionEasingImpact`, which is the same physics as the strike that caused
it. So do the cards that take the keypad's place: the PD-001 question, a retraction proposal, the
end-a-match choice. **The keypad coming back does not land**, because a player waiting to throw
wants their keys, not a flourish.

Before this round the whole application contained no `withAnimation` and no `.animation` outside the
opening sequence's own timeline. That is worth writing down plainly: it was not that the motion was
wrong, it was that there was none.

And nothing arrived. `throEntrance` gives each block of a screen a 12-point rise a beat after the one
above it, from the design's own `motionTravelMedium` and `motionEasingSet` — tokens that were in the
system all along and that nothing but the opening sequence could reach as an `Animation`. That is
what *generic* looked like from the inside: an app whose motion was Apple's rather than its own. It
withdraws completely under Reduce Motion, and the stagger caps at six blocks, because the eighth
section of a long screen arriving a third of a second late is a wait rather than choreography.

## Gate 5's other half: the journal on Android

Gate 5 had read *"on-device journal built on iOS … Android not started"* since the journal shipped,
and it was the one large item on the list that was neither a design commission, a legal question,
nor blocked on hardware somebody has to hold. `packages/journal` is that half.

**It is the same journal, not a second one.** The same schema, the same two append-only triggers
including PD-026's narrowing of the delete, the same gapless per-device sequence, the same replay
through the engine, the same refusal to interpret a row a later build wrote. ADR-002 argues the
domain is one domain rendered on several platforms; a journal that agreed with the iOS one only by
convention would be the counter-example rather than the proof.

**So the agreement is checked rather than trusted.** For the *engine* that claim is held by 258,516
exhaustive transitions run against both implementations. For the journal it was held by nothing —
two files, written weeks apart in two languages. A journal is a file, and a file outlives the process
that wrote it, so what has to agree is what is written down:
`tools/check_journal_parity.py` compares the columns of `local_match` and `journal` **in order**
(both readers address columns by index), both triggers verbatim once whitespace is normalised, and
the stored row kinds — which Kotlin's upper-case enum cases must serialise to. Each of those three
dimensions was re-broken to watch the check fail on it, because the pigment check earlier in this
round had already shown that a check nobody has seen fail is a check nobody has tested.

If one platform wrote `retirement` and the other `RETIREMENT`, every ending would read back as a row
the other build cannot interpret. Both readers **refuse** such a row rather than guess — which is
right, and which is exactly why that failure would be silent, total, and found by a player.

**And two things are not claimed.** These 32 tests run on the JVM's SQLite, not Android's, so what
they prove is the schema, the triggers, the replay and the API rather than how a device's storage
behaves. More importantly, **no Android durability number is claimed at all.** ADR-006's P95 of
1.64 ms is an iPhone measurement of an Apple barrier. Android has no `F_FULLSYNC`, and SQLite will
happily accept `PRAGMA fullfsync` on any platform and read it back as 1 while nothing has happened
to the hardware — a verification that always passes, which is worse than no verification. So the
Android configuration asks for the two pragmas that mean something everywhere, reads both back, and
a test holds it to exactly those two so the shape of that decision cannot be quietly widened into a
claim. The measurement on a real Android device is outstanding, in the same way OD-020's watch
measurement is.

### And the kill test now runs on a build server

ADR-011 requires a kill test and a power-cut test on every release candidate, and says in terms that
**an unowned manual test is a test that runs once.** The kill test was automated — and needed a
phone, a Mac, a cable and a person, so on a push nothing checked it at all.

The Kotlin journal made a second one possible with no hardware. A JVM is forked, writes visits
through the journal's own transaction discipline until it has acknowledged forty, and is sent
**SIGKILL** — `destroyForcibly`, not a polite stop, and a *process* rather than a thread, because a
thread cannot be killed and stopping one politely tests the happy path. The acknowledgement is
printed and flushed only after the commit returns, so an acknowledgement is a claim that the row is
on disk, which is the claim under test. What survives is then adjudicated by `Kill.verdict`, ported
from `KillProbe.verdict` so both platforms are judged by the same rule: one-directional, because a
kill discards a buffered acknowledgement for a write that did land, so the journal may hold **more**
than was acknowledged, never less, and never a hole.

A run by hand while writing it: 207 acknowledgements, 414 visits, SIGKILL, `integrity_check` ok, 414
rows, no holes. Nothing acknowledged was lost, and what survived reopened under the configuration
and replayed through the engine — because a file that passes an integrity check and cannot be read
by the app is not a pass either.

**It is not a durability test and must never be quoted as one.** The kernel, the filesystem and the
drive all keep running through a `SIGKILL`; a journal that only ever reached the OS page cache
passes this and would still lose data to a pulled battery. That is the fourth row of the runbook's
table, and the whole reason ADR-011 asks for two tests. The power-cut test still needs hands.

### Two more guards, and one measurement that stops short on purpose

**An icon-only control is now required to have a name.** A `Button` whose label draws a glyph and
nothing else is silent to VoiceOver — a screen reader announces "button" and stops, because a
chevron is not a word. `check_controls_react.py` gained that as its fourth rule. It found nothing:
every icon-only control in the client is named. That is the right outcome for a check written after
a near miss rather than after a defect, and it is only worth having because it was made to fail
first — the first version passed on a button whose label had been emptied, because it counted
`.buttonStyle(ThroPressStyle(...))` as "the label draws something". It reads the label alone now.

**And the disabled appearance was measured rather than fixed.** `DESIGN_UNSPECIFIED` item 15 said a
flat opacity multiplier "produces real contrast failures" and had said it since the audit. It is a
design commission, and PD-015 released four of those and not this one — so engineering may not
answer it. What engineering can do is turn the assertion into numbers: `ThroButton`'s 0.38 takes a
primary label from 11.24:1 to **2.10:1** and a secondary button's border from 1.70:1 to **1.21:1**,
which has effectively gone; the keypad's 0.4 takes a key from 18.81:1 to 2.66:1.

**It is not a WCAG failure** and the entry says so, because the difference matters to whoever
decides: 1.4.3 exempts text in an inactive component. What the numbers show is that a player can see
a disabled button is there and cannot comfortably read what it says. Which treatment replaces the
multiplier is the founder's call; the item now carries the evidence for making it.

## Set play was implemented in two engines and checked by nobody

`CONFORMANCE_CORPUS.md` listed three families as not built and said of one of them that *"set
structure is implemented and exercised by `match-completion`"*.

It was implemented and exercised by **nothing**. No committed vector carried a set structure at all.
`Effect.SET_WON` was mapped in both conformance runners and produced by no case. `Alternation.PER_SET`
was parsed by both and reached by none. The Swift runner even carried a comment explaining that sets
were deliberately not parsed *because the Kotlin runner does not parse them either and the corpus
carries no set structure today* — a correct description of a hole, sitting in the file that would
have closed it.

Sets are not an edge case. Every televised match and a great many league formats are played in them.
A whole competition format was carried by the type system, and the document that was supposed to say
so said the opposite.

**`sets-and-legs.jsonl` is that family**: four cases, each isolating one thing a set format does that
a leg format does not — a set taken while the match continues (`set_won`, not `match_won`); a set
*lost* and the counter reading one each; `perSet` alternation, where the set's opener opens every leg
inside it, which is exactly where the two alternation rules diverge and where a wrong implementation
is wrong silently because the scores still add up; and a match that ends on the **sets** unit rather
than the legs one. Both conformance runners gained the branch together, because a runner that read a
key its counterpart ignored would make the two platforms disagree about a vector neither engine got
wrong.

**The expectations are derived, not asserted.** `generate.py`'s simulator was extended from the rule
written out first — a set is won by taking its legs, the match by taking its sets, a new set counts
from nothing and numbers its legs from 1, the right to open a set alternates — and the Kotlin engine,
written weeks earlier, agrees with all four cases.

**And building it found a second hole, in the validator.** `validate.py` re-derives every case from
`classify` alone and knew only about legs, so a `set_won` looked like an ordinary visit: it never
reset the scores at a set boundary, and the next leg's first visit came out a bust. A new family
found a gap in the checking rather than in an engine, which is what a new family is for. 2,988
property checks became 3,064; 64 vectors became 68.

**One mistake of mine on the way, worth keeping.** The first draft of the family named both the
opener and the winner of each leg by hand. Naming the opener let a case claim a leg was opened by the
player whose turn it was not — and the whole rest of that case desynchronised into rejections and
busts while still producing a plausible-looking vector full of numbers. The builder derives the
opener from the rule now and only the winner is named.

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
- **The back button was off the edge of the phone, on four screens, and I had "fixed" it twice.** The founder sent a screenshot: no back button on a club, and *"Announce"* cut in half by the right edge. The first version put a −12 inset on the whole row, which pushed every trailing item toward the right edge. The correction moved that inset onto the chevron — the right principle, *a negative inset belongs to the thing it is insetting* — and missed the thing that actually mattered: **the row had no gutter to inset from at all.** So the chevron went to x = −12, off the screen, and the last action sat flush against the other edge. `TopBar` and `MatchHeader` never had the bug, and the reason is the whole lesson: they are components that apply `spaceScreenGutter` themselves, so their negative inset has something to be negative of. Four screens hand-rolled the row instead. There is now one `PageBar`, and `tools/check_screen_bars.py` fails a build on a `BackChevron` built anywhere else or a negative horizontal inset outside the design system — run against the shipped code to prove it names both halves. **Two rounds of tests, a design review and a canvas did not catch this; one screenshot did.** That is the argument for getting builds onto a phone sooner, not for writing more tests.
- **The runbook's test counts were a hundred short.** It said 89 tests where there are 189, and its table said "forty-six", "thirty-six", "thirty-one" for targets holding 67, 45 and 41. `tools/check_test_counts.py` had held the README to its sources since the last time this happened and nothing held anything else, so the drift moved to the document nobody was checking. It now holds twenty-five stated counts across both documents, including the sub-counts that must sum to their totals, and it fails both when a number is wrong **and** when a sentence is reworded so its number disappears — because a check that silently stops checking looks exactly like a check that passes.
- **The journal read its match rows with `SELECT *`.** That worked for exactly as long as the table never changed — and adding `in_rule` for double-in is precisely the change that shifts a column index, so the read would have started returning the wrong field for every match already on the device. Named columns now, in one constant both reads share.
- **My first club badge invented a mark for a person** — a green-tinted circle — when the system already draws one. The canvas and the Swift were both corrected and `Badge` is organisations only. A design system you have already extracted is the first place to look, not the last.
- **The contrast refusal I wrote for club branding could never fire.** With the brand's two neutrals 17.4:1 apart, the worst any colour in the cube does against the better of them is 4.17:1, above the floor. Rather than write a test that asserts a refusal which cannot happen, the refusal is documented as a guard on the *palette* and the headroom is asserted by sweeping the cube.
- **I guessed the palette's hex values rather than reading them**, and three of the five were wrong. The test now parses the generated `ThroTokens.kt`, so a guess cannot pass again.
- Across seven versions of the opening, in order: a chalk wedge with two right-angle corners; a Reduce Motion path that still animated four effects; letters that lost the face's kerning and an R that only ever reached 87%; lit cuts drawn as blobs on the dart's body; a tracking shot that framed a point ahead of the dart so its tail was off-screen throughout; a camera roll that made the dart change angle mid-flight, which the founder called and which is withdrawn; a flight with no flight in it; and a ring whose two strokes each thinned to a point where they met, so it closed on two pinches that never filled.
- **The journal told the player a visit was lost when it was saved.** ADR-006 requires the command to be durable before it is acknowledged, and the server has answered a repeated command id with the stored response since the command path shipped. Neither on-device journal did: `command_id` is `UNIQUE`, so a retry hit the constraint, rolled the transaction back and surfaced as *"Not saved, so not recorded"* — for a row that was already on disk. A player who believes that enters the visit again. Both journals now answer a replay with the stored row, **before** the ending is checked so a retry is not refused because the match has since been retired, and refuse a command id offered for a *different* command rather than swallowing it. Writing the tests found a second defect underneath: the entry a write **returned** carried the caller's sub-millisecond precision while the row on disk carried milliseconds, so the value handed to the caller was not the value in the file — invisible until something compared the two, which a replay does and sync will. No caller passes a command id yet, so nothing a player can see changed today; the point is that ADR-006's reconciliation cannot be built on a journal that answers a replay with an error.
- **Three sentences in the runbook were false, and all three said a shipped feature was absent.** *"7 Attestation | Not in the app… **Every result is self-reported**"* three weeks after PD-011 put both players' confirmation on the result screen; *"25 Haptics | None"* after PD-015 shipped four sensations — thirty lines below the same runbook describing them; and *"the checkout card shows the number and no route, because no route table exists in this repository"* after PD-013 built a table per out-rule that the conformance corpus holds to be a legal finish of exactly that number under exactly that rule. A stale code comment in `ThroDesign/Scoring.swift` repeated the last one. **A claim of absence is the dangerous kind**: it decays in the direction of a lie, because the code gains a capability and the sentence does not notice, while a claim of presence at least fails loudly when the thing is removed. `tools/check_absence_claims.py` now registers four load-bearing absences — no network code in the client, no rating ever passed to a `PlayerRef`, no write in the export reader, no authentication API before B4 designs one — each paired with the sentence that states it and a search that must find nothing, so a reworded sentence fails as well as a broken claim. It was perturbed five ways before being kept, and the corrections say the row *was* wrong rather than quietly making it right.
- **A share card, a wall screen and a widget each reach a place the honesty layer cannot.** Everywhere else a figure THRØ shows stands beside the words that qualify it — a bounded one marked as a range, a dash with its reason printed under it — on a screen that is still there to look at again. An image carries nothing but what was drawn into it, cannot be corrected once it is in somebody's group chat, and outlives the app that drew it; a board on a pub wall is read across a room by people who cannot see that it has stopped moving; a Home Screen widget is refreshed by the system rather than by the app and looks exactly as current when it is hours behind. So each of them carries what it would otherwise have left behind: the share card states **how the result is verified** in a sentence a stranger can weigh — including *disputed*, which is marked rather than quietly dropped — carries **its own sample** in visits and legs, and shows a figure only when it is known for **both** players, because a dash on one side of an image reads as a zero to somebody with no way to ask why. The wall is **cleared** when a match ends rather than left on the final leg. The widget says when it was written, on a fifteen-minute window rather than the Lock Screen's two and a half, because two surfaces with different refresh mechanics need different windows and giving them the same number would make one of them wrong.
- **The founder's original complaint reached a control the check written for it was not reading.** *"Buttons need to be more reactive"* produced `check_controls_react.py`, which looked at `Button` and not at `ShareLink` — and the export's share control was a bare `Text`: no pressed state, and a hit area the size of the ink. It looks at both now, and the fix was to extract `ThroButtonFace` from `ThroButton` so a control SwiftUI insists on constructing itself still wears the design's button. The accepted-target vocabulary gained a name, and the name is not taken on trust: the check reads the component and fails if it loses its `contentShape` or its minimum height. That needed bounding to the struct — unbounded, a later component's `contentShape` satisfied it and removing the face's own kept the check green, which is a check that had stopped checking.
- **Two guards now state opposite rules about the same tokens, and the exemption between them earns itself.** A screen must not paint a raw pigment as a surface, because a pigment does not flip with the appearance and is therefore right in one mode and wrong in the other. A share card must paint nothing else, because it is a raster that leaves the phone and two people in one group chat posting cards that did not match would have no way to tell a theme from a defect. Rather than a silent bypass, `check_tokens_exist` exempts the card **only while `check_share_card_tokens` is actually looking at it**, and says so in a sentence if that stops being true — proved by removing the file from the other check's list and by deleting the check.
- **The scoring screen said less to a listener than to a reader, in four places.** Being on a finish was carried by **colour alone**: a sighted player watches the hero turn brand green, a VoiceOver player was told a number and left to work out that 141 is checkable. `2–1` was read off its string, and an en dash between two numerals is not a word — spoken it is "2 1", the same sound as twenty-one, with no statement of who is ahead, on the one figure that says whether the match is nearly over. A **range** was read the same way, which is exactly the collapse into two loose numbers that the statistics layer exists to prevent, happening in a channel nobody looks at. And the keypad announced nothing at all: three taps and no confirmation of what was about to be committed, on the one screen where a mis-key becomes evidence. There is deliberately **no Python check** for any of it — the obvious one, that every case of a state enum appears in the function that speaks it, is what the compiler already does, and writing it would be duplicating the type checker and calling the duplicate rigour. What the compiler cannot see is a new state handled by speaking what an old one speaks, so the state enums are `CaseIterable` and four tests walk `allCases` holding that no two of them sound alike.
- **The backup flag was read from a cache rather than from the file system.** CI went red on one run and green on another over the same commit, which is what a memoised value looks like from outside; it was not a flake. `URL` caches resource values on the value itself, and `BackupPolicy.include` set the flag through a local copy and read it back through the caller's — a different value holding what the flag used to be. So Settings could tell a player *"your matches are NOT included in this phone's backup"* about a folder that was. The whole reason the flag is read rather than assumed is that a wrong answer is invisible until somebody sets up a new phone; **reading a stale cache is assuming with extra steps**.
- **The widgets' own file did not read back as itself.** A `Date` carries sub-millisecond precision and the ISO-8601 string it is written in does not, so a projection built from `Date()` came back as a different instant — the same defect, in the same shape, as the journal's returned-row timestamp two rounds earlier. Harmless while nothing compares the two, and that is exactly what made the journal's version reach a player as *"Not saved, so not recorded"* for a visit that was saved. Caught here by the round-trip test rather than by a phone.
- **A no-figures check cried wolf on the first real field it saw.** It searched for banned substrings and tripped on `liveFormat`, which contains "form" and is a match format. A check that produces a false alarm is a check people learn to edit rather than read, which is worse than not having one; it names the whole key set now, at both levels, which is stronger as well as quieter — a field added tomorrow fails it until somebody says out loud what it is.
- **Two approved components promise a server that does not exist, and neither is deleted.** `SyncState` — *"Synced · This match is saved to THRØ"* — and `OfflineState` are drawn nowhere, which makes them a trap rather than a defect: the obvious move when sync is built is to reach for `SyncState`, and that ships copy claiming a server confirmed a result before any server has. The design system is the founder's, so the components stay and a registered absence claim holds that no screen constructs either.
- **Nine surfaces shipped, and the founder could not find them: *"not sure I can see or test majority of this on the latest iphone build."*** They were right, and it is a defect in the work rather than in their looking. Every one of the nine is invisible until a condition is met that nothing tells you about — the Lock Screen scoreboard needs a match in progress **and** a locked phone, the widgets need an App Group and then a widget added by hand, the wall needs an HDMI cable or Screen Mirroring which no app may turn on for you, the share card needs a *finished* match, a fixture reminder needs a club fixture with a date more than two hours off, performance reports are off by default and arrive at most once a day, and universal links need a domain nobody has bought. **A feature nobody can find has not been delivered**, and the answer to that is not a longer release note. Settings now opens on *What you can see on this phone*: twelve rows, each carrying the surface's real state read from the device — Live Activities authorisation, whether the App Group resolves and when it was last written, whether an external-display scene is attached, notification and calendar authorisation, what is actually pending, whether Spotlight is indexing, how many reports are held, whether the brand faces registered — and a sentence saying either where to look or what is stopping it. **Nothing on it is a demonstration**: no sample match, no example fixture, no mock scoreboard, because an app whose whole argument is that it does not invent results cannot invent one to show a feature working. The states are five rather than two, because "you cannot see it" has five causes and only one is a fault; and the permission states are three rather than two, because **not yet asked is not a refusal** — a boolean there would send a player to iPhone Settings to turn on something nothing has asked them for. The runbook gained an ordered thirteen-row plan for the same reason, and the two things that are honestly not there — the domain and the watch complication — are rows on the screen rather than omissions from it.
- **The readiness screen's first version told the founder the wrong thing about the share card**, which is the one failure that screen exists to stop. It counted a *shareable* match as one that finished **with a result**, excluding an abandoned one on the reasoning that a match nobody won has no scoreline to print. That is true of the scoreline and false of the card: `MatchResultScreen` puts **Share the result** behind `session.isComplete` and nothing else, and `ThroShareCard` draws an abandoned match deliberately — no score, and the sentence *"Nothing is claimed about who won. The darts thrown are recorded; the match counts for nobody."* So the row would have said *finish a match first* to somebody looking at a match with a share button under it, and the runbook's new test plan said an abandoned match "gets no card". Caught by reading the result screen to check that the row's own instruction — *open one from Home and tap Share the result* — was true, which it is. The count is now a named function beside the sentences it feeds, with the reasoning that got it wrong written above it, and a test builds all five kinds of match on a real journal and holds the rule.
- **The screen that tells you where to look is the one screen a rename elsewhere can falsify in silence.** Every other screen in this app shows what it has; the readiness screen says *tap **Share the result** under the score* and *__Remind me__ is under an upcoming fixture* — sentences about controls drawn in other files, which no test in this repository constructs. Rename one and the screen goes on confidently sending somebody to a button that is gone, with everything green. `tools/check_readiness_directions.py` holds it in both directions: every control the copy names must exist as a literal in the file that draws it, and every other emphasised span must be accounted for in an emphasis list with a reason — so a new direction fails until somebody says which kind it is, and an excuse whose words have left the screen fails too, which stops that list becoming a record of what the screen used to say. It reads only string literals, never the doc comments, and joins literals a `+` split mid-sentence, because a bolded span broken across two lines is one span to a reader. Perturbed five ways before it was kept: a renamed control, a direction to a control that never existed, a dropped direction, a stale excuse, and the check made to stop looking.
- **A screen that only says where to look still leaves the walk to you**, and three of its twelve rows named the same five-screen detour: Discover, a club, Fixtures, a fixture with a date on it. So eight rows now carry the route as well as the words — *Start a match*, *Open a club*, *Open Home*, or this app's own page in iPhone Settings, the only page iOS lets any app open. They go through **the same router a universal link goes through**, so a row cannot reach a screen a link could not, and the sheet closes itself before the route is taken rather than leaving the destination behind two screens nobody asked to still be there. The other four rows carry no button, and that is the decision rather than an omission: no app may attach a display or start Screen Mirroring, the App Group is fixed in Xcode or in signing, and a domain is bought rather than tapped — a button there would have to apologise. Two invariants are held by tests: the button and the sentence must agree in **both** directions about iPhone Settings, so no row offers a page its words never mention or names a page it will not open; and a **not yet asked** permission is sent to the control that asks, never to iPhone Settings, where there is no switch to find until something has requested it. The row's accessibility element became `.contain` rather than `.combine` at the same time — `.combine` folds a control into the text around it, which would have left a VoiceOver user a row they could hear and could not operate.
- **Club TV mode could not have worked, and nothing would ever have said so.** iOS hands an app an external display as a *scene*, and it creates that scene only when the app's `UIApplicationSceneManifest` declares the `…ExternalDisplayNonInteractive` role **and** sets `UIApplicationSupportsMultipleScenes` to true. This build declared the role and set the flag to **NO**, with a comment reasoning that "the phone still has one window, and only the external role is added" — which describes what the player sees rather than what the key means, and the key means *may two scenes be connected at once*. A board on a wall while the keypad is in somebody's hand is exactly two. The consequence is invisible from every angle this repository can see: `application(_:configurationForConnecting:)` is simply never called, the cable mirrors the phone, and there is no error, no log and no failing test — the Swift is correct and unreachable, which is why fifty lines of reviewed, documented, CI-green scene code would have produced a large copy of the scoring screen on a pub wall. Found by writing the readiness screen's wall row and asking what would have to be true for *"plug in a cable"* to be honest advice. The key is corrected; the row now reads the manifest **on the running phone** and says **Blocked** rather than *Ready* when the build cannot be given a screen, so the founder is never left plugging things in to see whether it was a build problem; and `tools/check_scene_manifest.py` holds both keys and the named delegate class on every push, perturbed four ways before it was kept — one of the four being the exact state this build shipped in.
- **The readiness screen inferred the Lock Screen scoreboard from a match being open, and those are different things.** The Live Activity lasts exactly as long as the scoring screen — leaving that screen ends it, deliberately, because a scoreboard for a match nobody is currently throwing in is a scoreboard that lies. So the row read *Working — lock the phone* to somebody who had backed out to Home, and locking the phone would have shown them nothing. It asks ActivityKit's own list now (`Activity<ThroMatchActivityAttributes>.activities`, the system's answer rather than this process's handle, so an activity that outlived the app's last launch counts), and a match that is open with no scoreboard reads **Ready** with the route back into it and the sentence saying why. The same correction went into the runbook's test plan, which said "with that match open" where it needed to say "stay on the scoring screen".
- **A type face that does not register does not raise**, and the same is true of two more property-list keys. iOS falls back to the system face, every screen still draws, and the app looks like every other app — the founder's *"no generic slop anywhere"* arriving as a build problem rather than a design one. There are three ways in and the app can notice only the first: a listed file that is not in the target (which `ThroFont.customFacesRegistered` reports at runtime); a file in the target that `UIAppFonts` does not list, which ships unregistered so only that **weight** goes missing and reads as a design choice; and a file whose **PostScript name** is not the one the Swift asks for, where the family registers and the weight silently resolves to something else. `tools/check_bundle_faces.py` reads the PostScript name out of each `.ttf`'s own `name` table — the name `UIFont(name:)` actually matches — and holds the ten of them against `ThroFont.embeddedFaces` in both directions, plus `NSSupportsLiveActivities` (whose absence takes the whole Lock Screen scoreboard away in silence), the calendar usage description, and the two OFL licence texts that have to travel with the families. Perturbed five ways before it was kept, the sharpest being Archivo-Medium.ttf replaced by Archivo-Bold's bytes under its own filename: every list, every plist entry and every test still agrees, and the app just gets bolder.
- **The backup flag was still intermittent after the fix that was supposed to end it**, and I reported CI green while it was red. Two things went wrong. The defect: `BackupPolicy.include` built its write on `var target = url` — a copy of whatever URL the caller had already read or written through, carrying that URL's memoised resource values — while `read` built its own value from the path. CI caught the write through the cached copy not being visible to a read one line later, on the same directory, when the identical write through an uncached URL always was. Two functions answering the same question about the same file now reach it the same way and neither inherits a cache from anybody. The process failure is worth as much as the defect: I checked the **push**-event workflow runs, saw six greens, and told the founder CI was green — while the **pull_request**-event runs of the same jobs had been failing since the first commit of the tranche. A check that is green in the list you happened to look at is not a green build, and the PR's own check runs are the list that decides. The assertion also failed with `("excluded") is not equal to ("included")` and nothing else, which cost a round; it now makes three assertions naming three different stories — the write never landed, the write landed and `include`'s read missed it, or two reads of the same path disagree — so the next failure, if there is one, says which.
- **Five rounds on one flag, ended by asking the file instead of the framework.** `isExcludedFromBackup` is not a property of a `URL` — it is the presence or absence of the extended attribute `com.apple.metadata:com_apple_backup_excludeItem` on the file — and every round of this defect came from treating it as one. `URL` memoises resource values on the value itself, so the first version answered with what a URL had last been told rather than with what is on disk, and Settings told a player their matches were **not** in this phone's backup about a folder that was. Three further attempts each removed one participant carrying a cache and each left the test intermittent: the same commit went green on one CI run and red on the next, and in one red run `include`'s own read said *included* while two independent reads of the same path, a line later, said *excluded*. Whatever the last of those was — a cache below Foundation, or Time Machine's path-based exclusions being consulted for a folder under `/var/folders` on the macOS test host — it stopped being worth another round, because none of it exists underneath the attribute itself. `read` is now `getxattr` and `include` is `removexattr`: absence **is** inclusion, so there is no value to write and no format to get wrong, no cache on a URL, nothing in Foundation and no daemon between the question and the answer — and on iOS this is the same mechanism the backup itself uses. The cost is stated rather than hidden: on macOS this no longer reflects Time Machine's path exclusions, which is the right trade for a type describing the iOS device backup of an iOS-only app and is exactly why the macOS answer is now deterministic. The test still writes the flag through Foundation's own writer, so the two mechanisms are cross-checked rather than either being trusted alone.
- **A page told somebody to go and look for something, which is the founder's whole complaint in one sentence.** A groups tournament with no shape yet showed a note ending *"Set them on Edit"* — naming a place and carrying no way there. It now offers the control under the sentence, and the wording became load-bearing in three directions rather than one: an admin is told to set it below and given the button; somebody without the right is told **who** can, rather than sent to a screen that would refuse them; and once any result exists neither is offered the change at all, because `setupIsStillOpen` closes at the first result and a button there would look like it worked and do nothing. The sentence is a static function so the three can be told apart in a test, which matters here more than usual: no test in this repository constructs a screen, so a note that rots is invisible to the whole suite. Found by asking of an existing screen the question the readiness work made routine — *what would have to be true for this instruction to be honest?*
- **Two more screens named what was missing and left the player to find it.** Asking every `EmptyState` in the app the question that had just found the groups-setup gap turned up two more of the same shape. *Fixtures* told an official **Add one** while the only control was the `+` glyph in the top bar — an empty screen whose whole purpose is one action, and the action was a 20pt icon; it has the button every other empty state in this app already had. *Add a fixture* between two teams was worse: with fewer than two entered it said **Add them first** and offered nothing but Back, so somebody who came to make a fixture was told what was missing and had to go and find the list on their own. It routes there now, for an admin — and for anybody else the sentence changes to name who keeps the list, because this screen is reached from a control only an admin has, so telling somebody else to add them is sending them looking for something they will be refused. Both sentences are static functions with tests, for the reason the last one was: no test here constructs a screen, so screen copy is exactly what rots unnoticed.
- **The backup flag, measured at last: `URL.setResourceValues` silently skips a write its cache thinks is redundant.** Five rounds of theory ended with one line of evidence — *"round 19: set→included, on disk: no such attribute"*. The failing step was never `BackupPolicy` at all; it was the **fixture**, which set the flag through a `URL` that had been written through eighteen times. A `URL` caches the resource values it has seen and the cache does not notice the file changing underneath it, so asking it to set the value it already believes is in force skips the write and reports success. Every version of this defect was one write silently not happening, and the intermittency was only ever whether the cache happened to match. The production code was already right by then — `getxattr` to read, `removexattr` to write, no cache and no daemon in between — and the remaining red was a test lying to itself; its fixture now writes to the file with `setxattr`, because a fixture that sometimes does not take is a test that sometimes tests nothing. Two lessons worth more than the fix: a red build that cannot say **which layer** failed will cost a round every time, and the four rounds spent here bought nothing until an assertion finally quoted the file system instead of the framework.
- **A screen that answers a question on a phone has answered it to one person.** The readiness screen tells the founder which of thirteen surfaces this build can show and why the rest cannot — and then the answer stops there, because thirteen rows of state are exactly what somebody who can fix a build needs and exactly what nobody transcribes. *Send this* turns the whole screen into plain text with the build stamp and the phone's model identifier (the raw one: a table of marketing names goes stale every September, and the identifier is what a report can be looked up from). A `ShareLink` rather than a copy button, because the phone already has every way of sending it. A test holds that every row and its state reach the text, that the build does, and that **no match, no name and no score can** — a diagnostic that does not say what it carries is one nobody should send, so the last line of it says.
- **The launch screen's green is a hand-copied duplicate of a brand token, and nothing held the two together.** iOS paints `UILaunchScreen`'s colour before a line of the app has run; the opening then paints `ThroColor.throGreen`. They match today at `#0F3D2E` — and if the brand green ever moves, the property list keeps the old one and the app opens with a flash of the wrong colour for about a third of a second, at the exact moment seven versions of the opening exist to get right. Nothing could have caught it: not a compile error, not a test (none draws a launch screen), and not a screenshot, because the flash is over before anything is captured. `tools/check_launch_colour.py` reads the colour out of the asset catalogue — in hex or in floats, since Xcode writes both — and compares it to the token's own generated value. Perturbed five ways; the fourth is the one worth recording, because **the first version of the check could not fail**: it looked for the token anywhere in `LaunchSequence.swift` and passed with the background changed to something else entirely, since the same green appears three more times inside the dart. It anchors on the `.background(` now.
- **A build whose App Group does not survive signing installs, launches and behaves perfectly.** Its widgets read an empty container and draw nothing, and nothing anywhere raises: the entitlement is held in the source on every push by `tools/check_app_group.py`, so the code is right and the loss would be in signing. The app now says so on its readiness screen — but only after the founder has installed it and gone looking. The TestFlight workflow says it first: after the upload it reads `codesign -d --entitlements` from the signed app and its extension and writes *present in ThroDarts.app*, or a line naming what it is missing from, into the run summary. It reports and never gates — everything except the widgets works without the group, so refusing an otherwise good build would be the wrong trade — and when the export uploads directly and leaves nothing to look inside, it says that rather than implying a pass.
- **Four screens became one tap, on the only row in the app that exists because somebody owes something.** The Live tab gathers every fixture across every club that has been *played* and had no result entered — the one thing a league keeper has to act on, and the reason that section leads with a warning tag. Tapping one opened the **list of clubs**, from which the way to the control is the club, its fixtures, the fixture, and then Record. It opens the result screen now. That makes the landing rule load-bearing rather than incidental: `ClubRoute.result` shows a *gone* state unless the club is still there, the viewer may record results, and the fixture is between two teams — so a request that names a fixture is checked against every one of those before a route is chosen, and anything short of all of them lands on the club's own page, which is a worse answer than the control and a far better one than an empty state. A club that has been deleted since the request was made leaves the screen where it is, because a request that no longer means anything is not a reason to move somebody. The rule is a static function with a test for the reason the last three were: no test in this repository constructs a screen, so a route that quietly started landing on *gone* would look exactly like one that works.
- **And the other half of that screen, plus the lesson from the first half applied to itself.** The Live tab's *still to play* rows went to the list of clubs too; they go to their club's **fixture list** now, which is where a player's own controls live — the reminder, the calendar entry, the search for the venue — putting three of the surfaces the founder could least easily find two taps from the Live tab. Doing it exposed the shape of the thing I had just written: `ClubLanding` carried an optional fixture id and *meant* "a fixture is the result screen, no fixture is the club", which is a rule you have to already know to read a call site, and which had nowhere to say "this club's fixture list". It carries a named `Wanted` now — `.club`, `.fixtures`, `.result(fixture:)` — and the same nil-means-something smell I criticised in a permission boolean earlier in the day is gone from my own code, one commit after I wrote it.
- **A premise I had written three times was not true of the app.** The share card's argument opened *"everywhere else, a figure THRØ shows is one a player can tap for its basis"* — in the source, in the README and in this record. `StatGrid` does not put the basis behind a tap: it **prints** it, under the figure, where the eye already is. The conclusion the premise was serving is untouched and if anything stronger — an image carries nothing but what was drawn into it — but a document that describes the app wrongly is the defect this repository has been caught by more than once, and it decays in the direction of a lie whichever way the code moves. Corrected in all three.
- **A sixth registered absence: the `associated-domains` entitlement.** Three documents and one screen say it is deliberately not there, and the reason it is load-bearing is sharper than most: `applinks:thro.app` for a domain nobody owns makes iOS fetch an association file that does not exist, after which the app **silently stops handling links at all** — including the `thro://` ones that work today. Adding it early is strictly worse than not adding it, and it is exactly the line somebody pastes in while wiring something else. The proof looks in both entitlements plists **and** the Xcode project, because a capability can be declared in either and a claim that checks one of them is a claim about one of them; `Claim` gained a tuple of globs for that. Two perturbations, one per file. Registering it also caught a third thing on the first run: the pattern anchoring the screen's own sentence matched nothing, because the sentence is split by the source's line limit — and a pattern that matches nothing is a claim that has quietly stopped being checked, which this guard already treats as a failure. It found its own registration bug.
- **Both widgets sent every tap to the same place, in three states that are not the same thing.** `widgetURL` was `thro://continue` on the board and on the Lock Screen accessory, whatever they were drawing. On a live scoreboard that is right. On the one reading *Tuesday · Feathers v Bell · 8pm* it opened the Play tab with nothing on it — no crash, no error, no failing test, and nothing whatever to do with the fixture somebody had just tapped; a destination that ignores what is drawn above it is a link to somebody else's content. Each state now goes to the screen that holds what it is showing: the match being scored, the Live tab that lists every fixture this phone's clubs have not finished with, or — on a phone with neither, and on one whose file has never been written — the one action that is real. A fixture already past is not drawn, so it is not linked to either. The test is the whole loop: the URL the widget would carry, parsed by the app's own parser. Either half alone would have passed while the two disagreed, which is exactly how a widget comes to open the wrong screen with every test green.
- **Presence is not exclusion, and assuming it was cost one more round on the same flag.** After the attribute became the source of truth, `read` said *excluded* whenever the attribute was there. That is right for the pre-Foundation form — a single byte, 1 — and wrong for Foundation's: `URL.setResourceValues(isExcludedFromBackup: false)` does not remove the attribute, it writes an explicit **false** into it. So a folder somebody had just *included* through the framework read back as excluded. It was caught on the one assertion in the file that writes the flag off through Foundation and reads it back through `BackupPolicy` — exactly the cross-check that was kept when the rest of the fixture moved to the file system, and the reason for keeping it. The contents decide now, in both forms, with the property list tried first: a `false` plist is mostly non-zero bytes, so the byte rule would call it excluded, which is the same mistake one layer down. And the two findings are not rivals — Foundation skips a write its cache thinks is redundant **and** writes an explicit false rather than removing; each explains a different red run, and neither would have been found by reasoning about the other.
- **And the last red on that flag was the host, proved rather than asserted.** Rounds 18 and 19 of twenty failed with `set→included ... on disk: no such attribute` **after `setxattr` returned success** — the fixture's own write, gone a millisecond later. `com.apple.metadata:` is the Spotlight daemon's namespace, and an attribute written there on a folder under `/var/folders` is not the test's to keep. Saying so is exactly the excuse this session has refused all day, so it is not asserted: the loop no longer needs the fixture to hold. It asserts the contract that is true from **either** starting state — after `include`, included — and counts the rounds that did start from an exclusion, failing if none of twenty did, so a fixture that stopped working altogether still fails rather than quietly turning the loop into twenty no-ops. Nothing about `BackupPolicy` is asserted less; what changed is that the test stopped depending on something outside it.

## SLATE, step one: the keypad had no keys

The founder, after using the build: *"I have been using the app & still think the UI is generic &
like every other app… we want utterly beautiful, reactive & engaging UI & UX across all screens."*

Twelve agents worked four directions and chose **SLATE**: THRØ is a slate that is being written on,
and everything the app knows is chalk on it — what is certain is written firmly, what is uncertain
is written faintly with the reason beside it, and what was superseded is struck through at 45° and
left where it is. The app never erases because the journal never erases: a retraction is an `INSERT`
carrying `corrects_seq` (`Journal.swift:725`), and the screen will now say the same thing the record
does. It was the only one of the four whose distinctiveness comes from THRØ's own data rather than
from a metaphor laid over it.

This is step one of eight, and it is deliberately the smallest: one component, no screen file
touched, no motion, no layout change. What it found is why it goes first.

### Three measured defects, none of which would fail a test

**The keys had no edges.** Every key on the scoring keypad drew a 1 pt `colorBorderDefault` outline.
Measured against the surface underneath it: **1.37:1 in light, 1.26:1 in dark**. WCAG 1.4.11 asks
3:1 of a control's boundary. The contrast gate already carried those two ratios as recorded
exceptions reading *"decorative rule"* — which is an accurate description of a boundary nobody can
see. A player looking at the scoring screen was not seeing keys; they were seeing digits with gaps
between them, and every "the buttons feel generic" reading starts there. `colorMarkOnBoard` measures
**5.30:1** on a key face and 4.12:1 at the very centre of the lamp, with no exception recorded.

**The press was never visible.** `key()` built its face inside the label —
`.background(RoundedRectangle().fill(...))`, opaque, full frame — and then asked
`ThroPressStyle(pressedFill:)` for a pressed colour. `ThroPressStyle` draws that colour with
`.background`, which is *behind* the label. The pressed fill was drawn underneath an opaque surface
and **has never been visible on any build**. The only acknowledgement a key has ever given is a 2%
scale and the haptic — on the one surface a player touches sixty times a leg, and the exact
complaint that opened this line of work: *"sometimes when i press close to them they dont react."*
It could not be fixed from the call site: `isPressed` exists inside a `ButtonStyle` and nowhere else,
so `ChalkKeyStyle` owns the face, the boundary and the press together.

**The Enter key's resting label measured 2.20:1.** The whole control was drawn at `opacity(0.4)`
when nothing had been typed. Fading a control composites its label towards its background, and
contrast is a ratio between the two — so the fade moves both numbers at once and legibility
collapses faster than brightness does. Composited: **2.20:1 in light, 2.92:1 in dark**, on the one
control in this app that commits evidence. WCAG 2.1 exempts inactive components from the contrast
minimum entirely, which is precisely why the contrast gate never saw it.

The same arithmetic still applies to `ThroButtonFace`, which fades at 0.38: every disabled button in
the app measures between **1.91:1 and 3.48:1**. That is recorded as a dated exception rather than
fixed here — the paper side gets `colorBackgroundRecessed` when SLATE reaches it, and changing every
button in the app is not a thing to smuggle into a change scoped to the keypad.

**And the six most-used keys were the smallest ones.** The quick totals took
`touchTargetMinimum` (44) while the digits beside them took `touchTargetScoring` (64). They are one
size now, and that size is the style's default, so a new key inherits it.

### What was built

`ThroDesign/Geometry.swift` — `Easing` and `MarkGeometry` moved out of `ThroApp/LaunchSequence.swift`
byte for byte. Both were already `public` and depend on nothing but SwiftUI. The opening's thirteen
tests hold with no change to a single assertion; the whole cost of the move is one `import` in the
test file.

`ThroDesign/Chalk.swift` — three terminations and no others. `ChalkRule` is a filled band sampled
every 4 pt whose half-width is modulated by `MarkGeometry.chalkEdge`, the same function that
roughens the mark's own ring, and deterministic in its seed so it never crawls between frames.
`ChalkBox` is four of those with square corners, because nothing on a board is rounded.
`ChalkStrike` is the founder's mark's own bar, pointed at both ends at 45°, at 1.35× a figure's
width and 0.085 of its cap.

Six new tokens, all `color*`, all flipping, **and both values dark green** — a board is a board in
either appearance, so the rule that `color*` flips and `thro*` does not survives intact and nothing
has to paint a pigment to draw a board. Eighteen new contrast pairs: every board ink against every
board ground in both traits, because the board is one gradient and a figure can land anywhere in it.
No new failures and no new exceptions.

### Two corrections to the specification

- **`ChalkBox` is a `Shape`, not an `InsettableShape`.** `InsettableShape` exists so `.strokeBorder`
  can inset a stroke by half its width. A chalk rule is not a stroke — it is a filled band whose own
  edges carry the roughness — and stroking a rough outline would double the roughness and halve the
  weight. It is filled, so it is a `Shape`, and the type says so.
- **`Grain` and `Speck` did not move.** The specification said the four geometry types were "already
  `public`". `Grain` is `internal` and `Speck` is nested inside `LaunchFrame`; moving them would
  have been an access change dressed as a move. They are wanted by `ChalkField`, which is the
  board's background, and they move with it as a change that says what it is.

### And one number of my own to correct

The specification put the resting Enter key at 1.41:1. Recomposited from the tokens it actually
draws with, it is **2.20:1 in light and 2.92:1 in dark**. Both are far below the 4.5:1 floor and the
defect is the same defect; the figure quoted above is the one I measured, not the one I was handed.

### Two guards, each perturbed until it failed

`tools/check_no_dimming.py` — an `.opacity()` whose argument mentions availability is a breach.
Perturbed twice: putting the old Enter fade back fails it, and "fixing" `ThroButtonFace` so its
recorded exception matches nothing also fails it, because a stale exception is a hole with a date on
it. This is a design law and not a WCAG gate, and it says so: WCAG's exemption for inactive
components is exactly why the contrast gate is allowed to look away from the state this rule is
about.

`tools/check_controls_react.py` — `TARGET` accepted `ThroButtonFace` by name and proved it by reading
the component. It now holds a table, so `ChalkKeyStyle` is accepted on the same terms and by the same
proof. Perturbed three ways: strip its `contentShape` and it fails, rename the struct and it fails,
and take the name out of `TARGET` while keeping the proof and it fails *that* way too — a proof that
guards nothing is worth reporting.

## SLATE, step two: the number the product exists to move

`RemainingScore` drew a player's remaining score as one `Text` with `.minimumScaleFactor(0.5)` on
it. Three consequences, every one visible on a phone and none caught by anything:

- **It migrated sideways as it came down.** `501` and `41` are different widths in any face, so a
  centred figure walked left and right across the screen through a leg. The number a player glances
  at between darts was never twice in the same place.
- **It changed size as it came down.** `minimumScaleFactor` is what a figure does when nobody chose
  a size for it. Three digits shrank to fit and two did not, so the hero was *smaller* at 501 than
  at 41 — backwards from what a player needs.
- **Every digit re-rendered on every change.** With one `Text` there is no such thing as "the digit
  that changed", so nothing could land, and the app's most important moment was a swap.

`ThroFigure` is a fixed-cell register: `cells` cells of `0.540 × resolvedSize`, right-aligned, one
`Text` per cell, and the empty leading cells **empty** — never a leading zero, because `041` states
a digit the player does not have, and never a ghost, because a ghost is an opacity.

### The bust state was attributing the restored score to nobody

`RemainingScore` in `.bust` discarded the caller's label and drew `"Bust — score restored"` with no
player in it, while the pill below it named the other player. `spokenLabel` kept the name the whole
time — `"Ann requires. Bust — score restored"` — so **what a sighted player saw and what a VoiceOver
player heard did not agree**, on the one event in a leg where a player needs to know whose darts did
not count. Both come from the state now, and a test walks every state holding that the drawn eyebrow
contains the caller's label.

### Colour stopped carrying state

`RemainingScore` put the bust on `colorStatusError` and the finish on `colorTextBrand`: the two most
important moments in a leg on the two colours a red-green deficiency cannot separate. And
`colorStatusError` is `#8C1D18`, which measures **1.52:1** on a board and is unusable there. The
state is a shape under the figure now — `ThroBasis`, six forms, each with its own spoken string —
and the ink does not move. *No text changes contrast because of a state.*

The bust maps to `.struck`, which is the honest name: the journal did not colour that score red, it
superseded it.

### Three corrections to the specification

- **`boardHero` is not 88 pt.** 88 is not on the approved type scale, so it would have been exactly
  the off-scale bypass the design's own gate rejects in every platform source. And the arithmetic
  does not work either: at 0.540 em per cell, two three-digit registers at 88 pt need 285 pt, and an
  iPhone SE has 264 pt between its gutters. `boardHero` sits on the scale and a **density ladder**
  `[96, 72, 56, 40]` chooses the rung — every rung on the approved scale, held by a test, so a
  ladder cannot become a licence to invent a size.
- **`capRatio` is a function, not a dictionary.** SLATE gave it as `[Family: CGFloat]`, which needs a
  fallback at every lookup, and a fallback is how a new family silently takes somebody else's cap
  height and every figure drawn in it sits a point off its own baseline on a screen nobody
  re-measured. It is an exhaustive `switch`; `ThroFont.Family` gained `CaseIterable` so a test walks
  every one.
- **`ThroTypeRole.sized(_:)`, not `.size(_:)`.** A stored property and a method with one name is
  legal Swift and a trap for the next reader.

### And the inversion

When a figure cannot be computed, `StatGrid` drew the em dash at full strength and the reason in the
quiet grey — saying that the missing figure was the point and the explanation was a footnote. It is
the other way round: **when there is no number, the reason is the content.** The two colours swap,
both are on the contrast matrix, and a test holds that no confidence draws its figure and its reason
in the same ink, because then neither leads.

`Tag` gains `shape: .basis` — the word between two end-stop ticks, no fill, no capsule. `Range`,
`Not rated`, `Cannot be read` and `No result` are qualifications, and a filled pill makes a
qualification look like another category to skim past. Every existing `Tag("…")` literal is
untouched, so every test written against them stays green.

22 tests. All 17 `tools/check_*.py` green.

## The screen decides its own shape, so it can be turned on its side

The founder, relaying a player in a local league: *"Just make what's needed big — that's the main
hiccup u see"*, and *"People try use different or they're own tablets most of the time."* Then:
*"I feel we should also have a landscape view for mobile too. As well as taking tablets into
consideration."*

What the build actually does today:

```
TARGETED_DEVICE_FAMILY = 1
INFOPLIST_KEY_UISupportedInterfaceOrientations_iPhone = UIInterfaceOrientationPortrait
```

iPhone only, portrait only, and **no iPad orientation key at all** — so on an iPad THRØ runs in the
scaled-phone compatibility window. PD-005 made the scoring screen fit without scrolling by choosing
one screen and locking the app to it, which is a decision the app cannot re-examine at runtime.

**Flipping those two switches first would ship a worse app**, not a better one: a portrait layout
squeezed into 390 points of height has a keypad that does not fit and a hero the size of a caption.
So the shape comes first and the switches follow it.

### The shape is arithmetic

`ThroStage.choose(width:height:onAFinish:textScale:)` is a pure function returning the arrangement,
the hero's rung, the opponent's rung, the ledger's state and the key height. Because it is a
function and not a view, it can be held to the claim that matters:

> On every device THRØ runs on, in every orientation, at every text size, on a finish and not, the
> scoring screen fits without scrolling and every key is still big enough to hit.

The test walks eleven iOS 18 devices — an iPhone SE up to a 13-inch iPad Pro — both ways up, at four
text scales, with and without a checkout row. **352 screens**, each checked for four things: the
rail plus head plus ledger plus tray fits the safe area; the two three-digit registers do not
overlap; every key clears 44 points and the tray fits its height; and the hero is a rung of the
approved ladder.

A screen wider than 1.2× its height puts the keys **beside** the board — which is the shape a
scoreboard has always had, and the shape you get when a phone is propped up at the oche. A tablet
held upright stays stacked, because a tall screen has room for the board above the keys.

### One hole the first version had

`keyHeight` is clamped at 44 so it can never report a key nobody could hit. That clamp means a
screen too short for six 44 pt rows **overflows silently** — and `keysAreHittable`, which only read
the height, called that fine. A 4-inch phone on its side gives 299 points for a tray that needs 314.

`keysFit(in:)` asks both questions. The test that proves it uses that same 568 × 299 screen, which
does not run iOS 18 and is not in the device list — it is there because it is the shape where the
two questions give different answers.

### And a nicety with teeth

`ThroStage.Ledger.none` became `.hidden`. `.none` on an enum collides with `Optional.none` wherever
the context is optional, and the compiler resolves it without saying which one it picked.

13 tests. The device-family and orientation switches stay as they are until the board and the
scoring screen are built on this; flipping them is the last commit of that work, not the first.

## The board, and a claim of mine that CI knocked down

`ThroBoard` is one `RadialGradient` between three named tokens — `colorBoardLit` at the centre,
`colorBoardField` at 0.55, `colorBoardSunken` at the edge — and `ChalkField` is 180 specks quantised
into at most five `Path` fills in one static `Canvas`. There is no veil layer and no alpha over a
solid, because **the alpha is what the board law exists to keep out**: nothing drawn on a board may
be lighter than `colorBoardLit` or darker than `colorBoardSunken`, and that is what makes the
contrast matrix a description of what renders rather than of an assumed midpoint.

The specks are drawn in `colorBoardLit` and never white. A speck brighter than the lamp's own centre
would be a pixel the matrix does not cover, sitting under text the matrix says is legible.

`Grain` moved out of the opening and became `public` — an access change, which is exactly why it did
not travel with `Easing` and `MarkGeometry` in the move that claimed all four were already public.
`Speck` did **not** move: it is `LaunchFrame`'s own scatter, distributed through the wall's
perspective and tier-batched for the opening's foreground, while `ChalkField` distributes over a flat
rectangle for a background. Moving it would have shared a name, not a thing.

### CI found one test failure, and it was my arithmetic

`testACapBoxIsShorterThanTheLineBoxItReplaces` demanded that the cap box return more than 20 points
against the role's line height, and it returns **19**. The comparison was the wrong one:
`boardHero`'s token line height is 88, which is a line-spacing instruction, not the height a figure
takes up. Against the em box a `Text` actually occupies — 96 — the cap box of 69 returns **27 points
per figure**, and that is what funds the ledger.

Which also settles SLATE's figure: it put the saving at **55.8 points**. That is not a number these
ratios produce. It is 27. The code comment and the test both say 27 now, and the test says why the
first version asked the wrong question.

Everything else compiled and passed on the first attempt: 465 tests, one failure, and the failure
was a claim rather than a defect.

11 tests.
