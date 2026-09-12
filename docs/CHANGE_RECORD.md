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

## The scoring screen becomes a board, and turns on its side

The founder, relaying a player in a local league: *"Just make what's needed big — that's the main
hiccup u see"*, *"People try use different or they're own tablets most of the time"*, and *"We need
cool pop up notifications/banners on screen when scores are entered to confirm them."*

### What the screen was doing

- The thrower's remaining at 96 pt; **the opponent's remaining at 13 pt**, inside a row of chrome,
  truncated with an ellipsis. It is the second-most-asked question in darts and it was the smallest
  text on the screen.
- **No running column of visit totals at all.** Every paper scoresheet has had one for a century,
  and it is the only way a player catches a mis-key without replaying the leg in their head.
- A committed visit produced a haptic and a changed number and **nothing else**, so a player who
  half-saw the screen had to work backwards from the remainder to check their own entry.
- `TurnIndicator` drew three dart pips from a **hardcoded `dartsThrown: 0`**, so they were
  permanently empty and VoiceOver permanently said *"0 of 3 darts thrown"*.

### What it does now

`ThroBoard` fills the phone — one radial gradient between three named tokens, with chalk dust on it.
`ThroBoardHead` puts both players' three-digit registers side by side on one baseline, at the rung
`ThroStage` chose from the room actually available. The opponent goes from 13 pt to one rung below
the thrower. `ThroLedger` draws the leg beneath them in the three declared states the stage picks
from measured height — rows, a tally strip, or nothing, never a clipped list.

Whose throw it is is carried **three ways and none of them colour**: the `calledOut` double rule
under that column, the 45° `ChalkStrike` marker beside the name, and the name's own ink.

`ThroChalkMark` is the confirmation. On a board a score is chalked, not toasted: the total lands
under the head where a scorer's hand would be, holds for 1.1 seconds, and goes. Three kinds, because
the three things that can happen to an entry — it scores, it busts, it is refused — already have
three distinct haptics and now have three distinct sights. The haptic comes off the mark itself, so
what is felt and what is seen cannot drift apart.

### `TurnIndicator` is deleted rather than fixed

SLATE called the hardcoded `0` a wiring defect. It is not: **the engine scores a visit, not a dart**
(`ThroEngine/Types.swift:26`), so there is no count to wire. Three pips that can never fill are
furniture that states something untrue. They come back the day per-dart entry gives them something
true to show.

### PD-005 and PD-024 are superseded, and the switches are flipped

Both existed because the screen had **one layout** and had to survive every text size inside it:
PD-005 locked the app to an upright phone, PD-024 capped the text at `.accessibility1` and scrolled
above it. `ThroStage` reads the room and the text scale together and returns a shape that fits, so
there is nothing to cap and nothing to scroll — a player at the largest accessibility size gets a
smaller rung and a shorter ledger, not a scroll bar under their scoring thumb. The keypad keeps its
own pin, which was always a separate promise.

```
TARGETED_DEVICE_FAMILY                        1  →  "1,2"
UISupportedInterfaceOrientations_iPhone   portrait  →  portrait + both landscapes
UISupportedInterfaceOrientations_iPad     (absent)  →  all four
```

`StageTests` now walks **every** Dynamic Type size rather than a sample of four, because the screen
no longer caps its text and that promise is only worth something if the top of the range is walked.

### The guard, and the hole my first version of it had

`tools/check_orientation_is_earned.py` holds the project file and the layout together. Perturbed
four ways.

The third perturbation is why it exists twice. I deleted landscape from the iPhone key — the exact
silent regression the founder's request is about — and **the check passed**, because it only asked
whether each orientation *named* had a layout behind it, and the iPad key still named landscape. So
it now declares what THRØ has decided to offer, per key, and a missing orientation fails with the
sentence *"That is a whole orientation a player loses, and no test would notice."*

Also perturbed: iPad offered with no iPad in `StageTests`; the screen no longer calling
`ThroStage.choose`; and iPad dropped from `TARGETED_DEVICE_FAMILY`. All four fail.

## A retraction stops being a disappearance

This is SLATE's thesis, and until now it was the one part of it the app contradicted.

PD-004 made a retraction an **`INSERT` carrying `corrects_seq`** rather than a delete, precisely so
the record keeps what was written — `Journal.swift` has said so since the day it shipped, and
`testTheExportCarriesEveryRowAsWrittenIncludingTheStruckOnes` has held it. But every screen read
`replayVisits`, which excludes struck rows by design, so on the phone **an undo made a visit
vanish**. The journal and the board did not agree about what had happened.

`Journal.ledger(_:)` is a new read beside `replayVisits`, never a change to it. It returns every
scoring row in order, struck ones included, and:

- **A struck visit does not advance the match.** It was taken back, so whatever came next was thrown
  against the state before it. Its remainder is what stood on the board *at the moment it was
  written*, reproduced by applying it and then not keeping the result.
- **A struck row and the visit that replaced it share their place in the running order.** They are
  the same turn; numbering the replacement fresh would make the leg read one visit longer than it
  was thrown.
- **A struck row the engine can no longer apply keeps its place with a dash**, not a zero. A zero
  there is a score nobody threw.
- Every row carries the journal's own `deviceSeq` as its identity, because two rows sharing one
  would have SwiftUI animate a retraction as a number changing — the exact disappearance being
  fixed.

### The one test that makes it safe

Every figure in this app stands on `replayVisits`, and a struck visit must never reach one — that is
what `testTheStatisticsNeverSeeAStruckVisit` has protected since retraction shipped. So the first of
the nine new tests holds that **the ledger's standing rows are exactly the replayed visits**,
remainder for remainder, in order. If those ever part company, a figure and the board are reading
two different matches, and the figure is the one people are judged on.

`LedgerEntry` is deliberately not `ReplayedVisit`. A replayed visit is evidence and every one of
them counts; a ledger entry is what a scorer's hand put on the board and some of them were taken
back. One type for both would be an invitation to feed a struck visit to a statistic.

`check_journal_parity.py` still passes unchanged: no stored column, trigger or row kind moved.

9 tests. All 18 `tools/check_*.py` green.

## Per-dart entry: the vocabulary, and what it is actually worth

The founder, relaying a player in a local league: the app should take each of the three darts as
well as the total of three.

**The engine is not changing.** `ThroEngine/Types.swift:26` says it in as many words — *the engine
scores a visit, not a dart* — PD-008 settled the double-in rule on that basis, and ADR-002 keeps the
Swift and Kotlin engines structurally parallel against exactly this kind of drift. So the three
darts are captured as **evidence attached to the visit**: their sum *is* the visit total, the
`recordVisit` command is byte-identical, and every existing figure and replay is untouched.

### What it buys beyond the asking

- **Two modal questions disappear from every checkout.** PD-001 stops the player and asks *"Darts
  used to check out?"* and *"Darts thrown at a double?"*, because the app has no way to know.
  `dartsUsed` and `dartsAtDouble` are therefore **nil on every visit** unless a player is
  interrupted at the most pressured moment in a leg and asked to remember. A player who entered
  their darts has already answered both, with what they did.
- **A mis-key cannot reach the board.** Every entry's total is, by construction, a total three darts
  can make.
- **The engine's impossible-total table stops being unheld.** `RuleTables.impossibleVisitTotals` is
  a literal `[163, 166, 169, 172, 173, 175, 176, 178, 179]` — the correct set, and the single
  most-missed validation in X01 implementations. `ThroDartEntry.reachableTotals` derives the same
  fact from the 63 things a dart can do, and a test holds the two against each other. A table nobody
  re-derives is one that can rot without anything noticing.

### Where the line is drawn

`ThroDart` and `ThroDartEntry` live in `ThroDesign` and hold **no darts rules** — the keypad has to
know what a dart is to draw one, and `ThroDesign` must not depend on the engine, exactly as
`StatItem.Confidence` restates a basis without depending on the statistics package. `DartVisit` in
`ThroPlay` is where the two meet, in the one layer that may know both.

**The definition of "at a double", and its limit, stated rather than assumed.** The ring a dart
landed in does not tell you what it was aimed at: a player on 32 who throws a single 16 and then a
double 8 threw two darts at a double and landed one. So a dart counts when it was *thrown from a
checkable number* — the definition a scorer uses, observable from the entry, and read off the
match's own out rule rather than assuming double-out.

### Three assertions of mine that were wrong, and how

I wrote the darts facts in these tests from memory. All three were wrong:

| I asserted | It is | Why |
|---|---|---|
| 141 → 81 → 24 has one dart at a double | **three** | 170 is the largest checkout; 141, 81 and 24 are all finishes |
| 180 → 120 → 60 has one | **two** | 120 is a checkout (`T20, 20, D20`) |
| 51 is a master-out finish only | **both** | `51 = 19, D16` under double-out |

Every darts assertion in `DartVisitTests` is now computed from the engine's own tables before being
written down, and the out-rule test uses **159** — a master-out finish and a double-out bogey — with
a companion assertion that fails if 159 ever stops being one, so the test cannot quietly start
measuring nothing.

27 tests. All 18 `tools/check_*.py` green. The keypad's dart mode and the storage of the individual
darts are the next two slices; this one is the vocabulary and the evidence, and it is complete and
held on its own.

---

# The keypad that takes three darts

*"Option to enter per dart (for 3 darts) or total score of 3 darts."* — the founder, relaying a
player in a local league: *"Just make what's needed big that's the main hiccup u see."*

The previous entry built the vocabulary and the evidence layer. This one puts it in a player's
hands: a second keypad, the darts drawn on the board as they land, and the two PD-001 prompts
skipped when the darts have already answered them.

## The correction that came first

**`dartsAtDouble` was counting the wrong thing, and PD-001 says so in its own worked example.**

The definition I shipped in the previous entry was *a dart thrown from a checkable number*. PD-001's
decision text says:

> finishing 100 as T20 then D20 is two darts with **one** at a double

Under the definition I had written, that visit has **two**: 100 is a checkout and so is 40. Under the
definition PD-001 is actually describing — *a dart thrown from a score one dart could finish* — it
has one, which is also the answer the player gives when the app stops and asks them.

The consequence was not a crash. `Statistics.checkoutPercentage` divides leg wins by the sum of this
column, so an inflated count makes every player's checkout percentage look worse, silently, forever;
and a match scored partly by hand and partly from darts would have carried two different definitions
in one column. A 141 finish would have been recorded as three attempts rather than one.

| | old, wrong | now |
|---|---|---|
| 141 `T20 T19 D12` | 3 | **1** |
| 100 `T20 D20` | 2 | **1** — PD-001's own example |
| 32 `S16 S8 D4` | 3 | 3 |
| 40 `D20` | 1 | 1 |

`DartVisit.oneDartFinishes` is derived from the engine's route table — a route of length one **is** a
one-dart finish — rather than transcribed, and a test holds it against
`RuleTables.oneDartFinishesDouble`, the literal the engine has carried unused since it shipped. That
literal now has a job.

**This also corrects the previous entry's table of my own wrong assertions.** The first row of it —
*"141 → 81 → 24 has three darts at a double"* — was wrong for a second time, in the other direction.
It has one. The row is left standing above rather than edited, because the record of what I got
wrong is worth more than a tidy one.

## Three rules the engine already enforces, met from this side

`Engine.recordVisit` refuses evidence it cannot believe. Per-dart entry has to produce evidence that
survives, because a refusal a player cannot act on is a dead end:

- **Only a leg-winning visit may record fewer than three darts.** A bust, by the engine's
  convention, consumed the whole hand whatever the player had thrown when it happened. So a bust
  after one dart records `dartsUsed: nil` — one is the observed count, three is the convention, and
  nil is the only one of the three the record can stand behind.
- **`dartsAtDouble` may not exceed `dartsUsed`**, clamped.
- **`dartsAtDouble` may not be claimed from a remaining no three darts can finish.** The walk cannot
  produce that — a one-dart finish is at most 60, and two darts take at most 120 off, so nothing
  above 180 can reach one — and `testAOneDartFinishIsUnreachableFromAnythingThreeDartsCannotFinish`
  walks every out rule, every start and every one- and two-dart run to prove the floor is never
  load-bearing.

And `MatchSession.dartsMayBeEntered` keeps Enter out of the light until the hand is spent or the
visit has settled, so a two-dart entry that neither finishes nor busts is never offered to an engine
that would refuse it. The Enter key says *"One more dart"* rather than sitting unlit and unexplained.

## Six rows, because a ninth would cost the board its number

The obvious dart keypad is nine rows: a ring row, five rows of sectors, a bull row and Enter. On the
iPhone SE upright there are 647 points of safe area. A nine-row tray is 644 of them.

```
  9 rows: tray 644, board  63  ->  rungs of the hero ladder that fit: NONE
  6 rows: tray 434, board 161  ->  rungs that fit: 96, 72, 56, 40
```

So the tray is six rows, exactly like the visit tray, and the design came out of the arithmetic
rather than surviving it:

```
  1     SINGLE · DOUBLE · TREBLE        the ring, held
  2–5   the twenty sectors, five a row, in the board's own order
  6     25 · BULL · MISS · ENTER
```

- **The sectors are in the board's order, not 1-to-20.** A player looks for 20 where it is, between
  1 and 5. A keypad in counting order is one you have to read rather than find.
- **MISS sits between BULL and Enter.** Enter is the one control in this app that commits evidence,
  so the key beside it should be the one that costs nothing when a thumb catches it: a slip onto
  MISS adds zero, the same slip onto BULL would add fifty.
- **The ring is held, and falls back to single after each dart.** Holding TREBLE across one dart is a
  convenience; holding it across a visit is the mis-key that turns a 5 into a 15 with no tap in
  between.
- **A sector key shows the dart it would enter** — `20`, `D20`, `T20` — before the player commits to
  it, not after.

## The three darts go on the board, and the board was told about them

`ThroDartLine` draws the entry under the head, where the chalk is, because that is what is being
written and it is where a player is already looking. Each dart is its own tap target: tapping one
takes back everything from it onwards, which is what a player means when they point at the middle
dart and say *"that one was a five"*.

A row drawn hopefully is a row that clips on the smallest phone, so `ThroStage.choose` gained
`perDart:` and counts `dartLine` (44 + 8) into the head before it picks a rung. The cost is real and
declared: on a 6.1-inch phone the hero stays at 96 and the ledger drops from rows to a tally; on the
SE the hero steps from 96 to 56 and the ledger goes. That is the price of the notation, and it is
the player's to choose — which is why the notation is a switch in the rail (`TOTAL` / `DARTS`) and
not a setting buried somewhere, and why it is stored per device rather than per match.

`TurnIndicator` was deleted three slices ago with the note *"they come back the day per-dart entry
gives them something true to show."* This is that day, and what came back is not three empty pips
but the three darts themselves.

## What per-dart entry actually buys

A 141 checkout, typed as a total, stops the player twice mid-celebration: *how many darts?* and
*how many at a double?* Entered as darts it asks nothing — both answers are in the evidence. And
`dartsUsed` and `dartsAtDouble`, which are **nil on every visit today** unless PD-001 interrupts,
start arriving on every visit a per-dart scorer enters.

## A gap this slice can see and does not close

Under double-out the winning dart must be a double. The engine scores a visit, not a dart, so it can
only ask whether the score *before* the visit was finishable — a player on 6 who records 6 wins the
leg whether the last dart was D3 or S6. That is true of the app today and is why PD-001 asks about
doubles at all.

Entering three darts makes the last dart's ring visible for the first time, so the app could now
tell the difference. It does not. There is only one honest way to act on it and both halves are out
of reach here: the engine would have to become dart-aware, in Swift and Kotlin together, behind the
conformance corpus ADR-002 keeps them parallel with — or the entry layer would have to overrule the
engine about what a bust is, putting two authorities on the one question the design exists to keep
in one place. It is recorded in `DartVisit.swift` and here, and nothing claims to catch it.

## Held

20 design tests on the keypad, 5 net new on the evidence rules (9 written, 4 replaced because they
asserted the definition this slice corrects), 11 on the session. 548 in all. All
`tools/check_*.py` green — two of which caught defects in this slice before CI did:
`check_tokens_exist.py` found a test file naming `ThroSpacing` without importing `ThroTokens` (the
exact failure that cost a CI round last time), and `check_test_counts.py` found four stale numbers
in the README and the runbook.

---

# Two rounds of CI, and the guard that ends that class of round

`18dd3d6` and `9df01fc` both went red, and neither for a reason a macOS runner was needed to find.

## `Seat` was named in a file that could not see it

```
DartVisitTests.swift:29: error: cannot find 'Seat' in scope
```

`Seat` is `ThroJournal`'s. The file had `import ThroEngine` and `@testable import ThroPlay`, and
`ThroPlay` depends on `ThroJournal` — so `Seat` was **linked** and not **nameable**. Four minutes on
a runner to learn a fact that is in the source tree.

This is the second time. `Geometry.swift` cost a round naming `ThroMotion` with only
`import SwiftUI`, and the answer then was to teach `check_tokens_exist.py` to ask whether a file
that names a token can see the token layer. That fixed one module.

`tools/check_module_imports.py` asks it of all eight: it reads every module's **top-level** public
declarations, strips comments and string literals from every Swift file, and reports any name whose
declaring module the file does not import. It runs in about a second on Linux.

Three passes to make it honest, each one a false positive teaching the rule:

| It flagged | Because | The rule that fixed it |
|---|---|---|
| SwiftUI's `Group`, the stdlib's `Result` and `Failure` | matched our own **nested** `Groups.Group`, `Scoring.Result`, `Images.Failure` | only declarations at **column zero** — a nested type is not nameable unqualified from anywhere |
| `AccessibilityNotification.Announcement` | matched ThroApp's top-level `Announcement` | a name preceded by `.` is a **member**, and never needs its module imported |
| `FixtureActions`'s own nested `Outcome`, `MatchSession`'s own `Announcement` | the file's own target declares it | a name declared **anywhere in the file's own target**, at any nesting or access, is that target's |

Perturbed four ways: taking the `ThroJournal` import back out of `DartVisitTests` names all four
`Seat` lines; taking `ThroTokens` back out of `Geometry.swift` names all four `ThroMotion` lines; a
comment naming `Seat`, `MatchSession` and `BackupPolicy` passes cleanly; and one line of real code
naming `MatchSession` fails.

It is deliberately not a compiler. It matches whole words in stripped code and skips any name two of
our modules both declare rather than guessing — so it can miss a defect and cannot invent one, which
is the direction a guard should fail in.

## The backup flag, round six

`88d0c0f` went red on `testTheAnswerComesFromTheFileSystemAndNotFromWhatTheURLRemembers` — and
`acd33d5` went **green on one run of the same push and red on the other**, which is the shape this
flag has had since it was first touched.

The bottom of that test is a twenty-round loop written specifically because
`com.apple.metadata:` is the Spotlight daemon's namespace and an attribute written there on a folder
under `/var/folders` can be gone or rewritten a millisecond after `setxattr` returns success. The
**top** of it was still four straight-line assertions depending on the fixture holding across two
consecutive operations.

It is now twenty rounds on the same terms. What it demands of `BackupPolicy` did not go down:

- Every round still asserts the thing the test exists for — after a raw `removexattr`, the answer
  must be `.included` whatever the `URL` remembers.
- The two claims that need the fixture to have held are **counted with a floor of one**: at least
  one round must have seen a flag Foundation had just written (which is what cross-checks
  `BackupPolicy` against Foundation's property-list form — a defect that shipped here once), and at
  least one round must have left the URL believing it was excluded. A fixture that stops working
  altogether fails the test rather than turning twenty rounds into twenty no-ops.

"It's the environment" is not asserted, because that is the excuse this repository refuses. The test
simply stopped depending on something outside itself.

19 guards now. `check_module_imports.py` would have caught both compile failures this branch has had.

---

# A leg won that never happened, and a player's own page

Two things, both found by the same push going red.

## Per-dart entry can see a bust the engine cannot

CI rejected six of the evidence pairs `DartVisit` produces, all with `DARTS_AT_DOUBLE_INVALID`:

```
3 3 · 3 T1 · 60 — T20 · 60 T20 · 81 T7 T20 · 100 D20 T20
```

Every one of them reaches zero on a dart that cannot end a double-out leg. **The engine was right,
and the refusal was useless.** `Engine.recordVisit` requires a double-out finish to claim at least
one dart at a double; a visit that reaches zero on a treble has none by the corrected definition, so
it is rejected — with a reason a player at an oche cannot act on.

Worse, it only catches half of them. A player on 20 who throws a single 20 also reaches zero
illegally, but 20 **is** a one-dart finish (`D10`), so `dartsAtDouble` comes out 1 and the engine
**accepts it as a leg won that never happened**. Two behaviours for one situation, and the more
common one is the wrong one.

`DartVisit.illegalFinish` now catches both before either reaches the engine, and `MatchSession`
refuses with the dart named:

> That reaches zero on T20, and this leg has to end on a double. Take that dart back. THRØ records a
> visit rather than three darts, so it cannot yet score the bust this actually is.

Three things about that are deliberate:

- **It is not a second authority on what a bust is.** Nothing here decides a visit. It refuses to
  submit darts that cannot have been thrown, exactly as the keypad refuses a fourth dart.
- **A zero reached from a bogey is left alone.** From 159 under double-out, reaching zero is
  `NOT_CHECKOUT_POSSIBLE` — a bust the engine sees for itself and records correctly today. Refusing
  it here would take that away. This only speaks where the engine would otherwise call it a leg won.
- **It does not claim to have recorded the bust**, because it has not. That needs an engine that
  scores darts, in Swift and Kotlin together behind ADR-002's corpus, and it reopens PD-008's
  reasoning about what a visit is. It is the founder's, as **OD-023**.

The previous entry recorded this as a gap per-dart entry "can see and this slice does not close",
and said the engine's rule would not catch it. That was half right: the engine catches the cases
where the last dart's own value is not a one-dart finish, and misses the rest. The comment in
`DartVisit.swift` is corrected with what it got wrong.

## The backup flag, round seven — the host, caught in the act

Rounds 13 and 19 of twenty failed with the attribute present **61 bytes after a `removexattr` that
returned success**, and the bytes name the culprit:

```
attribute present, 61 bytes: bplist00_com.apple.backupd…
```

That is `com.apple.backupd` writing its own exclusion onto a folder under `/var/folders`. The folder
really is excluded, by Time Machine, and `BackupPolicy` saying so is **correct**. It is the third
distinct way this one attribute's host has interfered with this one test: an attribute that vanishes
after a successful write, a `URL` cache that skips a write it thinks is redundant, and now a daemon
that writes its own.

`exclusionShape` asks the file two questions the reader does not ask — *is it there* and *is it
ours* — deliberately content-independent, because a helper that classified contents would be a second
copy of the thing under test and every assertion built on it would be a tautology. Each round then
asserts against what is actually on the file:

- our own single byte on it → `BackupPolicy` must say excluded;
- nothing on it → must say included;
- the host's own flag on it → counted, skipped, and **never silently**: a floor fails the test if not
  one round of twenty managed each of the first two, and another fails if all twenty went the host's
  way.

Two reads of one path must still agree with each other whatever is on the file — that is this type's
own business and no host excuses it, and it is the assertion that once caught three reads of a single
path disagreeing within a millisecond.

## A player's own page

The founder asked for *"profile pictures for player profiles, proper player profile layouts"*. The
layout work turned up a defect that had nothing to do with layout.

**A bounded figure was drawn on a profile as though it were exact.** `PersonScreen` mapped each
`StatLine` into a `(value, label, unavailable)` triple and threw the confidence away, so a checkout
percentage the honesty layer marks as a **range** on every other screen in the app arrived on a
player's own page as a plain number. The page draws `StatGrid` now, like everywhere else, and the
mapping that lost the basis is gone — `StatLine.item` is the one conversion and it carries the
confidence across.

The rest is what "proper" means here:

- **PD-018's form figure leads the page** at 56 pt in the sport family, instead of sitting in the
  middle of a three-across grid at the size of the count of legs won. That is the founder's league
  player's complaint applied off the oche: *"just make what's needed big."* It is found by
  `PersonSummary.formLabel`, held in one place, so renaming it cannot silently produce a page with no
  headline and one extra cell.
- **The mark is 96 pt, not 52.** `PlayerIdentity(.large)` is right in a roster row and wrong as the
  subject of a page: a profile picture at list size reads as a list that happens to have one row.
  `PersonMark` already took any size — it was extracted for exactly this.
- The initials it falls back to are held against `LocalPerson`'s own rule, so a person's mark cannot
  change between the roster and their own page.
- `ratingHero` has its first user. It is a **size**; the role exists because a hero figure about a
  player was always intended, and PD-018 decided what that figure honestly is. What PD-018 forbids is
  the word, and the word is "Recent form" over a note ending "Not a rating." No rating value exists
  anywhere in this build — registered absence claim #2, which is the claim that matters.

**The picture itself is the part that is already decided and is not built.** OD-021 closed on
2026-09-07 as **PD-023**: a person on this phone gets a picture with an account, where the person in
the photograph answers for their own age rather than whoever is holding the phone answering for
them. A club member has one today, because a club's admin was asked for their age band when they
were added, and that profile now shows it at 96 pt. Nothing here reopens PD-023; the founder's ask
for player pictures runs into their own earlier decision, and that is theirs to revisit.

563 tests. 19 guards green.

---

# The row I added to the board, and what it cost

`ThroStage.choose` gained `perDart:` in the keypad slice, and the test that holds this screen's one
promise — *on every device THRØ runs on, in every orientation, at every text size, the scoring
screen fits without scrolling and every key is still big enough to hit* — was written before that
mode existed. It walked one notation of two.

A Python model of `choose`, run before the push, found fourteen failures the walk would have found
on a macOS runner four minutes later. All of them the iPhone SE upright, entering darts:

```
iPhone SE upright, on a finish, entering darts: hero 40, sum 670 > 647
```

The board there is 161 points. Its furniture is 63, the checkout route 39, a line of three darts 52,
and the smallest rung's cap box 30 — **184**. There is no rung of the ladder that fits, and
`ladderRung` returns the floor rather than crashing, so the screen simply overflowed.

## Two things now give way, in a stated order

The screen already had an order of sacrifice: **the ledger before the number**. It has two more
steps, and both are decided in `ThroStage` rather than in the view.

1. **The ledger**, as before.
2. **The checkout route.** It is a suggestion; the number, the keys and the darts being entered are
   the product. `ThroStage.checkout` says whether it is drawn, and `ScoringScreen` reads that
   instead of asking whether the thrower is on a finish.
3. **The tray's comfort**, down to the accessibility floor. The tray used to take `trayIdeal`
   unconditionally and the board took what was left, which was right while the board's contents were
   fixed. It now takes the lesser of `trayIdeal` and what is left after the board's own floor — its
   furniture, the dart line, and the smallest rung. A key never goes below 44, and a tray that still
   does not fit is a failure `keysFit` reports rather than one this hides.

Never the hero, never a key under 44, never a scroll.

## What it actually costs, measured

Across eleven devices both ways up at every Dynamic Type size, in both notations — 1,056 screens:

| | happens | where |
|---|---|---|
| checkout route dropped | 12 of 1,056 | iPhone SE upright, entering darts, on a finish |
| tray shrunk (64 → 63) | 4 of 1,056 | iPhone SE upright, entering darts, largest two accessibility sizes |
| **visit-total mode changed** | **0** | — |

Two tests hold that, and the second is the one that matters as much as the first: **entering darts
can never buy anything** — hero, ledger rows, key height and the checkout route are all the same or
smaller, never larger — and **a screen with room is identical in both notations**, asserted on every
iPad, so the arithmetic cannot start charging for the row twice.

A third assertion is that it costs something *somewhere*: if a 52 pt row goes onto the board and
nothing anywhere gives way, the row is being drawn out of thin air.

## And the mark that confirmed nothing

`ScoringScreen` draws a refused entry on the board as a chalk mark carrying what was refused.
It read `session.entry`, which is the **typed** string and is empty in per-dart mode — so a refused
visit of three darts put an em dash on the board with a reason beside it. It carries the darts'
total now, in whichever notation the visit was entered.

565 tests. 19 guards green.

## A type you can see is not a member you can reach

The profile rebuild put `StatGrid.valueColour`, `.noteColour` and `.spokenValue` — internal to
`ThroDesign` — into a screen in `ThroApp`. The package tests compiled it and the **app target** did
not:

```
ClubScreens.swift:881: error: 'spokenValue' is inaccessible due to 'internal' protection level
```

Three of them are public now, with the reason on the first: a figure is drawn outside that file as
well as inside it, and a player's own page leads with one at 56 pt that has to be coloured by the
same rule the grid uses, or the same basis reads two ways on two screens.

`check_module_imports.py` gained the second question. It already read every module's public
top-level declarations; it now also reads every **non-public direct member** of them — 886 of them —
and flags `Type.member` reached from outside that module. `@testable import` grants a test target
its module's internals, which is what it is for, so the reachability question is not asked of a
module imported that way; the import question still is.

Three more perturbations, all behaving: putting `spokenValue` back to internal names the exact line
CI named; a comment mentioning `StatGrid.valueColour` and `Journal.exec` passes; one line of real
code touching `Journal.exec` fails, and fails twice — once for the missing import and once for the
member.

That is three macOS rounds this branch has spent on things a second of Python can see, and all three
classes are now caught before a runner starts.


---

# Where a player finds the choice of notation

The founder asked for both notations. The keypad slice put the switch on the scoring rail, which is
where you want it once you are playing — and nowhere at all before your first match. So it is in
Settings too, under Scoring beside *Keep screen awake* and *Haptics*, both reading and writing one
stored value so the two cannot drift.

**The sentence under it names what each notation costs**, not only what it buys, because a setting
that lists advantages is one somebody switches and quietly regrets:

> **Total** — Type the total of three darts. Fewer taps, and the way every darts app works — but a
> checkout stops to ask how many darts it took and how many were at a double, because nothing else
> can know.
>
> **Darts** — Tap each dart as it lands. A checkout asks nothing, because the answers are in what
> you entered — and your checkout percentage becomes exact instead of a range. It is more taps, and
> on a small phone the score steps down a size to make room for the three darts.

Six tests, following this codebase's existing rule that **no two states may sound the same**: label,
spoken form and Settings sentence are all distinct, walked over `allCases` so a notation added
tomorrow is covered by a test written today. An unknown stored value falls back to the default rather
than guessing, as `Appearance` already does. And the default is `Total`, because per-dart entry is
the better record and the unfamiliar one — making it the default would meet a new player with six
taps a visit.

## And one the compiler had to catch

`ClubsFlow.figures(for:)` changed from `[ProfileScreen.Figure]` to `[StatItem]` — that is the change
that stopped a bounded figure being drawn as exact — and a test in `ClubStoreTests` still read
`f.unavailable`. `StatItem` calls that `note`, and the reason is on the type rather than beside it:
`.range` and `.unavailable` both take a **non-optional** reason, so an unexplained dash cannot be
constructed at all. The test asserts the confidence as well as the reason now, which is the stronger
claim the type already guarantees.

Nothing static could have caught a renamed property, and nothing should try: that is what a compiler
is for. The guard's job is the class of failure the compiler only finds on a runner four minutes
away.

571 tests. 19 guards green.

## A test of mine that described a design this app does not have

571 tests ran, everything compiled, and exactly one failed — mine:

```
ProfileTests.testEveryConfidenceHasADistinctDrawnForm:
XCTAssertNotEqual failed: ("NamedColor(name: "colorTextPrimary", …)")
                is equal to ("NamedColor(name: "colorTextPrimary", …)")
```

I asserted that the three confidences get three distinct value colours. They do not, on purpose:
`StatGrid.valueColour` gives `.exact` and `.range` the same one, and the range is marked by a `Tag`
instead — because colouring the confident case as well would make every figure on the screen look
qualified. The comment saying so has been in `StatGrid` since PD-015 shipped, three lines from the
function I was asserting about.

The claim underneath was right and the test was measuring the wrong thing. **Two states a reader
cannot tell apart are one state** — carried by `basis(for:)`, which is three distinct shapes, and by
`spokenValue`, which is three distinct sayings. It asserts those now, plus the part that is actually
interesting about the colours: the two neutrals **swap** between the value and its reason, so the
loudest thing in a cell is always the thing carrying the meaning — a number when there is one, the
reason when there is not.

Worth writing down because of the shape of it: a test that fails is not always a defect in the code.
This one was a defect in my description of the code, and it went in during a rebuild of that very
screen — the moment I was most likely to assume I already knew how it drew.

## Two keypads, one command — held end to end at last

The PR description says *"two keypads, one command"*, and until now nothing held it. It is the claim
the whole per-dart design rests on: the engine scores a visit, three darts are evidence attached to
it, so a visit entered as darts and the same visit typed as a total must reach the journal as the
same row. If they can diverge, a player's figures depend on which keypad they happened to be using —
which is the one thing this design exists to make impossible.

Two tests, over a checkout, a score from a finish and a visit that missed everything: same visit
total, same darts at a double, same bust, same remainder, same leg, same seat.

**The one column they may differ in is `dartsUsed`, and only in one direction.** PD-001 asks how many
darts were used *only on a visit that finished*, because that is the only visit whose count is
ambiguous — so a typed total that merely scored records nil where the darts record three. Writing
the test is what made that precise: the first version asserted plain equality and would have failed,
correctly, on a case where the darts carry **more** evidence than the prompt ever offered to collect.
The assertion states the relation instead: they may never disagree about a *number*; the darts may
only fill in a blank.

The second test closes the loop from the other side: the evidence the darts supply is the answer the
prompt would have got by asking. A 141 finish on `T20 T19 D12` is three darts with **one** at a
double — PD-001's own worked example, applied to a checkout a player actually hits — and the prompt
raised by typing 141 offers exactly that.

`check_module_imports.py` earned its keep again on the way: the helper's signature names `ThroDart`
and `ThroDartEntry`, which are `ThroDesign`'s, and the file had no import for them. One second on
Linux instead of four minutes on a runner.

573 tests.

## Two claims the runbook now makes to the founder, held by tests

The runbook's first-run plan tells the founder, in these words, that two surprising things are
deliberate. A sentence in a runbook that nothing checks is the defect this repository has been
caught by more than once, so both are assertions now.

- **On 60, entering `T20` is refused with the reason.** A treble cannot end a double-out leg; the
  engine would call it a leg won (OD-023). The session test plays a real match to 60, enters the
  dart, presses Enter and asserts that **nothing was written**, the score did not move, the notice
  names `T20` and the rule, and the dart is still there to take back. A companion assertion holds
  that the same dart is **accepted** under master-out, so the refusal stays the out rule's rather
  than becoming a rule of its own.
- **On an iPhone SE, entering darts on a finish, the route and the ledger go and the score is 56 pt.**
  Writing that test corrected the runbook: I had written *"the number never shrinks below the
  ladder"*, which is true and vague. The real numbers are 72 in totals mode and **56** entering
  darts — and off a finish the same phone still gets the top rung at 96. The checkout row's own cost
  on that phone predates this round entirely; the sentence now says so.

**CI green at `3734411`:** 573 tests, the app target builds for the simulator, 19 guards and the
token gate.

## The confirmation was landing on the number it was confirming

Reading my own comment against the code it sits on:

```swift
// It sits under the head so it never covers the numerals it is confirming …
.overlay(alignment: .center) { … }
```

The comment states the requirement and the code does not implement it. `.center` is the middle of
the **board side**, not a point under the head — and on the iPhone SE the board is 161 points of
which the head is about 132, so the middle of the board is *inside the head*. The chalk mark
confirming a visit landed across the number the whole screen exists to show, on the one phone with
the least room to spare.

It is `.bottom` now, over the ledger for its beat. That is the right thing to cover: the ledger is
what has been written and the mark is what has just gone onto it, while the hero is the product.

**Nothing here can hold an alignment** — no test in this repository constructs a screen, which is
the same admission the design-layer row in the README already makes. So it goes into the runbook's
first-run plan as something for the phone to check, with the reason next to it, rather than being
recorded as verified. That is the honest place for it.

Worth noting how it was found: not by a test and not by CI, but by reading a comment I had written
and asking whether the line under it does what it says.

## And the same question, asked of the row I had just added

Two comments — one in `DartKeypad.swift`, one in `Stage.swift` — say the three entered darts are
drawn **under the head**. `ScoringScreen` drew them after the spacer, at the foot of the board above
the ledger.

Under the head is both what I wrote down and the better answer, so the code moved rather than the
comments:

- The darts land **beside the number they are about to change**, which is the check a player is
  actually making — *what does 141 become after `T20` and `T19`*.
- It keeps them clear of the chalk mark, which now lands at the foot for its beat. Left at the foot
  they would have been the thing the confirmation covered.

That is two comment-versus-code mismatches in the same screen, both found in ten minutes by reading
what I had written and asking whether the next line does it. Neither was reachable by any test here,
and neither would have been found by CI.

## Round eight on the backup flag, and this time the mechanism rather than a workaround

Rounds 10, 13 and 15 of twenty failed, and the message is the whole diagnosis:

```
round 10: the file carries no exclusion at all and BackupPolicy claimed one —
          attribute present, 61 bytes: bplist00_…com.apple.backupd…
```

The shape was read, found **absent**, and `BackupPolicy.read` — microseconds later — found it
**present**. Not a stale cache, not a wrong comparison, not the fixture failing to take: on this
runner `com.apple.backupd` writes its own exclusion onto folders under `/var/folders`
**continuously**, so two reads of this one file milliseconds apart can honestly disagree.

Every previous version of this test asserted *across a pair of reads*. That is not a bug with a fix;
it is a structure with a failure **rate**, which is exactly why this flag has now taken eight rounds
and why each round's fix looked reasonable and then went red somewhere else.

`readWhileStill` closes it by construction: observe the file, ask `BackupPolicy`, observe the file
again, and return **nothing at all** if those two observations differ. Only a window the file
provably did not move in is asserted on. A round that could not see a still file says nothing about
this type, is counted, and three floors fail the test if the host ate all of them:

- not one round saw our own flag on a still file;
- not one round saw the file still and clear;
- not one round saw a still file after `include`.

Each failure message now carries how many rounds the host moved the file under, so the next red run
says which of the two things happened without needing another round to find out.

What `including` is held to also got sharper, because two of its four old assertions were about the
daemon rather than about it: the removal must not **fail**, and this test's own byte must be **gone**
afterwards. Whether the daemon has since written its own is not `including`'s business.


## Three sentences about the keypad that were not quite true

The same sweep, continued through what I wrote about the dart keypad's layout.

The runbook told the founder that **"20 is top-left, between 1 and 5, where it is on a real board."**
It is top-left, and it is between 1 and 5 *on a board* — but not on this keypad. The grid is the
board's sequence read clockwise from the top and wrapped into four rows of five:

```
20  1 18  4 13
 6 10 15  2 17
 3 19  7 16  8
11 14  9 12  5
```

so 5 ends up at the far corner from 20 rather than beside it. That is the wrap's one cost, and the
choice is still right — the board's **sequence** is how a player remembers where a number is, and
either beats 1-to-20 in rows — but the sentence claimed something the layout does not do. It says
what the layout actually is now, in the runbook, in the README and in `DartKeypad`'s own header,
with the cost named rather than glossed.

And one in `ThroStage`: *"the route is the first thing to go"*. It is the **second**; the ledger goes
first, and the order is stated three lines away in the type it belongs to.

Small things, and worth the ten minutes: each of them is a sentence a reader would have trusted.

## A 32-point control, in the Settings screen, on this branch

The Settings row for how a visit is entered was written with SwiftUI's `Picker(.pickerStyle(.segmented))`.

A `UISegmentedControl` is **32 points tall**, and a frame around it does not enlarge its segments —
so that row would have shipped a control below the 44-point floor every other control in this app is
held to, on the screen whose whole reason for existing is that the founder could not reliably hit
things. *"Buttons need to be more reactive sometimes when i press close to them they dont react and
have to be exactly direct on them."*

`SegmentedControl` is in `ThroDesign`, is 44 points, carries `ThroPressStyle` and a `contentShape`,
and was already drawing the **Appearance** row ten lines above the one I was writing. I reached past
it for the platform's.

`check_controls_react.py` now fails on `.pickerStyle(.segmented)` anywhere and names the replacement.
Perturbed by putting the platform control back: it names the file and the line.

The check has caught three distinct classes now, and all three were the same complaint from the
founder wearing different clothes: a control with no pressed state, a control whose label reaches no
tap target, and now a control the platform draws too small to hit.

## `spoken` had no caller

`ScoringEntryMode.spoken` was written with the type, asserted distinct by a test, and used by no
screen. That is the exact shape of defect this record has entered twice already — `ClubStore.setAvatar`
public and tested and called from nowhere, `EditClubScreen` written with no route to it — and a test
asserting a property is distinct is not the same as anything using it.

It has a caller now, and the caller needed it. The rail's switch reads **TOTAL** or **DARTS**, one
word each, and one word is not enough for a screen reader: read out on its own, *"darts"* is a noun
this whole app is about and says nothing about what the control does. It speaks *"Enter each dart"*
and *"Enter the total of three darts"*, with the hint still saying that tapping switches.

`MatchHeader` takes `modeSpoken:` as a defaulted parameter, so every other caller is untouched and
one that has nothing better to say falls back to the word on the key. A test holds that the spoken
form is a sentence rather than the label with different capitals.

## "Deleted" was true of the use and not of the type

A scan for public API referenced nowhere but its own declaration turned up **19** across the client,
and one of them was a claim this record already made:

> ### `TurnIndicator` is deleted rather than fixed

Its *use* was deleted, three slices ago. The type sat in `ThroDesign/Scoring.swift` the whole time,
public, compiled, drawing three dart pips from a `dartsThrown` nobody passed — and both this record
and the comment in `ScoringScreen` said it was gone. It is gone now, and both sentences say when.

The day per-dart entry gave the pips something true to show, they were not what came back:
`ThroDartLine` shows **which** darts, not how many, and that is strictly more. So the type had no
future either.

`check_screens_reachable.py` exists because of this exact shape and its own story ends *"deleted
rather than kept for later, which is the rule it exists for"* — it holds screens and routes, and a
component with no caller is one layer under it.

### The other eighteen, reported rather than acted on

Each of these is public and referenced by nothing at all, its own declaration included:

```
BasisRule.readableFrom            MarkGeometry.ringInnerRatio     RuleTables.specVersion
Club.hasEverHadAFixture           MarkGeometry.ringOuterRatio     Statistics.doublesHitRate
ClubStore.linkResult              MatchResult.homeWon             StoredFixture.isDrawn
Dialog                            OfflineState                    SyncState
Groups.matchCount                 ResultUnit.forAgainst           ThroLiveScoreboard.isRunning
ImagePolicy.purgeWithinDays       RuleTables.bustImpossibleAtOrAbove
WordmarkGeometry.descenderPerEm
```

They are **not** all defects, and that is why this is a report and not a sweep:

- `SyncState` and `OfflineState` are a **registered absence claim** — the claim is precisely that no
  screen constructs them.
- `RuleTables.specVersion` and `bustImpossibleAtOrAbove` belong to an engine that must not change,
  and are the kind of stated constant ADR-002 keeps parallel across two languages.
- `ImagePolicy.purgeWithinDays` describes a **server-side** schedule for bytes; on a phone
  `ImageStore.delete` removes them at once. It is a policy waiting for the surface OD-019 covers,
  not a promise this build breaks.
- `Statistics.doublesHitRate` is a computed figure no screen shows, which is a product question
  rather than a tidying one.

Deciding each would be making calls that are the founder's, so the list is written down where the
next session and the founder can both see it.


## A drawing of what this round rebuilt

<https://claude.ai/code/artifact/ae7ed5f9-c675-4f33-be0c-3fdd01ff0174>

The founder's standing complaint is that they cannot see or test most of what is built, and this
round rebuilt the screen they use most. The drawing shows the scoring board in both notations and a
player's own page **at true point size**: the three board greens and the two embedded faces read out
of `docs/design/extracted/tokens.css`, and every measurement — 96 / 72 / 56 / 40, the 64-point key,
the 434-point tray, the 161-point board on an SE — read out of `ThroStage` rather than chosen to
look right.

It says what it is at the top: **HTML standing in for SwiftUI, which cannot prove the real thing lays
out the same way on a phone.** The board's chalk grain and the hand-drawn wobble in every rule are
deliberately omitted rather than faked, because faking them would flatter the real screen.

Two states in the first draft were ones the code cannot produce, and both were corrected before it
went out: the chalk mark showed a visit that was not the one that had just landed, and the dart
keypad showed TREBLE held with two darts already entered — which cannot happen, because **the ring
falls back to single after every dart**. A drawing that shows an impossible state is worse than no
drawing, and asking of it the same question the code gets — *can this actually happen?* — is what
caught both.


## The vocabulary the founder set on 9 September, applied to the client built on 7 September

Two sessions worked this branch in parallel and met at a merge. One had built the iOS client,
the Android journal and a club/league/tournament model on the founder's 7 September brief (PD-009,
PD-010, PD-019). The other had been given the 9 September instruction — the connected-platform
brief — whose second section is a founder correction in capitals: **clubs are teams**. THRØ must
not carry a standing *club* distinct from a league's *team* because grassroots vocabulary is
inconsistent; the competitive organisation is the Team whatever it calls itself, a venue is a
place, and a "club" with an A and a B side is two teams sharing a venue and, usually, their admins.

The newer instruction wins, and PD-028 records it as an amendment to PD-009, PD-010 and PD-019
rather than an erasure: everything those decided about a public front, announcements and the
official's fixture list stands, applied to teams; what PD-019 decided about a league being made of
teams stands and is now the whole story.

**What changed on the phone, and what did not.** `OrgKind.club` is `OrgKind.team`, reading the
legacy token and writing the new one; `ClubBook.migrate` normalises `kind='club'` rows once, in
place, and gives every team a league fielded (`club_team`) an organisation row of kind `team` with
the **same identifier**, so every fixture's home and away ids keep their meaning and `club_team`
becomes the league's affiliation list. A team removed from a league loses its affiliation and the
league's fixtures for it; the team itself stays. The `thro://club/<id>` link still resolves and
`thro://team/<id>` now does too; the Spotlight domain string is kept because the iPhone's index
already holds it. Copy says *team*; the wall-screen feature is *Venue TV mode*, because the
television is the venue's. Four book tests hold the migration: a legacy row reads as a team; the
legacy word is accepted on write and stored as team; a league's team is a team in its own right,
renamed everywhere at once and surviving its removal from the league; and a pre-existing league
team gains its organisation on open **without** being merged into a standing team of the same
name — two "The Feathers" remain two teams until a person links them.

**What was deliberately not renamed.** The Swift type `Club`, the `ClubBook`, the `ClubRoute` and
`ThroRoute.club` cases and the file names are code identifiers, not concepts; renaming them is a
thousand-line churn with no behaviour in it, and it is scheduled for the round that wires the client
to the server's `competition.team`, when the type will change shape anyway. The record of earlier
phone looks in `docs/runbooks/CLIENT_IOS.md` keeps the words the screens showed at the time.

**The merge itself.** Nothing on the client side touched the migrations, so V014–V017 — the
organisational graph, organisational commands, the Secretary and discovery — apply cleanly over
V013. Five documents and the test harness conflicted and were rebuilt from the client side's
version with the server side's sections added. Where both sides had used the same record numbers,
the server side's now follow: ADR-017 (vocabulary), ADR-018 (organisational state), PD-028,
PD-029, OD-024. Every Kotlin suite, the schema script and all 581 client tests are green on the
result.

## Seats, not names

Open decision OD-024 was the last item hostile review of ADR-017 left standing, and it was the one
that blocked Phase C: `evidence.match` had carried `home_name` and `away_name` since V006, and every
visit payload named its thrower by that name, because the scoring engine works in string labels and
the labels were whatever was typed at the oche. That put a display name — possibly a child's —
inside the one schema no application role may update or delete, which is exactly the place it can
never be rectified or erased from.

The engine's two labels are now **seats**. The server's `Seat` object names them `home` and `away`,
which are not new words: the iOS journal and the Android journal had both already chosen them as
the stored form so that a row written on one phone is readable on the other, and the server's
first draft of this change had used `Home` and `Away` until the client's `Seat` was read. A label
the client will actually send is the label the server must accept, so the server changed. The
aggregate binds each seat to a competitor identifier when the match opens and stores no name; a
visit's evidence says which seat threw; the aggregate says who sat there; a name is joined from the
identity module at render. The command handler refuses a visit naming anything else with *"that is
not a seat in this match"*, and the playtest scorer keeps its two typed names in memory, maps them
to seats before recording and maps them back for display, so the browser page is unchanged and the
store is.

V018 drops the two columns and rewrites every existing payload's name to the seat it labelled,
matched per match against that match's own two names rather than by any global lookup, so a name
two people share across two matches cannot cross between them. It is the one deliberate rewrite of
evidence in this repository and it is written as such: a pseudonymisation the data-protection
promise requires, performed once by the owner role, with the row count unchanged and nothing else
in any payload touched. `MigrationTest` populates a V013 database with a named match and three
named visits and reads them back as `home, away, home` with every `remainingAfter` intact, the
columns gone, no name left anywhere in `evidence`, and the aggregate still binding the same two
competitors with the same thrower first — eighteen migration properties now.

The schema script had asserted the participant set was frozen by trying to change a name column;
it now tries to change `away_id`, and two of its inserts that had gone on supplying two name values
to a table with no name columns were corrected. That brought the count back to a number that was
run rather than remembered: **78**, not the 85 the plan had said or the 93 the README had, neither
of which this script has ever printed. The plan, README, glossary (a *Seat* entry), ADR-017's
deferred list and OD-024 itself now say what V018 does.

## What an event requires, stated in terms THRØ can check; and a ledger for the migrations

Discovery's read model had one honest gap it named on every card: a `member_only`, `qualified`,
`restricted` or `invitational` event appeared with *"eligibility not yet checkable by THRØ"*,
because the requirement lived in the organiser's head. V019 gives it a home,
`competition.event_eligibility`, in the five terms THRØ can check against its own records — a live
team membership, a live league-season registration, a live entry to a named qualifier, the claimed
account's age band, or an invitation by name. Rows in one group are alternatives, so a club's A side
or its B side; every group must hold, so a member *and* an adult. Nothing outside the five is a row.
Qualification by result, residence, "known to the committee" — THRØ cannot read those, so it does
not pretend to, and the card says *"requirement not stated in terms THRØ can check"* and never says
eligible. An unclaimed player's age band is unknown, and unknown satisfies neither `adult` nor
`minor`, in keeping with ADR-005: a guess in either direction is the one that lists a child.

The store answers through one predicate, `requirement_holds_for`, which both the whole-event
function and the card's per-row explanation call, so *"you qualify: member of Riverside A"* and
*"requires membership of Grange B"* are the same computation the eligibility section keys on. An
open event refuses a requirement, because open means open. A stated row is withdrawn with a reason,
never rewritten — the application role may fill the three withdrawal columns and nothing else, and
the owner cannot rewrite one either — so an entrant can be shown the rule as it stood when they were
told. The pure `Requirement` and `Eligibility.satisfies` in the competition package carry the same
rule for the client to share, and are held to the store's semantics by test. Twenty-five discovery
properties now, nine more schema properties, two more on the pure types.

**The hostile review of V018 found two traps, and both are closed.** First: every runner applied
migrations only when the `evidence` schema was absent, so a database migrated by an earlier checkout
sat silently behind the code — after V018 such a database still had `home_name NOT NULL` and could
not open a match at all, and thirty downstream properties would have failed for the wrong reason.
There is now a ledger, `thro.schema_migration`, kept by `Migrations.kt` and by the same logic in the
schema script: each file the ledger does not hold is applied in its own transaction with its row and
content digest; a database with THRØ's schemas and no ledger is refused as unknowable; a recorded
file whose content has changed is refused, because migrations are forward-only; a recorded version
this checkout has no file for is refused, because the database is ahead of the code. The test
harness rebuilds from nothing every run and asserts the ledger stands where each test believes it
does. Second: V018's rewrite matched a payload's name against its match's two names and quietly left
anything else — a spelling variant, a name from before the aggregate check — as personal data in the
one place it can never be removed from, which would have made the migration's own header a lie. V018
now refuses to run if any visit payload would be left naming something that is neither seat, refuses
a match whose two names are identical and has visits, and after the columns go adds
`visit_names_a_seat` so the database keeps what the glossary claims. `MigrationTest` now also writes
a `VisitCorrected`, a second match in which the same name sits on the other side, and two databases
the migration must refuse and leave untouched. The playtest scorer's attestation path, which had
keyed on the typed name and defaulted to away, now maps a name or a seat word and refuses anything
else — the same rule as recording a visit.

The reviewer's fifth finding was about the number. The schema script had counted its migration
apply lines and its "already present" line among the passes, so the figure the README carried
depended on whether the database was fresh, and the *78* the previous entry called "run rather than
remembered" was seventy-seven properties and one skip line. Applying is a precondition of the
properties and is no longer counted; the number is **86**, and it is the same number on a fresh
database and a current one.

## A check-in is a person

V014 typed entries as player, pair or team and left a note on `check_in`: the person present is a
person whatever entered, and making them the key was the contract half of an expand-then-contract
"once the grant actor is a player rather than a competitor". V020 is that half. `check_in` is keyed
on (event, player, device); the entry it is for must exist — a foreign key V013 never had, added
`NOT VALID` and validated in the same migration when every existing row satisfies it, otherwise
left standing for new rows with the count of old ones it could not vouch for said out loud; and the
person must belong to the entrant, enforced at the write by trigger — the player themself, one of
the pair, or a member of the team whose membership is live at the moment of check-in. A former
member is refused; a stranger is refused; an entry that does not exist is refused in the foreign
key's own words.

The grant follows. `trust.scoring_grant.actor_id` is what the command handler annotates evidence
with, and an annotation naming a pair names nobody, so check-in now issues the grant to the person
who did it, and the test holds that the pair and the team hold none. Any legacy check-in whose
competitor had never become a player is given a legacy player record, exactly as V014 gave one to
every entry competitor — nothing lost, nothing invented beyond what V014 already did.

## Match night, at the store level

Phase C's surface waits on the identity decision, but two of its rows do not: who can play, and who
is playing. V021 adds both as the organisational state ADR-018 describes — server-authoritative,
versioned, a stale write refused with the current row and never merged — and
`OrganisationCommands` gains `SetAvailability` and `NameLineup` beside the rename and the
rearrangement, with the same receipt-first, authorise, apply-at-the-version-seen shape.

**Availability** is a player's own word, which needs no relation, or a captain's on their behalf,
which needs `team.manage`; either way the row says who said it, and every change is appended to
`availability_change` by trigger, so *Sam said yes on Monday and the captain said no on Thursday*
is readable. **A lineup** is the captain's. The lineup row carries the version and the players are
entries under it, so naming a new side writes a new set and the old one is history rather than gone
— no role can delete an entry and nothing needs to. The store refuses, in its own words, a team
that is not one of the fixture's two, a player who is not a live member of that team at the moment
of writing, an entry under any version but the current one, and any *change* to a named side once
the fixture has a live outcome; a first naming after the outcome is allowed, because a captain
filling in the card after the match is recording what happened, and it carries the same trust as
the result it accompanies. What the store does not decide is deliberately listed: how many a side
is, whether they must be registered, whether a captain may pick someone who said they could not
make it. Those are the league's rules and the captain's judgement.

A refusal the store makes itself is now a `Refused` result in the store's words with a receipt,
not an exception: the command handler rolls back to a savepoint and records it like any other
refusal, so a replay of a refused lineup returns the refusal. The lineup entries are written one
statement at a time rather than as a batch, because a batch failure surfaces as a different
exception type and the words *not a member* were lost on the way out — found by the test that
expected them.

The Secretary's result card uses it. A played outcome still creates the home team's
`result_submission_due` task and its `result` submission, but the submission is now a **draft**
until both sides have a lineup, with the task's missing facts naming the side that has none, and
`onLineupNamed` makes it ready the moment both are there — the league is not sent a scoreline with
nobody on it. The existing Secretary property that expected the card ready at once was wrong about
the product and is replaced by three that are not. Seventeen match-night properties, sixty-four
Secretary properties; the schema stands at V021 and the script's 86 hold.

Plan §5 now says how ADR-016's local claim and V014's `identity.player_claim` meet — the account's
live claim names the THRØ ID the local person becomes, and each claimed seat lands as a
`local_match_claim` row with its digest, self-reported and claimable once — so the two designs
attach to each other without a migration when the claim flow arrives.

## The second hostile review, and a rule that had no teeth

A hostile review of V019–V021 and the ledger came back with twelve findings. The ones that were
holes are closed at the store, in V022, and the ones that were choices are now written down.

**The lineup was not fixed.** The freeze covered the lineup row and not its entries: after an
outcome, an entry under the current version could still be inserted, and the membership check ran
at the old naming time — a departed member could be slipped into a side that had "played". Now a
lineup is named at the transaction's own time and its entries must be written in that transaction;
the store holds the two to each other, so a side is complete when the naming commits and nobody can
be added afterwards, by any role. **A void froze the side for ever.** A void says the result did not
stand — often because the wrong side was named — so a void no longer freezes; played, awarded and
walkover do. **Open was not open in both directions.** An event could be set back to `open` while
live requirement rows stood, and discovery would then call it open; the store refuses that until the
requirement is withdrawn with a reason. **The audit row was rolled back.** A store refusal rolled
back to a savepoint taken before the authorization decision, discarding the ADR-008 record of the
decision that let the captain try; commands now authorise first, then take the savepoint, and the
test counts the audit rows. **Finished tasks are history**: `onLineupNamed` no longer rewrites the
missing facts of a done or cancelled task. **`currentVersion` could not return null** because the
ledger table is resolved at parse time; it asks `to_regclass` first. **Two runners racing** each
other to V001 now take turns under an advisory lock, and the script gained the "database ahead of
the code" refusal the Kotlin runner already had. The choices — a qualifier counts a player's own
entry or a pair containing them and not a team entry; the self-recording path compares THRØ IDs and
the HTTP layer must map an account to its claim before handlers run — are in the glossary, the
migration and plan §5.

**ADR-013 had no teeth.** The record of 3 September requires CI to fail on an unmarked destructive
statement and on any rewrite of evidence, and nothing enforced either: V014 dropped a column, V018
rewrote payloads and dropped two, V020 replaced a primary key, all unmarked and all green.
`tools/check_migrations.py` now runs first in the schema workflow and holds the discipline per
statement — destructive statements need `APPROVED-DESTRUCTIVE` with a reason, evidence rewrites need
`APPROVED-EVIDENCE-REWRITE (pseudonymisation|erasure)` with a reason, every file runs as the owner
from its first owned statement to `RESET ROLE`, and versions are contiguous. The three files carry
their markers, which changed their digests: a database migrated from the previous commit is refused
by the ledger and rebuilt, which is the intended cost of editing an applied file before the first
deployment and is now said in the ADR. The ADR is amended in five points: the ledger is its named
mechanism; the checker is its enforcement; the one permitted rewrite of evidence is the removal of
personal data that a read-time upcast cannot achieve, under five conditions V018 satisfies; expand
and contract may share a file until the first deployment; and the payload upcast corpus the record
requires does not exist yet, recorded as a debt rather than left to be discovered.

The `schema` workflow had also failed on the previous push for a reason that was not ours — a
third-party apt mirror's hash mismatch while installing `psql`, which the runner image already
ships. The step now consults apt only when `psql` is absent.

## The HTTP layer, behind a door that says what it is

Plan §5's first item. `services/api/src/main/kotlin/thro/api/http` is Ktor routes over the handlers
that already existed, and it decides nothing they do not: one command endpoint carrying a visit or
any organisational command (ADR-007), the caller's inbox, a team's inbox filtered on `team.manage`,
discovery, health, and the contract itself. Three rules hold across every route and the test names
each: **identity is the principal** — the authenticator says who is calling, and an actor named in
a request body is ignored, so a stranger who writes the admin's id is refused as the stranger;
**one connection per request**, closed whatever happens; and **a replay returns what it returned**,
status included, so a replayed stale is still a 409 — compared as the parsed answer, because the
stored receipt comes back through jsonb, which normalises whitespace and key order.

ADR-001 accepted Kotlin on the condition that the organiser console's contract be machine-checked
against a server-emitted schema, and doubted the framework could emit one. It cannot; the answer is
a registry. Every route is an `Endpoint` in one list, `/openapi.json` is rendered from that list,
the server refuses to start if a handler and an endpoint disagree, and `HttpTest` holds the served
document equal to the committed `services/api/openapi.json` on every run — so a change to the
contract is a change to a reviewed file. The other half of the condition, a client *generated*
from the schema, is not met, because the console it would serve does not exist; ADR-001 now says so
in a dated note rather than being read as accepted.

The server refuses to start without an authenticator, and the only one that exists is the
development one: it trusts an `X-Thro-Dev-Subject` header, cannot be constructed unless
`THRO_DEV_AUTH=1` is set, and says on every start that anyone who can reach the port is whoever
they claim. It exists so the layer could be built and tested before FB-1 is decided, not so a
server can be run without deciding it. A malformed date is the caller's 400, not the server's 500,
which the test found. Twenty HTTP properties; the runbook is `docs/runbooks/API.md`.

## The third hostile review: a stranger with a good seat

The review of the HTTP layer found the finding that mattered in the handler underneath it, where it
had sat since V006: the command handler checked that a visit named a *seat* of the match and never
that its *author* was in the match. Over the playtest harness that was academic; over an endpoint
any principal can call it is the cross-match injection ADR-008 names as the highest-value attack —
post a visit carrying a stranger's match id and the seat word `home`, and evidence lands in a match
you are not in. The handler now refuses an author who is neither a participant nor was ever granted
anything for the match, before any evidence exists and with a receipt, so a retry is answered the
same way. The rule is deliberately narrower than "must hold a sound grant": ADR-006's promise that a
revoked or expired scorer's visit still records, flagged, stands — that is a scorer whose authority
lapsed, not a stranger. Three fixtures that had used a random author for a legitimate visit were
wrong about the product and now name a participant; the grants test gained the stranger case, the
injection test gained the outsider-with-a-good-seat case, and the HTTP test posts the attack itself
and reads back that nothing was written.

The second finding was that a replayed visit did not return what it returned: the handler's stored
receipt carried no outcome, so the HTTP layer answered a replayed refusal with 200 and a different
shape. Receipts now carry `outcome`, the HTTP bodies are the receipts, and the test replays an
applied command and a refused visit. The rest was hardening a door should have had on the day it
was hung: a body over 64 KiB is 413 before a connection is held for it; the hand-rolled JSON parser
is bounded to thirty-two levels, so a thousand brackets are a 400 rather than a stack overflow; a
lineup of non-strings, an integer out of range and a wrong-typed field are 400s; every control
character is escaped on the way out; `/healthz` no longer repeats the driver's words to an
unauthenticated caller; the evidence's actor role is what the store knows about the caller rather
than a hard-coded `participant`; and the development authenticator's constructor is internal, it
honours `PGPASSWORD`, and it refuses to exist against a database that is not on this machine.
Twenty-seven HTTP properties.

## The founder decided, and the door has a real lock

Two decisions arrived on 10 September and are recorded as PD-030 and PD-031: **Sign in with Apple
and Google first, self-hosted passkeys as the fallback**, and **Fly.io with managed PostgreSQL in
London**. The first reverses the order ADR-008 had named and nothing else in it, which ADR-008 now
says in a dated note; the second is the vendor ADR-011's topology was waiting for.

The account and session core followed, written to an acceptance table (§12d) put down before the
code. The provider proves who is holding the phone and THRØ takes exactly one fact from its ID
token — the subject — after checking the signature against the provider's published keys, the
issuer, the audience and the expiry, each failure a 401 that says which and creates nothing; there
is no library, because RS256 is a signature over two base64 strings and a JWKS is a modulus and an
exponent, and the key source is an interface so the test holds the provider's private key and mints
both the tokens that must verify and the ones that must not. A first sign-in creates the account,
its player and the `self_created` claim in one transaction, with the person's own consent recorded
by V016's trigger; a second sign-in with the same subject finds the account and creates nothing.
The name is a placeholder until the person sets it, never the token's name claim.

The session is THRØ's own. An access token is thirty-two random bytes, opaque, looked up per request,
fifteen minutes; it names an account, and the account's live claim is the principal every route
already spoke. A refresh token is single-use: using it issues the next pair and marks it used with
its successor; using it again is reuse, the sign that a copy exists, and revokes the whole family —
the test does exactly that and watches the family's live access token die with it. Logout revokes
the family on purpose. Only the SHA-256 of any token is stored, held by reading the tables back, so
a dump yields nothing a caller can present; the tables refuse to un-revoke, to re-use, or to change
an access token at all. `Main` starts the bearer authenticator when a provider client id is
configured and refuses to start with none unless the development door is explicitly opened.
Twenty-five properties. Passkeys — the fallback, with recovery — are the next slice and are not
claimed.

## The fourth hostile review, of the lock itself

The security review of the sign-in code found nothing that let a forged token through — the
algorithm is pinned before any key is used, the key id is only a map key, the token is never
stored — and eleven things around it, of which three were races and two were ways to make the
server hurt itself. All are closed.

**A stream of invented key ids made THRØ call Apple once per request.** The key source honoured its
cache only for a known `kid` and refetched for any other; it now refetches at most once a minute per
provider, keeps the last good set through a failed fetch, caps the response at a megabyte, checks
the status, and surfaces "no keys at all" as a 503 rather than a 500 — held by a test that counts
the fetches for fifty invented ids. **Two first sign-ins with one subject at once** — the double tap
every mobile flow produces — raced to the unique index and the loser got a 500; they now take an
advisory lock on the subject and the loser finds the account the winner made. **Two refreshes with
one token at once** both read the token as unused and the loser hit the trigger; the row is now
locked for update, so the loser is answered as reuse. Both races are run as races in the test, on
two connections behind a latch. **A family lived for ever**, refreshing itself indefinitely; V024
gives it ninety days, after which the person signs in again, and the runbook says what the
append-only access-token table means for retention. **The sign-in bodies were read before they were
measured**; every non-GET route now refuses a missing Content-Length with 411 and a declared length
over 64 KiB with 413 before a byte is read, and every route opens one connection per request — the
authenticator uses the request's own instead of a second. The ID token gains what ADR-008's
threat model implied and the code had not said: a per-sign-in nonce, required whenever the token
carries one, matched raw or as its SHA-256; sixty seconds of clock leeway on expiry; a token issued
in the future refused. An account whose claim was revoked still signs in and is nobody to every
route until re-claimed, with no 500 on the way; a deleted account is 403; a display name is trimmed
before it is measured, counted in code points, and refuses control and formatting characters. V011's
whole-row UPDATE grant on the account, which let the application rewrite the two columns V016 keeps
honest by trigger, is now the four columns it legitimately writes. The plan's acceptance row that
had said "rate-limit-ready" now says rate limiting is not built and not claimed. Thirty-eight
properties, and one more without a database. The test for control characters in a name found one more: the hand-rolled JSON parser had never decoded `\uXXXX` escapes, so a name sent that way would have been stored as backslash text; it decodes every escape now.

## Passkeys, and a runbook with the names in it

PD-030's fallback. `WebAuthn.kt` is the registration and assertion ceremonies with no library: a
CBOR reader that accepts exactly what an attestation object and a COSE key need and refuses the
rest, the client data checked for type, challenge and origin, the authenticator data for the
relying-party hash, user presence, user verification, the credential and its key, and — for an
assertion — the counter advancing and the signature over authenticator data and client-data hash.
ES256 and RS256 are accepted; the attestation statement is deliberately not, because THRØ asks for
`none` and which make of authenticator holds the key is not its business. A challenge (V025) is
thirty-two stored random bytes, five minutes, spent once, bound to the device that asked; a
registration challenge issued to an account cannot be finished by an anonymous caller. The test is
the authenticator: it holds a P-256 key, builds every byte, signs, and then gets each thing wrong in
turn — origin, verification flag, relying party, a stale counter, another key, a spent challenge, an
old one — twenty properties.

Recovery is decided with it, as PD-030 said it would be, and it is a second way in (PD-032): a
second passkey or a provider added from a session, the profile reporting how many ways in the
person has, and no email or SMS channel, because neither exists and a channel weaker than the
credential it recovers is the surface passkeys were meant to remove. This host serves the Apple
association file for its passkeys from the configured app ids, and the server reads `DATABASE_URL`
as platforms set it, so `fly postgres attach` is enough; the release step migrates as the superuser
and grants the app's own user the application roles. `docs/runbooks/DEPLOY.md` now names the apps,
the database and every secret, and gives the seven staging steps in the order they run.

## The fifth hostile review: a five-byte body

The passkey review found the worst bug of the day in five bytes: a CBOR array header claiming two
billion items made the reader allocate for them before reading one, and `OutOfMemoryError` is not
an `Exception`. An unauthenticated caller could have taken a machine down with a handful of
requests. A count is now a claim checked against the bytes that remain — every item costs at least
one — and nothing is pre-sized; the test posts the five bytes and gets a 401 in constant memory.

Two account-confusion paths are closed with 409s: a signed-in caller finishing a challenge that was
issued to nobody would have landed in a new account while believing they had added a passkey to
theirs; and a signed-in caller linking a provider subject that another account already holds would
have been handed that other account's session, indistinguishable from success except by reading the
id. Neither is a way in any more. A WebAuthn user id is now the account's for life (V026), because
the platform keychain replaces a passkey created for the same relying party and user id, and the
options exclude the account's live passkeys so nothing is offered twice; the second-passkey test
reads both back. Expired challenges are swept by an owner-defined function the application may
call, and the device id on a challenge is described as what it is — bookkeeping. An EC key labelled
RS256 or an RSA key under 2048 bits is refused; an RS256 passkey registers and asserts, tested. The
database URL's credentials are percent-decoded exactly once, so a password with a plus or a percent
survives boot, held by a test with no database.

The runbook had a step that would have made the app's database user a superuser: `fly postgres
attach` defaults to it. It now says `--superuser=false` and why, `fly.toml` carries the staging
app name, and the runbook says in bold what the review said in plain terms — a passkey is bound to
its host, so production's domain is chosen before any real person registers one.

## A database that needs no card, and a first migration that did not run without one

Fly.io requires a card on file for every organisation, and the founder asked whether there was a
better database option — Neon was named — or a design that leaned on iCloud and Android's
equivalents instead of a server. The second question has a short answer that is in the plan and the
ADRs already: iCloud syncs one person's own data between that person's Apple devices, Android has
no equivalent that iOS can read, and THRØ's product is the shared world — a league's fixtures, a
team's roster, another person's result, the Secretary's tasks — which needs one authority that both
phones talk to. The on-device journal already is the iCloud-shaped part: a person's own matches
live on their phone and travel in its backup. Rebuilding the shared world on Firestore or CloudKit
would throw away the foundations the brief said not to, and CloudKit could not include a Pixel.

The first question had a better answer than the runbook gave. PD-031 said "Fly.io and a managed
Postgres with point-in-time recovery in London" and the runbook had reached for Fly Postgres, which
promises no PITR and needs the card. Neon is the managed Postgres the decision described: a London
region, a free plan with a six-hour restore window that needs no card, seven days on the plan below
that, and plain PostgreSQL out. PD-031 is amended to name it, and to split compute: Render's free
web service in Frankfurt for staging (no card; it sleeps after fifteen idle minutes and wakes in a
minute, which staging can bear), Fly in London for production, where a card is unavoidable because
always-on costs money. `render.yaml` is the blueprint; `gradle -p services/api migrate` is the
deploy step for a host with no release hook; the runbook has both paths with the names in them.

Testing the Neon path found a bug that was not Neon's. On a managed database the deploy user is
not a superuser, and PostgreSQL 16 no longer gives a role's creator the right to act as the role it
created: V001 created `thro_owner` and then could not `SET ROLE` to it, so the first migration
failed at its first schema. V001 now has the creator grant itself membership with SET and INHERIT
when it is not a superuser — using the ADMIN OPTION creation does confer — and the whole chain,
V001 to V026, was run as a plain role with CREATEROLE on a fresh cluster and passed. Every earlier
run had been as a superuser, which is exactly the condition ADR-013 says a migration must not be
tested only under. The edit changes V001's digest, so a database migrated before it is rebuilt.

## The London database exists

The founder created the Neon project `THRØ` in London (PostgreSQL 18) and connected it; from
this repository's `migrate` task all twenty-six migrations were applied as `neondb_owner`, an
application role `thro_app` was created by SQL — not by the console, whose roles join
`neon_superuser` and could write evidence — and granted exactly the five application roles, and
a second run applied nothing. Verified as `thro_app`: it reads the ledger and the tables and is
refused a delete on a competition table and an update on evidence. One thing the Neon run found
that the local one could not: the health route reads the migration ledger through the
application's connection, and the application could not see it; the runner now grants the read
role usage on the ledger schema and select on its one table, and a schema property holds that
this is all it may do. The runbook carries the real names and the one endpoint caveat — Neon's
pooler host is PgBouncer and cannot carry a migration's role switches. Cloudflare, asked about the
same day, is answered in the runbook: Workers cannot run a JVM, Containers need a card and will
not say where they run, and ADR-011 needs to know.

## Staging is live

`https://thro-api-staging.onrender.com/healthz` answers `{"database":"ok","schemaVersion":"V026"}`
against the Neon project in London, with no card on file anywhere. The first deploy died with
status 128 before the JVM started: `render.yaml` had a `dockerCommand: serve`, and on Render that
setting replaces the image's entrypoint as well as its command, so a bare `serve` was executed and
found nowhere. The image's default already serves; the line is gone. Probed from outside after
the redeploy: the served contract is byte-for-byte the committed `openapi.json` with its seventeen
operations, the Apple association file names `2XM324WPD5.app.thro.darts`, an unauthenticated
command is 401, Sign in with Apple without a token is 400, Google is 503 until its client id is
set, and a passkey challenge is issued for the relying party `thro-api-staging.onrender.com`. The
runbook records the live state and keeps the set-up steps for the next environment.

## Thirty a minute

The sign-in, refresh and passkey routes are the only ones a stranger may call, and until now they
could be called as fast as a connection allowed. A token bucket per client address and per device
id now sits ahead of them — thirty attempts a minute, refilled continuously, the thirty-first a 429
with `Retry-After` — and the test floods one address and reads the thirty-first answer and its
header. It is honest about what it is: one instance's memory, the difference between a thousand
token guesses a second and thirty a minute, not a flood defence, which is the host's business. The
runbook gains the steps for creating the Google iOS client id, which is the one value Sign in with
Google waits for.

## The phone signs in

Until today the client had a load-bearing absence: no network code, held by a check that failed on
the first `URLSession`. It is retired deliberately, and what replaces it keeps the promise the
absence was guarding. `ThroNet` is the one network target, reached only by `ThroApp` — the journal
and the scoring session still cannot import it, and two new claims in `tools/check_absence_claims.py`
hold that direction where the old one held the whole. It carries a sign-in and the session THRØ
issues, refreshes that session once behind every authorised call and signs out rather than loops
when the server stops honouring it, decodes the inbox and the discovery cards as the server sends
them with every reason intact, and speaks base64url and PKCE the way the server and Google expect.
The refresh token lives in the keychain, this device only, never in a backup that could restore it
to another phone.

The account store is the only thing the screens talk to, and the platform ceremonies behind it are
injected, so every state — signed out, busy with a sentence, signed in, failed with words — is
reached in a test with a scripted server and no device. The live services are Sign in with Apple,
Sign in with Google through a system web session with a code exchange that sends no secret because
an iOS client has none, and a passkey through the platform authenticator; a cancel puts the screen
back where it was and is never shown as a failure. Settings' *Account and profile · Not built* is
now a row that opens the Account screen: sign in three ways, or create an account with a passkey
alone; set the name a league knows you by; see how many ways into the account you have and add
another (PD-032); read your Secretary inbox and the darts you can play, each with the server's
reasons; sign out. The app's Associated Domains entitlement exists now, carrying `webcredentials`
for the staging host in developer mode so iOS offers passkeys for it; the `applinks` line is still
deliberately absent, and the claim that guarded that is reshaped rather than dropped. The runbook's
sentence about the phone is rewritten to what is true: nothing on it is uploaded, and the only
thing this build sends anywhere is a sign-in, if you choose to make one. Sixteen tests; 597 on
the client.

## Each request runs as its module

ADR-011 wanted each module on its own database role and the runbook had carried it as a
follow-up: the API connected as one user holding all five roles. It still connects as that user
— a managed database issues one — but no request uses it as such any more: the connection a
request opens narrows itself with `SET ROLE` before its first table, to `app_match` for a visit,
`app_competition` for an organisational command, a sign-in or a Secretary read, and `app_read` for
the health route. A handler that reaches past its module now fails on a grant rather than
succeeding by accident, and the whole API suite — which runs as a superuser and would have hidden a
missing grant forever — now runs every route under the narrowed role and passes, which is the
first time the grants have been exercised from the wire. The HTTP test watches every connection
the server opens and counts the statements that ran before the narrowing: zero.

The same day the founder's Xcode refused to sign: a free "Personal" Apple team cannot carry Sign in
with Apple, Associated Domains or App Groups, and the app has all three. A `Personal` build
configuration now signs with none of them — Google sign-in works, Apple and passkeys refuse, the
Live Activity has no shared container and shows its empty state — and `check_app_group` knows it
as the one configuration allowed without the group, never Release. The Developer Program lifts all
of it and is a precondition of TestFlight in any case; the runbook says so, and how to switch back.

## A match, live

ADR-007's first stream. `GET /v1/streams/match/{id}` sends every event of a match in commit order
and then each new one as it commits, over server-sent events, with the id `match:{id}:{commitXid}-
{seq}` so a reconnect with `Last-Event-ID` replays from the log rather than hoping. The order is
the pair the schema has indexed since V002 — `(commit_xid, global_seq)`, never `global_seq` alone —
and a row is served only once every transaction older than it has finished (its `commit_xid`
below the snapshot's `xmin`), which is the watermark hazard the schema's own comment warned about,
closed at the point of reading. A comment ping goes every fifteen seconds; the phone's parser
keeps the id and its stream reconnects and treats forty-five quiet seconds as stale on its own
clock. Participants, holders of a scoring grant and officials of the event may watch; there is no
spectator stream yet, so nothing is filtered for a reader who may see less than they. Fan-out is a
one-second poll of the log for now — the record's LISTEN/NOTIFY hint is a latency improvement over
that, recorded as the follow-up, not a correctness one.

Two things the test found. Ktor's test engine buffers a streaming response until the handler ends,
and a stream's handler does not end; the stream test now runs a real engine on an ephemeral port
and reads the body with the JDK's client as it arrives. And Ktor's SSE helper answers 200 before
the handler runs, which let a stranger through with an empty stream; the stream is served from a
plain route that writes its own frames, so 401, 403 and 404 come first. Nine stream properties on
the server; the parser and the staleness deadline on the phone.

## Start the Discover tab again

The founder's phone showed people listed as teams. The cause is the vocabulary migration of
9 September doing exactly what it said: every side a league fielded became a team in its own right,
and a singles league's sides are people. That is the right model for a league of teams and the
wrong picture for the data this phone held. Rather than special-case a guess about which sides were
people, Settings gains one confirmed act — *Remove every team, league and tournament* — that clears
the Discover tab: every organisation with its roster, fixtures and results, counted before the
button and named in the confirmation. Matches and the people book stay, because a person is who a
match was attributed to and that is history, not an organisation. The club book's test creates a
team with a member, a league with two sides and a fixture, clears them, and reads back nothing but
the person. What replaces the cleared data is the next slice: teams that live on the server, made
by the people who run them, and a map that shows official venues — from a source the founder names,
never invented here.

## The scoring screen, seen

The founder reported the game screen "ugly and cropped". Reproduced in the simulator, it was three
defects in the design layer, none of them the data's. **The board bled the safe area with its
content**: `ThroBoard` ignored the safe area for the whole stack, so the rail sat under the Dynamic
Island and its captions were cut in half; now only the surface — lamp, field, dust — runs edge to
edge, and the content stays inside. **Every numeral was cut in half**: `ThroFigure` positioned a
digit inside its clipped cap box by a hand-computed trim that assumed a 0.22 em descender, and the
sport face's is 0.275, so the top of every digit fell outside the box; the digit's baseline is now
declared as the cell's bottom alignment guide and the font is asked, not estimated. **The away
register ran off the right edge**: `ThroStage` chose the hero rung as if the head were two registers
and nothing else, and the legs column between them — "0–0", "BEST OF 5" — took width the arithmetic
never subtracted; the column is now a named, fixed 76 points, the format label shrinks rather than
widens it, and the rung is the largest whose two registers fit beside it. On the smallest phone that
is the third rung and not the first, which the tests had asserted; the first had only ever "fit" by
overflowing the screen, and the assertion now checks the sum against the width. Screenshots before
and after are in the session, not the repository; 600 client tests hold.

## The corners, the dots and the strike

The founder: the corners of the score buttons and "the dots" are ugly and not the brand; is the
strike-through the logo's, and is it accurate. **The corners** were `ChalkBox`'s 3 pt overrun —
each rule running past the corner as a "drawn, not stamped" tell, which on thirty keys is a hundred
and twenty small crosses. The box now meets square at the corners (`defaultOverrun` 0; each rule
runs to the far edge of the one it meets so the corner is filled, not notched) and stays inside its
frame by its own reach including the roughness excursion, which the existing containment test now
proves without the overrun's slack. **The dots** were the three empty per-dart slots, each showing
a "·": three marks the app had made before a dart was thrown. An empty slot is an empty box.
**The strike** was the mark's own bar (`MarkGeometry.bar`, pointed both ends, 45°), so its shape was
right, but its weight was 0.085 of the cap, chosen by eye; the wordmark's Ø slash measures 0.130 of
the cap (`Ratios.wordmark.halfWidth` 0.065, read off Archivo ExtraBold). `ChalkStrike.thickness` is
now defined from that ratio rather than restated. The two struck-row call sites passed a guessed
64 and 72 pt width; the shape now takes the width of the rect it is laid over, and the cap height
from the text role (`ThroTypeRole.capHeight`, new — cap ratio × scaled size). 604 client tests.

## The local leagues, in the app (PD-033)

Three local leagues were found publishing on LeagueRepublic — Stockton and District Thursday Night
(three seasons, 14/16/18 teams), Stockton & District Monday Night Mixed (8), Redcar and District
(two divisions, 21) — and their JSON web services answer "upgrade to a Gold plan"; the public HTML
is readable with a browser user agent. `tools/pull_leaguerepublic.py` reads the standings pages
(team names, never the team pages that list players) and writes `services/api/seed/leagues/
teesside.json`, with 18 venues curated by hand from OpenStreetMap by team name and each link marked
as the inference it is. **V027** adds `competition.source_record` — append-only provenance for any
organisational row, `UNIQUE NULLS NOT DISTINCT` so an inferred tenure with no page is still one
record — a venue postcode with a check, and a league's night and short name. `Seed.kt` imports the
file idempotently by natural key: the same organisation in two leagues is one team (Thornaby F.C
has four affiliations), a secretary's existing team is adopted rather than duplicated, and a
secretary's home tenure is never replaced. `GET /v1/leagues` is the public front, read as
`app_read`; the Discover tab gains **Local leagues** — a map with one pin per venue and the teams
under each league, every venue line saying "(by name)" where it was inferred and every league
saying what it was read from and when. Hostile points found while writing it: the first idempotence
run re-inserted 47 tenure records because NULL pages never conflicted; the first adoption rule
could not find a secretary's hand-made team and invented a second Sun Inn. Both are tests now.
Neon (staging) is migrated to V027 and seeded: 3 leagues, 5 seasons, 6 divisions, 44 teams, 18
venues, 77 affiliations, 208 source records. 609 client tests; 92 schema properties; the HTTP suite
holds 29 properties. Three `tools/check_*.py` scripts gained `from __future__ import annotations`
so they run on the Mac's Python 3.9 as well as CI's.

## Discover, rethought; the set-up screens made one screen; the brand on the paper side

The founder's second pass on PD-033 and the Play flow: a map nobody could touch over a long static
list; a set-up screen that scrolled and a ready screen that was one button in a field of paper;
"around here" said to somebody in Brighton; and no recent pass had moved the brand identity.

**The paper side gets the board's vocabulary** (`ThroDesign/Slate.swift`): `ThroSlate`, a
board-coloured panel with the lamp's three stops and the chalk dust; `ThroMark`, the Ø drawn from
its measured geometry; `ThroFixtureSlate`, two names either side of the mark with the format in
chalk boxes; `ThroBottomAction`, a screen's one decision pinned on a hairline; `ThroChoiceRow`, a
labelled choice on one line. `SegmentedControl` stops being the system pill with the numbers filed
off: the chosen segment is a block of the brand green with chalk text on a paper trough, the same
statement the primary button makes, and it changes on every screen that uses it at once.

**Match setup** is one screen: the two seats side by side, one row of known names that fills the
empty seat, four choice rows, Continue pinned. `MatchSetupLayout` holds the arithmetic and a test
holds it under the iPhone SE's height at the default text size (it scrolls only when Dynamic Type
makes it taller than the phone). **Match ready** is the fixture on a slate filling the screen, the
legs so far under it when there are any, Start pinned.

**Discover** opens on a slate that says what is around the player and how it knows. Location is
asked for on that slate and nowhere else (`Nearby`, while-in-use, read once per grant, never sent
to the server: distance is a subtraction done on the phone from the coordinates the server
publishes). With a location the leagues are ranked nearest first with miles on the right; when
the nearest is beyond 40 km the slate says "Nothing near you yet" and how far the nearest is; with
location off it says so and offers the button, disabled rather than vanished. Under it: leagues,
open tournaments (`GET /v1/events`, new: open access, public venues, no person), and the player's
own teams. **Local leagues** is a map you can use: pins are small boards with the mark, tapping one
opens the pub on a slate — postcode, distance, the sides that play there, a Directions button into
Maps, and the line that says it was matched by name where it was; tapping a team in the list takes
the map to its pub; the list folds by league, open on the one you came for. Every control has a
press state and a tap target (`check_controls_react` found four that did not, in the first cut).

**Per-dart keypad** runs 20 down to 1 as the founder set it (PD-034 amended; 1-to-20 with the big
five nearest the thumb was recommended and not taken).

## The mark made solid, the wordmark on Home, players you can remove, friends by code

The founder saw two darker bites in the mark where the dart met the ring on Match setup and Match
ready. Ring and bar were wound opposite ways, so a path made of both summed to zero winding at the
crossing and the non-zero fill left a hole. `MarkGeometry.mark(at:)` now winds the bar the same way
as the ring (its corners reversed when their signed area disagrees) and every mark — the slate,
the pins, the flights in the opening — is one solid thing; a test holds the crossing filled.
`ThroWordmark` draws THR in Archivo ExtraBold and the Ø as the mark at the wordmark's measured
ratios, live, and Home's masthead is the logo rather than a font's Ø.

**People** on a phone can be removed: the person's page ends in *Remove from this phone*, with a
dialog that says what it does — the name comes off the list; the matches stay, because they
happened; the next time the name is typed it starts a new history.

**Friends** (PD-035, V028): a code given in person, adults only, ended never deleted; routes
`/v1/friends`, `/invite`, `/accept`, `/{id}/remove`; `PUT /v1/me/profile` takes `ageBand`. The
account screen asks *I am 18 or over* once and offers Friends; the Friends screen shows the code on
a slate big enough to read across a table, shares it, takes one, lists who you have, and shows the
server's own sentence for every refusal. Tests: FriendsTest (2), HTTP 31 properties, 618 client.

## You as the profile, and pins that gather

The You tab opens on a slate that is the account: who you are, your age band, how many friends,
with FRIENDS and ACCOUNT on it — or, signed out, the door in. The old "not in this build" note that
said the app had no network code came off; it had stopped being true. The account screen can be
opened straight on Friends. On the leagues map, pins closer than a thumb's width at the current
scale gather into one marker with a count, and a tap zooms in until they come apart; clustering
is deterministic so markers do not shuffle between frames. Tests: FriendsTests (7) drive the
store against a scripted server and assert every refusal arrives as the server's sentence;
clustering has its own; 626 client.

## The Team OS reaches the phone: start a team, fill it by code, see the roster

Plan §6's first rows over the wire (PD-036, V029): `POST /v1/teams`, `GET /v1/me/teams`,
`GET /v1/teams/{id}`, `POST /v1/teams/{id}/invite`, `POST /v1/teams/join`, all through the domain's
own factories (`Organisations`, `Relations`) so a team started from a phone is the same rows a
test writes. A roster names a member only where `identity.player_may_be_disclosed` says so; the
rest are counted. On the phone, Discover's *Your teams on THRØ* lists the connected teams above
what the phone keeps on its own; a team's front is a slate with the code on it for whoever runs it,
the seasons it plays in and its roster with a line explaining anyone unnamed; *Join or start* is
one screen with two doors. Tests: TeamsTest (start, code, join, expiry, private, disclosure), HTTP
34 properties.

## A home for the team, a slate for the result, an honest Live tab

`GET /v1/venues` finds public venues by name; `POST /v1/teams/{id}/home` sets a team's home by id
or adds a new venue by name and town, closing the old tenure and opening the new — one second on
when the change lands in the same second as the last, because a tenure must last longer than
nothing and the domain's check says so. The team front's admin sees *Home venue · Set/Change* with
a search over THRØ's venues and a way to add one. The match result now lands on a slate — outcome,
score, names — in place of the paper card. The Live tab's note no longer claims the app has no
network code; it says the server streams a match and this build does not yet tune in. HTTP 35.

## The ledger strikes like a chalkboard, the fixture sits square, and 329 leagues take the map

**The scores columns.** The founder: *"the scores list on either side of competition screen doesnt
do that cool strike through like they do on the telly and pubs."* It did not: every remainder in the
column was drawn the same, and the only strike was the scraped-out row of a retraction. Now the
column does what a chalker's hand does — each remainder that a later visit wrote over carries **one
line through it and stays legible under it**, and the one figure with no line is what is on the
board. The line is `ChalkStrike` at a new `boardAngle` of eight degrees; the Ø's 45° slash, laid
through every old remainder in a 24 pt column, climbed into the neighbouring rows and read as
hatching, and a retraction's scrape at 45° across a whole row had been scraping the rows above and
below as well. Both marks take the hand's angle; the retraction stays in the board's colour so the
two things look like two things. `ThroLedger.standing` and `isSuperseded` hold the rule; LedgerTests
(6) hold it, including that a retracted row is never the standing one and the row before it stands
again.

**The fixture slate** on Match setup and Match ready — *"the text & symbols inside the box aren't
central."* Measured on the simulator, the names sat 13 pt below the slate's middle: the row took the
text line's height, which keeps room above the capitals for accents and below for descenders, and
the padding was equal round that invisible room rather than round what is seen. The names row is
now exactly one cap height tall with the capitals on its bottom edge (the same guide `ThroFigure`
uses), the mark's ring sits on the capitals' own centre, and the mark is sized from the cap height
rather than a fixed 36 or 56. The ready screen's footnote no longer breaks a line at "self-".

**Leagues beyond Teesside** (PD-037, V030). `tools/pull_leaguerepublic_directory.py` reads the
LeagueRepublic darts directory — 329 leagues in the British Isles with the position each gave it and
its web address — into `seed/leagues/directory.json`; a league now has a point and a website of its
own, and the importer finds a league by its address as well as its name so Stockton Thursday, listed
under a shorter name, gets its point and not a twin. `GET /v1/leagues` lists a league with no season
(a LEFT JOIN where there was a JOIN) and carries `latitude`, `longitude` and `website`. On the phone
a league with no pub placed is measured from its own point; Discover shows six leagues — nearest
first, or the ones with teams first when it cannot measure — and *All N leagues on the map*; the
map opens round the player and the five nearest pins, draws a league as a ring without the dart,
says under it that its teams are not on THRØ yet, and offers *ITS WEBSITE*; the sections under the
map are the leagues with teams, with a line counting the rest. Nothing on any of it is a person.
Tests: SeedTest (4) imports the directory twice and proves the count, the point on every row, the
absence of a twin and of any person; client 636 (LedgerTests 7, placed-league pins, shortlist).

**TestFlight.** A second archive from the Mac stopped where the first did — *No Accounts* — so the
runbook's Mac section is now the click-by-click the founder asked for, from the Xcode menu to the
Organizer.

## The app asks once, on the board: sign-in after the opening (PD-038)

The founder: *"sign in should be at the loading page before main screen ... need a beautiful way to
do this that matches our brand identity. google signin doesnt work either. need to sign in to be
able to see the beautiful you profile view."*

**The screen.** `WelcomeScreen` sits between the opening and the app, under the opening's own layer
so the dart resolves *into* it rather than cutting to it. It is a `ThroBoard`: lamp at the top, chalk
field, the wordmark at 1.3× display cap height on a `ChalkRule`, one headline in the sport face, one
sentence naming what an account is actually for — a team's lineup (V029), a league's register (V014),
a friend by code (PD-035) — and three ways in drawn as `ChalkKeyStyle` keys, the same control the
keypad is made of. Apple's key carries the Apple mark, as a custom Sign in with Apple button must.
Signing in dismisses it without a second tap; *Not now, just score* dismisses it for good. Four tests
hold the rules: asked once and only where there is a server to ask about, the door out worded as a
choice rather than a dismissal, the body selling only what THRØ has (no rating — OD-001), and the
local-first promise asserted verbatim so the day match upload ships, the test fails and the sentence
has to change with the behaviour.

Two layout defects were found by looking at it on the phone rather than by reasoning: five equal
`Spacer`s put a hole in the middle of the screen (now three groups and two flexible gaps), and
`.ignoresSafeArea()` on the content cut the top off the wordmark under the Dynamic Island — `ThroBoard`
already bleeds its surface to every edge while keeping content inside the safe area, which is the
distinction that exists because the scoring rail once sat under the island.

**Google sign-in was not broken.** Driven on the simulator it reaches Google's own consent sheet and
then *Sign in to continue to THRØ*, so the OAuth client, the reversed-client-id redirect, the PKCE
exchange and the server's audience are all correct; the staging routes verify both providers rather
than answering 503. What failed on the founder's phone was the build **installed** there: signed
before the App ID had its capabilities, so Sign in with Apple died with
`AuthorizationError Code=1000` and the whole sign-in surface looked dead. Rebuilding against the
corrected App ID fixes it, and the errors still on the Signing & Capabilities tab are stale — the
profiles on disk now carry `applesignin`, `associated-domains` and the app group, and Xcode's
capability cache refetched at 460 kB against the 25 kB stale one it had been answering from.

Counts: client 640 (four on the welcome), every repository check, 92 schema properties.

## Sign-in actually signs in: the nonce was never sent

The welcome screen shipped and the founder used it, which is how three defects that had been in the
build since accounts landed finally got seen. Every way in failed, each differently.

**The nonce was generated, handed to the provider, and thrown away.** `AccountStore` made a fresh
nonce for each ceremony and gave it to Apple and to Google; both put it in the token they returned —
Apple the SHA-256 of it, Google the value. `ThroAPI.signIn` then posted `idToken` and `deviceId` and
nothing else. The server's rule (`IdToken.verify`) refuses a token that carries a nonce when the
request supplies none, because a token replayed from elsewhere carries one too, so **every Apple and
Google sign-in was rejected** with *"the token carries a nonce and the request did not say which"*.
`signIn` takes the nonce now and sends the raw value; the server accepts either it or its hash, so
one field serves both providers. The route's own schema had documented this field from the start.

**`?mode=developer` on the associated domain made passkeys impossible for anybody but a developer.**
That flag tells the phone to fetch the association file straight from the domain rather than through
Apple's CDN, and it is **ignored unless the phone has Settings → Developer → Associated Domains
Development switched on** — which no TestFlight tester will have. Staging was serving
`/.well-known/apple-app-site-association` correctly the whole time, with the right app id and content
type; the phone simply never asked. The entitlement is the plain form now.

**And the errors were domains and codes.** The screen showed *"The operation couldn't be completed.
(com.apple.AuthenticationServices.AuthorizationError error 1000.)"* — no cause, no action, and an app
admitting it has not thought about the case. `SignInProblem.words` turns each into a sentence that
says what to do: an Apple failure names the Apple Account to check, a passkey on an unproven domain
says Apple and Google still work rather than being a dead end, an offline phone is told it can still
score, and the server's own sentence is passed through untouched because it is better than anything
this layer could write. Four tests hold it, including that no bundle identifier and no error code can
reach a player's screen.

**The welcome was recomposed and given an entrance.** It centred one block and left a hole above and
below it; a board is written top-down and the keys belong under the thumb, so the heading is chalked
at the top and the choices sit at the bottom. The entrance is the app's own gesture rather than a
borrowed effect: the wordmark appears, a line of chalk is **drawn** across the board under it
(`ChalkRule.trim`, animated — the component was built for this and nothing had used it), and the
heading and the keys arrive after it on their own beats. `throLanding` was deliberately not used;
that one is the impact of a dart and belongs to the outcome of a match. Under Reduce Motion
everything is simply there. A failure is now boxed in chalk rather than floating as loose red text.

Counts: client 644, every repository check.

## One way in, reachable more than once

The welcome is asked once ever, which is right, and it meant that a player who had answered it —
including the founder, who tapped *Not now* after the three sign-in errors above — could never see
it again, and the next launch went straight to Home. **SIGN IN on the You tab opens the same board
now.** It used to open a settings list of buttons under a paragraph; there is one way in and it is
the good one. The door out is worded for how the screen was reached: *Not now, just score* after the
opening, *Back* when it was asked for. Answering it either way answers it for the launch ask too.
The full account list is still what a signed-in player gets, and is still under Settings for the
create-an-account-with-a-passkey path that the board deliberately does not carry.

`docs/runbooks/TESTFLIGHT.md` also gained the thing that was only ever in this session's scrollback:
**the one-line command that builds and installs onto the phone over Wi-Fi**, which is how every
build in the last hour got there. The phone is paired and reports `transportType: localNetwork`, so
no cable is involved and neither is App Store Connect.

## Your profile, a picture, and the door out (PD-039, V031)

**Deleting an account.** THRØ had no way out, which is a legal problem and an App Store one
(guideline 5.1.1(v) rejects an app that can make an account and not delete one). V031 adds
`identity.erase_account`, a `SECURITY DEFINER` function that destroys the name, the age band, every
Apple, Google and passkey credential, every session on every device, the device labels, the live
friendships and any unspent friend code, the claim on the competitor row and the consent record —
and keeps the matches, because a leg is the other player's record too and after the erasure it
carries a competitor id that resolves to nobody. Redaction rather than DELETE, because DELETE is
revoked from every app role by ADR-013 and that is the reason the guarantee is worth anything.
`DELETE /v1/me` is the route; four tests hold it, including a **sweep of every text column in the
identity schema** for the person's name and provider subject, and one that the service still cannot
reach a credential's subject any other way — the argument the narrow function was chosen on. The app
lists what goes and what stays before it asks, and asks again with the consequence rather than *Are
you sure?*.

**Your profile.** Setting a name was You, SIGN IN, scroll, a row, a text link, a field, Save: seven
steps for two words, and no picture at all. It is one screen now — the mark at 96 pt, the name in
the sport face directly under it on a chalk rule, both edited where they are read, and the name
committing when the field is left rather than under a Save button. A picture uses the store the club
badges already use and the rule they already obey: adults only (PD-014), with the two refusals
written as the two different facts they are, one of which the person can change. It is kept **on
this phone** — THRØ's server stores no image of anybody — and the screen does not pretend otherwise.

**The welcome, again.** Still boring, and it was three identical rectangles above a hole. Two keys
now, because almost everybody arrives with Apple or Google and a passkey is PD-030's fallback, so
the third became a quiet line. A second chalk rule closes the board at the bottom, drawn from the
right as the top one is drawn from the left, so the composition is ruled the way a scoreboard is.
The slack is shared between the two gaps instead of being dumped below the sentence.

**A defect of mine, found and undone.** Writing the new tests to `ProfileTests.swift` overwrote a
file of that name that already existed and held eleven tests on a club member's page. The count
check caught it — the total went DOWN by four after seven tests were added — and the file was
restored from git with the new tests moved to `AccountProfileTests.swift`. The two profiles are two
different things and now have two different names.

Counts: client 651, API 26 suites, HTTP 37 properties, schema 92.

## Signed out means it asks

The welcome asked once and remembered the answer for ever, so somebody who had tapped *Not now* —
the founder, having just been shown three sign-in errors — never saw the sign-in board again, and
the app looked like it had lost it. *"Log In doesn't appear when loading app when signed out!!!"*

**The rule is now the obvious one: signed out means it asks.** It appears after the opening on every
cold launch while there is no account, and one tap is past it. `answeredThisLaunch` is `@State`
rather than `@AppStorage`, so nothing is written down and the next fresh start asks again — which is
right, because signing in is the thing THRØ needs a person to have done and somebody with no account
has not done it. It is still not a wall: everything works without it and it does not return for the
rest of that run.

One new guard came with it. `AccountStore.state` begins `signedOut` because nothing has looked yet,
so the naive version would have flashed the sign-in board at an already-signed-in player on every
single launch. `AccountStore.settled` says whether `start()` has finished, the root now calls
`start()` as the app comes up rather than waiting for somebody to open the account screen, and
`Welcome.shows` refuses to ask until the answer is actually known. A test holds both halves.

## Delete actually deletes, and your profile is one tap from You

**Why it did not work: 411.** `DELETE /v1/me` was deployed and reachable; the body guard in front of
every route required a `Content-Length` on any method that was not GET, and a DELETE carries no
body, so every correct caller was answered *Content-Length is required*. The guard now treats GET
and DELETE as bodyless — a body that IS sent is still measured twice, which is what the rule was
written for — and an HTTP property holds that a bodyless DELETE is never refused for having no
length. The phone also sends `{}` now, so erasure works against the server that is deployed today
rather than waiting for the next deploy.

**And why it looked like nothing happened.** `AccountStore.eraseAccount` signed the phone out
whatever the outcome, reasoning that a phone acting signed in to an account that has gone is worse.
True — but the account has NOT gone when the erasure fails, and signing out took the screen showing
the error off the screen with it, so a failure was indistinguishable from a success. A failure now
puts the state back where it was, still signed in, with the reason on the page. The wire layer
forgets the session only on 401 and 409, which are the two answers that mean it really is over.

**The journey.** Reaching your own name ran You → Settings → a long scroll → *Account and profile* →
*Your profile*: five steps, on the tab called You. The slate's second button says **PROFILE** and
opens the profile. Two taps to your name, your picture and the way out.

## Erasing worked only while the token was fresh, and the dart was metal over chalk

**"Doesn't work every time" was a missing refresh.** `eraseAccount` reached for `send` with the
bearer directly instead of `authorised`, which is the one call on this client that refreshes an
access token and tries again. Access tokens are short, so erasing worked immediately after signing
in and answered 401 an hour later — and that 401 was then read as *already gone*, which signed the
phone out and left the account standing. It goes through `authorised` now, so a stale token is
renewed and the delete goes through; a 401 that survives the refresh really is a dead session.
`NetTests` scripts the whole sequence (401, refresh, retry) and asserts the three paths in order,
and a second test asserts a failed erasure leaves the session alone so the error stays on screen.

**The grey line through the Ø.** At the lower-left crossing the mark showed a seam. It was not the
ring: it was the dart. A dart is drawn as a dart — a far flight shaded green under chalk, a shaft a
shade under full chalk, a hairline collar, knurl and grooves in the barrel — and all of that is
right against the board and wrong across the mark's band, which is pure chalk. Anything darker laid
over it reads as a line through the Ø.

The material now resolves with the dart, and **the ring closing is what resolves it**, not only the
wordmark morph: the ring is whole a beat before the wordmark begins, and that beat is where the seam
lived. The dart keeps its metal through three quarters of the ring being drawn — all of the part
anybody watches, the two fronts racing round — and becomes chalk over the last quarter as they meet.
By the time the bar and the ring are one shape they are one colour, and two shapes of one colour
cannot show a join. `DartInk` holds the rule and six tests hold `DartInk`.

## The server can receive a match (PD-040, V032)

The Play tab has said *"sending results to THRØ is not built"* since the app shipped. The server side
of it is built now.

**`POST /v1/matches` takes the journal, not a summary.** Every row the device wrote, in `deviceSeq`
order, visits and the retractions that struck them. A retraction becomes a `VisitRetracted` event
whose `corrects_event_id` names the visit it undid — a new word for the stream-ownership trigger and
nothing else, because `event_type` carries no CHECK and `corrects_event_id` has named a superseded
event since V006. It is a different act from `VisitCorrected`, which is an official's correction by
somebody not playing, and giving one the other's name would make an audit read as though an official
had been standing in a pub.

**Idempotent by construction rather than by cleverness.** `evidence.event` is unique on
`(match_id, device_id, device_seq)`, so the same upload twice is the same rows and a phone that lost
signal half way sends the lot again and only the missing half lands. A test sends two thirds, then
all of it, then all of it again, and counts the rows each time.

**The other seat is a competitor nobody has named.** On a phone the opponent is usually a local name
and nothing more, so THRØ mints an unclaimed `competition.player` and stores no name for them at all
— through `competition.mint_competitor`, a `SECURITY DEFINER` function, because `app_match` owns the
evidence schema and handing it standing INSERT on `player` would let the thing that writes visits
invent people whenever it liked. The same reasoning that gave erasure its own function in V031.

**And it arrives self-reported.** One player's word until the other confirms it (PD-011), recorded
on the match rather than on each visit, and set in the INSERT rather than by a later UPDATE because
`app_match` may append to evidence and may not rewrite it.

Six tests hold it, including that **nothing lands at all when one row is impossible** — half a match
is a record of something that did not happen — and that somebody else's match is not yours to add to.
HTTP 41 properties, API 26 suites, schema 92.

Still to come on the phone: reading the journal into that shape, the control that sends it, and the
Live tab tuning in to the stream the server already publishes.

## And the phone can send one

`MatchUpload` turns a match's journal into what the wire takes: every visit and every retraction, in
`deviceSeq` order, with the struck visit **sent rather than filtered out** — that is the whole of
PD-040 in one behaviour, and a test asserts it. Nothing on the phone remembers how far a previous
attempt got, deliberately: the server is unique on (match, device, deviceSeq), so sending the lot
again adds only what is missing, and a phone that kept its own high-water mark is a phone that can
be wrong about it.

It refuses rather than lying in three cases, each with its own sentence: a match that was **retired
or abandoned**, because the server has no event for an ending yet and uploading the visits alone
would leave THRØ holding a record that says the match is still going; a row written by a **newer
build**, which would have to be guessed at; and an **undo whose visit is not in the record**, caught
here so the reason names the record rather than reading as a fault in THRØ.

The control is on the Live tab rather than the result screen, because `ThroPlay` has no network
target — the rule that keeps scoring working with no signal — so the one place with both the journal
and the account is the app shell. **Which seat was yours is answered by your own name**: a local
match is two names typed at an oche, so if neither is yours THRØ says so and does not guess, because
a match filed under the wrong player is worse than a match not filed at all.

Counts: client 668, API 26 suites, HTTP 41 properties, schema 92.

## Delete that deletes, a launch that knows who you are, and the account area on the board (V033, PD-041)

Three things the founder said on 2026-09-11, all of them true: *"still won't let me delete full
account"*; *"Loaded me to home screen and when i checked profile tab it said checking, shouldn't load
past the checking screen until checked in"*; and *"the spacing on settings page is really ugly &
design is too colour palette & style, branding & design needs to be aligned throughout our E2E
journey."*

**Delete had a defect on each side.** On the server, V031's `identity.erase_account` spent every unused
friend code against the account being erased (`used_by = a`), and V028's trigger
`friend_actor_is_adult` refuses exactly that row — *a code is for somebody else*. So nobody who had
made a friend code and not handed it over could be erased: the function raised, the erasure rolled
back as it should, and the server answered 500. The founder's own account on staging was that account
— one code, made at 09:29 and never used — and `ErasureTest` had only ever made a code somebody then
used. V033 drops the step, because the door it closed is shut twice already: the trigger refuses any
use of a code whose maker is erased, and `Friends.accept` now refuses one first, in words that do not
say why (*"That code no longer works"*). V033 also pins `search_path` on both SECURITY DEFINER
functions. A new test reproduces the founder's account exactly — Apple and Google, three sessions, an
adult, one unused code — and fails without V033. Neon was migrated to V033 and the founder's erasure
was run inside a transaction and rolled back: it goes through (2 ways in, 3 sessions, 1 claim, 1
consent), and the account was untouched afterwards.

On the phone, every change to the account set the store to *busy*, and every screen about a signed-in
person is shown only while the store says *signed in*. So the delete screen left the screen the moment
the erasure began, the 500 was reported to a screen that no longer existed, and the founder landed back
on their profile with the account intact and nothing said. `AccountStore.working` now carries what is
happening to a signed-in account while the state stays `signedIn`, a failure lands in `problem` on the
page that asked, and the root holds the profile it opened (`ProfileOpening`) instead of re-reading the
account on every pass. The delete screen stays up through the erasure and, once the server answers,
reads back what it destroyed from the server's own counts before anybody leaves it — a person who
exercised a right is owed an account of what was done with it.

**A launch that knows who you are.** Knowing who was signed in took a round trip to a free server that
sleeps, so a signed-in person reached Home with the You tab saying *Checking* for up to a minute — and
offline, for as long as the signal stayed away. The phone now keeps the last profile THRØ gave it for
the held session (`KeychainProfileCache`, beside the session in the keychain), so a signed-in person is
themselves from the first frame; THRØ is asked behind it and can only correct it — a new name, or a
session it no longer honours, which signs the phone out and forgets the person. A cached profile for
anybody else is never shown. Only a phone holding a session and no profile for it has to wait, and then
the opening holds on its last frame — *Checking your sign-in* — offering *Just score* after four seconds
and saying why after eight (PD-041). The welcome asks `holdsSession` rather than `isSignedIn`, so an
offline launch never asks a signed-in person to sign in, and `AccountHolder` relays the store's changes
to the root, which decides the welcome, the hold and the profile route and used to notice a change only
when something else happened to redraw it.

The first build of the hold held for ever, and it was the simulator that found it rather than a test:
the closure that ends the throw is scheduled at `onAppear` and carries the copy of the view made then,
so it read *holding* as it was then. The account answered in a tenth of a second, `onChange` fired while
the dart was still in the air and did nothing, and 4.4 seconds later the throw came to rest believing
nobody had answered. It reads a `@State` mirror now, which even a stale copy of the view reads through
its storage.

**The account area, on the board.** Every screen in it now opens on the brand field with chalk on it —
Home's masthead — and lists its rows on raised cards, each icon on a tile of the brand, sections
`spaceSectionGap` apart (`AccountDesign.swift`); the section titles had been sitting on the hairline of
the row above, which is the spacing the founder saw. Settings opens on whoever is signed in, on the
slate; the ten rows under it are eight, in three groups, with the build as a line at the foot. Your
profile puts you on the field — your mark, your name in chalk where it is changed, and who sees it — and
the You tab opens on the same field with you on it, rather than on a slate under a system title bar. The
field runs under the clock on Home, You, Settings and your profile alike, so the opening, the welcome and
the app are one green from the first frame. Friends, the inbox and events open on the same header, and
Settings moved into its own file. The build page still said *Sending results to THRØ: Not built* after
PD-040 built it; it says *From the Live tab*. A Debug build launched with `-ThroScreenshotAccount` stands
up a signed-in account over a transport that answers from memory, so the signed-in screens can be seen in
a simulator that cannot sign in to anything; a Release build does not contain it.

Counts: client 682, API 26 suites, HTTP 41 properties, schema 92.

## A match that ended short is sent as it ended (PD-042, V034, V035)

PD-040's upload refused a retired or abandoned match: the server had no event for an ending, and the
visits alone would have left THRØ saying the match was still going. **The ending is now an event.** The
phone's retirement or abandonment row (PD-016) is sent last, like the rest of the journal, and the server
stores it as `MatchEndedShort` on the match stream — the same role and the same device sequence as the
visits before it. The payload says how it ended and, for a retirement, which seat retired; the winner is
the other seat and is not stored, because a stored copy of an inference is a second thing that can
disagree with the first. **Nothing is added after it**: a trigger refuses a visit, a retraction or a
second ending for a match that has ended, except a row the stream already holds — an upload is resent
whole, and `ON CONFLICT DO NOTHING` has to be reached for the resend to land as nothing. An official's
correction and the trust events are still allowed; they are about the record, and an ended match is when
they happen. The upload refuses the same things first, in words: a row after the ending, a second ending,
a retirement that names a person rather than a seat.

**V034's CHECK let NULL through, and the schema properties caught it the first time they ran.** It read
`ending = 'abandoned' OR (ending = 'retired' AND seat IN ('home','away'))`: a retirement with no seat
makes the second half NULL, the whole expression NULL, and a CHECK passes on NULL. The upload never sends
such a row — it checks the seat itself — which is why no Kotlin test could see it. V034 had already
reached staging, holding no ending rows, because my chained command took `grep` finding the failure lines
for the properties passing; the chain now reads the properties' own summary before it migrates anything.
V035 replaces the constraint forward with one that cannot be NULL (`IS NOT DISTINCT FROM`, and a missing
seat is false), and a new property holds an ending that says nothing at all.

The phone: `MatchUpload` sends the ending. The refusal and its sentence are gone, and the test that held
the refusal was replaced by three that hold what replaced it. `ThroAPI.Sent.ending` reads the server's
answer and is optional, so an older server still decodes; a person is told *"Sent 12 visits, 1 undo and
the retirement."* The result screen still said *"Sending results to THRØ is not built yet"* after PD-040
built it; it says where to send it.

Counts: client 684, API 26 suites, HTTP 41 properties, schema 96.

## Nobody signed in could watch a match, and now a new visit arrives on commit (V036)

Reading the stream end to end before building live watching on it found that no signed-in person could
ever have watched a match. The route narrowed its connection to the match role and **then** asked the
authenticator who the caller was — and the production authenticator resolves a bearer token against the
identity schema, which the match role cannot see at all: *permission denied for schema identity* is what
that role gets for the query today. The route's one test used the development principal, which reads
nothing, so it stayed green for the route's whole life. Identity is read first now, under the role every
other request starts with, and only then is the connection narrowed; a new test signs in for real and
watches.

The same reading found the grant door open too wide. `Grants.roleFor` answers what was ever issued —
revoked, expired, or scoped to a different event — which is right for stamping a command and wrong for a
door. The stream asks `liveRoleFor` now: in force, and for a grant that names no match, only on its own
event's matches. And an open stream asks again once a minute whether its watcher may still watch, so a
revoked grant or an ended session closes it rather than lasting as long as the connection (ADR-007's
re-authorisation, which the first version did not do).

**ADR-007's LISTEN/NOTIFY, built (V036).** An insert into the evidence log notifies `thro_match` with the
match id, delivered on commit; one connection in the server listens while anybody is watching and wakes the
streams of that match. The notification is a hint to re-read and never the transport — a woken stream reads
the log exactly as a polling one does, and every stream still polls once a second beneath it — so a
listener that is down costs latency and nothing else. It holds its connection only while somebody is
watching, because a connection held open all day would keep Neon's free compute awake for nobody. With the
poll set to thirty seconds, the test's new visit reached its watcher in 3 ms.

Two slips of mine on the way, recorded: the latency test's second visit was the same seat's, which the
engine rightly refused, and the check had no message, so it failed as *"Expected value to be true."*; and
my command moved staging to V036 on the schema properties alone while the Kotlin suite was red. V036 only
adds a notification the deployed server ignores, so it was harmless — the gate now needs both.

On the phone: the team front was one slot loaded only while it was empty, so after opening one team,
opening another showed the first. It now knows which team it holds and loads the one it is asked for, with
two tests. The team code's share text sent people to a Discover button named something else.

Counts: client 686, API 26 suites, HTTP 41 properties, schema 96.

## The other player takes their seat with a code, and answers for the result (PD-043, V037)

A match sent from a phone named one person and a competitor THRØ minted for the other seat, and stayed
one player's word with no way for the other player ever to answer. **Now the sender makes a code for the
other seat** — eight characters, seven days, one use — and the other player enters it on their own phone.
That records a **seat claim** (`competition.seat_claim`), not a claim on the minted competitor: the other
player already has a competitor of their own, an account holds one live claim, and nothing under the match
is rewritten. The match still names the competitor it was sent with; the claim says whose seat that was.
Then the other player **confirms or contests** the result: `ResultConfirmed` or `ResultContested` on the
trust stream, naming the seat, written as `app_trust` — the first route to write as that role, so the HTTP
test's role property now requires that role as well as permitting it. The sender cannot answer for their
own match, and an abandoned match has no result to answer for.

**Where a match stands is read, never stored.** `GET /v1/matches/{id}` and `GET /v1/me/matches` replay the
record through the engine with struck visits left out, take the winner from it or from a retirement, and
derive the standing — self-reported, confirmed, disputed, or recorded for a match scored live — from the
answers. **An answer stands only for the record it answered**: when the sender sends more of the match
after an agreement, the other player is asked again, because agreeing to two legs is not agreeing to
three. A seat shows a name only through the disclosure gate, so an age THRØ does not know shows none —
held by a test that signs two people in, one of them an adult who has said so.

**Entering a code is rationed** — the match code, and the friend and team codes too, which were not. A
code opens something, so guessing one is the attack; the allowances are separate from signing in, so a
run of mistyped codes costs nobody their sign-in.

On the phone, the Live tab has **On THRØ**: every match this person has on THRØ with where it stands —
*Your word*, *Needs your answer*, *Confirmed*, *Disputed* — and a page for each, with the score on the
slate, the code drawn as the friend code is, and Confirm and Contest for the other player. **Enter a code**
is there for somebody who was given one, and the share text names that button. Sending a match reads the
list again, so the code is one tap from the send. A name is the server's where it may show one, else the
name typed for that seat on this phone at the oche, which is this phone's own to show back.

Four things found on the way. `ThroJournal` already had a `MatchRecord` — the local match — and a second
one in `ThroNet` would have made every use in the app ambiguous, so the server's is `MatchOnRecord`.
*Claimable* first meant "held by no account", so a sender whose competitor had no account read their own
seat as up for grabs; it now means a code could be made for it — the seat opposite the sender, of a sent
match, that nobody holds — and a reading test caught the first version. **The stream's notifier had a
start-up race** (V036): a watch started the listener and returned at once, so a visit that committed in
the milliseconds before the new connection said LISTEN reached nobody, and its watcher sat out the poll.
The latency test failed on its second full run; a watch now returns once the listener is listening, and a
new test fires a notification the instant each of ten brand-new listeners begins. And an apostrophe inside
`${r:-…}` in the schema properties opened a quote in bash and broke the rest of the file; it is reworded.

Stale words retired: the README's *It talks to nothing* (it talks to staging), its two decisions called
open (PD-030 and PD-043 closed them), Live as *Not started*; the runbook's paragraph saying nothing is
uploaded, and its Settings line saying sending is not built, which the screen stopped saying at PD-040;
and `render.yaml`'s *not built yet*.

Counts: client 699, API 27 suites (58 tests), HTTP 45 properties, schema 106.

## The other player follows the match as it is scored — and two things that had never worked (PD-044)

**Live, for the two players.** On the Live tab, under a match still being scored, *Share it live on
THRØ*: while it is on, the phone sends the match's journal as it grows — PD-040's upload, whole and
idempotent, every three seconds while there is something new — and it stops itself once the match is
over and all of it is up. The other player, having taken their seat with a code (PD-043), opens the
match under On THRØ, and its page is the board: what each side needs, their legs, who is throwing and
the last visit, replayed on their phone through the same engine from the stream's events, with
*Connecting*, *Live*, *Reconnecting* or *Not following* as the stream is. The stream's door now asks for
a seat claim as well as the two competitors, the grants and the officials; every event carries its own
`eventId`, so a retraction's `correctsEventId` names a visit the watcher holds; and the summary's format
says who threw first, which a replay needs. Nobody else can watch: no spectators, no friends (PD-035).

**Two things found on the way had never worked, because nothing had run them end to end.**

**No phone had ever sent a match THRØ would take.** The Live tab's send wrote the legs mode as
`String(describing: legsMode).lowercased()` — `bestof` or `firstto` for the engine's two cases — and the
server parses `best_of` and `first_to`, so every send since PD-040 came back *"that match format is not
one THRØ can read"*. The upload's own tests built their wire by hand, and the HTTP test posted
`first_to` itself, so none of them could see it. `MatchUpload.format(for:)` spells the server's words
out, the send and the live share both use it, and a test holds both modes.

**The phone's match stream could never have delivered an event.** It read `URLSession.AsyncBytes.lines`,
and that sequence drops empty lines — fed a wire holding three, it yielded none — while an empty line is
what ends a server-sent event. It was found by feeding the sequence a wire in a script before building the
screen on it. `SSELineSplitter` keeps them, with a test; the same client now reports its health, which
its doc had always promised and it never did, and renews an expired access token once rather than ending
a watch at the first 401.

Counts: client 712, API 27 suites (59 tests), HTTP 45 properties, schema 106.

## The team's admin names the captain and vice-captain (PD-045)

The Team OS row after starting a team and filling it by code. On a team's front the admin taps a roster
entry's role and makes them captain, vice-captain, or a player again — one of each at a time, so naming a
new captain makes the old one a player. A change ends the membership row and opens another, because who
captained the side is the team's history (V014), and the captain's `team.manage` relation — the one the
command path asks for a lineup or a rearrangement — is granted with the captaincy and revoked with it. The
admin's front carries each entry's handle, the membership's own id and never a person's; a public front
and a member's carry none, which a test holds.

A change is never recorded at or before the row it ends began. The HTTP test's clock does not move, and
the first version would have ended a membership at the instant it started, which the table refuses; it is
recorded a microsecond after the start at the earliest, and a test turns the clock off to hold it. And one
ordering in the HTTP test mattered: the property that names a captain runs after the one holding that a
player may not set the team's home — a captain may, so run first it would have made that property false.

Counts: client 713, API 27 suites (60 tests), HTTP 46 properties, schema 106.

## The leagues are a board over a map, in a chalk for each league (PD-046)

The founder asked for the map to say which league a team is in when it is chosen. The screen is now the
map, full-bleed, under a board that rises from the bottom (`ThroDrawer`, with round `ThroCoinButton`s for
back and where-am-I). Each league with teams is drawn in its own chalk, from six new tokens that the
contrast gate measures against the board's worst ground — 82 pairs became 94, and the README says so
because the gate reads it. A pub's pin (`BoardPin`) is ringed in an arc of each league's chalk that plays
there. Choosing a team writes its name and league over its pub, chalks its division from it as dotted
lines on a dark band so they read on either map, and puts a card on the board: league and division in
the league's chalk, where and when, whether anybody plays for it on THRØ (read off its front, which the
server serves for a league's team — confirmed on staging), its division nearest first, its page, and
joining by a code.

What the board knows is `LeagueAtlas`: pure, built once per load, and tested — a team's league line, the
teams at a pub across leagues, a division nearest pub first with the unplaced last, a search for teams and
pubs whatever the case or accents, and leagues by name including those with no teams. Its sentences are
`LeagueBoardWords`, tested beside it. `LeaguesPlot` stays as it was and gains `region(covering:)`, which the
pin version now calls. `ThroDrawer`'s drag direction is `ThroDrawerDrag`, declared outside the drawer: a
type nested in a generic is a different type for every content, so a handler naming
`ThroDrawer<EmptyView>.Drag` pinned every drawer it was handed to `EmptyView`.

Two defects: a roster entry THRØ may not name drew "Ap", the initials of "A player", and now draws the
person glyph; and venues matched from OpenStreetMap now carry the credit its licence asks for, which a test
holds. Discover's "Your teams" rows say a team's league when it is in one. The screenshot account passes the
public front's reads — leagues, events, venues — through to the real server, so the board can be looked at
with the real leagues on it.

Looked at in the simulator against staging, and four things changed for it. The team card's page and
directions come before its division, so neither is under the drawer's fold. A rival named for its pub —
the Starting Gate, at the Starting Gate — says its town under its name rather than the same words twice.
A season a league names with a sentence ("Redcar Darts League 2026") is left off the line beside the
league's own name. And the board never reads a front that is not the chosen team's: the screenshot stage
had answered every team as the account's own, so a stranger's side said "You play for it" — the stage now
passes other teams' fronts through to the server, read as nobody, and the board checks the front's id.

Counts: client 731, API 27 suites (60 tests), HTTP 46 properties, schema 106, contrast 94 pairs.

## The card that leaves the phone is a board with the result chalked on it

The founder, with a card from their own phone: *"this can be massively improved. For a start it doesn't
even have the actual logo in top left it's using text symbol instead of actual."* It did: the card set
"THRØ" in a font and letterspaced it, where every other surface draws the wordmark from the mark's own
geometry. It carries `ThroWordmark` now, and the mark again as the stamp in its corner.

The rest of the card was a flat green panel. It is the app's board: the lamp, the field and the chalk
dust — but drawn in brand pigments, because the board's own tokens flip with the phone's appearance and
a card must be one picture whoever drew it. The result is a scoreboard rather than a sentence with a
number after it: each name stands over its own legs, the winner's in chalk and underlined in a stroke of
chalk, the loser's rubbed back, and the names are no longer said twice. The figures sit in a chalk box
whose label can no longer be cut short — "3-DART AVER…" was the label squeezed between two flexible
columns, and it keeps its own width now. How the result is verified is a tag an eye lands on, in the
chalk of what it says, with the sentence that says it in full underneath: the tag is decided by the same
branches as the sentence, so a confirmed tag can never sit over a self-reported one.

Every rule the card already kept, it keeps: the verification sentence, the sample in visits and legs, a
figure only where both players have one, and no scoreline for a match nobody won. `Copy` gained the legs
as numbers, so the view no longer has to read them out of "3–0".

One test was watching the wrong thing. It held that the card renders at the size it claims — which a
blank rectangle also does. The card's colours are an asset catalogue, and a build that has not compiled
one resolves every colour to nothing: four preview renders of the new card came out white before that was
noticed. The card is now held to being a picture of something — distinct colours, an opaque ground, and a
ground greener than it is red — and it skips where no catalogue is compiled rather than passing on a
picture it cannot see.

Counts: client 733, API 27 suites (60 tests), HTTP 46 properties, schema 106, contrast 94 pairs.

## A player says a listed team is theirs, and runs it on THRØ (PD-047, V038)

The board shows a player their own side and then offered nothing: a team read out of a league's pages has
no members, so there is no code to give the side and no roster to fill. Now the team card offers *It's my
team — I'll run it*, and the player becomes its admin.

Only a team THRØ read from a league's pages — a row with provenance (V027) — and only one nobody runs.
The first to say it takes it; the second is refused and told to ask that person for the code. Adults only,
through `competition.player_is_adult`, a SECURITY DEFINER function in the shape V037 set for `seat_of`: the
competition role may ask that one question about a person, nothing that reads a team may ask it at all, and
an age nobody has said answers false, as does a player no live account claims. Eight teams to a player,
because a club secretary runs several sides and a script should not run fifty.

The adoption is a row of its own — who, when, and the only basis there is, *said so themselves* — kept and
never rewritten, keyed by the team so two people saying it in the same moment end with one adopter and one
refusal without a lock held over the team. Nothing about the team is rewritten: it keeps the name and the
pub the league published. The front carries `adopted`, and both the team's page and the leagues board say
it in those words: run on THRØ by one of its own players, by their own say, nobody appointed them.

Counts: client 733, API 27 suites (61 tests), HTTP 47 properties, schema 115, contrast 94 pairs.

## The twenty-league pilot asked honestly and was refused (PD-048)

The founder chose the pilot: twenty leagues, read slowly, by an importer that gives its own name. It got as
far as the first request. `robots.txt` answers 200 to a client calling itself THRØ, and allows exactly the
pages the pilot wanted — the league's front page and its `/fg/` standings; fixtures, matches, players and
live are disallowed and were never wanted. Every content page then answers **403 from CloudFront**,
generated at the edge: *Request blocked*. The sites serve browsers and refuse everything else, and the tool
that worked in September worked because it called itself Safari.

So the pilot stopped there, which is what PD-048 said it would do. No league page was read and nothing was
seeded. The email to LeagueRepublic now carries the evidence and one more question: whether an identified
THRØ agent can be allow-listed at their CDN. Until they answer, teams reach the map through the players who
play in them (PD-047).

Two things in the importer were fixed before any of that, because a twenty-league seed would have exposed
both. A team already recorded by hand was matched by name and `locality IS NOT DISTINCT FROM`, so NULL
matched NULL — and every league the directory places has no locality, which means the Red Lion in Halifax
would have become the Red Lion in Burnley on the second import. No locality now means no match, and a test
holds two same-named teams apart across two leagues. And a league was found by name before its web address:
the address is the league, two leagues can share a name, and the order is now the other way round.

Counts: client 733, API 27 suites (62 tests), HTTP 47 properties, schema 115, contrast 94 pairs.

## A team says which league it plays in (PD-049, V039)

The map lists 329 leagues and three of them have teams, because teams come from a league's own published
pages and those pages are shut to a reader that gives its own name (PD-048). So the other direction, which
needs nobody's permission but the team's own: on the team's page, its admin or captain says which league it
plays in, picked from the leagues THRØ already lists, and the league's board fills from the people who play
in it.

It is carried as a say from end to end. `competition.team_league_claim` sits beside `team_affiliation`, not
in it: saying it gives the league no season, no division and no affiliation, and a test holds that. The
public front carries `saidTeams` beside `seasons` and never inside them; the team's page carries
`saysItPlaysIn` beside what the league published about it; the atlas marks the entry `said`, so a chosen
team's line reads *"Hartlepool Sunday Darts League · said by its players · Sunday nights"* and the league's
card puts them under their own heading with the sentence that says the league did not list them. A pub a
said team plays at is drawn in that league's chalk, which is how a league whose pages we cannot read gets
onto the map at all.

Withdrawable and kept: a team moves leagues and a captain mistypes, so a claim is marked withdrawn rather
than deleted — who said their team played there in September is still true of September — and saying it
again afterwards is a new claim with its own date. One live claim per team and league; a side may say it
plays in two, because sides do.

Counts: client 734, API 27 suites (64 tests), HTTP 48 properties, schema 124, contrast 94 pairs.

## The queue nobody could open (PD-050), and where THRØ runs (PD-051)

The safety kit landed with three of its four legs standing: anything a person wrote could be reported,
anyone could be blocked, and accepting the terms was recorded with the version accepted. The fourth leg —
**somebody answers** — was written and reachable by nothing. `Safety.queue()` and `Safety.decide()` existed,
had tests, and had no route, which is a promise to Apple and Google that was quietly not being kept.

Closing it needed an authority THRØ does not have: there is no staff, no admin role, and an event's officials
are officials of that event alone. So the people who answer reports are **named at boot**, in
`THRO_MODERATORS`, and both routes refuse everybody else; a server that names nobody refuses everybody, and
says so on every start. A table was the obvious alternative and is the wrong one — a list in the database is
a list somebody holding a session can eventually add themselves to, and this queue holds what people said
about each other. Answering a report that does not exist is now a 404 rather than a foreign key's 500.

**The terms travel with the profile.** `GET /v1/me` carries the version in force and whether this account has
accepted it, so the phone can hold somebody at the agreement before their first public word without a second
request to find out. Both fields are optional on the client's `Profile`, deliberately: the phone keeps the
last profile it was given, and a required field would stop a cache written by an older build from decoding at
all — a signed-in person shown as nobody because the terms had changed since they last opened the app.

**Two defects of mine, both found by tests rather than by looking at anything.** The first was blunt:
`TestDatabase` drops every schema a migration creates, its list did not know about `safety`, and 65 of 68
Kotlin tests failed on tables that survived the reset. The second is the better lesson. `Safety` is handed a
clock and used it for a report's hour but not a block's, leaving `blocked_at` to the column's
`clock_timestamp()` default — so a test that blocked at a fixed hour and lifted a minute later was lifting a
block the database believed had been made today, and `lift`'s own `AND ? > blocked_at` guard silently matched
no row. **A class handed a clock must use it everywhere or it has not got one.** That guard is gone as well:
V040's `a_lift_comes_after` already enforces the ordering, and a guard that turns a nonsensical lift into a
silent no-op is worse than a constraint that raises — somebody asked to be left alone no longer, nothing
happened, and nothing said so.

On the phone, a team's page now carries **Report this team**, because a team's name is the whole of what a
stranger sees of it and the way to say that name is wrong belongs on the page carrying the name, not in a
settings list somebody would have to already suspect exists. **Blocked** sits beside Friends on your own
page, since blocking is the other half of who may reach you, and the row reads "Anyone you never want to hear
from" until the list has been opened: nothing is fetched to put a number on a row a person may never tap.

**Where THRØ runs (PD-051).** The founder asked what Cloudflare costs and what the best arrangement is for
iOS, Android and the web, then added Apple Watch, the Android equivalents, and the television. The first
answer is that **Cloudflare cannot run this API at all** — Workers is a V8 isolate with no JVM, and Hyperdrive
is reachable only from inside one, so "move to Cloudflare" is a rewrite wearing a hosting bill. What it can
do (DNS, CDN, the free WAF ruleset, Turnstile, Tunnel, R2) costs nothing at our size. The rest is in
`docs/product/PLATFORM.md`: Fly London beats Render at every size, Supabase Pro beats Neon's paid curve at
launch because a pool that holds connections never earns a scale-to-zero discount, GitHub's macOS runners are
now effectively free at thirty builds a month, and every surface from the watch to Android TV is laid out with
what each would take. About $15 a month now, $40 at a thousand players, $142 at ten thousand. Neither move is
made: both need a card, and the card is the founder's.

One thing the research said we would have to build turned out to be built already. Behind Cloudflare a live
stream must heartbeat and resume or the proxy cuts it mid-leg; THRØ's pings every fifteen seconds and resumes
from `Last-Event-ID`, and `StreamTest` holds both.

Counts: client 737, API 28 suites (68 tests), HTTP 49 properties, schema 135, contrast 94 pairs.

## A league table is arithmetic, and the rules that order it are the league's (PD-054, V041)

The founder asked how league data gets processed and presented back to the people in the league: tables,
leaderboards, the lot. This is the table.

**It is computed on every read and stored nowhere.** `OrganisationTest` has long asserted that no table in
`competition` has "standing" in its name, and that is the guarantee being kept: a table that is arithmetic
over the fixtures beneath it cannot drift from them, cannot be edited into disagreeing with them, and cannot
be left behind by a corrected result. V041 adds one function that counts — `competition.league_tallies` —
and `Standings.kt` applies the league's rules to the counts and orders the rows with the ranker that already
existed in the pure package, so a league's table and a group's table cannot come to disagree about what a
point is worth.

**The live outcome of a fixture is not a column**, it is the one nobody has superseded with the voids
excluded, and that predicate was already written three times across V014, V021 and V022 — only the last of
which excludes voids. This was about to be the fourth copy. It is written once now.

**The rules are the league's, and the table says whose they are.** PD-054 is the founder's decision and it
was both halves: THRØ has a standard — two a win, one a draw, ordered by points then leg difference then
legs for — and a league may write its own, for the leagues that score by the leg or play double-in. The
condition that makes a standard safe is that it is never silent: every table names which policy ordered it
and whether that policy is the league's. OD-022 warned that a constant buried in a table calculation would
be THRØ deciding a league's rules without saying so, and the fault in that sentence is *buried*.

**A rule THRØ cannot compute is refused by name.** A league whose bonus point depends on each fixture's own
scoreline is told exactly that, and told what THRØ can do instead — because a table quietly missing a rule is
wrong in a way only that league would ever notice. The same goes for a policy naming a tie-break THRØ cannot
order by: the table is refused with the league's own word in the message, rather than quietly ordered by
somebody else's rules.

**Head to head is resolved as a mini-table, not as a pairwise question.** Three teams can each have beaten
the next, and a comparator built on that answers differently depending on the order rows arrive in — and on a
division large enough, Java's sort detects the contradiction and throws, which would have been a 500 on a
public route. The teams a chain leaves level are grouped, the fixtures among them are scored under the same
policy, and the comparison is between two numbers, which cannot cycle.

**What was missing turned out to be the results path itself.** Nothing in the codebase set
`league_fixture.match_id`, and V014 refuses a played outcome without it — so no played league result could
exist at all, only awards and walkovers. `citeMatch` and `recordPlayedResult` are the other half, and
`acceptAffiliation` is a third: `affiliate` left every team `applied`, and the tallies count accepted teams
alone. Three writers that were never there, found by trying to write a test that needed them.

**Two mistakes of mine, both caught rather than shipped.** The integration test copied its
`INSERT INTO evidence.match` from `MigrationTest`, which builds the pre-V018 shape on purpose — names, not
seats — so nine tests failed on a column that has not existed since V018. And the first expected order in the
standings test was simply my arithmetic being wrong: Riverside had drawn *and* lost, Feathers had only drawn,
so Feathers was second on leg difference and the table was right. That assertion now names the step that
separated each row rather than only the order, which is the form that would have caught me immediately.

Also here: the phone can read a table (`ThroAPI.standings`), and the JSON says `"whose":"league"` or
`"thro"` rather than a boolean called `leagues`, which read like a list of leagues. Settings' index got the
readable measure its own pages already had, and `Stage.swift`'s header stopped claiming THRØ is
iPhone-portrait-only — it has built for iPad and landscape for some time, and that comment is a fair part of
why thirty-three screens were written as though nobody would see them on a tablet.

And the audit's highest-leverage findings went in with it. **Five shared components truncated long names with
no scale factor**, which is dozens of screens from five files: an organisation row (the backbone of Discover,
You and every club page), a top bar whose eyebrow is a club or league name on a dozen screens, a player's
name on every roster, a button label that call sites interpolate club names into, and the league table's team
column. Each shrinks a little before it gives up now. The organisation row's meta — "Thursday nights · 18
teams · Stockton-on-Tees" — never fitted one line of a phone at all, so it wraps instead of shrinking to
unreadable.

**The league table's number columns were literals.** Seven of them, 212 points in total, which crowds an
iPhone SE and, worse, did not grow when the reader's text did — so a numeral at an accessibility size
overflowed a cell that had not moved. They scale with the text now. Adding the environment value to read that
size needed an explicit initialiser, because the file's own comment warned that a stored property would drag
the synthesised memberwise one private and break the two views that build the table — a trap already sprung
once, and documented, which is the only reason it did not spring twice.

Counts: client 737, API 29 suites (79 tests), HTTP 50 properties, schema 141, contrast 94 pairs.

## A league member can read the table, and every screen is a column

Two halves of the same night. The server could compute a league table and nothing showed one, and thirty-odd
screens were still drawn as though nobody would ever open them on a tablet.

**The table is on the league's own card**, in the board drawer, because that is where somebody looking for
their league already is — and it opens a screen that reads the season's standings from THRØ. It is drawn as
five things on a row rather than eight columns: the position and the name read across, the two figures that
decide the order sit at the end, and won-drawn-lost goes on a second line where it has room. Nothing on it is
a fixed width, so it holds at every text size and on every screen — a better answer than scaling a layout
that was wrong at both ends. Underneath, every time, the sentence that says whose rules ordered it and in
what order they were applied: *"Ordered on points, then leg difference, then legs won."* A step this build
does not recognise is printed rather than dropped, so a league that approves something a later server
understands is never handed a table quietly ordered by less than it asked for. Nine tests hold the words,
because the words are the part that can be wrong while nothing fails.

**The measure went from ten call sites to forty-three.** Every screen in the tab set, and the club, league,
tournament, team, match, account, profile, settings, welcome, readiness and safety screens, plus the Play
flow's setup, result and confirmation. What was left alone is now written into PD-052 rather than left to be
rediscovered: the scoring stage owns its width by arithmetic, the bars belong to the screen's edge, Home's
masthead floated when the measure was tried there, the announcement card is already capped at 340 points, and
a pinned footer is not content. One thing is still outstanding on purpose — the 400-point brand band behind
Home, You and your profile, which is 60% of an iPhone SE's height and covers a landscape phone entirely. It
is a visual constant, and the right number for it comes from looking at it on a device.

Counts: client 746, API 29 suites (79 tests), HTTP 50 properties, schema 141, contrast 94 pairs.

## The server was stricter than the phone, and wrong to be (PD-055, V042)

Building the league table turned up something the table itself could not fix. V014 admits a `played` league
outcome only where the fixture cites a real match, so a league on THRØ could award a fixture but could not
record that Grange A won it 5–2 on a Thursday from a paper card. The phone's own club book has always kept
both and held them apart — its constraint "refuses a scored result with no match and an official's word with
nobody's name". A secretary could therefore keep their season on a phone and not on the server, which is the
wrong way round, and it was put to the founder as a decision rather than patched around.

**A fifth outcome kind: a result declared by a named official**, carrying a scoreline and no match. It counts
in the table exactly as a played one does, because it is what happened. It is never evidence, because nobody
recorded it happening — and `decided_by` is already NOT NULL, so a declared result cannot exist without
somebody's name behind it.

**This is what made `evidenced` mean anything.** The column had gone into V041 as a straight copy of the
phone's — how many of a row's results came from a match scored on THRØ rather than somebody's word — and on
the server it was tautological: every played outcome cites a match by construction, so the count was always
the whole column. It was reported, in a shipped contract, telling nobody anything. With a declared result in
the world the distinction is real again, and V042's tallies count only the played ones.

**A fixture scored on THRØ cannot have a result declared over the top of it.** Where a match exists the
result is read from the match; an official declaring a different scoreline would be overwriting evidence with
a recollection, and superseding is what correcting a played result is for. A test holds the refusal by its
sentence.

The third option was the tempting one and is recorded in PD-055 as refused: invent a match from the typed
score so the foreign key is satisfied. It writes a match nobody played, with no visits, into the evidence
schema — the one place this codebase refuses to put anything that did not happen.

Counts: client 746, API 29 suites (81 tests), HTTP 50 properties, schema 144, contrast 94 pairs.

## A league can be run from THRØ, by whoever was named to run it (PD-053)

The founder asked for the admin side of things for league owners. The authority was decided earlier tonight —
a league's administrator is named and never self-appointed — but nothing in the server could act on it: the
writers existed in Kotlin and no route mounted them, and `Rules.DEFAULT` held exactly one league action.

Three routes now, all behind one new action, `league_season.administer`, granted the same way rearranging a
fixture already is: a relation on the season, held in `authz.relation`, decided by the same Authorizer and
audited by it, so a refusal is on the record beside the ones that were allowed. **Accepting a team into a
season** is the act that puts a side in the table, since only an accepted affiliation is a row. **Awarding a
fixture** goes to one of its two teams with a reason and never a scoreline. And **recording a result** does
the thing worth saying plainly:

> The caller does not choose what kind of result it is. The evidence does.

A fixture with a match scored on THRØ behind it records a played result; one without records the official's
declared word. A client cannot claim otherwise, because the server never asks it to — which is the only way
PD-055's distinction survives contact with a phone that could just as easily send `"kind":"played"`.

**Nothing here can grant the relation**, and that is the point rather than an omission. A test holds the
whole loop at the database: creating a league does not make you its administrator — the case worth holding,
because it is the one a reasonable person would assume — naming one lets them run it, and naming one names
one rather than everybody. On a fresh deployment every league-admin route refuses everybody, exactly as the
moderation queue does, and the runbook says how a name is added.

Counts: client 746, API 29 suites (82 tests), HTTP 51 properties, schema 144, contrast 94 pairs.

## Looking at it on a tablet, which is the only way this was ever going to be settled

Every layout change tonight had been compiled and none of it had been seen. The founder's standing note on
this work is *look in the simulator before calling it done*, so the app was built for an iPad Pro 11-inch and
opened.

**The measure holds.** Home and the Welcome both put their content in a centred column of about 560 points on
an 834-point screen, with the brand field and the board still running the full width behind it. That is what
the forty-three call sites were for, and it is doing what it was supposed to do.

**The tab bar spread, exactly as the audit said**, and reading the code had not made it real: five small
marks a hand's width apart along the bottom of a tablet. The bar is the screen's edge and keeps the width of
it; the five tabs are not, and they now sit in the same measure the content does, centred, with the bar's
paper and hairline still running the whole way. Built again and looked at again: the tabs cluster in the
middle and the bar is unchanged.

**And width turned out to be the easier half.** A tablet screen is also tall, and a phone's vertical rhythm
leaves long empty runs down the middle of one — most obvious on a screen whose state is empty. No measure
fixes that. It is recorded in PD-052 as the next piece of work and as a design question rather than a rule:
what a screen with room to spare should *do* with the room.

Two smaller things the session learned by looking. The 400-point brand band is harmless on an iPad, because
the page's own paper covers it from the header down — which says nothing about a phone in landscape, the case
the audit actually flagged, and that has still not been looked at. And `xcrun simctl openurl` raises an
"Open in THRØ?" confirmation the simulator will not dismiss without a tap, which is why two captures came
back as a flat green field before the cause was understood rather than explained away.

Counts: client 746, API 29 suites (82 tests), HTTP 51 properties, schema 144, contrast 94 pairs.

## THRØ on the web, because two things were already waiting on it (PD-056)

With everything buildable on iPhone and iPad done, the founder was asked which surface came next and chose
the web. It is also the one that unblocks the others: Google Play will not take an app carrying accounts
without a web URL for deleting one, and the organiser subscription is better sold off-store.

Three pages, no framework, no build step. The leagues THRØ knows, searchable by name or town. A league
season's table, from the same route the phone reads — so a table on the web and a table in the app cannot
come to disagree, and PD-054's condition holds in both: the sentence under it says whose rules ordered it and
in what order. And the deletion page, which says what the app says, word for word, because a page that
contradicted the app about what deletion destroys would be worse than no page.

**It is on brand without a design system in it.** `apps/web/tokens.css` is the generated token file, and
`tools/check_web_tokens.py` fails the build if the copy drifts — a static host serves a directory and will
not follow a link out of one, so a copy is the only shape available and an unguarded copy is how a brand
quietly forks. Everything else in the stylesheet is arrangement.

**The API is on the same origin**, which is a design decision rather than a convenience: the client calls
`/v1/...` with no host, the edge routes `/v1/*` to the API, and the browser never makes a cross-origin
request — no CORS, no preflight, no second host to configure. `serve.py` mirrors that locally, so what a
developer looks at is arranged the way the real thing is.

**And looking at it found two things reading it had not.** The leagues page reported *"undefined leagues"*
over an empty list, because `/v1/leagues` answers with an envelope and the first version took the object for
the array. Then, fixed, it said *"1 leagues"*. Both were found by opening the page against a real API with a
real league in it — a Stockton season whose three results were **declared** rather than scored, which also
put V042 on a screen: every row's evidence column reads nought, because a secretary's paper card is not a
match anybody scored on THRØ.

Counts: client 746, API 29 suites (82 tests), HTTP 51 properties, schema 144, contrast 94 pairs.

## A ridiculous amount of negative space, and what actually fixed it

The founder, on the tablet screenshots: *the designs should be utterly beautiful and engaging in our brand
style — we don't want a ridiculous amount of negative space.* They were looking at Play, where two thirds of
an iPad was empty grey.

**First, a way to look at any screen at all.** Every screen here is reached by tapping and a simulator driven
from a script cannot tap, which is why most surfaces were being changed unseen. `-ThroScreen tab/discover` is
a Debug-only launch argument that opens the app on a named screen through **the same parser a real link goes
through** (ADR-011), so it can reach exactly the screens a link can and there is no second grammar to keep in
step. Six screens were then looked at rather than reasoned about.

**The first fix was wrong, and was deleted.** A `ThroRoom` container centred short content in the room instead
of leaving it under the bar. Built, installed, looked at: worse. The same emptiness, redistributed — an island
with voids above and below. It is not in the tree.

**The second was right, and Settings had been demonstrating it all along.** Settings reads as designed on a
tablet because its content has body: rows in cards that fill the measure. Play's *how this works* was two
paragraphs floating on grey; it is a card with two icon-tiled lines now. You's *teams you keep*, in the empty
case, was a sentence and a loose button; it is a card holding both. `CardLine` learned to render emphasis the
way `Note` already did, so the bold in those sentences is bold rather than four asterisks.

**And the honest part.** Most of what is left is an empty state rather than a layout. Those screens are the
emptiest the app can be — nothing scored, no teams — while Discover fills its page with the map and Settings
with rows. The work here made *nothing yet* look like a decision instead of a page that failed to load; a
screen with something to say already fills. What a tablet should do with genuine spare room is recorded in
PD-052 as open, because it is a design question and not a rule.

Counts: client 746, API 29 suites (82 tests), HTTP 51 properties, schema 144, contrast 94 pairs.

## Every empty state in the app is a card now

Fifteen uses across eight files, one component. `EmptyState` drew its title, its sentence and its action on
bare paper, which on a phone reads as restraint and on a tablet reads as a page that failed to load. It is
the card surface every other card in the app uses now — the same raised fill, radius and hairline — so
*nothing here yet* looks like a decision. Home, the blocked list, a league with no results, a club with no
fixtures: all of them, from one change.

Counts: client 746, API 29 suites (82 tests), HTTP 51 properties, schema 144, contrast 94 pairs.

## The other half of a league's own data: its fixtures (PD-056)

A table says how a season stands; it does not say what is left. `GET /v1/seasons/{id}/fixtures` is the rest
of it — every fixture with its date, its lifecycle, its venue, and what it finished as where it has — read
from the same rows the table is, so the two cannot disagree about a result.

**A result says how it was arrived at**, which is the distinction V042 exists for: *scored on THRØ* where a
match sits behind it, *the league's word* where an official declared it, and awarded or walked over where
nobody played. The web page prints exactly that, so a league member reading a score can see what is standing
behind it without knowing anything about the schema.

**Public means public, and a hole in a calendar is not privacy.** A team or venue marked private is not
named. The fixture is still listed, with the private side simply unnamed — the same answer the app gives for
a player who may not be disclosed. A test holds both halves: the fixture survives, and the name does not
appear.

One thing the schema caught, which is the sort of thing it is for: the test set a team private with a plain
UPDATE and the trigger refused it as a stale write, because every write to a team advances its row version.
The test obeys the same rule as the store rather than sidestepping it.

Counts: client 746, API 29 suites (83 tests), HTTP 52 properties, schema 144, contrast 94 pairs.

## A league secretary, a laptop, and the week's results (PD-056, PD-053)

The routes to run a league went in earlier tonight and had nobody to call them: an administrator is named
out of band, and the app has no screen for it. The web does now.

**Signing in is a passkey.** The API already speaks WebAuthn, and a redirect flow on a static site would mean
a client id, a callback page and a third party in the round trip. A passkey needs none of that — the browser
holds the key, the server holds the public half, and the exchange is two requests to our own origin. The
session lives in `sessionStorage` and goes when the tab closes, which is the right default for a shared
laptop in a pub back room.

**Entering a result is two boxes and a button**, and the page does not say what kind of result it is. It
sends the legs; the server reads whether a match was scored on THRØ and records *played* or *declared*
accordingly (PD-055). A client cannot claim otherwise because it is never asked.

**Proven end to end through the web's own origin**, with the dev principal standing in for the ceremony: a
post before the grant is *"You do not administer this league season"*; the same post after the relation is
granted returns `"kind":"declared"`, because that fixture had no match behind it; and a second result on it
is *"This fixture already has a result. Correcting one is a new decision that supersedes it."* The authority
model, the evidence rule and the supersede rule, all three, from the outside.

**What is not verified**: the passkey ceremony needs a human with a device, so the signed-in view has not
been seen in a browser. Said plainly in the web README rather than left to be discovered.

And the dev server learned to proxy more than GET, which is how the first attempt failed — it answered 501
to the very POST the page exists to make, and a developer chasing that would have gone looking in the API.

Counts: client 746, API 29 suites (83 tests), HTTP 52 properties, schema 144, contrast 94 pairs.

## Buying the domain is one command, because doing it by hand would break passkeys

The founder's constraint, plainly put: the free arrangement is for a handful of testers, and *"adding the
domain is what kicks it all into gear."* Making that true needed one correction and one tool.

**The correction.** PD-056 put the app and the browser behind one name, with `/v1` rewritten from the static
site to the API. Right for the browser, wrong for the app: it puts a CDN in front of the live match stream,
and a CDN that buffers `text/event-stream` is how a live match dies silently (ADR-007). So with a domain
there are two names — `thro.uk` serves the pages, `api.thro.uk` serves the app — and **one relying party
covers both**, because WebAuthn lets an origin assert a relying party that is a registrable-domain suffix of
itself. That is the whole value of owning the domain, and it is unavailable on Render's free subdomains at
any price: `onrender.com` is on the Public Suffix List.

**The tool.** `tools/host.py` holds the four values that name a host to one of two legal arrangements and
switches between them. It is not a convenience. A find-and-replace at launch sets the relying party to
`api.thro.uk`, which works silently for everyone who has no passkey yet and permanently separates the
website's credentials from the app's; it also drags `render.yaml`'s rewrite destinations, which address the
API service and must not move. Both mistakes were perturbed into the check and both are caught, along with a
forgotten file, a `www.` prefix, and a name under `onrender.com`. The round trip is the identity, and a bare
run is registered in CI, so a half-finished switch fails the build rather than reaching a tester.

**And a thing to say out loud rather than discover:** a passkey is bound to its relying party, so every one
registered under the old host dies at the switch. Sign in with Apple does not — a native app's audience is
the bundle id, not a host. Hence the guidance for the testing period, now written where a tester's account
depends on it (PD-058, `docs/runbooks/GOING_LIVE.md`).

## A result could be entered and never corrected, and the page said otherwise

The organiser page shipped with this sentence: *"A result already in is corrected by a new decision that
supersedes it, which this page does not do yet — the app and the API can."* Neither could. The database has
taken `supersedes_outcome_id` since V014 and the store has passed it since PD-055, but no HTTP route ever
did — so a mistyped 5–2 was permanent, and the 409 telling you to supersede it named a capability that
existed nowhere. A claim of absence that was wrong in the generous direction, which is the harder kind to
notice.

Both writing routes now take the `outcomeId` of the result being replaced, and `seasons.fixtures` carries it
so a page can name what it is correcting. Naming it is not ceremony: the V042 trigger refuses a correction
that leaves another live outcome unaccounted for, so two officials with the page open cannot overwrite each
other — the second is told the result changed while they were typing rather than being silently discarded.
The two 409s read differently because the handler knows which case it is and the trigger does not.

**And a second fault fell out of it.** Every reader treats a voided outcome as no result; the writer counted
it as one. So a voided fixture sat in "still to enter", and entering a result was refused as *"already has a
result"* — about a result the page could not show and therefore could not offer to correct. V043 gives the
trigger the same definition of "live" that the tallies and the fixture list have always used: a void annuls,
the fixture is open, the next decision is a first one. Proven by a test written before the migration, which
failed with exactly that message.

Verified rather than assumed: the correction form was driven in a browser against stubbed data, and it sends
`{"legsHome":4,"legsAway":2,"supersedes":"…"}` for a correction and no `supersedes` for a first result;
an awarded fixture opens with empty boxes rather than the string "null"; and the stale-correction 409 renders
as the note, with the button re-enabled so it can be retried after a reload.

Counts: API 29 suites (86 tests), schema 148 properties.

## The brand field was a portrait number, and looking at it gave a negative result

PD-052 left one thing open deliberately: the 400-point brand field, *"60% of an iPhone SE's height"*, whose
right number *"comes from looking at it on a device."* It has now been looked at, on an iPhone 17 Pro in both
orientations.

**The number was a portrait assumption wearing a constant.** 400 is the answer to how far a page can be
dragged before paper shows above the field, measured upright; in landscape that phone is 402 points tall, so
the field was the entire background. It is now `min(400, height × 0.7)` — every portrait phone unchanged to
within two points, no screen ever covered — with four tests over the four phone sizes THRØ runs on.

**And the honest part: the change is not visible.** The old constant was restored, rebuilt, and photographed
beside the new one on the You tab in landscape. In both builds the green stopped where the page's own card
stopped — 156 points in one state, 245 in another — never at 400 and never at 281. The pages paint their own
paper over the background, so the field only shows during a pull. The iPad finding holds for a landscape
phone: harmless, because the content covers it. Kept anyway, because a background larger than its container
is wrong whether or not something is currently hiding it, and recorded as a negative result rather than
written up as a fix for a problem that was not there.

**What landscape did show is worth more.** On You in landscape the sign-in prompt takes 61% of the screen's
402 points and the content beneath it gets the rest; on Home the masthead takes 29% before the first card.
These are portrait proportions on a screen that is not portrait — the same finding as the tablet one, in a
second place. Not fixed here: what a masthead does when the screen is short is a design decision, and it is
PD-060's open question rather than a default to fall into.

Two smaller things the session learned by looking. `xcrun simctl` cannot rotate a simulator, so rotation goes
through the Simulator app's own Device menu — and with three devices booted the menu acts on whichever window
is frontmost, which is why the first two rotate attempts appeared to do nothing. And screenshots of a rotated
device come back in the portrait framebuffer, so taps are still in portrait points while the image is
sideways; the conversion is what made the second attempt land.

## A phone on its side, made a case THRØ is good at rather than one it survives

Put to the founder with three options and a preview of each; they chose to **compress the masthead** and said
landscape should be a case the app is good at — people prop a phone beside a board, and the scoring screen
has put the keys beside the board in landscape for some time, so the promise was already made.

The masthead folds below 500 points of screen: the mark and its line on one row at the heading2 cap, stacked
at the display cap above it. Every phone is 320–440 on its side and 568–956 upright and a tablet is 834, so
the threshold has forty points either way and a tablet keeps the full mark. The rule is arithmetic in
`ThroDesign`, the same shape `ThroStage`'s beside-or-stacked choice takes; the view reads iOS's vertical size
class because it cannot measure the window, and **a test holds the two to the same answer on every device**,
because two ways of saying one thing is how a rule becomes two.

Looked at, not assumed: Home's green band goes from 116 points to 51 of the 402 there are, and Continue —
which was off the bottom of the card — is on the screen. Portrait is pixel-identical, checked against the
capture taken before the change.

**And it found something worse on the first screen of the app.** The welcome is a fixed composition with no
scroll view, on purpose. On a phone on its side it did not fit and SwiftUI clipped both ends: the mark off
the top, and *"Not now, just score"* — the control that gets a player past sign-in — off the bottom. There
was no way to decline sign-in on a landscape phone. It now scrolls only when it does not fit, by giving the
column the viewport height as a minimum: the spacers expand as they always did, portrait is unchanged to the
pixel, and a short screen scrolls instead of losing its ends.

What a tablet does with spare room is untouched. Folding a masthead buys back a strip on a screen with too
little; it says nothing about a screen with too much, and that stays PD-052's open question.

Counts: client 755 tests (178 design), all 22 checks.

## One thing, one column; two things, two columns

Put to the founder with three options and a preview of each, and they chose two columns where a screen earns
them. `ThroSpread` decides it from the width available, in the shape `ThroStage`'s beside-or-stacked choice
takes. The threshold is derived rather than picked — a column must clear 340 points, which is an iPhone SE's
proven 280 with margin, so the narrowest spreading screen is the one that fits two of those and a gutter —
and the test that holds the rule to its own stated reason caught the first pair of numbers disagreeing
within a minute of being written.

**The app had no fixtures.** They existed on the web and nowhere else, so this added the model, the call
beside `standings`, and the column. The two load together because a reader compares them, and the fixtures
may fail on their own into a quiet note rather than taking the table down with them.

The words carry what the drawing cannot and are tested apart from it: an award never reads as a scoreline
(ADR-012), a declared result says "the league's word" because 5–2 cannot carry PD-055 by itself, a team THRØ
may not name is "A team" and not a blank, and a scoreline is spoken "5 to 2".

**And it was correct and unreachable.** On an iPad it stacked — the rule was right and the sheet it lives in
is 577 points, under the threshold, so a tablet got a phone page floating in the middle of a map. The
table's sheet is page-sized now; the two sheets beside it are single objects and keep the form width.

Two things this needed that are worth more than the feature. A Debug build now takes `-ThroAPIBaseURL`, so a
server-backed screen can be looked at against a local API instead of guessed at — staging holds no seasons,
which is why the table and everything under a league had gone unopened. And the local runbook now says
`serve` rather than `run`: `run` starts the playtest harness, which answers HTML to every API path and cost
a confused ten minutes.

Counts: client 770 tests (184 design), all 22 checks.

## Discover is two things as well, and the second one found the rule's sharp edge

The same treatment, on the split the screen already had in it: what is out there — the leagues near you and
the tournaments taking entries — beside what is yours. A phone runs them one after the other as it always
did.

Applying it twice is what taught it something. `yours` carried a section gap of its own to hold it off the
section above; beside `ThroBeside`'s gutter that became 64 points on a phone and pushed the right-hand
column 32 points below the left on a tablet. The gap belongs to whichever thing knows the arrangement, which
is not the half — a half that adds its own spacing is a half that cannot be put anywhere else.

Counts unchanged: client 770 tests, API 29 suites (86 tests), 148 schema properties, all 22 checks.

## Three files agreed perfectly about a host that does not exist

`tools/host.py` was written to stop a find-and-replace breaking passkeys at launch. Four commits later it
caught something else, and the something else was mine: a `--set thro.uk` run to exercise the tool got swept
into a later `git add -A`, and the repository spent an afternoon configured for a domain nobody has bought.
`Info.plist` pointed the app at `api.thro.uk`; the relying party was `thro.uk`. The check passed the whole
time, because **all three places agreed** — which is what it was asked to verify.

That is the gap. Internal consistency is not correctness, and a tool that can put the repo into an
arrangement can put it into the wrong one. So the check now asks whether the arrangement is *true*: if the
repo claims a domain, that domain has to resolve. A missing name and a missing network raise the same
exception, so a control lookup against `onrender.com` separates them — no network is a note and a pass, a
name that genuinely is not there is a failure that says so and names the fix.

Nothing shipped from the bad state: the app was only ever built against a local API through the Debug
override, and the API service on Render was made through the dashboard and does not read `render.yaml`. The
cost was an afternoon of a config that would have failed the moment anybody built for a device.

Also fixed here, from the same session's evidence: the web service in `render.yaml` had `autoDeploy: false`,
copied from the API where it is right because ADR-013 puts migrations before the code that expects them. A
static deploy runs no migration and cannot half-apply anything, so the web deploys itself now — with a build
filter on `apps/web/**`, because this repository commits often and almost none of it touches those files.

## A result can be annulled, and the fixture says why rather than going quiet

The founder chose annulment with a reason on show, over leaving it out and over requiring a second
administrator — the last of which is unusable in a league that has only ever named one, which is every
league on THRØ today. The store has had `voidOutcome` since V014 with nothing calling it; it has a route
now.

**The safety in this is the visibility, not the authority.** A voided fixture used to reappear among the
ones still to play, indistinguishable from one nobody had got round to, and a result that vanishes without
trace is how a league stops trusting its own table. So `seasons.fixtures` carries `annulled` — the reason
and when — and every surface prints "annulled, to be replayed — played under protest" where a fixture is
open for that reason. The old result stays, superseded.

Two things fell out of building it. `annulled` means *open*, and a first version kept reporting it after a
replayed result was entered — a fixture showing a scoreline and an annulment at once, caught by the test
written with it. And the new join was aliased `v`, which is already the venue: five tests failed at once
with "table name v specified more than once", which is the cheapest kind of failure there is.

Verified in a browser, not assumed: the organiser page refuses an annulment with no reason and **sends
nothing**, and with one sends `{"supersedes": "…", "reason": "played under protest"}` to `/void` with the
reason trimmed. A fixture open because it was annulled shows the reason where it is entered.

Counts: API 29 suites (87 tests), 53 HTTP properties, 148 schema properties, client 772 tests.

## The selected segment did not fill its own cell

First thing the polish pass turned up, and it was on every device. The chosen segment's green stopped short
of the top and bottom of its cell while the dividers either side ran the full height past it — a smaller
control floating inside a larger one, on the screen where a player picks 501 and best of five.

A `Rectangle` is greedy. The dividers are rectangles a point wide with no height given, so they take
whatever is offered; the segments carry a `minHeight` and no maximum, so they do not. The control grew to
whatever spare height the parent had and the selection stayed at the touch minimum. A phone had no spare
height to hand it, which is why this survived to an iPad to be seen.

The row reports its ideal height now instead of accepting what it is offered, and the fill may reach the
full height of its cell. The setup screen came in tighter as a side effect: four rows that were each about
twice their proper height are the right height.

**And the empty-state finding, which is not fixed here.** Home on an iPad with nothing scored is a small
card with 77% of the page empty beneath it; You is 56%, Play 54%. This is the emptiest the app can be, and
the earlier pass (PD-052) already made these read as decisions rather than failures by giving them cards —
on a phone. The cards did not transfer: a card that is 90% of a phone's width and a quarter of its height is
a notice in the corner of a tablet.

Centring was tried in that earlier pass and rejected — *"the same emptiness, redistributed"* — and a bigger
card is a bigger empty box, so neither is the answer. The diagnosis is now sharper than it was: **an empty
state that is the only thing on the page should not be a card at all**, because a card is a container for
content among other content. What it should be instead is a product decision and is going to the founder
rather than being guessed at, with the numbers above as the evidence.

## Annulling twice returned a 500, and only calling it twice would have found it

The annulment route was exercised against a real server rather than a stub, with the wrong thing on purpose:
no principal, no reason, nothing to annul, and then the same result annulled twice. The last one returned
**500**.

`outcome_supersedes_once` is a unique index stopping two decisions from both replacing the same one — a fork
in the chain nothing downstream could read. Right constraint, unmapped error. A correction never reaches it
because the trigger gets there first; an annulment does, because V043 keeps voids out of the live count and
the named result is already superseded. So the index threw raw.

It is the same 409 as every other stale write now — *"That result has already been dealt with"* — and the
correction path gets the same mapping behind its trigger. Two officials annulling the same result, or one
person pressing the button twice, are both ordinary; a 500 tells a league secretary the app broke when what
happened is that somebody else got there first.

**And the method is the point.** Nothing in the code looks wrong at any layer, so reading would not have
found this, and no test existed to fail. It took calling the route with the wrong thing twice. The seed that
made that possible is checked in now at `services/api/seed/demo_season.sql` — a season carrying a played
result, a declared one, an award, an annulment and four fixtures to come — because a full test run rebuilds
the local database and anything seeded by hand is gone by the next one.

Counts: API 29 suites (88 tests), 148 schema properties, client 772 tests, all 22 checks.

## A page with nothing on it is the board now

The founder was shown the measurements — Home on an iPad with nothing scored was a card with 77% of the page
empty under it — and chose the field over a hero and over leaving it.

`ThroNothingYet` is the board with the lamp above the middle, the invitation chalked under it and the action
as a chalk key, built from `ThroBoard`, `ChalkKeyStyle` and the on-board inks that already exist. **A
background has no size of its own to be too small**, which is precisely why it answers a question that a
bigger card does not, and why centring — tried and rejected in the earlier pass — never could. Home keeps
its masthead because that is already green, so the wordmark and the board read as one surface with a lamp in
it; and there is no scroll view, because there is nothing to scroll.

It is a state and not a size: identical on a phone, checked on both.

Applied only where a page has nothing at all — Home with no matches, no archive and no problem. Play and You
have content and are short, which is a different problem, and this does not pretend to solve it.

Two things the first build got wrong, worth writing down: `ChalkKeyStyle` sets no ink, because a keypad key
inherits the board's, so the label came out near-black on lit green; and a keypad key is full width because
it is one of twenty in a tray, so one invitation read as a bar until it was sized to its own words. Both
were found by looking at the crop, not by the build failing. `check_controls_react.py` caught a third before
any of that — a `.buttonStyle(.plain)` with no pressed state — which is why the chalk key is the app's own
rather than one rolled by hand here.

Counts: client 772 tests, all 22 checks.

## Two columns need two things in them, and one of the two pages did not have them

The two remaining short pages were put through PD-062's rule. One holds conditionally, one does not hold at
all, and the failure is the useful half.

**Play was reverted.** It looked like two things — what you do, and how it behaves — and split cleanly, and
then it was looked at: the void got *bigger*. Halving the height of the content on a page whose problem is
that it has little content leaves more empty page, and it cut the one primary button on a screen whose job
is *start a match* to half width. Play was never stacked-when-it-should-be-side-by-side; it is just short.

**You splits only when its left column has somebody in it.** It genuinely is two things — the people on this
phone, the teams kept on it — and on a tablet where nobody had played, the teams sat to the right of an
empty half. A hole where content should be reads as a page that failed, which is worse than a page with one
thing on it. `ThroBeside` takes `split:` now and the caller answers: SwiftUI cannot ask a view whether it is
empty, and a container that guessed would guess wrong.

So the rule gained its missing half. Two columns need two things that are **both there** and **comparable in
weight**. Width is necessary and not sufficient. The league table beside its fixtures and Discover's *out
there* beside *yours* both pass; Play failed on weight and You could fail on presence.

Counts: client 772 tests, all 22 checks.

## Match ready was a phone-shaped box on a tablet

Found by playing a match through on an iPad rather than by reading anything. *Match ready* is a fixture on a
slate that holds the screen, and it was also held to the 560-point reading measure — so it held a tablet's
height at a phone's width and drew a portrait-phone-shaped green box, 430 by 800, with three lines in the
middle of it.

The measure is for prose. A slate's subject is two names either side of a mark, which is width, and PD-052
carves out precisely this case. It uses the width now, capped so a 13-inch tablet does not get a wall. At
834 points it is about square and reads as a board with the fixture chalked on it. A phone is unchanged.

**And the scoring screen was looked at and left alone.** Head at the top, keys at the bottom, a large field
between: that is `ThroStage` doing what it is specified to do, and the space between is the board's own
surface rather than a void. Recorded so the next pass does not rediscover it as a fault.

Counts: client 772 tests, all 22 checks.

## The scoring screen looked clipped on its side, and was not

Scoring a match on an iPhone 17 Pro in landscape, the bottom looked cut: the ledger and **ENTER SCORE** both
seemed to run off the edge. The app's core screen, in the orientation just committed to, so it was chased.

The device was not in `StageTests`' list — the simulator this project is developed against, which is the only
reason a doubt about it could not be settled by running the tests. Added, and the sixteen stage tests pass.
Probing deeper: beside the board the tray clears the height by exactly **1.0 point**, which looks like luck,
so a stricter assertion was written to turn the suspicion into a failing test. It failed everywhere including
an iPhone SE — which is how the assertion, not the layout, was shown to be wrong. Beside the board the tray
is given the whole height on purpose and clears by whatever the key height's rounding leaves.

**And it cannot clip**: the screen passes `GeometryReader`'s own `proxy.size`, so the stage measures the room
it actually has rather than an inset modelled from published figures. Flush is flush. The fragility that a
one-point margin implies would be real if the height were modelled, and it is not.

Kept: the device in the list, and a note where the assertion would have gone. Not kept: any change to the
stage, which was right. Recording a negative result costs a paragraph and saves the next person the hour.

Counts: client 772 tests, all 22 checks.

## Every place anyone looked was right, and the binary still had no entitlements

Sign in with Apple failed on the founder's phone. The App ID had every capability ticked, the caches were
cleared, the app was reinstalled, and it failed again — with `AKAuthenticationError Code=-7026` and
`client is not entitled` for the app group.

**The `Personal` build configuration signs against an empty entitlements file, and the scheme's Run action
uses `Personal`.** Pressing ▶ in Xcode produces a build with no capabilities at all. The file was correct
when written — a free Apple team cannot sign those three — and its own comment predicted these exact
symptoms, down to "Google still works". It stopped being correct at enrolment: `Personal` carries the paid
team now, and the entitlements file is the *only* thing left that differs between it and `Debug`.

Fixed by pointing `Personal` at the real entitlements and deleting the two empty files. All three
configurations build.

**Why it survived two investigations:** everything anyone reads says the right thing. The repository's
entitlements are right, the App ID is right, the profile is right, and `check_app_group.py` passed
throughout — it holds the group's name in agreement across three places, which it was, and never asked
whether the configuration being run grants it. The single wrong artefact is a build setting pointing at a
second file.

And the PD-074 diagnostic changed to suit. `SecTask` is macOS-only, so there is no way to read your own
entitlements on iOS; it probes the app-group container instead, which is nil exactly when the binary is not
entitled — the same fault the phone's log named, asked directly.

Counts: client 774 tests, all 22 checks, Debug/Personal/Release all build.

## A leg on a wrist, drawing the state four other surfaces already draw

The first piece of the watch, after checking the thing that decides whether a watch is cheap: **does the
design system compile for watchOS?** It does — four errors, all in one file, both about picking a club's
accent colour (a trait resolution with nothing to resolve on a watch, and a `ColorPicker` nobody uses from a
wrist). The scoring engine and statistics build untouched. CI now builds all four for watchOS every push,
because a foundation nobody compiles rots and the bill arrives all at once.

**`ThroWatchKit` carries no model.** `ThroLiveState` already answers what a leg looks like from outside the
app — the Lock Screen, the Dynamic Island, the widgets and an external display all draw it, and it is
Codable and Sendable because ActivityKit made it cross a process boundary inside 4 KB, which is what
WatchConnectivity will want. A fifth shape for two numbers and a checkout would be a fifth thing to keep
true, and the first divergence would be silent. A test round-trips it to hold that.

What is new is the arrangement. A Lock Screen banner is wider than it is tall and puts the players side by
side; a watch is nearly square and read at arm's length with a dart in the other hand, so the sides stack,
the thrower's score is the largest thing on the screen, and the checkout sits under it rather than at the end
of a caption — the route being the one fact a player at the oche wants, and the thing a wrist is better at
than a phone across the room. Carried, never derived: the rule tables are in the engine and a watch that
computed a finish would be linking a scoring engine to draw three words.

Its own target rather than a view in `ThroLiveKit`, which is deliberately the lightest here because a widget
extension links it.

Still to come: the watchOS target in the Xcode project and the connectivity to feed it.

Counts: client 780 tests (6 on a wrist), all 22 checks.

## A watch app, and the third build configuration retired

**The watch app ships.** `apps/ios/ThroWatch` is thirteen lines mounting a package module, the same shape as
the phone target and the widget extension, and it is a **dependency of the phone app** rather than an
optional extra — CI cannot go green while the watch is broken. Debug and Release were built for the
simulator, Debug for a device with automatic provisioning (which registered `app.thro.darts.watchkitapp` on
its own), and the phone's three entitlements re-read off the signed binary to prove nothing was disturbed,
because a project-file mistake had broken that same build four hours earlier.

**The link is `updateApplicationContext`**, which keeps one dictionary and replaces it, because a scoreboard
wants the latest truth: `sendMessage` needs a watch that is awake, and `transferUserInfo` is a queue that
would walk a returning wrist forward through every dead score in order. That is last-write-wins and it does
not bend the rule about sync, because nothing on the watch is a source of truth — no journal, nothing written
back, the same projection the Lock Screen holds. Staleness is judged on the receiving clock, never on a
timestamp in the message: two devices are two clocks. The sender holds one pending dictionary until
activation completes, or the very first thing a launch says — *nothing is on* — would be dropped, and a phone
killed mid-leg would leave that leg on a wrist forever. One line joins `LiveBoard`, which already was the one
place a leg leaves the app; the wall is cleared at the end and the wrist is sent the finished leg, because a
room reading a decided scoreline as live is the failure the wall exists to avoid and a watch is on the arm of
somebody who was there.

**Three faults were found by looking at it on a watch, and none had a failing test.** The route was said
twice. A stale score kept showing its finish — a route is only as true as the remainder behind it, and the
caption had always dropped it *inside a sentence*, so a surface drawing the route on its own line got none of
the rule; it is now `ThroLiveCopy.route`, which both surfaces ask, and which is also empty when nobody is on
the oche, which was the same fault a third time. And a decided leg dimmed both numerals, because emphasis
followed "is throwing" and nobody throws once it is won — so the answer to the only question left was drawn
in the quiet colour. `-ThroWristDemo` exists for exactly this: a DEBUG-only launch argument that puts a leg
on a wrist with no phone attached, confirmed absent from a Release binary.

**And `Personal` is retired.** It broke this change in a second way, unrelated to PD-075's: a custom
configuration is compiled as *release* by the Swift package build whatever the Xcode targets set, so
`#if DEBUG` was true in the app target and false in the package it links, and code that built under Debug and
Release failed under Personal alone. Its three configurations were confirmed byte-identical to Debug first;
the scheme's Run action moves to Debug. Two configurations that must stay identical are one configuration and
a trap.

Counts: client 803 tests (29 on a wrist), all 22 checks, Debug and Release both build for the simulator and
the device, and the watch app for watchOS.
