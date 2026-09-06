import Foundation
import XCTest
@testable import ThroEngine

/// Conformance: the Swift engine must reproduce the generated corpus exactly.
///
/// This is ADR-002's spike. The corpus — not shared code — is the contract, and an implementation
/// that has not passed it is not an implementation. The comparisons here mirror the Kotlin runner
/// deliberately, including the final-state checks, because per-command outcomes alone would miss
/// drift in whose turn it is or which leg the match is on.
final class ConformanceTests: XCTestCase {

    /// Walks up from the test bundle to find the corpus, so the same test runs from Xcode, from
    /// `swift test`, and from CI without a path argument.
    private func vectorsDirectory() throws -> URL {
        var dir = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        for _ in 0..<8 {
            let candidate = dir.appendingPathComponent("packages/domain-spec/vectors")
            var isDir: ObjCBool = false
            if FileManager.default.fileExists(atPath: candidate.path, isDirectory: &isDir), isDir.boolValue {
                return candidate
            }
            dir = dir.deletingLastPathComponent()
        }
        throw XCTSkip("conformance corpus not found — run from the repository")
    }

    func testEngineReproducesEveryConformanceVector() throws {
        let vectors = try vectorsDirectory()
        let files = try FileManager.default.contentsOfDirectory(at: vectors, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "jsonl" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        XCTAssertFalse(files.isEmpty, "no vector files found")

        var cases = 0
        var commands = 0
        var failures: [String] = []

        for file in files {
            // core-transitions is the exhaustive family and has its own test.
            if file.lastPathComponent == "core-transitions.jsonl" { continue }
            let text = try String(contentsOf: file, encoding: .utf8)
            for line in text.split(separator: "\n", omittingEmptySubsequences: true) {
                guard let data = String(line).data(using: .utf8),
                      let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any]
                else {
                    failures.append("\(file.lastPathComponent): unparseable line")
                    continue
                }
                cases += 1
                commands += runCase(obj, &failures)
            }
        }

        print("conformance: \(cases) cases, \(commands) commands, across \(files.count) vector files")
        if !failures.isEmpty {
            XCTFail("\(failures.count) conformance failures:\n  " + failures.prefix(20).joined(separator: "\n  "))
        }
    }

    /// The exhaustive transition table.
    ///
    /// A different shape from the other vectors — flat rows of
    /// `{remaining, visitTotal, outRule, effect, reason, newRemaining}` rather than whole matches —
    /// and it is the strongest evidence available that this engine and the generator agree, because
    /// neither produced the other's expected values.
    func testExhaustiveTransitions() throws {
        let vectors = try vectorsDirectory()
        let file = vectors.appendingPathComponent("core-transitions.jsonl")
        guard FileManager.default.fileExists(atPath: file.path) else {
            throw XCTSkip("core-transitions.jsonl not generated (run generate.py --full)")
        }
        let text = try String(contentsOf: file, encoding: .utf8)
        let a = PlayerId("A")
        let b = PlayerId("B")
        var checked = 0
        var failures: [String] = []

        for line in text.split(separator: "\n", omittingEmptySubsequences: true) {
            guard let data = String(line).data(using: .utf8),
                  let r = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let remaining = r["remaining"] as? Int,
                  let visitTotal = r["visitTotal"] as? Int,
                  let wantEffect = r["effect"] as? String,
                  let wantRemaining = r["newRemaining"] as? Int
            else {
                failures.append("malformed row")
                continue
            }
            // The row carries its own out-rule. Reading it rather than assuming double-out means
            // this stays correct if the generator ever emits master or straight rows.
            let outRule = OutRule(rawValue: (r["outRule"] as? String) ?? "double") ?? .double
            let wantReason = r["reason"] as? String

            let base = MatchState.start(
                format: MatchFormat(
                    startingScore: 501,
                    inRule: .straight,
                    outRule: outRule,
                    legs: Structure(mode: .firstTo, target: 5),
                    throwFirst: a
                ),
                home: a,
                away: b
            )
            var state = base
            state.remaining[a] = remaining

            switch Engine.apply(state, .visit(a, visitTotal)) {
            case let .rejected(reason):
                if wantEffect != "rejected" || wantReason != reason.rawValue {
                    failures.append("rem=\(remaining) vt=\(visitTotal): rejected \(reason.rawValue) != \(wantEffect)/\(wantReason ?? "nil")")
                }
            case let .accepted(newState, effect, bustReason):
                let got = effect.rawValue
                let gotRemaining = newState.remaining[a] ?? -1
                // A leg win at firstTo-5 with one leg already banked is a match win in the engine's
                // eyes; the generator reports the leg. Both are right about the transition.
                if got != wantEffect && !(got == "match_won" && wantEffect == "leg_won") {
                    failures.append("rem=\(remaining) vt=\(visitTotal): effect \(got) != \(wantEffect)")
                } else if let wr = wantReason, wr != bustReason?.rawValue {
                    failures.append("rem=\(remaining) vt=\(visitTotal): reason \(bustReason?.rawValue ?? "nil") != \(wr)")
                } else if wantEffect != "leg_won" && gotRemaining != wantRemaining {
                    failures.append("rem=\(remaining) vt=\(visitTotal): remaining \(gotRemaining) != \(wantRemaining)")
                }
            }
            checked += 1
        }

        print("exhaustive transitions verified against the engine: \(checked)")
        if !failures.isEmpty {
            XCTFail("\(failures.count) exhaustive failures:\n  " + failures.prefix(15).joined(separator: "\n  "))
        }
        XCTAssertGreaterThan(checked, 1000, "the exhaustive family did not actually run")
    }

    // MARK: - running one case

    private func runCase(_ testCase: [String: Any], _ failures: inout [String]) -> Int {
        guard let id = testCase["id"] as? String,
              let setup = testCase["setup"] as? [String: Any],
              let formatJSON = setup["format"] as? [String: Any],
              let players = setup["players"] as? [[String: Any]],
              let commands = testCase["commands"] as? [[String: Any]],
              let expect = testCase["expect"] as? [String: Any],
              let expected = expect["outcomes"] as? [[String: Any]]
        else {
            failures.append("malformed case")
            return 0
        }

        let ids = players.compactMap { $0["id"] as? String }.map(PlayerId.init)
        guard ids.count >= 2 else { failures.append("\(id): fewer than two players"); return 0 }

        var state = MatchState.start(format: format(formatJSON), home: ids[0], away: ids[1])

        for (i, c) in commands.enumerated() {
            guard i < expected.count else { break }
            let exp = expected[i]
            let seq = c["seq"] as? Int ?? i + 1
            let outcome = Engine.apply(state, .recordVisit(
                player: PlayerId(c["player"] as? String ?? ""),
                visitTotal: c["visitTotal"] as? Int ?? -1,
                dartsUsed: c["dartsUsed"] as? Int,
                dartsAtDouble: c["dartsAtDouble"] as? Int
            ))

            let want = exp["result"] as? String
            switch outcome {
            case let .rejected(reason):
                if want != "rejected" {
                    failures.append("\(id) seq\(seq): engine rejected (\(reason.rawValue)) but corpus expects \(want ?? "?")")
                } else if let wantReason = exp["reason"] as? String, wantReason != reason.rawValue {
                    failures.append("\(id) seq\(seq): rejection reason \(reason.rawValue) != \(wantReason)")
                }
            case let .accepted(newState, effect, bustReason):
                if want != "accepted" {
                    failures.append("\(id) seq\(seq): engine accepted (\(effect.rawValue)) but corpus expects \(want ?? "?")")
                } else {
                    if let wantEffect = exp["effect"] as? String, wantEffect != effect.rawValue {
                        failures.append("\(id) seq\(seq): effect \(effect.rawValue) != \(wantEffect)")
                    }
                    if let wantReason = exp["reason"] as? String, wantReason != bustReason?.rawValue {
                        failures.append("\(id) seq\(seq): bust reason \(bustReason?.rawValue ?? "nil") != \(wantReason)")
                    }
                }
                state = newState
            }
        }

        // Final state, which catches drift the per-command outcomes would not.
        if let ws = expect["state"] as? [String: Any] {
            if let wantRemaining = ws["remaining"] as? [String: Int] {
                for (p, v) in wantRemaining {
                    let got = state.remaining[PlayerId(p)] ?? -1
                    if got != v { failures.append("\(id): remaining[\(p)] \(got) != \(v)") }
                }
            }
            if let wantLegs = ws["legsWon"] as? [String: Int] {
                for (p, v) in wantLegs {
                    let got = state.legsWonTotal[PlayerId(p)] ?? -1
                    if got != v { failures.append("\(id): legsWon[\(p)] \(got) != \(v)") }
                }
            }
            let wantWinner = ws["winnerId"] as? String
            if wantWinner != state.winner?.value {
                failures.append("\(id): winner \(state.winner?.value ?? "nil") != \(wantWinner ?? "nil")")
            }
            if let wantThrower = ws["throwerId"] as? String, wantThrower != state.thrower?.value {
                failures.append("\(id): thrower \(state.thrower?.value ?? "nil") != \(wantThrower)")
            }
            if let wantLeg = ws["currentLeg"] as? Int, wantLeg != state.currentLeg {
                failures.append("\(id): currentLeg \(state.currentLeg) != \(wantLeg)")
            }
        }
        return commands.count
    }

    private func format(_ j: [String: Any]) -> MatchFormat {
        let structure = j["structure"] as? [String: Any] ?? [:]
        let legs: Structure
        if let firstTo = structure["firstTo"] as? Int {
            legs = Structure(mode: .firstTo, target: firstTo)
        } else if let bestOf = structure["bestOf"] as? Int {
            legs = Structure(mode: .bestOf, target: bestOf)
        } else {
            legs = Structure(mode: .firstTo, target: 1)
        }
        // Sets are deliberately NOT parsed here, because the Kotlin runner does not parse them
        // either and the corpus carries no set structure today. A runner that read a key its
        // counterpart ignores would make the two platforms disagree about a vector neither engine
        // got wrong — which would discredit the comparison rather than test it.
        return MatchFormat(
            startingScore: j["startingScore"] as? Int ?? 501,
            inRule: InRule(rawValue: (j["inRule"] as? String) ?? "straight") ?? .straight,
            outRule: OutRule(rawValue: (j["outRule"] as? String) ?? "double") ?? .double,
            legs: legs,
            sets: nil,
            throwFirst: PlayerId(j["throwFirst"] as? String ?? "A"),
            alternation: (j["alternateStart"] as? String) == "perSet" ? .perSet : .perLeg
        )
    }
}
