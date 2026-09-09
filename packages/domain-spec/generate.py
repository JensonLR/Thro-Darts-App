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
SPEC_VERSION = "1.3.0"

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
# What may OPEN a leg, by in-rule. The same segment sets as the finishers, and for the same reason:
# the bull is a double, and master admits a treble. Straight-in opens on anything that scores.
OPENERS = {"double": DOUBLE_SEGMENTS, "master": MASTER_SEGMENTS, "straight": SEGMENTS - {0}}

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

# ---------------------------------------------------------------- checkout routes (PD-013)
#
# THRØ shows one route to a finish. That is a POSITION, not a fact: most finishes have several legal
# routes and players disagree about which is best, so the founder decided (PD-013) that the app takes
# a position rather than staying silent. What follows is that position, written as a rule so that
# every route is derivable and checkable rather than a table somebody typed.
#
# The rule, in full:
#   1. Fewest darts.
#   2. On the LAST dart, prefer the finishing double by the order below.
#   3. On every dart BEFORE it, prefer a treble (highest first), then a single (highest first).
#      A double, the outer bull or the bull is used as a scoring dart only when nothing else reaches.
#   4. On a three-dart finish, choose the first dart by (3) among those that leave a two-dart finish,
#      then apply (2) and (3) to what is left.
#
# The order in (2) puts 32 and 40 first because they are the two doubles the game is taught around,
# then the rest of the even doubles, then the odd ones — a missed odd double leaves an odd number —
# and the bull last, because it is the smallest target on the board. Where this differs from a chart
# somebody has seen, both routes are legal. This one is derived, so it can be checked.
DOUBLE_ORDER = [16, 20, 12, 18, 10, 8, 14, 6, 4, 2] + list(range(19, 0, -2))

def named(kind, n):
    """The name a player would say: T20, D16, 20, 25, Bull."""
    return {"S": str(n), "D": "D%d" % n, "T": "T%d" % n}[kind] if kind != "B" else ("Bull" if n == 50 else "25")

THROW_SCORE = {}
for _n in range(1, 21):
    THROW_SCORE[named("S", _n)] = _n
    THROW_SCORE[named("D", _n)] = 2 * _n
    THROW_SCORE[named("T", _n)] = 3 * _n
THROW_SCORE["25"] = OUTER_BULL
THROW_SCORE["Bull"] = BULL

# Scoring darts, best first: by score, and where a single and a treble score the same, the SINGLE —
# nobody aiming for nine aims at treble three. Then, only as a fallback, everything else: a route
# that needs a double to score is still a route, and is better than no route.
SCORING_FIRST = [t for _, _, t in sorted(
    [(-n, 0, named("S", n)) for n in range(1, 21)] + [(-3 * n, 1, named("T", n)) for n in range(1, 21)])]
SCORING_LAST   = [named("D", n) for n in range(20, 0, -1)] + ["Bull", "25"]

def finisher_names(out_rule):
    """Legal finishing throws, in the order THRØ prefers them."""
    order = []
    if out_rule == "straight":
        # A straight-out finish of 17 is thrown at 17, not at a double that happens to equal it.
        order += [named("S", n) for n in range(1, 21)]
    order += [named("D", n) for n in DOUBLE_ORDER]
    order += ["Bull"]
    if out_rule in ("master", "straight"):
        order += [named("T", n) for n in range(20, 0, -1)]
    if out_rule == "straight":
        order += ["25"]
    legal = FINISHERS[out_rule]
    seen, out = set(), []
    for t in order:
        if THROW_SCORE[t] in legal and t not in seen:
            seen.add(t); out.append(t)
    return out

def scoring_for(value):
    """The throw THRØ would aim at to score exactly `value`, or None."""
    for t in SCORING_FIRST:
        if THROW_SCORE[t] == value: return t
    for t in SCORING_LAST:
        if THROW_SCORE[t] == value: return t
    return None

def route_of_length(remaining, out_rule, darts):
    if darts == 1:
        for f in finisher_names(out_rule):
            if THROW_SCORE[f] == remaining: return [f]
        return None
    if darts == 2:
        # Two passes: a scoring dart THRØ would actually aim at, and then anything that reaches.
        for pool in (SCORING_FIRST, SCORING_FIRST + SCORING_LAST):
            for f in finisher_names(out_rule):
                need = remaining - THROW_SCORE[f]
                if need <= 0: continue
                for t in pool:
                    if THROW_SCORE[t] == need: return [t, f]
        return None
    for t in SCORING_FIRST + SCORING_LAST:
        need = remaining - THROW_SCORE[t]
        if need <= 0: continue
        rest = route_of_length(need, out_rule, darts - 1)
        if rest: return [t] + rest
    return None

def route(remaining, out_rule):
    for d in (1, 2, 3):
        r = route_of_length(remaining, out_rule, d)
        if r: return r
    return None

def routes(out_rule):
    return {v: route(v, out_rule) for v in sorted(CHECKOUTS[out_rule])}

def encode_routes(table):
    """One string per rule: `170=T20,T20,D20|167=T20,T19,Bull|…`.

    A map literal of 170 entries is a lot of generated code and, in Kotlin, a lot of bytecode in one
    initialiser. A string parsed once is smaller, and the parse is five lines that a test can hold.
    """
    return "|".join("%d=%s" % (v, ",".join(r)) for v, r in sorted(table.items()) if r)

def opening_totals(in_rule):
    """Every counted total a visit can record while the player has not yet opened.

    This is the rule that makes double-in scorable at visit granularity, and it is the whole of
    PD-008. The engine scores a visit, not a dart; under double-in the darts before the opening one
    score nothing, so what the scorer records — and what they call at the oche — is the score FROM
    the opening dart onward. Zero means the player did not open.

    So an opening total is a legal opening segment plus up to two free darts after it: the player
    may open on the first dart and throw two more, on the second and throw one, or on the third and
    throw none. Everything before the opener contributes nothing and is not recorded, which loses no
    statistic this repository computes, because a visit is three darts either way.

    Enumerated, never listed: under double-in the largest is D20+T20+T20 = 160, and 41 — which no
    sequence beginning with a double can make — is not in the set."""
    out = set()
    for f in OPENERS[in_rule]:
        for rest in achievable_totals(2):
            t = f + rest
            if 0 < t <= 180:
                out.add(t)
    return out

OPENING = {r: opening_totals(r) for r in OPENERS}

def unopenable(in_rule):
    """Totals three darts CAN make but no sequence beginning with a legal opener can. Under
    straight-in this is empty by construction; under double-in it is the list that makes the
    rejection meaningful."""
    return sorted(v for v in ACHIEVABLE_3 if v > 0 and v not in OPENING[in_rule])

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
    # Two distinct rejections, deliberately. "Above 180" means the input is out of range at all —
    # a client bug or tampering. "Unreachable with three darts" means a plausible but impossible
    # value, which is usually a mis-key. They warrant different messages and different signals.
    if visit_total < 0 or visit_total > 180:
        return ("rejected", "VISIT_TOTAL_OUT_OF_RANGE", remaining)
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
        "inRules": {
            r: {
                "openingSegments": sorted(OPENERS[r]),
                "maxOpeningTotal": max(OPENING[r]),
                "unopenableTotals": unopenable(r),
            } for r in ("double", "master", "straight")
        },
        "outRules": {
            r: {
                "minCheckout": min(CHECKOUTS[r]),
                "maxCheckout": max(CHECKOUTS[r]),
                "bogeyNumbers": bogeys(r),
                "oneDartFinishes": ONE_DART[r],
                "bustOnExactScore": bust_on_exact(r),
                "minDartsToFinish": {str(s): min_darts(s, r) for s in (301, 501, 701)},
                # PD-013: one route per finish, derived by the stated rule above. A position, not
                # a fact — see the comment on DOUBLE_ORDER.
                "routes": encode_routes(routes(r)),
            } for r in ("double", "master", "straight")
        },
        "invariants": {
            "remainingOneUnreachableAtVisitStart": True,
            "bustImpossibleAtOrAbove": max(ACHIEVABLE_3) + 2,
        },
    }

# ---------------------------------------------------------------- vectors
def fmt(out_rule="double", start=501, first_to=5, sets=None, legs_per_set=None,
        alternate="perLeg"):
    """A match format. `sets` promotes it to set play: `first_to` then means legs per set.

    The shape was here from the beginning and no vector used it, which is how set play came to be
    implemented in two engines and exercised by nothing at all.
    """
    f = {"game": "X01", "startingScore": start, "inRule": "straight", "outRule": out_rule,
         "structure": {"kind": "legs", "firstTo": first_to},
         "throwFirst": "A", "alternateStart": alternate}
    if sets:
        f["structure"] = {"kind": "sets", "firstTo": sets,
                          "legsPerSet": {"firstTo": legs_per_set or first_to}}
    return f

def case(cid, desc, commands, expect, format_=None):
    return {"id": cid, "specVersion": SPEC_VERSION, "description": desc,
            "setup": {"format": format_ or fmt(), "players": [{"id": "A"}, {"id": "B"}]},
            "commands": commands, "expect": expect}

def visit(seq, player, total, darts=None, at_double=None):
    c = {"seq": seq, "id": f"01J{seq:029d}", "type": "RecordVisit",
         "player": player, "visitTotal": total}
    if darts is not None: c["dartsUsed"] = darts
    if at_double is not None: c["dartsAtDouble"] = at_double
    return c

def simulate(commands, format_):
    """Reference outcome, computed from `classify` alone — so expected values are derived,
    never asserted."""
    out_rule = format_["outRule"]; start = format_["startingScore"]
    rem = {"A": start, "B": start}; legs = {"A": 0, "B": 0}
    thrower, outcomes, winner = format_["throwFirst"], [], None
    leg_starter, leg_no = format_["throwFirst"], 1
    structure = format_["structure"]

    # Set play, stated as the rule rather than read off an implementation:
    #
    #   * a **set** is won by the player who first wins the required number of legs IN THAT SET;
    #   * the **match** is won by the player who first wins the required number of sets;
    #   * a new set starts both counters again, and its legs are numbered from 1 — because a set is
    #     a match within a match, and "leg 3 of set 2" is what a scorer calls;
    #   * the right to throw first in a **set** alternates; under `perSet` alternation the set's
    #     starter also opens every leg within it, and under `perLeg` it changes hands every leg.
    #
    # With no set structure the legs unit decides the match, which is what every other family uses.
    playing_sets = structure.get("kind") == "sets"
    target = (structure["legsPerSet"]["firstTo"] if playing_sets
              else structure.get("firstTo", 5))
    sets_target = structure.get("firstTo", 1) if playing_sets else None
    legs_in_set = {"A": 0, "B": 0}
    sets_won = {"A": 0, "B": 0}
    set_no, set_starter = 1, format_["throwFirst"]
    per_set = format_.get("alternateStart") == "perSet"
    for c in commands:
        if winner:
            outcomes.append({"seq": c["seq"], "result": "rejected", "reason": "MATCH_COMPLETE"}); continue
        p = c["player"]
        if p != thrower:
            outcomes.append({"seq": c["seq"], "result": "rejected", "reason": "NOT_YOUR_TURN"}); continue
        before = rem[p]
        eff, reason, new = classify(before, c["visitTotal"], out_rule)
        if eff == "rejected":
            outcomes.append({"seq": c["seq"], "result": "rejected", "reason": reason}); continue
        dad = c.get("dartsAtDouble")
        du = c.get("dartsUsed")
        bad_dad = None
        if dad is not None:
            if not (0 <= dad <= 3): bad_dad = "DARTS_AT_DOUBLE_INVALID"
            elif du is not None and dad > du: bad_dad = "DARTS_AT_DOUBLE_INVALID"
            # a double can only be attempted from a finishable remaining — verified by enumeration
            # to be exactly the checkout set
            elif dad > 0 and before not in CHECKOUTS[out_rule]: bad_dad = "DARTS_AT_DOUBLE_INVALID"
            # under double-out the winning dart IS a double, so a finish claiming none contradicts
            elif eff == "leg_won" and out_rule == "double" and dad < 1:
                bad_dad = "DARTS_AT_DOUBLE_INVALID"
        if bad_dad:
            outcomes.append({"seq": c["seq"], "result": "rejected", "reason": bad_dad}); continue
        rem[p] = new
        if eff == "leg_won":
            legs[p] += 1
            legs_in_set[p] += 1
            took_leg_unit = (legs_in_set[p] if playing_sets else legs[p]) >= target
            if not took_leg_unit:
                leg_no += 1
                leg_starter = set_starter if per_set else ("B" if leg_starter == "A" else "A")
                thrower = leg_starter
                rem = {"A": start, "B": start}
            elif not playing_sets:
                # A leg that decides the match is reported as such: the effect a client renders
                # differs, and a corpus that blurred them would let an engine confuse the two.
                winner = p
                eff = "match_won"
            else:
                sets_won[p] += 1
                if sets_won[p] >= sets_target:
                    winner = p
                    eff = "match_won"
                else:
                    eff = "set_won"
                    set_no += 1
                    leg_no = 1
                    legs_in_set = {"A": 0, "B": 0}
                    set_starter = "B" if set_starter == "A" else "A"
                    leg_starter = set_starter
                    thrower = set_starter
                    rem = {"A": start, "B": start}
        else:
            thrower = "B" if p == "A" else "A"
        o = {"seq": c["seq"], "result": "accepted", "effect": eff}
        if reason: o["reason"] = reason
        outcomes.append(o)
    state = {"matchState": "complete" if winner else "in_progress",
             "currentLeg": leg_no, "throwerId": None if winner else thrower,
             "remaining": rem, "legsWon": legs, "winnerId": winner}
    if playing_sets:
        state["setsWon"] = sets_won
        state["currentSet"] = set_no
    return {"outcomes": outcomes, "state": state}


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

def build_match_vectors():
    """Matches played to completion, so the corpus exercises match_won, rejection after
    completion, and leg-start alternation across a whole match."""
    cases = []
    for first_to in (2, 3, 5):
        f = fmt(first_to=first_to)
        cmds, seq = [], 1
        for leg in range(first_to):
            starter = "A" if leg % 2 == 0 else "B"
            other = "B" if starter == "A" else "A"
            # A wins every leg regardless of who started it, so the match completes in `first_to`.
            if starter == "A":
                cmds += [visit(seq, "A", 180, 3), visit(seq+1, "B", 60, 3),
                         visit(seq+2, "A", 180, 3), visit(seq+3, "B", 60, 3),
                         visit(seq+4, "A", 141, 3)]
            else:
                cmds += [visit(seq, "B", 60, 3), visit(seq+1, "A", 180, 3),
                         visit(seq+2, "B", 60, 3), visit(seq+3, "A", 180, 3),
                         visit(seq+4, "B", 60, 3), visit(seq+5, "A", 141, 3)]
            seq = cmds[-1]["seq"] + 1
        cmds.append(visit(seq, "A", 60, 3))   # a visit after the match is over
        cases.append(case(f"match.first-to-{first_to}.completes",
                          f"A wins first to {first_to}; a further visit is rejected as the match is complete.",
                          cmds, simulate(cmds, f), f))
    return cases

def build_sets_vectors():
    """Set play — implemented in two engines and, until this family, exercised by nothing.

    `Effect.SET_WON` was mapped in both conformance runners and produced by no vector;
    `Alternation.PER_SET` was parsed by both and reached by no vector. A format real competitions
    use constantly was carried by the type system and checked by nobody.

    The rule these expectations are derived from, stated before any of them:

      * a **set** is won by the player who first wins the required number of legs IN THAT SET;
      * the **match** is won by the player who first wins the required number of sets;
      * a new set starts its leg count again and numbers its legs from 1, because a set is a match
        within a match and "leg 3 of set 2" is what a scorer calls;
      * the right to open a **set** alternates; under `perSet` alternation that player also opens
        every leg inside it, and under `perLeg` the opening changes hands every leg.

    Four cases, each isolating one thing a set format does that a leg format does not.
    """
    cases = []

    def leg_won_by_opener(seq, opener):
        """One leg, opened and won by `opener` in three visits: 180 + 180 + 141 = 501."""
        other = "B" if opener == "A" else "A"
        return ([visit(seq, opener, 180, 3), visit(seq + 1, other, 60, 3),
                 visit(seq + 2, opener, 180, 3), visit(seq + 3, other, 60, 3),
                 visit(seq + 4, opener, 141, 3)], seq + 5)

    def leg_won_against_the_opener(seq, opener):
        """One leg opened by `opener` and won by the other player, who needs a fourth turn."""
        winner = "B" if opener == "A" else "A"
        return ([visit(seq, opener, 60, 3), visit(seq + 1, winner, 180, 3),
                 visit(seq + 2, opener, 60, 3), visit(seq + 3, winner, 180, 3),
                 visit(seq + 4, opener, 60, 3), visit(seq + 5, winner, 141, 3)], seq + 6)

    def run(f, winners):
        """`winners` names who takes each leg; who OPENS it is derived, never asserted.

        Written this way after getting it wrong by hand: naming the opener as well let a case claim
        a leg was opened by the player whose turn it was not, and the whole rest of that case
        desynchronised into rejections and busts that still produced a plausible-looking vector.
        The opener follows from the rule — the set's opener alternates, and inside a set the
        opening either stays with them (`perSet`) or changes hands every leg (`perLeg`).
        """
        per_set = f.get("alternateStart") == "perSet"
        legs_target = f["structure"]["legsPerSet"]["firstTo"]
        cmds, seq = [], 1
        opener = set_opener = f["throwFirst"]
        in_set = {"A": 0, "B": 0}
        for winner in winners:
            block, seq = (leg_won_by_opener(seq, opener) if opener == winner
                          else leg_won_against_the_opener(seq, opener))
            cmds += block
            in_set[winner] += 1
            if in_set[winner] >= legs_target:
                in_set = {"A": 0, "B": 0}
                set_opener = "B" if set_opener == "A" else "A"
                opener = set_opener
            else:
                opener = set_opener if per_set else ("B" if opener == "A" else "A")
        return cmds, seq

    # 1. A set is taken and the match goes on. Legs first-to-2 inside sets first-to-2, per-leg
    #    alternation: A takes leg 1, B opens leg 2 and takes it, A opens leg 3 and takes the set —
    #    so the third leg reports `set_won` rather than `match_won`, which is the distinction this
    #    whole family exists for.
    f = fmt(sets=2, legs_per_set=2)
    cmds, _ = run(f, ["A", "B", "A"])
    cases.append(case("sets.first-set-taken-match-continues",
                      "Legs first to 2 inside sets first to 2: taking the second leg of a set "
                      "reports set_won, not match_won, and the match continues with the leg count "
                      "back at 1.",
                      cmds, simulate(cmds, f), f))

    # 2. A set can be LOST and the match continue. B takes set 1, A takes set 2, and the set
    #    counter reads 1-1 — which a counter that only ever tracked the leader would get wrong.
    cmds, _ = run(f, ["B", "B", "A", "A"])
    cases.append(case("sets.a-set-lost-and-the-match-continues",
                      "B takes the first set, A takes the second: the set counter reads one each "
                      "and the match is still in progress.",
                      cmds, simulate(cmds, f), f))

    # 3. `perSet` alternation: the set's opener opens EVERY leg in it, so A throws first in both
    #    legs of set 1 — exactly where per-leg and per-set formats diverge, and a divergence a
    #    wrong implementation gets wrong silently, because the scores still add up either way.
    f2 = fmt(sets=2, legs_per_set=2, alternate="perSet")
    cmds2, _ = run(f2, ["A", "A", "B"])
    cases.append(case("sets.per-set-alternation-keeps-one-starter",
                      "Under perSet alternation the set's opener opens every leg in it, and the "
                      "right to open alternates between sets rather than between legs.",
                      cmds2, simulate(cmds2, f2), f2))

    # 4. The match ends on the SETS unit, not the legs one. A wins four legs and two sets; the
    #    deciding leg reports `match_won` and a visit after it is refused.
    cmds3, seq3 = run(f2, ["A", "A", "A", "A"])
    cmds3.append(visit(seq3, "A", 60, 3))
    cases.append(case("sets.match-ends-on-the-sets-unit",
                      "Two sets of two legs each: the deciding leg reports match_won, and a "
                      "further visit is rejected as the match is complete.",
                      cmds3, simulate(cmds3, f2), f2))
    return cases

def build_double_attempt_vectors():
    """Darts thrown at a double, recorded on EVERY visit that began on a finish — not only on one
    that finished. A player on 40 who throws a single 20 and misses has attempted a double, and
    without that attempt recorded, checkout percentage cannot be computed at all."""
    cases, f = [], fmt()
    # on a finish, missed it: the case the earlier rule never asked about
    cmds, seq = setup_cmds(40)
    if cmds:
        cmds = cmds + [visit(seq, "A", 20, 3, at_double=1)]
        cases.append(case("double-attempt.on-a-finish-missed",
                          "On 40, threw a single 20 and missed the double. One attempt, no checkout.",
                          cmds, simulate(cmds, f), f))
    # on a finish, hit it
    cmds, seq = setup_cmds(40)
    if cmds:
        cmds = cmds + [visit(seq, "A", 40, 1, at_double=1)]
        cases.append(case("double-attempt.on-a-finish-hit",
                          "On 40, hit the double with the first dart. One attempt, one checkout.",
                          cmds, simulate(cmds, f), f))
    # two attempts then a hit
    cmds, seq = setup_cmds(40)
    if cmds:
        cmds = cmds + [visit(seq, "A", 40, 3, at_double=3)]
        cases.append(case("double-attempt.three-attempts-one-hit",
                          "On 40, missed twice before hitting. Three attempts, one checkout.",
                          cmds, simulate(cmds, f), f))
    # claiming an attempt from a remaining no double can be reached from
    cmds, seq = setup_cmds(180)
    if cmds:
        cmds = cmds + [visit(seq, "A", 60, 3, at_double=1)]
        cases.append(case("double-attempt.impossible-from-this-remaining",
                          "No double can be reached from 180 within one visit, so an attempt is refused.",
                          cmds, simulate(cmds, f), f))
    # more attempts than darts thrown
    cmds, seq = setup_cmds(40)
    if cmds:
        cmds = cmds + [visit(seq, "A", 40, 1, at_double=2)]
        cases.append(case("double-attempt.more-attempts-than-darts",
                          "Two attempts cannot fit in one dart.",
                          cmds, simulate(cmds, f), f))
    # a double-out finish claiming no double attempt contradicts itself
    cmds, seq = setup_cmds(40)
    if cmds:
        cmds = cmds + [visit(seq, "A", 40, 1, at_double=0)]
        cases.append(case("double-attempt.finish-claiming-no-double",
                          "A double-out finish must have thrown at a double.",
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

def emit_kotlin(tables, path):
    """Rule DATA is generated into every platform. Only the state machine is hand-written per
    language, which removes most of the divergence surface at near-zero toolchain cost."""
    d = tables["outRules"]["double"]; m = tables["outRules"]["master"]; st = tables["outRules"]["straight"]
    def ints(xs): return ", ".join(str(x) for x in xs)
    L = []
    L.append("// GENERATED by packages/domain-spec/generate.py - DO NOT EDIT.")
    L.append("// Derived from the dartboard segment set by enumeration. specVersion " + tables["specVersion"] + ".")
    L.append("package thro.engine")
    L.append("")
    L.append("public object RuleTables {")
    L.append('    public const val SPEC_VERSION: String = "%s"' % tables["specVersion"])
    L.append("    public const val MAX_VISIT_TOTAL: Int = %d" % tables["maxVisitTotal"])
    L.append("")
    L.append("    /** Totals no three darts can produce. Validating 0..180 alone is wrong. */")
    L.append("    public val IMPOSSIBLE_VISIT_TOTALS: Set<Int> = setOf(%s)" % ints(tables["impossibleVisitTotals"]))
    L.append("")
    L.append("    /** No visit can exceed the maximum, so bust cannot occur at or above this. */")
    L.append("    public const val BUST_IMPOSSIBLE_AT_OR_ABOVE: Int = %d" % tables["invariants"]["bustImpossibleAtOrAbove"])
    L.append("")
    for name, t in (("DOUBLE", d), ("MASTER", m), ("STRAIGHT", st)):
        L.append("    private val BOGEYS_%s: IntArray = intArrayOf(%s)" % (name, ints(t["bogeyNumbers"])))
        L.append("    private const val MIN_%s: Int = %d" % (name, t["minCheckout"]))
        L.append("    private const val MAX_%s: Int = %d" % (name, t["maxCheckout"]))
    L.append("")
    L.append("    public val ONE_DART_FINISHES_DOUBLE: Set<Int> = setOf(%s)" % ints(d["oneDartFinishes"]))
    L.append("")
    L.append("    /**")
    L.append("     * One route to each finish (PD-013). A POSITION, not a fact: most finishes have")
    L.append("     * several legal routes and players disagree about which is best. The founder decided")
    L.append("     * the app shows one rather than staying silent, and these are derived by a stated")
    L.append("     * rule in the generator so every route is checkable rather than typed.")
    L.append("     *")
    L.append("     * Encoded as one string per rule and parsed once: a map literal of %d entries is a" % len(d["routes"].split("|")))
    L.append("     * lot of bytecode in one initialiser, and the parse is five lines a test can hold.")
    L.append("     */")
    for name, t in (("DOUBLE", d), ("MASTER", m), ("STRAIGHT", st)):
        L.append('    private const val ROUTES_%s: String = "%s"' % (name, t["routes"]))
    L.append("")
    L.append("    private fun parseRoutes(encoded: String): Map<Int, List<String>> =")
    L.append("        encoded.split('|').associate { entry ->")
    L.append("            val eq = entry.indexOf('=')")
    L.append("            entry.substring(0, eq).toInt() to entry.substring(eq + 1).split(',')")
    L.append("        }")
    L.append("")
    L.append("    private val ROUTE_TABLES: Map<OutRule, Map<Int, List<String>>> = mapOf(")
    L.append("        OutRule.DOUBLE to parseRoutes(ROUTES_DOUBLE),")
    L.append("        OutRule.MASTER to parseRoutes(ROUTES_MASTER),")
    L.append("        OutRule.STRAIGHT to parseRoutes(ROUTES_STRAIGHT),")
    L.append("    )")
    L.append("")
    L.append("    /** The route THRØ shows for `remaining`, or null when there is no finish. */")
    L.append("    public fun route(remaining: Int, outRule: OutRule): List<String>? =")
    L.append("        ROUTE_TABLES.getValue(outRule)[remaining]")
    L.append("")
    L.append("    private val CHECKOUTS_DOUBLE: Set<Int> = build(MIN_DOUBLE, MAX_DOUBLE, BOGEYS_DOUBLE)")
    L.append("    private val CHECKOUTS_MASTER: Set<Int> = build(MIN_MASTER, MAX_MASTER, BOGEYS_MASTER)")
    L.append("    private val CHECKOUTS_STRAIGHT: Set<Int> = build(MIN_STRAIGHT, MAX_STRAIGHT, BOGEYS_STRAIGHT)")
    L.append("")
    L.append("    public fun checkouts(outRule: OutRule): Set<Int> = when (outRule) {")
    L.append("        OutRule.DOUBLE -> CHECKOUTS_DOUBLE")
    L.append("        OutRule.MASTER -> CHECKOUTS_MASTER")
    L.append("        OutRule.STRAIGHT -> CHECKOUTS_STRAIGHT")
    L.append("    }")
    L.append("")
    L.append("    /**")
    L.append("     * Counted totals a visit can record while the player has not yet opened (PD-008).")
    L.append("     *")
    L.append("     * A legal opening segment plus up to two free darts after it. Under double-in the")
    L.append("     * bull opens, so the largest is D25+T20+T20 = %d; the totals three darts can make" % tables["inRules"]["double"]["maxOpeningTotal"])
    L.append("     * but no opening sequence can are %s." % ints(tables["inRules"]["double"]["unopenableTotals"]))
    L.append("     */")
    for name in ("DOUBLE", "MASTER", "STRAIGHT"):
        t = tables["inRules"][name.lower()]
        L.append("    private val UNOPENABLE_%s: IntArray = intArrayOf(%s)" % (name, ints(t["unopenableTotals"])))
        L.append("    private const val MAX_OPENING_%s: Int = %d" % (name, t["maxOpeningTotal"]))
    L.append("")
    L.append("    private val OPENING_DOUBLE: Set<Int> = opening(MAX_OPENING_DOUBLE, UNOPENABLE_DOUBLE)")
    L.append("    private val OPENING_MASTER: Set<Int> = opening(MAX_OPENING_MASTER, UNOPENABLE_MASTER)")
    L.append("    private val OPENING_STRAIGHT: Set<Int> = opening(MAX_OPENING_STRAIGHT, UNOPENABLE_STRAIGHT)")
    L.append("")
    L.append("    public fun openingTotals(inRule: InRule): Set<Int> = when (inRule) {")
    L.append("        InRule.DOUBLE -> OPENING_DOUBLE")
    L.append("        InRule.MASTER -> OPENING_MASTER")
    L.append("        InRule.STRAIGHT -> OPENING_STRAIGHT")
    L.append("    }")
    L.append("")
    L.append("    private fun opening(max: Int, unopenable: IntArray): Set<Int> {")
    L.append("        val bad = unopenable.toHashSet()")
    L.append("        val out = HashSet<Int>(max)")
    L.append("        for (v in 1..max) if (v !in bad && v !in IMPOSSIBLE_VISIT_TOTALS) out.add(v)")
    L.append("        return out")
    L.append("    }")
    L.append("")
    L.append("    /** The floor is the rule's own: under straight-out a single 1 finishes. */")
    L.append("    private fun build(min: Int, max: Int, bogeys: IntArray): Set<Int> {")
    L.append("        val bad = bogeys.toHashSet()")
    L.append("        val out = HashSet<Int>(max)")
    L.append("        for (v in min..max) if (v !in bad) out.add(v)")
    L.append("        return out")
    L.append("    }")
    L.append("}")
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text("\n".join(L) + "\n")
    return path

def emit_swift(tables, path):
    """The same rule DATA, generated into Swift.

    ADR-002 keeps the shared-core question open by making the CORPUS the contract rather than shared
    code. That only holds if the rule tables themselves are generated into every platform: a
    hand-copied checkout set is a divergence waiting to happen, and it would be one nobody notices
    until a player is told they cannot finish a number they can.
    """
    d = tables["outRules"]["double"]; m = tables["outRules"]["master"]; st = tables["outRules"]["straight"]
    def ints(xs): return ", ".join(str(x) for x in xs)
    L = []
    L.append("// GENERATED by packages/domain-spec/generate.py - DO NOT EDIT.")
    L.append("// Derived from the dartboard segment set by enumeration. specVersion " + tables["specVersion"] + ".")
    L.append("")
    L.append("public enum RuleTables {")
    L.append('    public static let specVersion = "%s"' % tables["specVersion"])
    L.append("    public static let maxVisitTotal = %d" % tables["maxVisitTotal"])
    L.append("")
    L.append("    /// Totals no three darts can produce. Validating 0...180 alone is wrong.")
    L.append("    public static let impossibleVisitTotals: Set<Int> = [%s]" % ints(tables["impossibleVisitTotals"]))
    L.append("")
    L.append("    /// No visit can exceed the maximum, so bust cannot occur at or above this.")
    L.append("    public static let bustImpossibleAtOrAbove = %d" % tables["invariants"]["bustImpossibleAtOrAbove"])
    L.append("")
    for name, t in (("double", d), ("master", m), ("straight", st)):
        L.append("    private static let bogeys%s: Set<Int> = [%s]" % (name.capitalize(), ints(t["bogeyNumbers"])))
        L.append("    private static let min%s = %d" % (name.capitalize(), t["minCheckout"]))
        L.append("    private static let max%s = %d" % (name.capitalize(), t["maxCheckout"]))
    L.append("")
    L.append("    public static let oneDartFinishesDouble: Set<Int> = [%s]" % ints(d["oneDartFinishes"]))
    L.append("")
    L.append("    /// One route to each finish (PD-013). A POSITION, not a fact: most finishes have")
    L.append("    /// several legal routes and players disagree about which is best. The founder decided")
    L.append("    /// the app shows one rather than staying silent, and these are derived by a stated rule")
    L.append("    /// in the generator, so every route is checkable rather than typed.")
    L.append("    ///")
    L.append("    /// Encoded as one string per rule and parsed once, for the reason the Kotlin gives.")
    for name, t in (("double", d), ("master", m), ("straight", st)):
        L.append('    private static let routes%s = "%s"' % (name.capitalize(), t["routes"]))
    L.append("")
    L.append("    private static func parseRoutes(_ encoded: String) -> [Int: [String]] {")
    L.append("        var out: [Int: [String]] = [:]")
    L.append("        for entry in encoded.split(separator: \"|\") {")
    L.append("            let parts = entry.split(separator: \"=\")")
    L.append("            guard parts.count == 2, let n = Int(parts[0]) else { continue }")
    L.append("            out[n] = parts[1].split(separator: \",\").map(String.init)")
    L.append("        }")
    L.append("        return out")
    L.append("    }")
    L.append("")
    L.append("    private static let routeTableDouble = parseRoutes(routesDouble)")
    L.append("    private static let routeTableMaster = parseRoutes(routesMaster)")
    L.append("    private static let routeTableStraight = parseRoutes(routesStraight)")
    L.append("")
    L.append("    /// The route THRØ shows for `remaining`, or nil when there is no finish.")
    L.append("    public static func route(_ remaining: Int, _ outRule: OutRule) -> [String]? {")
    L.append("        switch outRule {")
    L.append("        case .double: return routeTableDouble[remaining]")
    L.append("        case .master: return routeTableMaster[remaining]")
    L.append("        case .straight: return routeTableStraight[remaining]")
    L.append("        }")
    L.append("    }")
    L.append("")
    L.append("    private static let checkoutsDouble = build(minDouble, maxDouble, bogeysDouble)")
    L.append("    private static let checkoutsMaster = build(minMaster, maxMaster, bogeysMaster)")
    L.append("    private static let checkoutsStraight = build(minStraight, maxStraight, bogeysStraight)")
    L.append("")
    L.append("    public static func checkouts(_ outRule: OutRule) -> Set<Int> {")
    L.append("        switch outRule {")
    L.append("        case .double: return checkoutsDouble")
    L.append("        case .master: return checkoutsMaster")
    L.append("        case .straight: return checkoutsStraight")
    L.append("        }")
    L.append("    }")
    L.append("")
    L.append("    /// Counted totals a visit can record while the player has not yet opened (PD-008):")
    L.append("    /// a legal opening segment plus up to two free darts after it. Under double-in the")
    L.append("    /// bull opens, so the largest is D25+T20+T20 = %d." % tables["inRules"]["double"]["maxOpeningTotal"])
    for name in ("double", "master", "straight"):
        t = tables["inRules"][name]
        L.append("    private static let unopenable%s: Set<Int> = [%s]" % (name.capitalize(), ints(t["unopenableTotals"])))
        L.append("    private static let maxOpening%s = %d" % (name.capitalize(), t["maxOpeningTotal"]))
    L.append("")
    L.append("    private static let openingDouble = opening(maxOpeningDouble, unopenableDouble)")
    L.append("    private static let openingMaster = opening(maxOpeningMaster, unopenableMaster)")
    L.append("    private static let openingStraight = opening(maxOpeningStraight, unopenableStraight)")
    L.append("")
    L.append("    public static func openingTotals(_ inRule: InRule) -> Set<Int> {")
    L.append("        switch inRule {")
    L.append("        case .double: return openingDouble")
    L.append("        case .master: return openingMaster")
    L.append("        case .straight: return openingStraight")
    L.append("        }")
    L.append("    }")
    L.append("")
    L.append("    private static func opening(_ max: Int, _ unopenable: Set<Int>) -> Set<Int> {")
    L.append("        var out = Set<Int>(minimumCapacity: max)")
    L.append("        for v in 1...max where !unopenable.contains(v) && !impossibleVisitTotals.contains(v) {")
    L.append("            out.insert(v)")
    L.append("        }")
    L.append("        return out")
    L.append("    }")
    L.append("")
    L.append("    /// The floor is the rule's own: under straight-out a single 1 finishes.")
    L.append("    private static func build(_ min: Int, _ max: Int, _ bogeys: Set<Int>) -> Set<Int> {")
    L.append("        var out = Set<Int>(minimumCapacity: max)")
    L.append("        for v in min...max where !bogeys.contains(v) { out.insert(v) }")
    L.append("        return out")
    L.append("    }")
    L.append("}")
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text("\n".join(L) + "\n")
    return path

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
    kt = emit_kotlin(tables, OUT.parent / "engine" / "src" / "main" / "kotlin" / "thro" / "engine" / "RuleTables.kt")
    sw = emit_swift(tables, OUT.parent / "engine-swift" / "Sources" / "ThroEngine" / "RuleTables.swift")

    files, total = {}, 0
    for name, cases in (("bust-rules.jsonl", build_bust_vectors()),
                        ("checkouts.jsonl", build_checkout_vectors()),
                        ("leg-rotation.jsonl", build_rotation_vectors()),
                        ("match-completion.jsonl", build_match_vectors()),
                        ("sets-and-legs.jsonl", build_sets_vectors()),
                        ("double-attempts.jsonl", build_double_attempt_vectors()),
                        ("adversarial.jsonl", build_adversarial_vectors())):
        p, n = write_jsonl(name, cases); total += n
        files[name] = {"cases": n,
                       "sha256": hashlib.sha256(p.read_bytes()).hexdigest()}

    if full:
        p = OUT / "vectors" / "core-transitions.jsonl"
        n = 0
        with open(p, "w") as fh:
            # Every out-rule, and from a remaining of 1. It covered double-out from 2 only, so two
            # rules in three were never exhausted and the one transition where the engines disagreed
            # with this spec — finishing from 1 under straight-out, which a single 1 does — was
            # outside the table entirely. A gap in an exhaustive check is worse than no check,
            # because the number in the README reads as if it covered everything.
            for out_rule in ("double", "master", "straight"):
                for rem in range(1, 502):
                    for vt in sorted(ACHIEVABLE_3):
                        eff, reason, new = classify(rem, vt, out_rule)
                        fh.write(json.dumps({"remaining": rem, "visitTotal": vt, "outRule": out_rule,
                                             "effect": eff, "reason": reason, "newRemaining": new},
                                            separators=(",", ":")) + "\n"); n += 1
        # Deliberately excluded from the manifest and the total: it is regenerated in CI rather
        # than committed (8.6 MB), so counting it would make the committed manifest churn on every
        # full run and turn the staleness gate into noise.
        print(f"exhaustive transition table: {n} cases (not committed)")

    (OUT / "vectors" / "manifest.json").write_text(json.dumps(
        {"specVersion": SPEC_VERSION, "files": files, "totalCases": total}, indent=2) + "\n")

    print(f"specVersion {SPEC_VERSION}")
    print(f"impossible visit totals ({len(IMPOSSIBLE_3)}): {IMPOSSIBLE_3}")
    for r in ("double", "master", "straight"):
        t = tables["outRules"][r]
        print(f"{r:9} max checkout {t['maxCheckout']:>3}  bogeys {t['bogeyNumbers']}  "
              f"1-dart finishes {len(t['oneDartFinishes'])}  min darts 501={t['minDartsToFinish']['501']}")
    print(f"vectors written: {total} cases across {len(files)} files")
    print(f"generated {kt}")

if __name__ == "__main__":
    main()
