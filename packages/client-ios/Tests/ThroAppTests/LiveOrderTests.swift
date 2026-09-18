import XCTest
@testable import ThroApp

/// The order the Live tab reads in (PD-156).
///
/// Live was three to five screens long, and the pub-screen chooser sat fourth — above *Still to play*,
/// above *Send to THRØ*, above the player's own record on THRØ. So a player scrolled past an offer meant
/// for a venue to reach the matches they came for, and had no way of knowing the page had more of theirs
/// below it. The order is declared once, here, and the screen takes its entrance order from the same
/// value, so a section cannot quietly move without this failing.
final class LiveOrderTests: XCTestCase {

    func testEverythingTheReaderOwnsComesBeforeAnOfferMeantForAVenue() {
        let theirs = LiveSection.allCases.filter { $0.isTheReadersOwn }
        XCTAssertFalse(theirs.isEmpty, "the tab is the reader's matches before it is anything else")
        for section in theirs {
            XCTAssertLessThan(section.rawValue, LiveSection.pubScreen.rawValue,
                              "\(section) is the reader's own and must read before the pub screen")
        }
    }

    func testTheMatchGoingOnRightNowIsFirst() {
        XCTAssertEqual(LiveSection.allCases.first, .onThisPhone,
                       "a match being scored now is why somebody opens Live")
    }

    func testThePubScreenIsAnOfferAndNotTheReadersOwn() {
        XCTAssertFalse(LiveSection.pubScreen.isTheReadersOwn)
        XCTAssertFalse(LiveSection.followingAMatch.isTheReadersOwn, "a closing note is not content either")
    }

    func testTheOrderIsWhatItSaysItIs() {
        XCTAssertEqual(LiveSection.allCases.map(\.self),
                       [.onThisPhone, .waitingOnAResult, .stillToPlay, .sendToThro, .onThro, .pubScreen, .followingAMatch],
                       "the whole order, written out, so a change to it is a change to this line")
    }
}
