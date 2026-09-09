#!/usr/bin/env python3
"""ADR-013's discipline, enforced rather than described.

ADR-013 says three things CI must hold and, until this file, nothing did:

  * destructive statements need an explicit approval marker in the file, and CI fails on an
    unmarked DROP, TRUNCATE or column type change;
  * a migration may never UPDATE or DELETE rows in `evidence` — with the one exception the
    2026-09-09 amendment names: removing personal data (pseudonymisation or erasure) that a
    read-time upcast cannot achieve, marked as such;
  * every migration runs as `thro_owner`, so ownership — and with it the append-only guarantee —
    never lands on the deploy user.

It also holds the things the ledger runner (`services/api/src/main/kotlin/thro/api/Migrations.kt`)
assumes about file names: `V<number>__<snake_name>.sql`, versions unique and contiguous from 1.

Markers, one line each, anywhere in the file:

    -- APPROVED-DESTRUCTIVE: <why this drop is safe, in a sentence>
    -- APPROVED-EVIDENCE-REWRITE (pseudonymisation|erasure): <what personal data goes, and why an upcast cannot do it>

A marker is an approval recorded next to the statement it approves, so a reviewer of the diff sees
both. It is not a way to switch the check off: a file whose marker gives no reason fails too.

Exit status 1 on any finding; the report says which file and which rule.
"""
from __future__ import annotations

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
MIGRATIONS = ROOT / "services" / "api" / "migrations"

NAME = re.compile(r"^V(\d{3})__([a-z0-9_]+)\.sql$")
# Judged per statement, on its leading keywords, so the privilege name in `REVOKE ... TRUNCATE`
# and the word "drop" in a comment are not statements.
DESTRUCTIVE_START = re.compile(r"^(DROP\s+\w+|TRUNCATE\b)", re.IGNORECASE)
DESTRUCTIVE_ALTER = re.compile(r"^ALTER\s+TABLE\b.*?\b(DROP\s+(COLUMN|CONSTRAINT)|ALTER\s+COLUMN\s+\w+\s+(SET\s+DATA\s+)?TYPE)\b", re.IGNORECASE | re.DOTALL)
EVIDENCE_DML = re.compile(r"^(UPDATE|DELETE\s+FROM)\s+evidence\.", re.IGNORECASE)
# What may precede SET ROLE: creating the schema the owner will own, or an extension only a
# superuser may install. Anything else that runs before SET ROLE would be owned by the deploy user.
BEFORE_ROLE_OK = re.compile(r"^(CREATE\s+SCHEMA\s+\w+\s+AUTHORIZATION\s+thro_owner|CREATE\s+EXTENSION\b)", re.IGNORECASE)
DESTRUCTIVE_MARKER = re.compile(r"^--\s*APPROVED-DESTRUCTIVE:\s*(\S.{19,})$", re.MULTILINE)
REWRITE_MARKER = re.compile(r"^--\s*APPROVED-EVIDENCE-REWRITE\s*\((pseudonymisation|erasure)\):\s*(\S.{19,})$", re.MULTILINE)


def strip_comments(sql: str) -> str:
    """SQL with `--` comments removed, so a rule that is *described* in a comment does not trip it."""
    return "\n".join(line.split("--", 1)[0] for line in sql.splitlines())


def statements(code: str) -> list[str]:
    """Top-level statements. Dollar-quoted bodies are kept whole so a `;` inside a function body
    does not split it; what is inside a body is the function's business, not a migration statement."""
    out, buf, i, n = [], [], 0, len(code)
    in_dollar = None
    while i < n:
        if in_dollar:
            j = code.find(in_dollar, i)
            if j < 0:
                buf.append(code[i:]); break
            buf.append(code[i:j + len(in_dollar)]); i = j + len(in_dollar); in_dollar = None
            continue
        m = re.match(r"\$[A-Za-z_]*\$", code[i:])
        if m:
            in_dollar = m.group(0); buf.append(in_dollar); i += len(in_dollar); continue
        if code[i] == ";":
            stmt = "".join(buf).strip()
            if stmt: out.append(stmt)
            buf = []
        else:
            buf.append(code[i])
        i += 1
    tail = "".join(buf).strip()
    if tail: out.append(tail)
    return out


def destructive(stmt: str) -> str | None:
    if DESTRUCTIVE_START.match(stmt):
        return " ".join(stmt.split()[:2]).upper()
    m = DESTRUCTIVE_ALTER.match(stmt)
    if m:
        return "ALTER TABLE ... " + " ".join(m.group(1).split()[:2]).upper()
    return None


def main() -> int:
    files = sorted(MIGRATIONS.glob("*.sql"))
    findings: list[str] = []
    versions: list[int] = []
    for f in files:
        m = NAME.match(f.name)
        if not m:
            findings.append(f"{f.name}: not named V<3 digits>__<snake_name>.sql")
            continue
        versions.append(int(m.group(1)))
        text = f.read_text(encoding="utf-8")
        stmts = statements(strip_comments(text))

        if versions[-1] != 1:
            first_owned = next((i for i, st in enumerate(stmts) if not BEFORE_ROLE_OK.match(st)), None)
            if first_owned is None or not stmts[first_owned].upper().startswith("SET ROLE THRO_OWNER"):
                findings.append(f"{f.name}: an owned statement runs before SET ROLE thro_owner (ADR-013: DDL runs as the owner)")
            if not stmts or not stmts[-1].upper().startswith("RESET ROLE"):
                findings.append(f"{f.name}: the last statement is not RESET ROLE")

        hits = sorted({d for st in stmts if (d := destructive(st))})
        if hits and not DESTRUCTIVE_MARKER.search(text):
            findings.append(f"{f.name}: destructive statement(s) {hits} without an '-- APPROVED-DESTRUCTIVE: <reason>' marker (ADR-013)")

        if any(EVIDENCE_DML.match(st) for st in stmts) and not REWRITE_MARKER.search(text):
            findings.append(
                f"{f.name}: rewrites rows in evidence without an '-- APPROVED-EVIDENCE-REWRITE (pseudonymisation|erasure): <reason>' marker "
                "(ADR-013: evidence is never rewritten except to remove personal data)"
            )

    if versions:
        expected = list(range(1, len(versions) + 1))
        if versions != expected:
            findings.append(f"migration versions are not unique and contiguous from 1: {versions}")

    print(f"{len(files)} migrations checked, latest V{max(versions):03d}" if versions else "no migrations found")
    for f in files:
        text = f.read_text(encoding="utf-8")
        flags = []
        if DESTRUCTIVE_MARKER.search(text):
            flags.append("destructive, approved")
        if REWRITE_MARKER.search(text):
            flags.append(f"evidence rewrite, approved ({REWRITE_MARKER.search(text).group(1)})")
        if flags:
            print(f"  {f.name}: {'; '.join(flags)}")
    if findings:
        print()
        for x in findings:
            print(f"  FAIL  {x}")
        return 1
    print("  every migration keeps ADR-013's discipline")
    return 0


if __name__ == "__main__":
    sys.exit(main())
