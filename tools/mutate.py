"""Mutation testing: break one thing, see whether the suite notices, put it back (PD-165).

A test that has only ever been green is a test nobody has shown can fail. Where the first red run was not
watched and cannot be recovered, this answers the same question: remove a guard, run the suite, and see
whether anything goes red. A mutation that SURVIVES is either a gap in the suite or a rule enforced a
layer down — read which before calling it either.

    python3 tools/mutate.py <source-path> <backup-path> <test.class.Name> <old> <new> [<old> <new> ...]

It restores the file after every mutation and again at the end. Take the backup first:
    cp services/api/src/main/kotlin/thro/api/Foo.kt /tmp/Foo.keep
"""
import pathlib, subprocess, sys, os, xml.etree.ElementTree as ET

REPO = "/Users/jensonlr/Documents/Thro-Darts-App"
env = dict(os.environ)
env.update(PATH="/opt/homebrew/opt/openjdk@21/bin:" + env["PATH"],
           JAVA_HOME="/opt/homebrew/opt/openjdk@21",
           PGHOST="localhost", PGPORT="5432", PGUSER="postgres", PGDATABASE="postgres",
           THRO_REQUIRE_DB="1")

def run(suite):
    subprocess.run(["gradle", "-p", "services/api", "test", "--tests", suite, "--rerun", "-q"],
                   cwd=REPO, env=env, capture_output=True)
    x = pathlib.Path(REPO, f"services/api/build/test-results/test/TEST-{suite}.xml")
    if not x.exists(): return None, "no report (did not compile?)"
    r = ET.parse(x).getroot()
    fails = [tc.get("name") for tc in r.iter("testcase") if tc.find("failure") is not None]
    return int(r.get("failures")), fails

def mutate(path, old, new):
    p = pathlib.Path(REPO, path); s = p.read_text()
    if old not in s: return False
    p.write_text(s.replace(old, new, 1)); return True

def restore(path, keep):
    pathlib.Path(REPO, path).write_text(pathlib.Path(keep).read_text())

path, keep, suite = sys.argv[1], sys.argv[2], sys.argv[3]
muts = []
for i in range(4, len(sys.argv), 2):
    muts.append((sys.argv[i], sys.argv[i+1]))

for old, new in muts:
    restore(path, keep)
    if not mutate(path, old, new):
        print(f"SKIP (anchor absent): {old[:60]}"); continue
    n, fails = run(suite)
    verdict = "CAUGHT" if (n or 0) > 0 else "*** SURVIVED ***"
    print(f"{verdict}  mutation: {old[:70]}")
    if fails: print(f"          caught by: {fails[0][:80]}")
restore(path, keep)
print("restored")
