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
        // CI runs this from the repository and sets THRO_REQUIRE_CORPUS=1, so a run that cannot find the
        // corpus fails rather than reporting a green suite that checked nothing. Locally, from somewhere
        // else on disk, it still skips.
        if let required = ProcessInfo.processInfo.environment["THRO_REQUIRE_CORPUS"], !required.isEmpty {
            XCTFail("THRO_REQUIRE_CORPUS is set but the conformance corpus was not found from \(FileManager.default.currentDirectoryPath)")
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
            if let required = ProcessInfo.processInfo.environment["THRO_REQUIRE_CORPUS"], !required.isEmpty {
                XCTFail("THRO_REQUIRE_CORPUS is set but core-transitions.jsonl is missing: run generate.py --full")
            }
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

    /// Double-in, and the capture rule that makes it scorable at visit granularity (PD-008).
    ///
    /// The founder asked for it because leagues and tournaments play it. Before PD-008 the format was
    /// refused rather than scored as straight-in and silently wrong (OD-015). The rule: a visit thrown
    /// while the player has not opened records the score FROM the opening dart onward, and zero means
    /// they did not open — what the scorer calls at the oche, and it costs no statistic, because a
    /// visit is three darts whether it opened or not.
    ///
    /// Written against the Swift engine independently of the Kotlin one; the corpus is what holds
    /// them to each other.
    func testUnderDoubleInNothingScoresUntilAPlayerOpensAndOnlyAnOpeningTotalCan() {
        let a = PlayerId("A"), b = PlayerId("B")
        let format = MatchFormat(startingScore: 501, inRule: .double, outRule: .double,
                                 legs: Structure(mode: .firstTo, target: 2), throwFirst: a)
        let start = MatchState.start(format: format, home: a, away: b)
        XCTAssertEqual(start.opened[a], false, "double-in starts closed")
        XCTAssertEqual(start.opened[b], false)
        XCTAssertTrue(InRule.double.requiresOpening)
        XCTAssertTrue(InRule.master.requiresOpening)
        XCTAssertFalse(InRule.straight.requiresOpening)
        XCTAssertEqual(MatchState.start(format: MatchFormat(
            startingScore: 501, inRule: .straight, outRule: .double,
            legs: Structure(mode: .firstTo, target: 2), throwFirst: a), home: a, away: b).opened[a], true)

        // A visit that does not open scores nothing and does not open the player.
        guard case .accepted(let afterMiss, let effect, _) = Engine.apply(start, .visit(a, 0)) else {
            return XCTFail("a visit that did not open is still a visit")
        }
        XCTAssertEqual(effect, .scored)
        XCTAssertEqual(afterMiss.remaining[a], 501, "nothing counts before the double")
        XCTAssertEqual(afterMiss.opened[a], false, "and they are still not in")
        XCTAssertEqual(afterMiss.thrower, b, "the turn still rotates")

        // Both directions over the whole range, so neither the table nor the guard can be trimmed.
        for total in 0...180 {
            let openable = total == 0 || RuleTables.openingTotals(.double).contains(total)
            switch Engine.apply(start, .visit(a, total)) {
            case .accepted: XCTAssertTrue(openable, "\(total) was accepted but cannot open")
            case .rejected(let reason):
                XCTAssertFalse(openable, "\(total) can open but was rejected as \(reason)")
                if !RuleTables.impossibleVisitTotals.contains(total) && total <= 180 {
                    XCTAssertEqual(reason, .IMPOSSIBLE_OPENING_TOTAL,
                                   "\(total) is a possible visit; it is the OPENING that is impossible")
                }
            }
        }
        XCTAssertEqual(RuleTables.openingTotals(.double).max(), 170, "the bull opens: D25+T20+T20")
        XCTAssertTrue(RuleTables.openingTotals(.double).contains(41), "D1 then 19 and 20")
        XCTAssertFalse(RuleTables.openingTotals(.double).contains(1), "the smallest double is 2")
        XCTAssertEqual(RuleTables.openingTotals(.master).max(), 180, "master-in admits trebles")
        // Opening and checking out are the same set, for every rule: a checkout is free darts then a
        // finisher, an opening is an opener then free darts, and addition commutes.
        XCTAssertEqual(RuleTables.openingTotals(.double), RuleTables.checkouts(.double))
        XCTAssertEqual(RuleTables.openingTotals(.straight), RuleTables.checkouts(.straight))
        // The floor of a checkout set is the rule's own, not the constant 2: under straight-out a
        // single 1 finishes. Both engines hardcoded 2 and would have busted a player finishing from 1.
        XCTAssertTrue(RuleTables.checkouts(.straight).contains(1))
        XCTAssertFalse(RuleTables.checkouts(.double).contains(1))

        // Opening is per player, and it survives to the end of the leg.
        guard case .accepted(let bIn, _, _) = Engine.apply(afterMiss, .visit(b, 40)) else {
            return XCTFail("40 opens")
        }
        XCTAssertEqual(bIn.remaining[b], 461)
        XCTAssertEqual(bIn.opened[b], true)
        if case .rejected(let reason) = Engine.apply(bIn, .visit(a, 180)) {
            XCTAssertEqual(reason, .IMPOSSIBLE_OPENING_TOTAL, "one player opening does not open the other")
        } else {
            XCTFail("A is still closed, so 180 cannot be theirs")
        }

        // A new leg closes the door again; a bust reverts the score but never the opening.
        let short = MatchFormat(startingScore: 40, inRule: .double, outRule: .double,
                                legs: Structure(mode: .firstTo, target: 2), throwFirst: a)
        guard case .accepted(let won, let wonEffect, _) =
                Engine.apply(MatchState.start(format: short, home: a, away: b),
                             .visit(a, 40, dartsUsed: 1, dartsAtDouble: 1)) else {
            return XCTFail("D20 from 40 wins the leg")
        }
        XCTAssertEqual(wonEffect, .leg_won)
        XCTAssertEqual(won.opened[a], false, "a new leg is a new opening")
        XCTAssertEqual(won.opened[b], false)

        let tight = MatchFormat(startingScore: 30, inRule: .double, outRule: .double,
                                legs: Structure(mode: .firstTo, target: 2), throwFirst: a)
        guard case .accepted(let bust, let bustEffect, _) =
                Engine.apply(MatchState.start(format: tight, home: a, away: b), .visit(a, 40)) else {
            return XCTFail("40 from 30 busts")
        }
        XCTAssertEqual(bustEffect, .bust)
        XCTAssertEqual(bust.remaining[a], 30)
        XCTAssertEqual(bust.opened[a], true, "opening survives the bust that follows it")
    }

    // MARK: - checkout routes (PD-013)

    /// Which route is best is a preference and THRØ takes a position on it. Whether a route is a
    /// LEGAL FINISH is not a preference, and that is what this holds — arithmetically, for every
    /// route in every rule, rather than against a chart somebody typed. It also proves the encoded
    /// table survived being parsed, which is the one thing the generator cannot check for us.
    func testEveryRouteIsALegalFinishOfExactlyThatRemaining() {
        var throwScore: [String: Int] = ["25": 25, "Bull": 50]
        for n in 1...20 {
            throwScore["\(n)"] = n
            throwScore["D\(n)"] = 2 * n
            throwScore["T\(n)"] = 3 * n
        }
        let doubles = Set(stride(from: 2, through: 40, by: 2)).union([50])
        let trebles = Set(stride(from: 3, through: 60, by: 3))
        let finishers: [OutRule: Set<Int>] = [
            .double: doubles,
            .master: doubles.union(trebles),
            .straight: doubles.union(trebles).union(Set(1...20)).union([25]),
        ]

        for rule in [OutRule.double, .master, .straight] {
            let checkouts = RuleTables.checkouts(rule)
            for remaining in checkouts.sorted() {
                guard let route = RuleTables.route(remaining, rule) else {
                    return XCTFail("\(rule) \(remaining) has no route")
                }
                XCTAssertTrue((1...3).contains(route.count), "\(rule) \(remaining): \(route)")
                let scores = route.map { throwScore[$0] ?? -1 }
                XCTAssertFalse(scores.contains(-1), "\(rule) \(remaining): \(route) names a throw that does not exist")
                XCTAssertEqual(scores.reduce(0, +), remaining, "\(rule) \(remaining): \(route) does not sum to it")
                XCTAssertTrue(finishers[rule]!.contains(scores.last ?? 0),
                              "\(rule) \(remaining): \(route) does not finish on a legal segment")
                for i in 0..<(scores.count - 1) {
                    XCTAssertLessThan(scores.prefix(i + 1).reduce(0, +), remaining,
                                      "\(rule) \(remaining): \(route) finishes before its last dart")
                }
            }
            // A number with no finish is offered no route, rather than one that cannot be thrown.
            for n in 1...180 where !checkouts.contains(n) {
                XCTAssertNil(RuleTables.route(n, rule), "\(rule) \(n) is a bogey and must have no route")
            }
        }
    }

    /// A handful anyone who plays darts can check by eye. If the rule stops producing them, look.
    func testTheConventionalFinishesAreTheConventionalFinishes() {
        let known: [Int: String] = [
            170: "T20 T20 Bull", 167: "T20 T19 Bull", 164: "T20 T18 Bull", 161: "T20 T17 Bull",
            160: "T20 T20 D20", 158: "T20 T20 D19", 141: "T20 T19 D12", 110: "T20 Bull",
            100: "T20 D20", 96: "T20 D18", 90: "T18 D18", 81: "T19 D12", 60: "20 D20",
            50: "Bull", 41: "9 D16", 40: "D20", 32: "D16", 2: "D1",
        ]
        for (remaining, want) in known {
            XCTAssertEqual(RuleTables.route(remaining, .double)?.joined(separator: " "), want, "\(remaining)")
        }
    }
}
