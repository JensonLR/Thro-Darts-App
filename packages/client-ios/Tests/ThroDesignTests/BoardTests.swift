import XCTest
import SwiftUI
import ThroTokens
@testable import ThroDesign

/// SLATE B.1 and B.2 — the board and its dust, held to the law that makes the contrast matrix true.
final class BoardTests: XCTestCase {

    func testTheBoardIsThreeNamedStopsAndNothingElse() {
        // One gradient IS the lamp pool and the vignette. A separate veil layer would be an alpha
        // over a solid, and the alpha is what the board law exists to keep out.
        let stops = ThroBoard<EmptyView>.stops
        XCTAssertEqual(stops.count, 3)
        XCTAssertEqual(stops.map(\.location), [0, 0.55, 1])
        XCTAssertEqual(stops[0].color, ThroColor.colorBoardLit)
        XCTAssertEqual(stops[1].color, ThroColor.colorBoardField)
        XCTAssertEqual(stops[2].color, ThroColor.colorBoardSunken)
    }

    func testNoSpeckCanBeBrighterThanTheLampsOwnCentre() {
        // The board law, by construction. Every ground is at least as dark as `colorBoardLit`, and
        // a speck drawn in `colorBoardLit` at any alpha below 1 composites no brighter than it. A
        // white speck would be a pixel the contrast matrix does not cover, sitting under text the
        // matrix says is legible.
        for tier in 0..<ChalkField.tiers {
            let alpha = ChalkField.alpha(tier: tier, density: 1)
            XCTAssertGreaterThan(alpha, 0, "tier \(tier) is invisible")
            XCTAssertLessThanOrEqual(alpha, ChalkField.maximumAlpha + 1e-9, "tier \(tier)")
        }
        XCTAssertLessThan(ChalkField.maximumAlpha, 1)
    }

    func testEveryTierIsDistinctAndTheyRunDarkToLight() {
        let alphas = (0..<ChalkField.tiers).map { ChalkField.alpha(tier: $0, density: 0.6) }
        XCTAssertEqual(Set(alphas).count, ChalkField.tiers, "two tiers are the same fill")
        XCTAssertEqual(alphas, alphas.sorted(), "the tiers do not run in order")
    }

    func testTheFieldIsGrainAndNotNoiseSoTwoVisitsSeeTheSameBoard() {
        let once = ChalkField.scatter(seed: 4177)
        let again = ChalkField.scatter(seed: 4177)
        XCTAssertEqual(once.map { $0.x }, again.map { $0.x })
        XCTAssertEqual(once.map { $0.tier }, again.map { $0.tier })
        XCTAssertNotEqual(once.map { $0.x }, ChalkField.scatter(seed: 4178).map { $0.x })
    }

    func testTheFieldIsAtMostFiveFillsAndCoversTheWholeBoard() {
        let specks = ChalkField.scatter(seed: 0x5448_5200)
        XCTAssertEqual(specks.count, ChalkField.speckCount)
        XCTAssertLessThanOrEqual(Set(specks.map { $0.tier }).count, ChalkField.tiers)
        for speck in specks {
            XCTAssertTrue((0...1).contains(speck.x), "a speck landed off the board")
            XCTAssertTrue((0...1).contains(speck.y), "a speck landed off the board")
            XCTAssertGreaterThan(speck.r, 0)
        }
        // Spread across the whole rectangle, not clustered: each quarter gets a real share.
        let quarters = specks.reduce(into: [Int](repeating: 0, count: 4)) { counts, speck in
            counts[(speck.x < 0.5 ? 0 : 1) + (speck.y < 0.5 ? 0 : 2)] += 1
        }
        for count in quarters {
            XCTAssertGreaterThan(count, ChalkField.speckCount / 8, "the field is clustered: \(quarters)")
        }
    }

    func testTheBackgroundIsQuieterThanTheOpeningsForeground() {
        // The opening's dust is lit by a beam and is the subject. This is a background, and a
        // background that competes with the figure on it is not one.
        XCTAssertLessThan(ChalkField.speckCount, 420)
    }

    func testEveryScreenGetsItsOwnFieldAndNoSeedIsEverZero() {
        // A zero seed makes the generator emit one value forever — 180 specks in a single place.
        XCTAssertNotEqual(ThroBoardSeed.home, 0)
        var seen: Set<UInt32> = [ThroBoardSeed.home]
        for id in ["", "m1", "m2", "match-0001", "0000000000000000"] {
            let seed = ThroBoardSeed.match(id)
            XCTAssertNotEqual(seed, 0, "the match id \(id) hashed to zero")
            seen.insert(seed)
        }
        XCTAssertEqual(seen.count, 6, "two different matches share a board")
    }

    func testTheSameMatchAlwaysGetsTheSameBoard() {
        XCTAssertEqual(ThroBoardSeed.match("match-0001"), ThroBoardSeed.match("match-0001"))
        XCTAssertNotEqual(ThroBoardSeed.match("match-0001"), ThroBoardSeed.match("match-0002"))
    }

    func testTheLampSitsWhereTheThrowersNumberIs() {
        // Not the middle of the screen. The pool's centre is the brightest ground there is, and the
        // thing that belongs in it is the one number the product exists to move.
        XCTAssertEqual(ThroLampKey.defaultValue.x, 0.5)
        XCTAssertLessThan(ThroLampKey.defaultValue.y, 0.5, "the lamp is below the head it lights")
        XCTAssertGreaterThan(ThroLampKey.defaultValue.y, 0.1)
    }

    func testTheLampReachesPastTheCornerSoTheBoardIsNotAVignette() {
        // Under 0.86 the corners go flat before the edge and it reads as a filter over a photograph.
        XCTAssertGreaterThan(ThroBoard<EmptyView>.reach, 0.7)
        XCTAssertLessThan(ThroBoard<EmptyView>.reach, 1.0)
    }

    func testTheGeneratorIsTheOpeningsAndItStillWalks() {
        // The same LCG the opening has used since PD-007. If this ever returns a constant, both the
        // board's field and the opening's dust collapse to one point, and nothing else would say so.
        var rng = Grain(seed: 0x9E37_79B9)
        let draws = (0..<8).map { _ in rng.next() }
        XCTAssertEqual(Set(draws).count, 8, "the generator repeated inside eight draws")
        for draw in draws { XCTAssertTrue((0..<1).contains(draw), "\(draw) is outside 0..<1") }
    }
}
