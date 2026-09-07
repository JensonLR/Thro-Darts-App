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
}
