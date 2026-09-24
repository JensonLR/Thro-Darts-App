import Foundation
import ThroDesign
import ThroEngine

/// Three entered darts, handed to the engine as darts (OD-023).
///
/// `ThroDart` and `ThroDartEntry` live in `ThroDesign` and are the keypad's vocabulary: what a dart
/// is called and what three of them add up to. **Every rule question goes to the engine** — whether
/// a dart busts the visit, whether it may finish the leg, how many darts were thrown at a double,
/// what is left and what route is still on. This file is the one translation between the two, and it
/// holds no darts arithmetic of its own.
///
/// **What it replaced.** This file used to answer those questions itself, because the engine scored
/// visits and not darts. It summed the darts into a total, walked them for darts at a double, and
/// refused an entry that reached zero on a treble or a single — because the engine, seeing only the
/// total, would have called it a checkout. Two defects came of that, and both are gone with it:
///
///  - **A bust the darts could see was refused rather than recorded.** A player on 20 who threw a
///    single 20 had busted; the app told them to take the dart back, leaving them no way to record
///    what happened at the board. The engine now decides it from the darts, as the bust it is.
///  - **Double-in was scored from the wrong darts.** The entry sent the raw sum of the three darts, so
///    under double-in the darts thrown before the opening double counted: `20 D20 20` from a player
///    not yet in scored 80 instead of 60, and three singles counted as having opened. The engine now
///    reads the darts in order and counts from the opening dart.
public enum DartVisit {

    /// The engine's dart for one the keypad entered. Total: every keypad dart is on the board.
    public static func engineDart(_ dart: ThroDart) -> Dart {
        switch dart.ring {
        case .miss: return .miss
        case .single: return Dart(dart.sector, .single)
        case .double: return Dart(dart.sector, .double)
        case .treble: return Dart(dart.sector, .treble)
        case .outerBull: return .outerBull
        case .bull: return .bull
        }
    }

    /// The keypad's dart for one the engine holds — how a stored visit's darts are drawn again.
    public static func keypadDart(_ dart: Dart) -> ThroDart? {
        switch (dart.ring, dart.number) {
        case (.miss, _): return .miss
        case (.single, Dart.bullNumber): return .outerBull
        case (.double, Dart.bullNumber): return .bull
        case (.single, let n): return .single(n)
        case (.double, let n): return .double(n)
        case (.treble, let n): return .treble(n)
        }
    }

    public static func engineDarts(_ entry: ThroDartEntry) -> [Dart] { entry.darts.map(engineDart) }

    /// What the darts so far have done, read by the engine from where the visit began.
    public static func read(_ entry: ThroDartEntry, from remaining: Int, format: MatchFormat,
                            opened: Bool = true) -> Darts.Reading {
        Darts.read(before: remaining, darts: engineDarts(entry), outRule: format.outRule,
                   inRule: format.inRule, opened: opened)
    }

    /// The command an entered visit produces: the darts themselves. The engine derives the total, the
    /// bust and where it happened, the darts used and the darts at a double.
    public static func command(_ entry: ThroDartEntry, player: PlayerId) -> Command {
        .recordDarts(player: player, darts: engineDarts(entry))
    }

    /// Darts at a double in `entry` from `remaining`, as the engine counts them: darts thrown while the
    /// score in front of them was a one-dart finish. Nil for an empty entry — zero darts at a double is
    /// a claim about a visit that happened, and no visit happened.
    public static func dartsAtDouble(_ entry: ThroDartEntry, from remaining: Int, outRule: OutRule) -> Int? {
        guard !entry.isEmpty else { return nil }
        return Darts.read(before: remaining, darts: engineDarts(entry), outRule: outRule).atDouble
    }

    /// Whether a dart may end a leg under `outRule`. The engine's answer, by ring.
    public static func mayFinish(_ dart: ThroDart, outRule: OutRule) -> Bool {
        engineDart(dart).mayFinish(outRule)
    }

    /// Whether entering darts answers PD-001's questions outright, so the player is not stopped and
    /// asked something they have already told the app. Both, or neither: a half-answered prompt is a
    /// prompt.
    public static func answersThePrompts(_ entry: ThroDartEntry) -> Bool { entry.dartsUsed != nil }
}
