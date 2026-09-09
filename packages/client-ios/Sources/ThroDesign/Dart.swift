import SwiftUI
import ThroTokens

// Per-dart entry, asked for by the founder on behalf of a player in a local league: the app should
// take each of the three darts as well as the total of three.
//
// **The engine is not changing.** `ThroEngine/Types.swift:26` says it in as many words — *the engine
// scores a visit, not a dart* — PD-008 settled the double-in rule on that basis, and ADR-002 keeps
// the Swift and Kotlin engines structurally parallel against exactly this kind of drift. So the
// three darts are captured as **evidence attached to the visit**, their sum IS the visit total, and
// the engine's input is byte-identical. Every existing figure and every replay is unchanged.
//
// What it buys, beyond the asking:
//
//  - **Two modal questions disappear from every checkout.** PD-001 asks "Darts used to check out?"
//    and "Darts thrown at a double?" after the fact, because the app has no way to know. A player
//    who entered their darts has already answered both, and answered them with what they did rather
//    than with what they remember, at the most pressured moment in a leg.
//  - **A mis-key cannot reach the board.** Each dart must be one of the 63 things a dart can do.
//
// This file is the vocabulary only: what a dart is and what three of them add up to. It holds no
// darts *rules* — checkability, out rules, busts — because those are the engine's and `ThroDesign`
// must not depend on it, exactly as `StatItem.Confidence` restates a basis without depending on the
// statistics package. `ThroPlay` does the rule work.

/// One dart, as a scoreboard records it.
public struct ThroDart: Equatable, Hashable, Sendable {

    /// Where it landed. Not what it was aimed at — a board cannot know that, and neither can this.
    public enum Ring: String, CaseIterable, Sendable, Comparable {
        /// Off the board, or in a bed that scores nothing.
        case miss
        case single
        case double
        case treble
        /// The 25 ring. A single, despite what people call it.
        case outerBull
        /// The 50. **It is a double** — the double of 25 — which is why it finishes a leg under the
        /// double-out rule, and why a dart that lands in it is a dart that landed in a double.
        case bull

        public static func < (a: Ring, b: Ring) -> Bool {
            (allCases.firstIndex(of: a) ?? 0) < (allCases.firstIndex(of: b) ?? 0)
        }

        /// Whether a dart in this ring is in a double bed.
        public var isDouble: Bool { self == .double || self == .bull }

        /// Whether this ring takes a sector number.
        public var takesSector: Bool { self == .single || self == .double || self == .treble }
    }

    public let ring: Ring
    /// 1...20 for a ring that takes one; 0 otherwise.
    public let sector: Int

    /// The twenty numbered beds, clockwise from the top as they sit on a board. The order is the
    /// board's, not 1-to-20, because a keypad laid out 1-to-20 is a keypad nobody can find a number
    /// on — a player looks for 20 next to 1 and 5, where it is.
    public static let sectors: [Int] = [20, 1, 18, 4, 13, 6, 10, 15, 2, 17,
                                        3, 19, 7, 16, 8, 11, 14, 9, 12, 5]

    /// The most one dart can score.
    public static let maximum = 60

    public init?(ring: Ring, sector: Int = 0) {
        if ring.takesSector {
            guard (1...20).contains(sector) else { return nil }
            self.sector = sector
        } else {
            guard sector == 0 else { return nil }
            self.sector = 0
        }
        self.ring = ring
    }

    public static let miss = ThroDart(ring: .miss)!
    public static let outerBull = ThroDart(ring: .outerBull)!
    public static let bull = ThroDart(ring: .bull)!
    public static func single(_ n: Int) -> ThroDart? { ThroDart(ring: .single, sector: n) }
    public static func double(_ n: Int) -> ThroDart? { ThroDart(ring: .double, sector: n) }
    public static func treble(_ n: Int) -> ThroDart? { ThroDart(ring: .treble, sector: n) }

    public var value: Int {
        switch ring {
        case .miss: return 0
        case .single: return sector
        case .double: return 2 * sector
        case .treble: return 3 * sector
        case .outerBull: return 25
        case .bull: return 50
        }
    }

    public var isDouble: Bool { ring.isDouble }

    /// Every distinct thing one dart can do. **63**: a miss, twenty singles, twenty doubles, twenty
    /// trebles, the 25 and the 50.
    public static let all: [ThroDart] = {
        var darts: [ThroDart] = [.miss]
        for ring in [Ring.single, .double, .treble] {
            for sector in sectors {
                if let dart = ThroDart(ring: ring, sector: sector) { darts.append(dart) }
            }
        }
        darts.append(.outerBull)
        darts.append(.bull)
        return darts
    }()

    /// How it is written on a scoresheet: `T20`, `D16`, `5`, `25`, `BULL`, `—`.
    public var written: String {
        switch ring {
        case .miss: return "—"
        case .single: return "\(sector)"
        case .double: return "D\(sector)"
        case .treble: return "T\(sector)"
        case .outerBull: return "25"
        case .bull: return "BULL"
        }
    }

    /// How it is said. `T20` read aloud is "tee twenty", which is not a number — and on the one
    /// screen where a mis-key becomes evidence, a listener needs the words.
    public var spoken: String {
        switch ring {
        case .miss: return "missed"
        case .single: return "single \(sector)"
        case .double: return "double \(sector)"
        case .treble: return "treble \(sector)"
        case .outerBull: return "twenty five"
        case .bull: return "bullseye"
        }
    }
}

/// Three darts being entered, or fewer.
///
/// A visit is at most three darts and may be fewer — a checkout ends it early. Nothing here decides
/// whether it finished; that is the engine's, and this only carries what was typed.
public struct ThroDartEntry: Equatable, Sendable {
    public private(set) var darts: [ThroDart]

    public init(_ darts: [ThroDart] = []) {
        self.darts = Array(darts.prefix(ThroDartEntry.perVisit))
    }

    public static let perVisit = 3

    public var total: Int { darts.reduce(0) { $0 + $1.value } }
    public var isEmpty: Bool { darts.isEmpty }
    /// Whether three darts have been entered. A visit can be **complete at fewer** — that is a
    /// checkout — so this says the hand is used up, not that the visit is over.
    public var handIsSpent: Bool { darts.count >= ThroDartEntry.perVisit }

    /// Add a dart. Refused once the hand is spent, so an entry can never carry a fourth.
    public mutating func add(_ dart: ThroDart) {
        guard !handIsSpent else { return }
        darts.append(dart)
    }

    /// Take the last one back. This is the undo a player reaches for when they tap D16 for D18, and
    /// it takes back one dart rather than the whole visit.
    public mutating func removeLast() {
        guard !darts.isEmpty else { return }
        darts.removeLast()
    }

    public mutating func clear() { darts.removeAll() }

    /// How many darts were thrown. **This is the evidence PD-001 has been asking players for.**
    /// Nil while nothing is entered, because a visit of no darts is not a visit.
    public var dartsUsed: Int? { darts.isEmpty ? nil : darts.count }

    /// What the entry says so far, written out: `T20 T20 D12`.
    public var written: String { darts.map(\.written).joined(separator: " ") }

    /// What a screen reader is told. The running total comes last, because it is the thing that
    /// changed and VoiceOver reads a changed value without re-reading the name.
    public var spoken: String {
        guard !darts.isEmpty else { return "no darts entered" }
        return darts.map(\.spoken).joined(separator: ", ") + ", \(total)"
    }

    /// The totals three darts can actually make, computed rather than transcribed.
    ///
    /// The engine carries `RuleTables.impossibleVisitTotals` as a literal set, which is the correct
    /// list and has been since it shipped. This derives the same fact from the darts themselves, so
    /// the two can be held against each other — a hand-written table of impossible totals is the
    /// single most-missed validation in X01 implementations, and one nobody re-derives is a table
    /// that can rot without anything noticing.
    public static let reachableTotals: Set<Int> = {
        let values = Set(ThroDart.all.map(\.value))
        var reachable: Set<Int> = [0]
        for _ in 0..<perVisit {
            var next: Set<Int> = []
            for running in reachable {
                for value in values { next.insert(running + value) }
            }
            reachable = next
        }
        return reachable
    }()
}
