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

    /// Whether a dart may be the one that ends a leg, under this out rule.
    public static func mayFinish(_ dart: ThroDart, outRule: OutRule) -> Bool {
        switch outRule {
        case .double: return dart.isDouble
        case .master: return dart.isDouble || dart.ring == .treble
        case .straight: return dart.value > 0
        }
    }

    /// The dart in the entry that reaches zero but is not allowed to, if there is one.
    ///
    /// **This is the thing per-dart entry can see and a visit total cannot**, and it turned up as a
    /// row of red in CI rather than as a thought. A player on 60 who throws `T20` reaches zero on a
    /// treble: under double-out that is a bust, not a checkout. The engine scores a visit
    /// (`ThroEngine/Types.swift:26`), so all it can ask is whether the score the visit STARTED from
    /// was finishable — 60 is — and it has no way to know the last dart was not a double.
    ///
    /// Left to itself the engine then answers two ways for one situation, which is worse than
    /// either answer alone: `T20` from 60 produces `dartsAtDouble: 0`, which it rejects as
    /// `DARTS_AT_DOUBLE_INVALID` — a true refusal with a reason no player can act on — while `20`
    /// from 20 produces `dartsAtDouble: 1`, because 20 is `D10` and the dart was thrown from a
    /// one-dart finish, and it accepts it as a leg won that never happened.
    ///
    /// So the entry layer refuses **both**, before either reaches the engine, and says which dart
    /// and why. That is not a second authority on what a bust is: nothing here decides the visit,
    /// and nothing pretends to record the bust. It refuses to submit darts that cannot have been
    /// thrown, exactly as the keypad refuses a fourth dart.
    ///
    /// **What is still not built** is recording that bust. It needs an engine that scores darts, in
    /// Swift and Kotlin together behind ADR-002's conformance corpus, and that is the founder's
    /// call — OD-023.
    public static func illegalFinish(_ entry: ThroDartEntry, from remaining: Int,
                                     outRule: OutRule) -> ThroDart? {
        // `finishes` and not merely "reaches zero": from a bogey — 159 under double-out — reaching
        // zero is a bust the engine sees for itself (`NOT_CHECKOUT_POSSIBLE`), and refusing it here
        // would take away a bust the app records correctly today. This only speaks where the engine
        // would otherwise call it a leg won.
        guard finishes(entry, from: remaining, outRule: outRule), let last = entry.darts.last,
              !mayFinish(last, outRule: outRule) else { return nil }
        return last
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
// Entering three darts makes the last dart's ring visible for the first time, and `illegalFinish`
// above now catches it — so the app refuses such an entry rather than recording a leg nobody won.
//
// **What this comment got wrong when it was first written.** It said the engine's own rules would
// not catch any of it. They catch about half: a finish whose last dart is not itself a one-dart
// finish produces `dartsAtDouble: 0`, which the engine rejects under double-out. The other half —
// a single 20 thrown from 20 — produces 1, because 20 is `D10`, and is accepted as a leg won. Two
// behaviours for one situation, and the more common one was the wrong one. That is what made this
// worth acting on rather than only recording.
//
// **What is still not built is recording the bust**, and that has not changed: it needs an engine
// that scores darts, in Swift and Kotlin together behind ADR-002's conformance corpus, and it
// reopens PD-008's reasoning about what a visit is. OD-023, and the founder's.
