import Foundation
import ThroDesign

/// Settings that belong to scoring. Keys are a contract with every install that has saved one.
public enum ScoringPreferences {
    /// The export's Settings lists "Keep screen awake · On" under Scoring. While the scoring screen
    /// is up and this is on, the phone does not sleep between visits.
    public static let keepScreenAwakeKey = "thro.keepScreenAwake"

    /// Whether the phone answers in the hand (PD-015). Default on: a keypad that acknowledges a key
    /// is the point of having haptics at a dartboard, where the player is looking at the board.
    /// A player can turn them off, because a phone buzzing in a pocket through a match is somebody
    /// else's idea of helpful — and because a shared phone at an oche is not always in a hand.
    public static let hapticsKey = ThroHaptics.enabledKey

    /// Which keypad the scoring screen offers: the total of three darts, or the three darts.
    ///
    /// **Both, and the player chooses** — the founder's brief, and the right answer for a reason
    /// beyond preference. A visit total is three taps and no evidence; three darts is up to six taps
    /// and answers PD-001's two questions outright, so a checkout no longer stops the player to ask
    /// how many darts it took. A league scorer keeping two boards wants the fast one; a player
    /// working on their doubles wants the one that remembers.
    ///
    /// Stored per device rather than per match: it is how *this scorer* scores, not a property of
    /// the game. It can be changed mid-leg — the two keypads produce the same command.
    public static let entryModeKey = "thro.entryMode"
}

/// How a visit is entered.
public enum ScoringEntryMode: String, CaseIterable, Sendable {
    /// The total of three darts, typed. The default, because it is what every existing player of
    /// every existing darts app already knows how to do, and because it is fewer taps.
    case visitTotal
    /// The three darts, one at a time.
    case perDart

    public static let `default` = ScoringEntryMode.visitTotal

    public init(stored: String) { self = ScoringEntryMode(rawValue: stored) ?? .default }

    /// What the switch says. The label names what you get, not what you leave.
    public var label: String {
        switch self {
        case .visitTotal: return "Total"
        case .perDart: return "Darts"
        }
    }

    public var spoken: String {
        switch self {
        case .visitTotal: return "Enter the total of three darts"
        case .perDart: return "Enter each dart"
        }
    }

    public var other: ScoringEntryMode { self == .visitTotal ? .perDart : .visitTotal }
}
