import XCTest
@testable import ThroApp
import ThroNet

/// A tournament night's page in the app (PD-126). Discover listed tournaments as rows that did nothing; the way in was
/// under You, four taps away and unsignposted. The row opens this now, and what it says is read off the server's page.
final class EventScreenTests: XCTestCase {

    private func page(state: String, entries: Int = 5, spots: Int? = 11, kind: String = "player", draw: String = "", winner: String? = nil) -> EventPage {
        let json = """
        {"eventId":"11111111-0000-4000-8000-000000000001","name":"Friday Knockout","startsAt":"2026-01-09T19:00:00Z","sessionEndsAt":"2026-01-09T23:30:00Z",
         "venue":null,"locality":null,"venueLabel":"the back room","entrantKind":"\(kind)","access":"open","state":"\(state)","entriesCloseAt":null,
         "capacity":16,"entries":\(entries),"spotsRemaining":\(spots.map(String.init) ?? "null"),"you":null,"draw":[\(draw)],"winnerId":\(winner.map { "\"\($0)\"" } ?? "null"),"boards":[]}
        """
        return try! Wire.decoder.decode(EventPage.self, from: Data(json.utf8))
    }
    private let a = "aaaaaaaa-0000-4000-8000-000000000001", b = "bbbbbbbb-0000-4000-8000-000000000002"
    private func tie(_ round: Int, _ position: Int, winner: String? = nil, outcome: String? = nil, bye: Bool = false) -> String {
        """
        {"tieId":"\(UUID().uuidString)","round":\(round),"position":\(position),"homeId":"\(a)","home":"Alice Aims","awayId":\(bye ? "null" : "\"\(b)\""),"away":\(bye ? "null" : "null"),
         "isBye":\(bye),"matchId":null,"board":null,"winnerId":\(winner.map { "\"\($0)\"" } ?? "null"),"outcome":\(outcome.map { "\"\($0)\"" } ?? "null"),"note":null}
        """
    }

    func testThePageSaysWhatKindOfNightItIsAndHowFullItIs() {
        XCTAssertEqual(EventWords.kind("player"), "Singles")
        XCTAssertEqual(EventWords.kind("pair"), "Pairs")
        XCTAssertEqual(EventWords.kind("team"), "Teams")
        XCTAssertEqual(EventWords.places(page(state: "open")), "5 entered · 11 places left")
        XCTAssertEqual(EventWords.places(page(state: "open", entries: 16, spots: 0)), "16 entered · full")
        XCTAssertEqual(EventWords.places(page(state: "open", entries: 1, spots: nil)), "1 entered")
    }

    func testThePageSaysWhereTheNightHasGotTo() {
        XCTAssertEqual(EventWords.standing(page(state: "open")), "Taking entries")
        XCTAssertEqual(EventWords.standing(page(state: "entries_closed")), "Entries are closed. The draw is next.")
        XCTAssertEqual(EventWords.standing(page(state: "in_progress", draw: [tie(1, 1, winner: a, outcome: "played"), tie(2, 1)].joined(separator: ","))), "Round 2 is being played")
        XCTAssertEqual(EventWords.standing(page(state: "complete", draw: tie(1, 1, winner: a, outcome: "played"), winner: a)), "Over. Alice Aims won it.")
        XCTAssertEqual(EventWords.standing(page(state: "cancelled")), "Called off")
    }

    func testATieSaysWhoPlaysWhomAndHowItWent() {
        let drawn = page(state: "in_progress", draw: [tie(1, 1, winner: a, outcome: "played"), tie(1, 2, bye: true), tie(2, 1)].joined(separator: ","))
        // A name THRØ may not show is a guest, never a blank and never a guess.
        XCTAssertEqual(EventWords.tie(drawn.draw[0]), "Alice Aims beat a guest")
        XCTAssertEqual(EventWords.tie(drawn.draw[1]), "Alice Aims · a bye")
        XCTAssertEqual(EventWords.tie(drawn.draw[2]), "Alice Aims v a guest")
        XCTAssertEqual(EventWords.rounds(drawn).map(\.round), [1, 2])
        XCTAssertEqual(EventWords.rounds(drawn).first?.ties.count, 2)
    }

    func testTheCardTheActionsNeedIsReadOffThePage() {
        let card = DiscoveryCard(page: page(state: "open"))
        XCTAssertEqual(card.name, "Friday Knockout")
        XCTAssertEqual(card.entrantKind, "player")
        XCTAssertEqual(card.access, "open")
        XCTAssertFalse(card.entered)
        XCTAssertEqual(card.spotsRemaining, 11)
    }

    /// A night nobody can enter themselves says so, in one sentence, wherever it is drawn (PD-138).
    ///
    /// The card under "Darts you can play" used to draw nothing at all for an invitational night: the
    /// section heading said a player could enter, the card's own reason line said "by invitation — you
    /// qualify", and beneath that there was no button and no sentence. The tournament's own page had the
    /// sentence all along; it lived inline in a view, so nothing held the two surfaces together.
    func testAnInvitationalNightSaysSoAndAnOpenOneSaysNothing() {
        XCTAssertEqual(EventWords.access("invitational"), "Entry is by invitation, from the organiser.")
        XCTAssertNil(EventWords.access("open"), "an open night needs no sentence: the button is the answer")
        XCTAssertEqual(EventWords.access("anything else"), "Entry is by invitation, from the organiser.",
                       "a kind THRØ does not know is not something a player can enter themselves")
    }
}
