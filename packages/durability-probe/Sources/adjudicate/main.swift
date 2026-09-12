import Foundation
import DurabilityProbe

// Adjudicates a journal pulled off a device, on the Mac.
//
//     swift run adjudicate <journal.sqlite> [lastAcknowledgedSeq]
//
// This exists so the pass rule lives in exactly one place. The power-cut script used to
// re-implement it in shell as `LOST=$(( LAST_ACK - MAXSEQ ))`, which checked the tail and nothing
// else — not the row count, not holes, not integrity_check — and would have printed "nothing
// acknowledged was lost" over a journal missing an interior page. That is the same false pass
// KillProbe.verdict was written to remove, reintroduced one layer up. Every script now comes
// through here.
//
// Exit codes follow KillProbe.Verdict: 0 pass, 2 fail, 3 void (nothing to adjudicate), 64 usage.

func usage() -> Never {
    print("usage: adjudicate <journal.sqlite> [lastAcknowledgedSeq]")
    exit(64)
}

let args = CommandLine.arguments
guard args.count >= 2, args.count <= 3 else { usage() }

let path = args[1]
guard FileManager.default.fileExists(atPath: path) else {
    print("ADJUDICATE-ERROR no file at \(path)")
    exit(64)
}

var lastAck: Int? = nil
if args.count == 3 {
    let raw = args[2].trimmingCharacters(in: .whitespacesAndNewlines)
    guard let parsed = Int(raw), parsed >= 0 else {
        print("ADJUDICATE-ERROR unparseable acknowledgement '\(args[2])'")
        exit(64)
    }
    lastAck = parsed
}

// Checked BEFORE the database is opened, and by size rather than existence. SQLite creates an
// empty -wal alongside a WAL-mode database the moment a connection reads it, so a check made after
// `inspect` — which is where this check first lived — always found a sidecar and never warned. The
// demonstration that was meant to show the warning showed it silently absent instead.
let hadSidecar = KillProbe.hasWalSidecar(at: path)

do {
    let report = try KillProbe.inspect(at: path)
    // A WAL-mode journal with no sidecar alongside it is the shape of the "967 visits lost" mistake:
    // the recent commits are in the file that was not copied. Say so loudly. It is not made a void
    // here because a cleanly closed WAL database legitimately has no sidecar — but no journal that
    // was SIGKILLed or power-cut closed cleanly, so for this test it almost always means the pull
    // was incomplete.
    if report.journalMode.lowercased() == "wal", !hadSidecar {
        print("ADJUDICATE-WARNING journal_mode is wal and no non-empty \(path)-wal sidecar was present.")
        print("ADJUDICATE-WARNING If this journal came off a device that was killed or restarted, the")
        print("ADJUDICATE-WARNING most recent commits live in that file and this verdict is missing them.")
    }
    KillProbe.printReport(report, lastAck: lastAck)
    exit(KillProbe.verdict(report, lastAck: lastAck).exitCode)
} catch {
    print("ADJUDICATE-ERROR \(error)")
    exit(1)
}
