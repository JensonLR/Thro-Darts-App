import XCTest
@testable import ThroEngine

/// The dart (OD-023), held to the rest of this engine rather than to itself — written against the Swift
/// engine independently of the Kotlin `DartsPropertyTest`; the corpus is what holds the two to each other.
final class DartsPropertyTests: XCTestCase {

    private let a = PlayerId("A")
    private let b = PlayerId("B")

    /// Every dart on the board: miss, 20 singles, 20 doubles, 20 trebles, the outer bull and the bull.
    private let board: [Dart] = {
        var out: [Dart] = [.miss]
        for ring in [Ring.single, .double, .treble] { for n in 1...20 { out.append(Dart(n, ring)) } }
        return out + [.outerBull, .bull]
    }()

    private func state(_ remaining: Int, _ out: OutRule, _ bust: BustRule = .restoreVisit) -> MatchState {
        var s = MatchState.start(
            format: MatchFormat(startingScore: 501, inRule: .straight, outRule: out,
                                legs: Structure(mode: .firstTo, target: 5), throwFirst: a, bustRule: bust),
            home: a, away: b)
        s.remaining[a] = remaining
        return s
    }

    func testEveryDartOnTheBoardIsNamedAndReadBackAsItself() {
        XCTAssertEqual(Set(board).count, 63)
        for d in board {
            XCTAssertTrue(d.isOnTheBoard, d.name)
            XCTAssertEqual(Dart.parse(d.name), d, "round trip of \(d.name)")
        }
        for text in ["T25", "D0", "T0", "21", "D21"] {
            let d = Dart.parse(text)
            XCTAssertTrue(d != nil && !(d!.isOnTheBoard), text)
        }
        for text in ["", "X20", "D", "T+5", "twenty"] { XCTAssertNil(Dart.parse(text), text) }
    }

    /// Darts and their total agree, except where the darts reach zero on a dart that may not finish —
    /// which only darts can see. Every rule, every reachable remaining, every hand of one or two darts.
    func testDartsAndTotalsAgreeEverywhereTheDartsDoNotKnowMore() {
        var checked = 0
        for out in [OutRule.double, .master, .straight] {
            for rem in (out == .double ? 2 : 1)...182 {
                for first in board {
                    for hand in [[first]] + board.map({ [first, $0] }) {
                        guard case let .accepted(byDarts, effect, reason, reading?) =
                                Engine.apply(state(rem, out), .recordDarts(player: a, darts: hand)) else { continue }
                        checked += 1
                        let zeroOnANonFinisher = rem - reading.visitTotal == 0 && !hand.last!.mayFinish(out)
                        if zeroOnANonFinisher {
                            XCTAssertEqual(effect, .bust)
                            XCTAssertEqual(reason, .NOT_A_FINISHING_DART)
                            XCTAssertEqual(byDarts.remaining[a], rem)
                            continue
                        }
                        guard case let .accepted(byTotal, tEffect, tReason, _) =
                                Engine.apply(state(rem, out), .visit(a, reading.visitTotal)) else {
                            XCTFail("\(out) \(rem) \(hand): the total was refused"); continue
                        }
                        if tEffect != effect || tReason != reason || byTotal.remaining != byDarts.remaining {
                            XCTFail("\(out) \(rem) \(hand): darts \(effect) \(String(describing: reason)), total \(tEffect)")
                        }
                    }
                }
            }
        }
        // Most two-dart hands neither finish nor bust and are refused as unfinished; these are the rest.
        XCTAssertGreaterThan(checked, 250_000)
    }

    func testKeepScoredDartsKeepsExactlyTheDartsBeforeTheBust() {
        for out in [OutRule.double, .master, .straight] {
            for rem in (out == .double ? 2 : 1)...182 {
                for first in board {
                    for hand in [[first]] + board.map({ [first, $0] }) {
                        let restore = Engine.apply(state(rem, out), .recordDarts(player: a, darts: hand))
                        let keep = Engine.apply(state(rem, out, .keepScoredDarts), .recordDarts(player: a, darts: hand))
                        guard case let .accepted(r, rEffect, _, rReading?) = restore,
                              case let .accepted(k, kEffect, _, kReading?) = keep else { continue }
                        XCTAssertEqual(rEffect, kEffect)
                        let left = k.remaining[a]!
                        if rEffect == .bust {
                            let before = hand.prefix(rReading.bustAt!).reduce(0) { $0 + $1.value }
                            XCTAssertEqual(left, rem - before, "\(out) \(rem) \(hand)")
                            XCTAssertEqual(kReading.scored, before)
                            XCTAssertTrue(left > 0 && !(out == .double && left == 1), "\(out) \(rem) \(hand) kept \(left)")
                        } else {
                            XCTAssertEqual(r.remaining, k.remaining, "\(out) \(rem) \(hand)")
                        }
                    }
                }
            }
        }
    }

    /// Whether a finish exists with the darts in hand, against a search over the board that never
    /// consults the route table: the scores a hand can leave, dart by dart, and whether a finishing
    /// dart lands exactly.
    func testACheckoutIsPossibleExactlyWhenTheBoardAllowsOne() {
        for out in [OutRule.double, .master, .straight] {
            let floor = out == .double ? 2 : 1
            for rem in 1...200 {
                var reachable: Set<Int> = [rem]
                var finishable = false
                for n in 1...3 {
                    finishable = finishable || reachable.contains { left in
                        board.contains { $0.mayFinish(out) && $0.value == left }
                    }
                    XCTAssertEqual(Checkout.isPossible(rem, dartsLeft: n, out), finishable, "\(out) \(rem) in \(n)")
                    if let route = Checkout.route(rem, dartsLeft: n, out) {
                        let darts = route.compactMap(Dart.parse)
                        XCTAssertEqual(darts.count, route.count, "\(route) names darts")
                        XCTAssertLessThanOrEqual(darts.count, n)
                        let walked = Darts.read(before: rem, darts: darts, outRule: out)
                        XCTAssertEqual(walked.settled, .legWon, "\(out) \(rem) via \(route)")
                        XCTAssertEqual(walked.thrown, darts.count, "\(out) \(rem) via \(route) finishes early")
                    } else {
                        XCTAssertFalse(finishable, "\(out) \(rem) has a finish in \(n) and no route")
                    }
                    reachable = Set(reachable.flatMap { left in board.map { left - $0.value } }.filter { $0 >= floor })
                }
            }
        }
    }

    /// After any darts of a visit, what is left and the darts left always give a throwable route or none.
    func testMidVisitRoutesAreAlwaysThrowableFromWhereTheDartsLeftThePlayer() {
        for rem in 2...170 {
            for first in board {
                for hand in [[first]] + board.map({ [first, $0] }) {
                    let r = Darts.read(before: rem, darts: hand, outRule: .double)
                    guard r.settled == nil, r.thrown == hand.count,
                          let route = Checkout.route(r.left, dartsLeft: r.dartsLeft, .double) else { continue }
                    let finish = Darts.read(before: r.left, darts: route.compactMap(Dart.parse), outRule: .double)
                    XCTAssertEqual(finish.settled, .legWon, "\(rem) after \(hand): \(r.left) via \(route)")
                }
            }
        }
        XCTAssertEqual(Checkout.route(Darts.read(before: 100, darts: [Dart(20, .treble)], outRule: .double).left,
                                      dartsLeft: 2, .double), ["D20"])
        XCTAssertNil(Checkout.route(80, dartsLeft: 1, .double), "80 cannot be finished with one dart")
        XCTAssertEqual(Checkout.route(50, dartsLeft: 1, .double), ["Bull"])
    }

    /// The founder's example, and the one a total cannot see, through the engine as a scorer enters it.
    func testTheFoundersExampleBothWays() {
        let hand = [Dart(20, .single), Dart(15, .double)]
        guard case let .accepted(standard, _, reason, _) =
                Engine.apply(state(40, .double), .recordDarts(player: a, darts: hand)),
              case let .accepted(local, _, _, _) =
                Engine.apply(state(40, .double, .keepScoredDarts), .recordDarts(player: a, darts: hand)) else {
            return XCTFail("refused")
        }
        XCTAssertEqual(reason, .BELOW_ZERO)
        XCTAssertEqual(standard.remaining[a], 40)
        XCTAssertEqual(local.remaining[a], 20)
        guard case let .rejected(why) = Engine.apply(state(40, .double, .keepScoredDarts), .visit(a, 50)) else {
            return XCTFail("a busting total under keep-scored darts must be refused")
        }
        XCTAssertEqual(why, .DARTS_REQUIRED)
        guard case let .accepted(_, effect, treble, _) =
                Engine.apply(state(60, .double), .recordDarts(player: a, darts: [Dart(20, .treble)])) else {
            return XCTFail("refused")
        }
        XCTAssertEqual(effect, .bust)
        XCTAssertEqual(treble, .NOT_A_FINISHING_DART)
    }
}
