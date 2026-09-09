import XCTest
import ThroPlay
@testable import ThroApp

/// How a visit is entered, and where a player finds out.
///
/// The founder asked for both notations. A control that exists only inside a match is one nobody
/// finds before their first match, so the choice is on the scoring rail **and** in Settings, both
/// reading and writing one stored value.
final class EntryModeTests: XCTestCase {

    func testAnUnknownStoredNotationFallsBackToTheDefaultRatherThanGuessing() {
        // The same rule `Appearance` follows: a value this build does not recognise — an older
        // phone's, or a corrupted one — is the default, not a crash and not a coin toss.
        XCTAssertEqual(ScoringEntryMode(stored: "sideways"), ScoringEntryMode.default)
        XCTAssertEqual(ScoringEntryMode(stored: ""), ScoringEntryMode.default)
        XCTAssertEqual(ScoringEntryMode(stored: ScoringEntryMode.perDart.rawValue), .perDart)
    }

    func testTheDefaultIsTheNotationEveryExistingDartsPlayerAlreadyKnows() {
        // Typing the total is what every darts app does. Per-dart entry is the better record and
        // the unfamiliar one; making it the default would meet a new player with six taps a visit.
        XCTAssertEqual(ScoringEntryMode.default, .visitTotal)
    }

    func testSwitchingTwiceComesBack() {
        for mode in ScoringEntryMode.allCases {
            XCTAssertEqual(mode.other.other, mode)
            XCTAssertNotEqual(mode.other, mode)
        }
    }

    func testTheTwoNotationsAreTheOnlyOnes() {
        // If a third arrives, `other` stops being meaningful and the rail's one-tap switch is a
        // control that cannot reach it. This fails on the day that happens.
        XCTAssertEqual(ScoringEntryMode.allCases.count, 2)
    }

    func testTheSpokenFormIsASentenceAndNotTheWordOnTheKey() {
        // **TOTAL and DARTS are one word each, and one word is not enough.** Read out on its own,
        // "darts" is a noun this whole app is about and says nothing about what the control does.
        // The rail's switch speaks this instead; `spoken` had no caller at all until it did, which
        // is the shape of defect this repository has recorded twice — a public API, tested, called
        // from nowhere.
        for mode in ScoringEntryMode.allCases {
            XCTAssertNotEqual(mode.spoken, mode.label, mode.label)
            XCTAssertGreaterThan(mode.spoken.split(separator: " ").count, 2,
                                 "\(mode.label) is spoken as \(mode.spoken), which is not a sentence")
        }
    }

    func testNoTwoNotationsDescribeThemselvesTheSameWay() {
        // Two states a reader cannot tell apart are one state. Walked over `allCases`, so a
        // notation added tomorrow is covered by a test written today.
        let labels = ScoringEntryMode.allCases.map(\.label)
        let spoken = ScoringEntryMode.allCases.map(\.spoken)
        let notes = ScoringEntryMode.allCases.map(SettingsScreen.entryModeNote)
        XCTAssertEqual(Set(labels).count, ScoringEntryMode.allCases.count)
        XCTAssertEqual(Set(spoken).count, ScoringEntryMode.allCases.count)
        XCTAssertEqual(Set(notes).count, ScoringEntryMode.allCases.count)
        for label in labels { XCTAssertFalse(label.isEmpty) }
    }

    func testEveryNotationSaysWhatItCostsAndNotOnlyWhatItBuys() {
        // A setting that lists only advantages is one somebody switches and quietly regrets. Both
        // notes are long enough to carry a trade-off rather than a slogan, and neither is the
        // label with a full stop after it.
        for mode in ScoringEntryMode.allCases {
            let note = SettingsScreen.entryModeNote(mode)
            XCTAssertGreaterThan(note.count, 80, "\(mode.label) is a slogan, not a trade-off")
            XCTAssertFalse(note.hasPrefix(mode.label), mode.label)
        }
        // And each names the thing the other is better at, so the row reads as a choice.
        XCTAssertTrue(SettingsScreen.entryModeNote(.visitTotal).contains("Fewer taps"))
        XCTAssertTrue(SettingsScreen.entryModeNote(.perDart).contains("more taps"))
    }
}
