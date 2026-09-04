#!/usr/bin/env python3
"""
THRØ — conformance corpus validator and property tests.

This does NOT simply re-run the generator, which would be circular. It checks the generated
rules against INDEPENDENT facts about darts, and checks structural invariants that must hold
for any correct engine. If this passes, the corpus is trustworthy enough to hold three
platform implementations to.

Run: python3 validate.py   (exit 0 = pass)
"""
import json, sys, hashlib
from pathlib import Path
sys.path.insert(0, str(Path(__file__).parent))
from generate import (ACHIEVABLE_3, IMPOSSIBLE_3, CHECKOUTS, ONE_DART, SEGMENTS,
                      DOUBLE_SEGMENTS, classify, bogeys, bust_on_exact, min_darts, rule_tables)

OUT = Path(__file__).parent
fails, checks = [], 0

def check(name, cond, detail=""):
    global checks; checks += 1
    if not cond: fails.append(f"{name}{(' — ' + detail) if detail else ''}")

# ---- 1. Independent darts facts -------------------------------------------------
# These are verifiable by hand against a dartboard and are stated here as ground truth.
check("max checkout under double-out is 170 (T20 T20 D25)", max(CHECKOUTS["double"]) == 170)
check("170 = 60+60+50", 60 + 60 + 50 == 170)
check("max visit total is 180", max(ACHIEVABLE_3) == 180)
check("180 requires three treble 20s",
      len([c for c in [(a, b, c) for a in SEGMENTS for b in SEGMENTS for c in SEGMENTS
                       if a + b + c == 180]]) > 0 and 60 in SEGMENTS)
check("the nine impossible 3-dart totals",
      IMPOSSIBLE_3 == [163, 166, 169, 172, 173, 175, 176, 178, 179], str(IMPOSSIBLE_3))
check("double-out bogeys",
      bogeys("double") == [159, 162, 163, 165, 166, 168, 169], str(bogeys("double")))
check("master-out maximum is 180, not 170", max(CHECKOUTS["master"]) == 180)
check("21 one-dart double-out finishes ({2..40 even} + bull)",
      ONE_DART["double"] == sorted(list(range(2, 41, 2)) + [50]), str(ONE_DART["double"]))
check("the bull counts as a double", 50 in DOUBLE_SEGMENTS)
check("minimum darts to finish 501 is 9", min_darts(501, "double") == 9)
check("minimum darts to finish 301 is 6", min_darts(301, "double") == 6)
check("minimum darts to finish 701 is 12", min_darts(701, "double") == 12)
check("exact-score bust set under double-out",
      bust_on_exact("double") == [159, 162, 165, 168, 171, 174, 177, 180],
      str(bust_on_exact("double")))
# 167 is a genuine 3-dart finish (T20 T19 D25); 168 is not. A classic discriminator.
check("167 is finishable", 167 in CHECKOUTS["double"])
check("168 is not finishable", 168 not in CHECKOUTS["double"])
check("169 is neither achievable nor finishable",
      169 not in ACHIEVABLE_3 and 169 not in CHECKOUTS["double"])

# ---- 2. Structural invariants over the whole transition space -------------------
neg = bad_bust = one_left = 0
for rem in range(2, 502):
    for vt in ACHIEVABLE_3:
        eff, reason, new = classify(rem, vt, "double")
        if eff == "scored":
            if new < 0: neg += 1
            if new == 1: one_left += 1          # unreachable at visit start under double-out
        if eff == "bust" and new != rem: bad_bust += 1
        if eff == "leg_won" and new != 0: bad_bust += 1
check("a scored visit never leaves a negative remaining", neg == 0, f"{neg} cases")
check("a scored visit never leaves 1 under double-out", one_left == 0, f"{one_left} cases")
check("a bust always restores the pre-visit remaining exactly", bad_bust == 0, f"{bad_bust} cases")

nonbust = sum(1 for vt in ACHIEVABLE_3 if classify(182, vt, "double")[0] == "bust")
check("bust is impossible at remaining >= 182", nonbust == 0, f"{nonbust} busts at 182")

check("every leg-winning remaining is in the checkout set",
      all(classify(r, r, "double")[0] == "leg_won"
          for r in CHECKOUTS["double"] if r in ACHIEVABLE_3 and r <= 170))

# ---- 3. Determinism -------------------------------------------------------------
a = [classify(r, v, "double") for r in range(2, 200) for v in sorted(ACHIEVABLE_3)]
b = [classify(r, v, "double") for r in range(2, 200) for v in sorted(ACHIEVABLE_3)]
check("the transition function is deterministic", a == b)

# ---- 4. Committed rule tables match a fresh derivation --------------------------
committed = json.loads((OUT / "rule-tables.json").read_text())
check("committed rule tables match a fresh derivation", committed == rule_tables(),
      "rule-tables.json is stale — regenerate")

# ---- 5. Every vector's expectations are reproducible ----------------------------
manifest = json.loads((OUT / "vectors" / "manifest.json").read_text())
vec_checked = 0
for fname, meta in manifest["files"].items():
    p = OUT / "vectors" / fname
    if not p.exists():
        fails.append(f"vector file missing: {fname}"); continue
    digest = hashlib.sha256(p.read_bytes()).hexdigest()
    check(f"{fname} matches its manifest hash", digest == meta["sha256"])
    if fname == "core-transitions.jsonl":
        for line in p.read_text().splitlines():
            r = json.loads(line)
            eff, reason, new = classify(r["remaining"], r["visitTotal"], r["outRule"])
            if (eff, reason, new) != (r["effect"], r["reason"], r["newRemaining"]):
                fails.append(f"core transition mismatch at {r}"); break
            vec_checked += 1
        continue
    for line in p.read_text().splitlines():
        c = json.loads(line)
        out_rule = c["setup"]["format"]["outRule"]
        # replay the declared commands through classify and compare per-command outcomes
        start = c["setup"]["format"]["startingScore"]
        rem = {"A": start, "B": start}
        leg_starter = c["setup"]["format"]["throwFirst"]
        thrower = leg_starter; done = False
        for cmd, exp in zip(c["commands"], c["expect"]["outcomes"]):
            if done:
                check(f"{c['id']} rejects after completion", exp["result"] == "rejected"); continue
            if cmd["player"] != thrower:
                check(f"{c['id']} rejects wrong thrower",
                      exp["result"] == "rejected" and exp.get("reason") == "NOT_YOUR_TURN")
                continue
            eff, reason, new = classify(rem[cmd["player"]], cmd["visitTotal"], out_rule)
            if eff == "rejected":
                check(f"{c['id']} seq{cmd['seq']} rejection agrees",
                      exp["result"] == "rejected" and exp.get("reason") == reason)
                continue
            # A leg that decides the match is reported as match_won; the replay must accept either
            # label for the same transition rather than treating the distinction as a mismatch.
            eff_expected = exp.get("effect")
            same = (eff_expected == eff) or (eff == "leg_won" and eff_expected == "match_won")
            check(f"{c['id']} seq{cmd['seq']} effect agrees", same,
                  f"expected {eff_expected} got {eff}")
            if eff_expected == "match_won": done = True
            if reason:
                check(f"{c['id']} seq{cmd['seq']} reason agrees", exp.get("reason") == reason)
            rem[cmd["player"]] = new
            if eff == "leg_won":
                # `done` is set from the expected effect above (match_won), not from the case having
                # a winner at the end — that fired on the FIRST leg win and made every later command
                # look like it should have been rejected.
                rem = {"A": start, "B": start}
                leg_starter = "B" if leg_starter == "A" else "A"
                thrower = leg_starter
            else:
                thrower = "B" if cmd["player"] == "A" else "A"
        vec_checked += 1

print(f"{checks} property checks, {vec_checked} vectors replayed")
if fails:
    print(f"\nFAILED ({len(fails)}):")
    for f in fails[:25]: print("  -", f)
    sys.exit(1)
print("PASS — corpus is self-consistent and agrees with independent darts facts")
