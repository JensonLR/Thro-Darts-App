import Foundation

/// Settings that belong to scoring. Keys are a contract with every install that has saved one.
public enum ScoringPreferences {
    /// The export's Settings lists "Keep screen awake · On" under Scoring. While the scoring screen
    /// is up and this is on, the phone does not sleep between visits.
    public static let keepScreenAwakeKey = "thro.keepScreenAwake"
}
