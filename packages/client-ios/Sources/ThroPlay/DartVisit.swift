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

    /// How many of the entry's darts were thrown while the player was on a finish.
    ///
    /// **The definition, and its limit, stated plainly.** The ring a dart landed in does not tell
    /// you what it was aimed at: a player on 32 who throws a single 16 and then a double 8 threw two
    /// darts at a double and landed one. So "at a double" here means *thrown while the remaining was
    /// a checkable number* — which is the standard scoring definition, is what a scorer writes down,
    /// and is observable from the entry rather than assumed about the player's intent.
    ///
    /// Darts entered after the visit was already decided do not count: once the remaining reaches
    /// zero or goes below what the out rule allows, the visit is over and nothing further was
    /// thrown at anything.
    public static func dartsAtDouble(_ entry: ThroDartEntry, from remaining: Int,
                                     outRule: OutRule) -> Int? {
        guard !entry.darts.isEmpty else { return nil }
        let checkable = RuleTables.checkouts(outRule)
        var left = remaining
        var count = 0
        for dart in entry.darts {
            if checkable.contains(left) { count += 1 }
            left -= dart.value
            // Below this the visit is settled — finished or bust — and a further dart was not thrown.
            if left <= (outRule == .straight ? 0 : 1) { break }
        }
        return count
    }

    /// The evidence a visit carries, from what was entered.
    ///
    /// `dartsAtDouble` is clamped to `dartsUsed` because the engine refuses a visit where it exceeds
    /// it, and a refusal a player cannot act on is a dead end rather than a correction. The clamp
    /// can only bind if the walk above and the engine's bust rule disagree, which would itself be a
    /// defect — so it is a floor under a defect, not a licence.
    public static func evidence(_ entry: ThroDartEntry, from remaining: Int,
                               outRule: OutRule) -> (dartsUsed: Int?, dartsAtDouble: Int?) {
        guard let used = entry.dartsUsed else { return (nil, nil) }
        let atDouble = DartVisit.dartsAtDouble(entry, from: remaining, outRule: outRule)
        return (used, atDouble.map { min($0, used) })
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
