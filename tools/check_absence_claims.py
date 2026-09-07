#!/usr/bin/env python3
"""Hold every claim that something is ABSENT to a mechanical proof that it still is.

`check_test_counts.py` was written because a stated number drifted five times and each time it was
found by hand afterwards. This is the same failure in prose, and it has now happened too: the
runbook said *"Attestation | Not in the app… Every result is self-reported"* three weeks after
PD-011 shipped, said *"Haptics | None"* after PD-015 shipped them, and said the checkout card
carried no route because *"no route table exists in this repository"* after PD-013 built one per
out-rule. Three sentences, all false, all in a document whose purpose is to tell the founder what
this build does.

A claim of absence is the most dangerous kind to leave unchecked, because **it decays in the
direction of a lie**: the code gains a capability and the sentence does not notice. A claim of
presence at least fails loudly when the thing is removed.

So each registered claim carries two halves, and BOTH must hold:

  - **the sentences**, by regex, in the documents that state it. A pattern that matches nothing is a
    failure, not a pass — it means the sentence was reworded and the claim silently stopped being
    checked, which is exactly how `check_test_counts.py` learned to treat a missing anchor.
  - **the proof**: a search that must find **zero** hits. One hit and the claim is no longer true.

Only claims that are load-bearing AND mechanically provable belong here. A sentence whose truth
needs a human to judge it does not become checkable by being listed; it becomes a false comfort.

The proof reads **lines, not code**, so a comment naming a forbidden symbol fails too. That is
deliberate. Narrowing a check to "only the real code" is precisely what made the icon-only-button
rule pass on a button with no label: the narrowing looks like precision and is where the hole gets
in. A comment that has to say `URLSession` can say *the networking API* instead, which costs one
word; a check that quietly stops seeing half its input costs a defect nobody finds.
"""
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parents[1]
CLIENT = "packages/client-ios/Sources"


class Claim:
    def __init__(self, what, why, sentences, where, forbidden, glob="**/*.swift"):
        self.what = what
        self.why = why
        # (document, pattern) pairs. Each must still match, or the claim stopped being stated.
        self.sentences = sentences
        self.where = where          # directory or file the proof searches
        self.forbidden = re.compile(forbidden)
        self.glob = glob

    def hits(self):
        base = ROOT / self.where
        paths = sorted(base.rglob(self.glob.split("/")[-1])) if base.is_dir() else [base]
        found = []
        for path in paths:
            for i, line in enumerate(path.read_text(encoding="utf-8").splitlines()):
                if self.forbidden.search(line):
                    found.append(f"{path.relative_to(ROOT)}:{i + 1}: {line.strip()[:100]}")
        return found


CLAIMS = [
    Claim(
        what="the iOS client has no network code",
        why=("LATENCY_BUDGETS.md requires the scoring module to have no compile-time dependency on a "
             "network layer, and the app tells the player *nothing leaves the phone*. A single "
             "URLSession would make that sentence false while every test still passed."),
        sentences=[
            ("packages/client-ios/Sources/ThroApp/ThroRootView.swift",
             r"There is no network code in this app"),
            ("packages/client-ios/Package.swift",
             r"There is no network target in this package for anything to depend on"),
        ],
        where=CLIENT,
        forbidden=r"\b(URLSession|URLRequest|NWConnection|NWPathMonitor|CFSocket|Alamofire)\b",
    ),
    Claim(
        what="the app never supplies a rating value",
        why=("OD-001 is open, and its own refusal names the way it would be decided by accident: "
             "*shipping a placeholder rating to fill the UI*. `PlayerRef` carries the field because "
             "the design export does; nothing here may ever pass it."),
        sentences=[
            ("packages/client-ios/Sources/ThroDesign/Forms.swift", r"never supplied by this app"),
        ],
        where=CLIENT,
        forbidden=r"PlayerRef\([^)]*\brating\s*:",
    ),
    Claim(
        what="reading an export writes nothing",
        why=("ADR-006: merging an exported journal into a live one is the reconciliation sync needs, "
             "and an import that pretended to do it would leave a journal whose per-device sequence "
             "claims this device wrote rows it did not."),
        sentences=[
            ("docs/adr/ADR-006-offline-sync.md", r"\*\*There is deliberately no importer\.\*\*"),
        ],
        where="packages/client-ios/Sources/ThroJournal/Export.swift",
        forbidden=r"\b(INSERT\s+INTO|DELETE\s+FROM|UPDATE\s+\w+\s+SET)\b",
    ),
    Claim(
        what="there is no account, sign-in or credential store in the client",
        why=("B4 — the authentication and identity-claim surface — is a founder blocker and the "
             "design for it does not exist. Settings says *Account and profile · Not built*. An "
             "auth API appearing before that surface is designed is the shape B4 exists to prevent."),
        sentences=[
            ("packages/client-ios/Sources/ThroApp/ThroRootView.swift",
             r'label: "Account and profile", value: "Not built"'),
        ],
        where=CLIENT,
        forbidden=r"\b(AuthenticationServices|LocalAuthentication|ASAuthorization\w*|LAContext"
                  r"|kSecClass|SecItemAdd|SecItemCopyMatching)\b",
    ),
]


def main() -> int:
    problems = []
    for claim in CLAIMS:
        for document, pattern in claim.sentences:
            path = ROOT / document
            if not path.exists():
                problems.append(f"{claim.what}: {document} does not exist")
                continue
            if not re.search(pattern, path.read_text(encoding="utf-8")):
                problems.append(
                    f"{claim.what}: nothing in {document} matches {pattern!r} any more, so the "
                    f"claim stopped being checked. Reword the pattern or the document."
                )
        hits = claim.hits()
        mark = "ok " if not hits else "BAD"
        print(f"{mark} {claim.what}")
        for hit in hits[:10]:
            print(f"      {hit}")
            problems.append(f"{claim.what}: {hit}")
        if len(hits) > 10:
            print(f"      … and {len(hits) - 10} more")

    if problems:
        print("\nA claim of absence is no longer true, or no longer stated:", file=sys.stderr)
        for problem in problems:
            print(f"  - {problem}", file=sys.stderr)
        print("\nEither the claim is now false and the document must say what is true, or the code "
              "gained something it should not have.", file=sys.stderr)
        return 1
    print(f"\nEvery one of the {len(CLAIMS)} registered absences is still stated and still true.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
