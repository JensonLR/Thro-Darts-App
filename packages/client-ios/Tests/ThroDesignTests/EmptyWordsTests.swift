import XCTest
@testable import ThroDesign

/// What THRØ says when there is nothing to show, held to its own rule.
///
/// Nine of the app's nineteen empty-state bodies were over fourteen words and the longest was
/// thirty-eight, because a body is the easiest place in a codebase to answer a question nobody asked.
/// Prose does not compile, so the rule was kept by nobody. It is kept here.
final class EmptyWordsTests: XCTestCase {

    func testEveryBodyIsUnderTheCeilingOrOnTheDebtListWithAReason() {
        for words in EmptyWords.every where words.bodyWordCount > EmptyWords.ceiling {
            XCTAssertNotNil(EmptyWords.overTheCeiling[words.place],
                            "\(words.place): \(words.bodyWordCount) words and no reason recorded. "
                                + "Cut it to \(EmptyWords.ceiling), or say in `overTheCeiling` why it stays.")
        }
    }

    /// The debt list is closed from the other end too. A body brought under the ceiling that is left on
    /// the list makes the list a licence rather than a debt, and the next reader learns the wrong lesson.
    func testNothingSitsOnTheDebtListOnceItIsUnderTheCeiling() {
        for (place, why) in EmptyWords.overTheCeiling {
            guard let words = EmptyWords.every.first(where: { $0.place == place }) else {
                return XCTFail("\(place) is on the debt list and is not an empty state THRØ has")
            }
            XCTAssertGreaterThan(words.bodyWordCount, EmptyWords.ceiling,
                                 "\(place) is under the ceiling now — take it off the list. Its reason said: \(why)")
        }
    }

    func testNoBodyIsEmptyAndEveryPlaceIsNamedOnce() {
        for words in EmptyWords.every {
            XCTAssertFalse(words.body.trimmingCharacters(in: .whitespaces).isEmpty,
                           "\(words.place): an empty state with no sentence says nothing about why it is empty")
            XCTAssertFalse(words.place.trimmingCharacters(in: .whitespaces).isEmpty)
        }
        let places = EmptyWords.every.map(\.place)
        XCTAssertEqual(Set(places).count, places.count, "two empty states share a name, so the debt list cannot tell them apart")
    }

    /// The inbox is the one empty state in the app that is a good outcome: nobody needs anything from
    /// you. An action there would mirror a noun that is not missing.
    func testTheInboxOffersNothingToDoBecauseNothingIsWrong() {
        XCTAssertNil(EmptyWords.inbox.actionLabel)
    }
}
