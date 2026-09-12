import XCTest
@testable import ThroDesign

/// What the scoring screen says to somebody who cannot see it.
///
/// Every figure in this app carries a basis and a sample, and a screen reader gets none of the
/// things a sighted reader takes that from: not the colour, not the weight, not the en dash. So
/// each of these is a place where the honesty layer either survives the trip to speech or quietly
/// stops at the glass — and none of it can be caught by looking at a screenshot.
///
/// Pure functions rather than rendered views, for the same reason `StatGrid.spoken` was already
/// one: the words are the part that can be wrong.
final class SpokenTests: XCTestCase {

    // MARK: the remainder

    /// **The finish was carried by colour and nothing else.** A sighted player sees the hero turn
    /// brand green; a VoiceOver player was told a number and left to work out that 141 is
    /// checkable — which is the whole thing they need to know before throwing.
    func testBeingOnAFinishIsSaidAndNotOnlyColoured() {
        XCTAssertEqual(RemainingScore.spokenLabel(label: "Ann requires", state: .checkout),
                       "Ann requires, on a finish")
        XCTAssertEqual(RemainingScore.spokenLabel(label: "Ann requires", state: .normal),
                       "Ann requires")
    }

    /// A bust says what happened to the score, because the number shown is the restored one and a
    /// player hearing "Ann requires 141" after a bust would think their darts had counted.
    func testABustSaysTheScoreWasRestored() {
        let spoken = RemainingScore.spokenLabel(label: "Ann requires", state: .bust)
        XCTAssertTrue(spoken.contains("Bust"), spoken)
        XCTAssertTrue(spoken.lowercased().contains("restored"), spoken)
    }

    /// The number is the accessibility *value*, so a changed value is re-announced without the name
    /// being read again — which is what a figure that moves every visit needs.
    func testTheRemainderIsTheValueAndCarriesTheDartsWhenThereAreSome() {
        XCTAssertEqual(RemainingScore.spokenValue(value: 141, darts: nil), "141")
        XCTAssertEqual(RemainingScore.spokenValue(value: 40, darts: "2 darts"), "40, 2 darts")
    }

    // MARK: the legs

    /// `2–1` drawn is `2 to 1` spoken. Read off the string, an en dash between two numerals gives
    /// "2 1" — the same sound as twenty-one, and no statement of who is ahead, on the one figure
    /// that says whether the match is nearly over.
    func testTheLegsAreSpokenAsAScoreAndNotAsTwoLooseNumbers() {
        XCTAssertEqual(LegState.spoken(home: 2, away: 1, bestOf: 5), "2 to 1, best of 5")
        XCTAssertEqual(LegState.spoken(home: 0, away: 0, bestOf: nil), "0 to 0")
        XCTAssertFalse(LegState.spoken(home: 2, away: 1, bestOf: nil).contains("–"))
    }

    // MARK: the figures

    /// A range spoken as its string is two loose numbers. Spoken as a range it is what the
    /// statistics layer computed — the collapse into something else is precisely what that layer
    /// exists to prevent, and speech is a place it could happen without anybody seeing it.
    func testARangeIsSpokenAsARange() {
        let value = StatGrid.spokenValue(.range("3-dart average", "58.2–61.0",
                                                why: "Some legs are unfinished."))
        XCTAssertEqual(value, "between 58.2 and 61.0")
        XCTAssertFalse(value.contains("–"))
    }

    /// A dash read out is "dash". What it means is *this cannot be worked out*, and the reason is
    /// carried separately so it is spoken after the figure rather than inside it.
    func testAnUnavailableFigureSaysSoRatherThanReadingOutADash() {
        let stat = StatItem.unavailable("Checkout %", why: "No darts were thrown at a double.")
        XCTAssertEqual(StatGrid.spokenValue(stat), "not available")
        XCTAssertEqual(stat.value, "—", "the drawn form is still a dash")
        XCTAssertEqual(stat.note, "No darts were thrown at a double.")
    }

    func testAnExactFigureIsSpokenAsItself() {
        XCTAssertEqual(StatGrid.spokenValue(.exact("180s", "4")), "4")
    }

    /// The one-string form still carries all three parts, for a caller with only a label to put
    /// them in.
    func testTheWholeFigureStillFitsInOneStringWhenItHasTo() {
        let spoken = StatGrid.spoken(.range("First 9", "58.2–61.0", why: "Two legs ended early."))
        XCTAssertEqual(spoken, "First 9, between 58.2 and 61.0. Two legs ended early.")
    }

    // MARK: what has been typed

    /// Three taps and no confirmation of what is about to be committed, on the one screen where a
    /// mis-key becomes evidence. The Enter key is the readout for anybody who can see it; for
    /// anybody who cannot, this is.
    func testEachDigitAnnouncesWhatHasBeenTypedSoFar() {
        XCTAssertEqual(ScoreKeypad.spokenEntry(from: "", to: "1"), "1")
        XCTAssertEqual(ScoreKeypad.spokenEntry(from: "1", to: "14"), "14")
        XCTAssertEqual(ScoreKeypad.spokenEntry(from: "14", to: "141"), "141")
    }

    /// Clearing says so. Silence there is indistinguishable from the tap not registering — the same
    /// complaint that produced `check_controls_react.py`, heard rather than felt.
    func testClearingATypedEntrySaysSo() {
        XCTAssertEqual(ScoreKeypad.spokenEntry(from: "141", to: ""), "Cleared")
    }

    /// A screen arriving announces nothing, and neither does a re-evaluation that changed nothing.
    /// An app that talks when nothing happened is one people turn off.
    func testNothingIsAnnouncedWhenNothingChanged() {
        XCTAssertNil(ScoreKeypad.spokenEntry(from: "", to: ""))
        XCTAssertNil(ScoreKeypad.spokenEntry(from: "141", to: "141"))
    }

    // MARK: no two states sound the same

    // The compiler already makes sure every case of these enums is *handled* — a `switch` with no
    // `default` will not build otherwise, which is why there is no Python check for it and writing
    // one would be duplicating the type checker. What the compiler cannot see is a new state that
    // is handled by speaking what an existing one speaks. Two states a listener cannot tell apart
    // are, to that listener, one state; and the case it would happen to is exactly the one it
    // already happened to — a state added for its colour, whose speech was an afterthought.
    //
    // These walk every case, so a state added tomorrow is covered by a test written today.

    func testNoTwoRemainderStatesSoundTheSame() {
        let spoken = RemainingScore.State.allCases.map {
            RemainingScore.spokenLabel(label: "Ann requires", state: $0)
        }
        XCTAssertEqual(Set(spoken).count, RemainingScore.State.allCases.count, "\(spoken)")
    }

    func testNoTwoConfidencesSoundTheSame() {
        // One value, three bases. What separates them on the screen is weight and colour; what has
        // to separate them in speech is these words.
        let spoken = StatItem.Confidence.allCases.map { confidence -> String in
            switch confidence {
            case .exact: return StatGrid.spokenValue(.exact("Average", "58.2"))
            case .range: return StatGrid.spokenValue(.range("Average", "58.2–61.0", why: "why"))
            case .unavailable: return StatGrid.spokenValue(.unavailable("Average", why: "why"))
            }
        }
        XCTAssertEqual(Set(spoken).count, StatItem.Confidence.allCases.count, "\(spoken)")
    }

    /// Every verification label has words and an explanation, and no two of them share either. The
    /// difference between *self-reported* and *participant-confirmed* is the whole trust model
    /// (PD-002); two of them reading alike would collapse it for anybody listening.
    func testEveryVerificationLabelHasItsOwnWordsAndItsOwnExplanation() {
        let labels = VerificationLabel.allCases.map(\.label)
        let helps = VerificationLabel.allCases.map(\.help)
        XCTAssertFalse(labels.contains(where: \.isEmpty))
        XCTAssertFalse(helps.contains(where: \.isEmpty), "the hint would be silence")
        XCTAssertEqual(Set(labels).count, VerificationLabel.allCases.count, "\(labels)")
        XCTAssertEqual(Set(helps).count, VerificationLabel.allCases.count, "\(helps)")
    }
}
