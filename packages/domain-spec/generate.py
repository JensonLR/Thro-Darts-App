#!/usr/bin/env python3
"""
THRØ — rule tables and conformance corpus generator.

Everything here is DERIVED FROM THE DARTBOARD, not transcribed from a source that could be
wrong. The segment set is the only input; achievable totals, checkout sets, bust conditions
and finish counts all fall out of it. That matters because the approved design's own sample
data contains four arithmetic impossibilities, so no number in this system is copied.

Output:
  rule-tables.json    compact, complete, generated into Swift/Kotlin/server source
  vectors/*.jsonl     the conformance corpus every platform must reproduce

Usage:
  python3 generate.py            curated + boundary-exhaustive vectors (committed)
  python3 generate.py --full     adds the exhaustive transition table (CI only, ~91k cases)
"""
import json, os, sys, itertools, hashlib
from pathlib import Path

OUT = Path(__file__).parent
SPEC_VERSION = "1.0.0"

# ---------------------------------------------------------------- the dartboard
SINGLES  = set(range(1, 21))
DOUBLES  = {2 * n for n in range(1, 21)}
TREBLES  = {3 * n for n in range(1, 21)}
OUTER_BULL, BULL = 25, 50
# A dart either misses (0) or lands on exactly one of these.
SEGMENTS = {0} | SINGLES | DOUBLES | TREBLES | {OUTER_BULL, BULL}
# The bull counts as a double (D25) for double-out.
DOUBLE_SEGMENTS = DOUBLES | {BULL}
# Master-out admits a double or a treble.
MASTER_SEGMENTS = DOUBLE_SEGMENTS | TREBLES
FINISHERS = {"double": DOUBLE_SEGMENTS, "master": MASTER_SEGMENTS, "straight": SEGMENTS - {0}}

def achievable_totals(n_darts):
    """Every total reachable with exactly n darts (a miss scores 0, so fewer darts is a subset)."""
    totals = {0}
    for _ in range(n_darts):
        totals = {t + s for t in totals for s in SEGMENTS}
    return totals

ACHIEVABLE_3 = achievable_totals(3)
IMPOSSIBLE_3 = sorted(set(range(0, 181)) - ACHIEVABLE_3)

def finishes_in(n_darts, out_rule):
    """Scores finishable in exactly n darts: n-1 free darts then a legal finishing segment."""
    fin = FINISHERS[out_rule]
    pre = achievable_totals(n_darts - 1)
    return {p + f for p in pre for f in fin}

def checkout_set(out_rule, max_darts=3):
    s = set()
    for n in range(1, max_darts + 1):
        s |= finishes_in(n, out_rule)
    return {v for v in s if v > 0}

CHECKOUTS = {r: checkout_set(r) for r in FINISHERS}
ONE_DART  = {r: sorted(v for v in finishes_in(1, r) if v > 0) for r in FINISHERS}

def bogeys(out_rule):
    """Unfinishable values at or below the maximum checkout — the classic trap list."""
    mx = max(CHECKOUTS[out_rule])
    return sorted(v for v in range(2, mx + 1) if v not in CHECKOUTS[out_rule])

def bust_on_exact(out_rule):
    """Remaining values where scoring EXACTLY that amount busts: not finishable, but reachable
    as a visit total. This is the bust condition implementations drop.

    1 is excluded: under double-out a remaining of 1 is unreachable at the start of a visit
    (the transition that would produce it is itself a bust), so it is not a reachable case.
    The invariant is asserted in validate.py rather than assumed here."""
    lo = 2 if out_rule == "double" else 1
    return sorted(v for v in ACHIEVABLE_3 if v >= lo and v not in CHECKOUTS[out_rule])

def min_darts(start, out_rule):
    """Fewest darts that can finish from `start`. Breadth-first over dart counts."""
    reach, n = {start}, 0
    while n < 30:
        n += 1
        fin = FINISHERS[out_rule]
        if any(r in fin for r in reach): return n
        reach = {r - s for r in reach for s in SEGMENTS if r - s > 0}
        if not reach: return None
    return None

# ---------------------------------------------------------------- the rules
def classify(remaining, visit_total, out_rule):
    """The single normative transition. Order matters: overthrow, then remainder-one, then
    exact-but-unfinishable. Returns (effect, reason, new_remaining)."""
    if visit_total not in ACHIEVABLE_3:
        return ("rejected", "IMPOSSIBLE_VISIT_TOTAL", remaining)
    left = remaining - visit_total
    if left < 0:
        return ("bust", "BELOW_ZERO", remaining)
    if left == 1 and out_rule == "double":
        return ("bust", "REMAINDER_ONE", remaining)
    if left == 0:
        if remaining in CHECKOUTS[out_rule]:
            return ("leg_won", None, 0)
        return ("bust", "NOT_CHECKOUT_POSSIBLE", remaining)
    return ("scored", None, left)

# ---------------------------------------------------------------- rule tables
def rule_tables():
    return {
        "specVersion": SPEC_VERSION,
        "note": "Generated from the dartboard segment set. Do not hand-edit.",
        "segments": sorted(SEGMENTS),
        "doubleSegments": sorted(DOUBLE_SEGMENTS),
        "impossibleVisitTotals": IMPOSSIBLE_3,
        "maxVisitTotal": max(ACHIEVABLE_3),
        "outRules": {
            r: {
                "maxCheckout": max(CHECKOUTS[r]),
                "bogeyNumbers": bogeys(r),
                "oneDartFinishes": ONE_DART[r],
                "bustOnExactScore": bust_on_exact(r),
                "minDartsToFinish": {str(s): min_darts(s, r) for s in (301, 501, 701)},
            } for r in ("double", "master", "straight")
        },
        "invariants": {
            "remainingOneUnreachableAtVisitStart": True,
            "bustImpossibleAtOrAbove": max(ACHIEVABLE_3) + 2,
        },
    }

# ---------------------------------------------------------------- vectors
def fmt(out_rule="double", start=501, first_to=5, sets=False):
    f = {"game": "X01", "startingScore": start, "inRule": "straight", "outRule": out_rule,
         "structure": {"kind": "legs", "firstTo": first_to},
         "throwFirst": "A", "alternateStart": "perLeg"}
    if sets:
        f["structure"] = {"kind": "sets", "firstTo": 3, "legsPerSet": {"firstTo": 3}}
    return f

def case(cid, desc, commands, expect, format_=None):
    return {"id": cid, "specVersion": SPEC_VERSION, "description": desc,
            "setup": {"format": format_ or fmt(), "players": [{"id": "A"}, {"id": "B"}]},
            "commands": commands, "expect": expect}

def visit(seq, player, total, darts=None):
    c = {"seq": seq, "id": f"01J{seq:029d}", "type": "RecordVisit",
         "player": player, "visitTotal": total}
    if darts is not None: c["dartsUsed"] = darts
    return c

def simulate(commands, format_):
    """Reference outcome, computed from `classify` alone — so expected values are derived,
    never asserted."""
    out_rule = format_["outRule"]; start = format_["startingScore"]
    rem = {"A": start, "B": start}; legs = {"A": 0, "B": 0}
    thrower, outcomes, winner = format_["throwFirst"], [], None
    leg_starter, leg_no = format_["throwFirst"], 1
    target = format_["structure"].get("firstTo", 5)
    for c in commands:
        if winner:
            outcomes.append({"seq": c["seq"], "result": "rejected", "reason": "MATCH_COMPLETE"}); continue
        p = c["player"]
        if p != thrower:
            outcomes.append({"seq": c["seq"], "result": "rejected", "reason": "NOT_YOUR_TURN"}); continue
        eff, reason, new = classify(rem[p], c["visitTotal"], out_rule)
        if eff == "rejected":
            outcomes.append({"seq": c["seq"], "result": "rejected", "reason": reason}); continue
        o = {"seq": c["seq"], "result": "accepted", "effect": eff}
        if reason: o["reason"] = reason
        outcomes.append(o)
        rem[p] = new
        if eff == "leg_won":
            legs[p] += 1
            if legs[p] >= target: winner = p
            else:
                leg_no += 1
                leg_starter = "B" if leg_starter == "A" else "A"
                thrower = leg_starter
                rem = {"A": start, "B": start}
        else:
            thrower = "B" if p == "A" else "A"
    return {"outcomes": outcomes,
            "state": {"matchState": "complete" if winner else "in_progress",
                      "currentLeg": leg_no, "throwerId": None if winner else thrower,
                      "remaining": rem, "legsWon": legs, "winnerId": winner}}


def path_to(target, start=501):
    """Visit totals bringing a player from `start` down to exactly `target` without busting.
    Used to construct setup sequences; searched rather than assumed, so a chunk is never an
    unachievable total."""
    need = start - target
    if need < 0: return None
    if need == 0: return []
    chunks = []
    while need > 180:
        chunks.append(180); need -= 180
    if need == 0: return chunks
    if need in ACHIEVABLE_3:
        chunks.append(need); return chunks
    # final chunk unachievable: shave the previous 180 and retry
    for k in range(1, 60):
        if chunks and (180 - k) in ACHIEVABLE_3 and (need + k) in ACHIEVABLE_3:
            chunks[-1] = 180 - k; chunks.append(need + k); return chunks
        if not chunks and (need + k) in ACHIEVABLE_3 and (start - target - (need + k)) == -k:
            pass
    for a in sorted(ACHIEVABLE_3, reverse=True):
        b = need - a
        if 0 < b <= 180 and b in ACHIEVABLE_3:
            return (chunks[:-1] if chunks else []) + ([180] * 0) + [a, b]
    return None

def setup_cmds(target, seq=1, start=501):
    """Interleave A's setup visits with B scoring 0, so turn order stays legal."""
    path = path_to(target, start)
    if path is None: return None, seq
    cmds = []
    for v in path:
        cmds.append(visit(seq, "A", v, 3)); seq += 1
        cmds.append(visit(seq, "B", 0, 3)); seq += 1
    return cmds, seq

def build_bust_vectors():
    cases, f = [], fmt()
    # EVERY remaining value where scoring exactly that amount busts. This is the bust condition
    # implementations drop, so it is covered exhaustively rather than sampled.
    for rem in bust_on_exact("double"):
        cmds, seq = setup_cmds(rem)
        if cmds is None: continue
        cmds = cmds + [visit(seq, "A", rem, 3)]
        cases.append(case(f"bust.exact.unfinishable.{rem}",
                          f"Scoring exactly {rem} from {rem} busts: {rem} is not finishable on a double.",
                          cmds, simulate(cmds, f), f))
    # remainder-one, from several starting positions
    for rem in (2, 41, 101, 170):
        cmds, seq = setup_cmds(rem + 1)
        if cmds is None: continue
        cmds = cmds + [visit(seq, "A", rem, 3)]
        cases.append(case(f"bust.doubleout.remainder-one.from{rem+1}",
                          f"Leaving 1 from {rem+1} busts and restores the pre-visit score.",
                          cmds, simulate(cmds, f), f))
    # overthrow
    for rem in (40, 100, 180):
        cmds, seq = setup_cmds(rem)
        if cmds is None: continue
        cmds = cmds + [visit(seq, "A", rem + 20 if rem + 20 in ACHIEVABLE_3 else rem + 21, 3)]
        cases.append(case(f"bust.below-zero.from{rem}",
                          f"Overthrowing from {rem} busts and restores the pre-visit score.",
                          cmds, simulate(cmds, f), f))
    # impossible totals are REJECTED, never busted
    for t in IMPOSSIBLE_3:
        cmds = [visit(1, "A", t, 3)]
        cases.append(case(f"reject.impossible-total.{t}",
                          f"{t} is not achievable with three darts: rejected, not busted.",
                          cmds, simulate(cmds, f), f))
    return cases

def build_checkout_vectors():
    cases, f = [], fmt()
    # every one-dart finish, plus the notable multi-dart ones
    for rem in ONE_DART["double"]:
        cmds, seq = setup_cmds(rem)
        if cmds is None: continue
        cmds = cmds + [visit(seq, "A", rem, 1)]
        cases.append(case(f"checkout.doubleout.{rem}.in1",
                          f"Finishing {rem} with one dart wins the leg; dartsUsed is 1.",
                          cmds, simulate(cmds, f), f))
    for rem, darts in ((170, 3), (167, 3), (110, 2), (101, 2), (60, 2)):
        cmds, seq = setup_cmds(rem)
        if cmds is None: continue
        cmds = cmds + [visit(seq, "A", rem, darts)]
        cases.append(case(f"checkout.doubleout.{rem}.in{darts}",
                          f"Finishing {rem} with {darts} darts wins the leg.",
                          cmds, simulate(cmds, f), f))
    return cases

def build_rotation_vectors():
    cases, f = [], fmt(first_to=5)
    cmds, seq = [], 1
    for leg in range(3):
        starter = "A" if leg % 2 == 0 else "B"
        other = "B" if starter == "A" else "A"
        cmds.append(visit(seq, starter, 180, 3)); seq += 1
        cmds.append(visit(seq, other, 60, 3)); seq += 1
        cmds.append(visit(seq, starter, 180, 3)); seq += 1
        cmds.append(visit(seq, other, 60, 3)); seq += 1
        cmds.append(visit(seq, starter, 141, 3)); seq += 1
    cases.append(case("rotation.alternating-leg-start",
                      "Leg start alternates; the leg-1 starter also starts leg 3.",
                      cmds, simulate(cmds, f), f))
    cmds = [visit(1, "B", 60, 3)]
    cases.append(case("rotation.wrong-thrower",
                      "A visit from the player who is not to throw is rejected.",
                      cmds, simulate(cmds, f), f))
    return cases

def build_adversarial_vectors():
    cases, f = [], fmt()
    cmds = [visit(1, "A", 501, 3)]
    cases.append(case("adversarial.nine-dart-impossible-in-one",
                      "501 cannot be scored in a single visit; max is 180.",
                      cmds, simulate(cmds, f), f))
    cmds = [visit(1, "A", 180, 3), visit(2, "B", 0, 3), visit(3, "A", 180, 3),
            visit(4, "B", 0, 3), visit(5, "A", 141, 3)]
    cases.append(case("adversarial.nine-darter",
                      "A genuine nine-darter: 180+180+141. dartsUsed is unambiguous at 3.",
                      cmds, simulate(cmds, f), f))
    cmds = [visit(1, "A", 100, 3), visit(2, "A", 100, 3)]
    cases.append(case("adversarial.two-visits-same-player",
                      "The same player cannot throw twice in succession.",
                      cmds, simulate(cmds, f), f))
    return cases

def write_jsonl(name, cases):
    p = OUT / "vectors" / name
    with open(p, "w") as fh:
        for c in cases: fh.write(json.dumps(c, separators=(",", ":")) + "\n")
    return p, len(cases)

def main():
    full = "--full" in sys.argv
    (OUT / "vectors").mkdir(exist_ok=True)
    tables = rule_tables()
    (OUT / "rule-tables.json").write_text(json.dumps(tables, indent=2) + "\n")

    files, total = {}, 0
    for name, cases in (("bust-rules.jsonl", build_bust_vectors()),
                        ("checkouts.jsonl", build_checkout_vectors()),
                        ("leg-rotation.jsonl", build_rotation_vectors()),
                        ("adversarial.jsonl", build_adversarial_vectors())):
        p, n = write_jsonl(name, cases); total += n
        files[name] = {"cases": n,
                       "sha256": hashlib.sha256(p.read_bytes()).hexdigest()}

    if full:
        p = OUT / "vectors" / "core-transitions.jsonl"
        n = 0
        with open(p, "w") as fh:
            for rem in range(2, 502):
                for vt in sorted(ACHIEVABLE_3):
                    eff, reason, new = classify(rem, vt, "double")
                    fh.write(json.dumps({"remaining": rem, "visitTotal": vt, "outRule": "double",
                                         "effect": eff, "reason": reason, "newRemaining": new},
                                        separators=(",", ":")) + "\n"); n += 1
        files["core-transitions.jsonl"] = {"cases": n,
                                           "sha256": hashlib.sha256(p.read_bytes()).hexdigest()}
        total += n

    (OUT / "vectors" / "manifest.json").write_text(json.dumps(
        {"specVersion": SPEC_VERSION, "files": files, "totalCases": total}, indent=2) + "\n")

    print(f"specVersion {SPEC_VERSION}")
    print(f"impossible visit totals ({len(IMPOSSIBLE_3)}): {IMPOSSIBLE_3}")
    for r in ("double", "master", "straight"):
        t = tables["outRules"][r]
        print(f"{r:9} max checkout {t['maxCheckout']:>3}  bogeys {t['bogeyNumbers']}  "
              f"1-dart finishes {len(t['oneDartFinishes'])}  min darts 501={t['minDartsToFinish']['501']}")
    print(f"vectors written: {total} cases across {len(files)} files")

if __name__ == "__main__":
    main()
