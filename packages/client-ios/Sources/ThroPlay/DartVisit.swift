import Foundation
import ThroDesign
import ThroEngine

/// Turning three entered darts into the evidence a visit carries.
///
/// `ThroDart` and `ThroDartEntry` live in `ThroDesign` and hold no darts rules — checkability, out
/// rules and busts are the engine's. This is where the two meet, in the one layer that may know
/// both, exactly as `MatchSession` is where the engine and the journal meet.
///
/// **The engine's input does not change.** A visit entered as three darts produces the same
/// `recordVisit` command a visit entered as a total does, with the same `visitTotal` — the sum. What
/// it adds is `dartsUsed` and `dartsAtDouble`, which are today **always nil** unless PD-001 stops
/// the player and asks. Those two columns already exist in the journal, are already validated by the
/// engine, and are already what the statistics layer is missing.
public enum DartVisit {

    /// The remainders one dart can finish, under each out rule.
    ///
    /// Derived from the engine's own route table — a route of length one **is** a one-dart finish —
    /// rather than transcribed, so it cannot drift from the rules it is supposed to describe. The
    /// engine already carries `oneDartFinishesDouble` as a literal for the double-out case; the
    /// tests hold this against it, which is what makes the literal worth having.
    static let oneDartFinishes: [OutRule: Set<Int>] = {
        var table: [OutRule: Set<Int>] = [:]
        for rule in [OutRule.double, .master, .straight] {
            table[rule] = Set((1...RuleTables.maxVisitTotal).filter { RuleTables.route($0, rule)?.count == 1 })
        }
        return table
    }()

    /// How many of the entry's darts were thrown at a double.
    ///
    /// **The definition, and what it is not.** A dart is *at a double* when the score standing in
    /// front of it is one a single dart can finish — 32, 16, 50 under double-out. It is **not**
    /// every dart thrown from a checkable number: a player on 141 throwing `T20 T19 D12` threw one
    /// dart at a double, not three, and that is also the answer they would give if PD-001 stopped
    /// and asked them.
    ///
    /// This is worth stating plainly because the first version of this function counted the second
    /// thing. It compiled, it passed its tests, and it would have quietly tripled the denominator of
    /// every checkout percentage in the app — `Statistics.checkoutPercentage` divides leg wins by
    /// the sum of this column, so a wrong count here does not fail, it just makes every player look
    /// worse than they are. Two definitions in one column is worse still: the same match would carry
    /// human answers under one and computed answers under the other.
    ///
    /// **The limit that remains.** The ring a dart lands in does not say what it was aimed at. A
    /// player on 32 who throws a single 16 has, on this count, thrown one dart at a double and is
    /// then on 16 with another. That is what a scorer writes down, and it is observable; what the
    /// player intended is not.
    ///
    /// Darts entered after the visit was already decided do not count: once the remaining reaches
    /// zero or goes below what the out rule allows, the visit is over and nothing further was thrown.
    public static func dartsAtDouble(_ entry: ThroDartEntry, from remaining: Int,
                                     outRule: OutRule) -> Int? {
        guard !entry.darts.isEmpty else { return nil }
        let atADouble = DartVisit.oneDartFinishes[outRule] ?? []
        var left = remaining
        var count = 0
        for dart in entry.darts {
            if atADouble.contains(left) { count += 1 }
            left -= dart.value
            // Below this the visit is settled — finished or bust — and a further dart was not thrown.
            if left <= (outRule == .straight ? 0 : 1) { break }
        }
        return count
    }

    /// Whether the entry, thrown from `remaining`, ends the leg.
    public static func finishes(_ entry: ThroDartEntry, from remaining: Int, outRule: OutRule) -> Bool {
        remaining - entry.total == 0 && RuleTables.checkouts(outRule).contains(remaining)
    }

    /// Whether the entry has settled the visit — finished it, or busted it — so there is nothing
    /// further to throw. A bust after one dart is a real thing: on 20, a double 20 is a bust and the
    /// player stops.
    public static func settles(_ entry: ThroDartEntry, from remaining: Int, outRule: OutRule) -> Bool {
        let left = remaining - entry.total
        if left < 0 { return true }
        if left == 1 && outRule == .double { return true }
        return left == 0
    }

    /// The evidence a visit carries, from what was entered.
    ///
    /// **Three clamps, each of them a rule the engine already enforces.** A refusal a player cannot
    /// act on is a dead end rather than a correction, so evidence that the engine would refuse is
    /// carried as *unknown* rather than as a number it will throw back.
    ///
    ///  - `dartsUsed` is only recorded on a leg-winning visit unless it is three. `Engine` rejects
    ///    `DARTS_USED_INVALID` for any other visit that claims fewer, because a visit that did not
    ///    end the leg used the whole hand — and a bust, by its convention, consumed three darts
    ///    whatever the player had thrown when it happened. A bust after one dart therefore records
    ///    nil: one is the observed count, three is the convention, and nil is the only one of the
    ///    three that does not assert something the record cannot stand behind.
    ///  - `dartsAtDouble` is clamped to `dartsUsed`, which the engine also refuses to see exceeded.
    ///  - `dartsAtDouble` is zero from a remaining no three darts can finish. The engine calls that
    ///    "evidence that cannot have happened", and it is right: the walk below cannot produce it
    ///    (a one-dart finish is unreachable from a non-checkout), so this is a floor under a defect
    ///    rather than a licence — and `DartVisitTests` proves the floor is never load-bearing.
    public static func evidence(_ entry: ThroDartEntry, from remaining: Int,
                               outRule: OutRule) -> (dartsUsed: Int?, dartsAtDouble: Int?) {
        guard let used = entry.dartsUsed else { return (nil, nil) }
        let carried = (used == ThroDartEntry.perVisit
                       || finishes(entry, from: remaining, outRule: outRule)) ? used : nil
        guard RuleTables.checkouts(outRule).contains(remaining) else { return (carried, 0) }
        let atDouble = DartVisit.dartsAtDouble(entry, from: remaining, outRule: outRule)
        return (carried, atDouble.map { min($0, carried ?? ThroDartEntry.perVisit) })
    }

    /// The command an entered visit produces. Identical in every field to the one a typed total
    /// produces, apart from the two pieces of evidence a typed total cannot supply.
    public static func command(_ entry: ThroDartEntry, player: PlayerId, from remaining: Int,
                              outRule: OutRule) -> Command {
        let carried = DartVisit.evidence(entry, from: remaining, outRule: outRule)
        return .recordVisit(player: player, visitTotal: entry.total,
                            dartsUsed: carried.dartsUsed, dartsAtDouble: carried.dartsAtDouble)
    }

    /// Whether entering darts answers PD-001's questions outright, so the player is not stopped and
    /// asked something they have already told the app.
    ///
    /// Both, or neither: a half-answered prompt is a prompt.
    public static func answersThePrompts(_ entry: ThroDartEntry) -> Bool { entry.dartsUsed != nil }
}

// **A gap per-dart entry can see and this slice does not close.**
//
// Under double-out the winning dart must be a double. The engine scores a visit, not a dart
// (`ThroEngine/Types.swift`), so it can only ask whether the score *before* the visit was
// finishable — which means a player on 6 who records a total of 6 wins the leg, whether the last
// dart was D3 or S6. That is true of the app today and is why PD-001 asks about doubles at all.
//
// Entering three darts makes the last dart's ring visible for the first time, so the app could now
// tell the difference. It does not, because there is only one honest way to act on it and both
// halves are out of this slice's reach: the engine would have to become dart-aware, in Swift and in
// Kotlin together, behind the conformance corpus that ADR-002 keeps them parallel with — or the
// entry layer would have to overrule the engine about what a bust is, which puts two authorities on
// the one question the whole design exists to keep in one place.
//
// Recorded rather than half-fixed. Nothing here claims to catch it.
