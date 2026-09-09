import XCTest
import SwiftUI
@testable import ThroDesign
import ThroJournal
import ThroPlay
@testable import ThroApp

/// A player's own page.
///
/// The founder asked for *"profile pictures for player profiles, proper player profile layouts"*,
/// and the layout work turned up a defect that had nothing to do with layout: the page took each
/// figure apart into a value, a label and an optional reason, and drew all three the same whatever
/// the basis was. A **bounded** figure — one the honesty layer marks as a range on every other
/// screen — was drawn on a profile as though it were exact.
final class ProfileTests: XCTestCase {

    // MARK: - the basis survives the trip to the page

    func testABoundedFigureReachesTheProfileStillMarkedAsARange() {
        // The mapping that used to lose it: StatLine -> (value, label, unavailable). `.item` is the
        // one conversion, it is on `StatLine`, and it carries the confidence across.
        let line = StatLine(label: "Checkout %", value: "31–44%",
                            note: "Two visits on a finish did not record their darts at a double.",
                            confidence: .range)
        XCTAssertEqual(line.item.confidence, .range)
        XCTAssertEqual(line.item.value, "31–44%")
        XCTAssertNotNil(line.item.note, "a range without its reason is the thing StatItem forbids")
    }

    func testAnUnavailableFigureReachesTheProfileWithItsReason() {
        let line = StatLine(label: "Checkout %", value: "—",
                            note: "No visit recorded how many darts were thrown at a double.",
                            confidence: .unavailable)
        XCTAssertEqual(line.item.confidence, .unavailable)
        XCTAssertEqual(line.item.note, "No visit recorded how many darts were thrown at a double.")
    }

    func testNoTwoConfidencesAreDrawnOrSpokenTheSameWay() {
        // **What the first version of this asserted, and why CI was right to refuse it.** It
        // demanded three distinct value colours. `valueColour` gives `.exact` and `.range` the
        // same one deliberately: only a range is marked, and it is marked with a `Tag`, because
        // colouring the confident case as well would make every figure on the screen look
        // qualified. My assertion described a design this app does not have and never did.
        //
        // The claim that matters — two states a reader cannot tell apart are one state — is
        // carried by the basis and by the speech, and those are three ways each.
        let bases = StatItem.Confidence.allCases.map(StatGrid.basis(for:))
        XCTAssertEqual(Set(bases).count, StatItem.Confidence.allCases.count)
        let items: [StatItem] = [.exact("Checkout %", "31%"),
                                 .range("Checkout %", "31–44%", why: "Two visits did not record."),
                                 .unavailable("Checkout %", why: "No visit recorded.")]
        XCTAssertEqual(Set(items.map(StatGrid.spokenValue)).count, items.count)

        // And the two neutrals **swap** between the value and its reason, so the loudest thing in
        // a cell is always the thing carrying the meaning: a number when there is one, the reason
        // when there is not.
        XCTAssertEqual(StatGrid.valueColour(.exact), StatGrid.valueColour(.range))
        XCTAssertNotEqual(StatGrid.valueColour(.exact), StatGrid.valueColour(.unavailable))
        XCTAssertEqual(StatGrid.valueColour(.unavailable), StatGrid.noteColour(.exact))
        XCTAssertEqual(StatGrid.noteColour(.unavailable), StatGrid.valueColour(.exact))

        XCTAssertEqual(StatItem.Confidence.allCases.count, 3,
                       "a fourth basis was added and nothing here walks it")
    }

    // MARK: - the headline

    func testTheHeadlineIsFoundByTheLabelTheFiguresActuallyCarry() {
        // The page leads with PD-018's figure and takes it out of the grid, both by matching this
        // label. A literal typed at the call site would make a rename a profile with no headline
        // and one extra cell, with nothing failing.
        XCTAssertEqual(PersonSummary.formLabel, "Recent form")
    }

    func testTheHeadlineIsTakenOutOfTheGridRatherThanDrawnTwice() {
        let figures = [
            StatLine(label: "Matches", value: "12", note: nil),
            StatLine(label: PersonSummary.formLabel, value: "47.20", note: "Not a rating."),
            StatLine(label: "180s", value: "3", note: nil),
        ]
        let headline = figures.first { $0.label == PersonSummary.formLabel }?.item
        let grid = figures.filter { $0.label != PersonSummary.formLabel }.map(\.item)
        XCTAssertEqual(headline?.label, PersonSummary.formLabel)
        XCTAssertEqual(grid.count, 2)
        XCTAssertFalse(grid.contains { $0.label == PersonSummary.formLabel })
    }

    // MARK: - the mark

    func testTheProfileMarkIsBiggerThanARosterRowsMark() {
        // 52 is `PlayerIdentity(.large)`, which is right in a list and wrong as the subject of a
        // page: a profile picture at list size reads as a list that happens to have one row.
        XCTAssertGreaterThan(ProfileScreen.markSize, 52)
    }

    func testInitialsAreTheFirstLettersOfTheFirstTwoNames() {
        XCTAssertEqual(ProfileScreen.initials(of: "Jenson Lewis"), "JL")
        XCTAssertEqual(ProfileScreen.initials(of: "jenson lewis richards"), "JL")
        XCTAssertEqual(ProfileScreen.initials(of: "Alex"), "A")
    }

    func testANameWithNoLettersStillDrawsSomething() {
        // A mark is a circle with something in it. An empty one reads as a loading state.
        XCTAssertEqual(ProfileScreen.initials(of: "   "), "?")
        XCTAssertEqual(ProfileScreen.initials(of: ""), "?")
    }

    func testTheProfileInitialsAgreeWithTheRecordsOwn() {
        // The page is handed a name and not a record, so it computes them — and if the two rules
        // ever part company a person's mark changes between the roster and their own page.
        for name in ["Jenson Lewis", "Alex", "Mary Jane Watson", "de Vries"] {
            XCTAssertEqual(ProfileScreen.initials(of: name),
                           LocalPerson(id: "x", name: name).initials, name)
        }
    }

    // MARK: - a club member's figures

    func testAMemberWithNoAverageGetsADashWithAReasonRatherThanAZero() {
        let member = ClubMember(id: "m", name: "Alex", role: .member, ageBand: .adult,
                                joined: "2026-01-01", threeDartAverage: nil)
        for figure in ClubsFlow.figures(for: member) {
            XCTAssertEqual(figure.confidence, .unavailable, figure.label)
            XCTAssertEqual(figure.value, "—", figure.label)
            XCTAssertNotNil(figure.note, "\(figure.label) is a dash with no reason beside it")
        }
    }

    func testAMemberWithAnAverageStillGetsReasonsForWhatIsNotKnown() {
        let member = ClubMember(id: "m", name: "Alex", role: .member, ageBand: .adult,
                                joined: "2026-01-01", threeDartAverage: 47.2)
        let figures = ClubsFlow.figures(for: member)
        let average = figures.first { $0.label == "3-dart average" }
        XCTAssertEqual(average?.confidence, .exact)
        XCTAssertEqual(average?.value, "47.20")
        for figure in figures where figure.label != "3-dart average" {
            XCTAssertEqual(figure.confidence, .unavailable, figure.label)
            XCTAssertNotNil(figure.note)
        }
    }
}
