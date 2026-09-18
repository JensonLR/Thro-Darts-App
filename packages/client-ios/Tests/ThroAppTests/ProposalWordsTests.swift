import XCTest
@testable import ThroApp
import ThroNet

/// A proposal to move a fixture says when, and where when it names somewhere else (PD-128). The pub being shut is the
/// commonest reason a game moves, and a proposal that could only carry a date left the place to a text message.
final class ProposalWordsTests: XCTestCase {

    private let mine = UUID(uuidString: "aaaaaaaa-0000-4000-8000-000000000001")!
    /// `venue` names somewhere else to play it; `locality` is the town THRØ holds for that venue, which it may not have.
    /// `venueSaidToBeNull` sends the key explicitly as null, which is what a server that knows about PD-128 sends when
    /// the proposal names nowhere — as against a server from before it, which sends no key at all.
    private func proposal(state: String = "proposed", by: UUID? = nil, venue: String? = nil,
                          locality: String? = "Stockton-on-Tees", reason: String? = nil,
                          venueSaidToBeNull: Bool = false) -> FixtureProposal {
        let place: String
        if let venue {
            place = ",\"venue\":{\"venueId\":\"\(UUID().uuidString)\",\"name\":\"\(venue)\",\"locality\":\(locality.map { "\"\($0)\"" } ?? "null")}"
        } else {
            place = venueSaidToBeNull ? ",\"venue\":null" : ""
        }
        let json = """
        {"proposalId":"\(UUID().uuidString)","fixtureId":"\(UUID().uuidString)","leagueSeasonId":"\(UUID().uuidString)","state":"\(state)",
         "to":"2026-11-19T19:30:00Z","reason":\(reason.map { "\"\($0)\"" } ?? "null"),"byTeamId":"\((by ?? UUID()).uuidString)","byTeam":"Grange A",
         "toTeamId":"\(UUID().uuidString)","toTeam":"Riverside A","proposedAt":"2026-11-01T10:00:00Z","answeredAt":null,
         "scheduledAt":"2026-11-12T19:30:00Z","fixtureVersion":1\(place)}
        """
        return try! Wire.decoder.decode(FixtureProposal.self, from: Data(json.utf8))
    }

    func testAProposalSaysWhereWhenItNamesSomewhereElse() {
        let when = RearrangementTaskActions.when(proposal().to)
        XCTAssertEqual(ProposalWords.what(proposal(venue: "Grange Social Club")), "\(when), at Grange Social Club")
        XCTAssertEqual(ProposalWords.what(proposal()), when, "no venue named: the place stays as it was, and nothing is said about it")
        // A venue THRØ holds no town for is still a venue. The name alone is said, and the sentence must not
        // end in the comma that a town would have followed.
        let unlocated = ProposalWords.what(proposal(venue: "Grange Social Club", locality: nil))
        XCTAssertEqual(unlocated, "\(when), at Grange Social Club", "no town on file: the name alone, and no trailing comma waiting for one")
        XCTAssertFalse(unlocated.hasSuffix(", "), "a missing town must not leave the sentence hanging")
        XCTAssertFalse(unlocated.contains("Grange Social Club,"), "nothing follows the name when there is no town to follow it")
    }

    func testTheFixtureScreenSaysWhoProposedWhatAndWhereItStands() {
        let when = RearrangementTaskActions.when(proposal().to)
        XCTAssertEqual(ProposalWords.line(proposal(by: mine, venue: "Grange Social Club", reason: "the pub is shut"), viewing: mine),
                       "Grange A proposed \(when), at Grange Social Club — the pub is shut · waiting for Riverside A")
        XCTAssertEqual(ProposalWords.line(proposal(), viewing: mine), "Grange A proposed \(when) · waiting for your answer — it is in your inbox")
        // The place carries into the line the other team reads too, or the side being asked to agree is the one
        // side that cannot see where it is being asked to play.
        XCTAssertEqual(ProposalWords.line(proposal(venue: "Grange Social Club"), viewing: mine),
                       "Grange A proposed \(when), at Grange Social Club · waiting for your answer — it is in your inbox")
        XCTAssertEqual(ProposalWords.line(proposal(state: "accepted"), viewing: mine), "Grange A proposed \(when) · \(RearrangementTaskActions.standing("accepted"))")
        // Every state a proposal can come to rest in, with the words written out rather than asked for: calling
        // standing() on both sides would let the sentence change to anything and this test would still be green.
        XCTAssertEqual(ProposalWords.line(proposal(state: "declined"), viewing: mine),
                       "Grange A proposed \(when) · Declined.")
        XCTAssertEqual(ProposalWords.line(proposal(state: "withdrawn"), viewing: mine),
                       "Grange A proposed \(when) · Withdrawn by the team that proposed it.")
        XCTAssertEqual(ProposalWords.line(proposal(state: "applied"), viewing: mine),
                       "Grange A proposed \(when) · Applied by the league: the fixture has moved.")
        XCTAssertEqual(ProposalWords.line(proposal(state: "accepted"), viewing: mine),
                       "Grange A proposed \(when) · Agreed. The league applies it; the fixture moves when it does.")
    }

    func testAnOlderServerSendsNoVenueAndTheProposalStillReads() {
        XCTAssertNil(proposal().venue)
        let when = RearrangementTaskActions.when(proposal().to)
        XCTAssertEqual(ProposalWords.what(proposal()), when, "no venue key at all: the date alone, and the proposal still reads")
        // A server that knows about PD-128 and has nowhere to name says so out loud. It must read the same as
        // the older server's silence, not crash on the null and not invent a place.
        let saidNull = proposal(venueSaidToBeNull: true)
        XCTAssertNil(saidNull.venue)
        XCTAssertEqual(ProposalWords.what(saidNull), when)
        XCTAssertEqual(ProposalWords.line(saidNull, viewing: mine), "Grange A proposed \(when) · waiting for your answer — it is in your inbox")
    }

    // --- the captain says it (PD-129) ---

    private func reading(ready: Bool, say: String, doubt: String?, to: String?) -> MoveReading {
        let json = """
        {"text":"x","ready":\(ready),"confidence":0.9,"say":"\(say)","doubt":\(doubt.map { "\"\($0)\"" } ?? "null"),"to":\(to.map { "\"\($0)\"" } ?? "null"),"on":null,"time":null}
        """
        return try! Wire.decoder.decode(MoveReading.self, from: Data(json.utf8))
    }

    func testWhatWasReadIsSaidBackToBeChecked() {
        XCTAssertEqual(ProposalWords.read(reading(ready: true, say: "Thu 22 Oct, 8:30 pm", doubt: nil, to: "2026-10-22T19:30:00Z")),
                       "Read as Thu 22 Oct, 8:30 pm. Check it below, then propose it.")
        // The server's say for a ready reading is a date, not a sentence, so it ends in no punctuation of its own.
        // The read-back supplies the full stop, and supplies exactly one.
        let saidBack = ProposalWords.read(reading(ready: true, say: "Fri 7 Nov, 8 pm", doubt: nil, to: "2026-11-07T20:00:00Z"))
        XCTAssertEqual(saidBack, "Read as Fri 7 Nov, 8 pm. Check it below, then propose it.")
        XCTAssertFalse(saidBack.contains(".."), "one full stop after the date, never two")
        XCTAssertFalse(saidBack.contains("Pick the date below"), "a reading that worked does not send the captain to the form instead")
    }

    func testASentenceThatCouldNotBeUsedSaysWhyAndPointsAtTheForm() {
        XCTAssertEqual(ProposalWords.read(reading(ready: false, say: "That does not read as a new date for this fixture.", doubt: "move", to: nil)),
                       "That does not read as a new date for this fixture. Pick the date below.")
        XCTAssertEqual(ProposalWords.read(reading(ready: false, say: "A move, but to when?", doubt: "date", to: nil)), "A move, but to when? Pick the date below.")
        XCTAssertEqual(ProposalWords.read(reading(ready: false, say: "Thu 2 Jul, 8:30 pm is outside the season", doubt: "date", to: "2027-07-02T19:30:00Z")),
                       "Thu 2 Jul, 8:30 pm is outside the season. Pick the date below.")
        // A date already gone is the server's own sentence and already ends in a question mark. The words that
        // follow are added to it, not instead of it, and no second full stop is stitched on behind the question.
        let gone = ProposalWords.read(reading(ready: false, say: "Thu 22 Oct has gone. To when?", doubt: "date", to: nil))
        XCTAssertEqual(gone, "Thu 22 Oct has gone. To when? Pick the date below.")
        XCTAssertFalse(gone.contains("?."), "a question mark is punctuation enough")
        XCTAssertFalse(gone.contains(".."), "and never two full stops")
    }

    func testOnlyAReadyReadingFillsTheForm() {
        XCTAssertNotNil(ProposalWords.fills(reading(ready: true, say: "s", doubt: nil, to: "2026-10-22T19:30:00Z")))
        XCTAssertNil(ProposalWords.fills(reading(ready: false, say: "s", doubt: "date", to: "2027-07-02T19:30:00Z")), "outside the season: said, not filled in")
        // Ready, and yet no date came back with it. There is nothing to put in the form, so nothing goes in it:
        // the date the captain had already picked stays where it was rather than being cleared by a blank.
        XCTAssertNil(ProposalWords.fills(reading(ready: true, say: "Read, but no date came with it.", doubt: nil, to: nil)),
                     "no date read: the form keeps the one the captain had")
    }

    func testAReadingTheServerRefusedIsSaidInTheServersOwnWords() {
        // What the catch in readIt says back (PD-129): the server's refusal is shown as the server worded it,
        // never as a status code, and never as silence.
        let refused = APIError.status(503, "{\"error\":\"That could not be read just now. The reader is down; pick the date below.\"}")
        XCTAssertEqual(ThroAPI.refusal(refused), "That could not be read just now. The reader is down; pick the date below.")
        // A refusal with nothing to say leaves the screen to supply its own words rather than showing a body or a number.
        XCTAssertNil(ThroAPI.refusal(APIError.status(503, "<html>Service Unavailable</html>")),
                     "no words from the server: the screen says its own, and never shows the body")
        XCTAssertNil(ThroAPI.refusal(APIError.unreachable("offline")), "a call that never landed carries no refusal to read back")
    }

    // --- what the inbox card says, and what the form takes (PD-142) -----------------------------------
    //
    // These three were assembled inline in views, so the audit of PD-128 and PD-129 could name them as
    // promises and no test could reach them. They are functions now, and these are the tests that were
    // waiting for them.

    // These assert the SENTENCE, never the formatted date. `Date.formatted` follows the reader's locale, so
    // "19 Nov 2026 at 19:30" here and "Nov 19, 2026 at 7:30 PM" on a runner set to American English — and a
    // test that pins the literal passes on the machine it was written on and fails everywhere else. It did
    // exactly that: green locally, five red in CI. What these hold is what the function composes.
    func testTheInboxCardSaysWhoProposedWhatInsteadOfWhenAndWhy() {
        let p = proposal(venue: "Grange Social Club", reason: "the pub is shut")
        XCTAssertEqual(ProposalWords.card(p),
                       "Grange A proposes \(ProposalWords.what(p)) instead of \(RearrangementTaskActions.when(p.scheduledAt)) — the pub is shut")
        XCTAssertTrue(ProposalWords.card(p).contains("at Grange Social Club"), "the card says the place")

        let noPlace = proposal(reason: "the pub is shut")
        XCTAssertEqual(ProposalWords.card(noPlace),
                       "Grange A proposes \(ProposalWords.what(noPlace)) instead of \(RearrangementTaskActions.when(noPlace.scheduledAt)) — the pub is shut")
        XCTAssertFalse(ProposalWords.card(noPlace).contains(", at "), "no venue: no place in the sentence")

        let noReason = proposal(venue: "Grange Social Club")
        XCTAssertFalse(ProposalWords.card(noReason).contains("—"),
                       "no reason given: the sentence ends rather than trailing a dash")
        XCTAssertTrue(ProposalWords.card(noReason).hasSuffix(RearrangementTaskActions.when(noReason.scheduledAt)),
                      "and it ends on the date it is instead of")
    }

    func testTheAgreeButtonSaysWhatIsBeingAgreedTo() {
        // The button's label is the one place a captain reads what they are about to agree to, so it
        // carries the place as well as the date.
        let withPlace = proposal(venue: "Grange Social Club")
        XCTAssertEqual(ProposalWords.agree(withPlace), "Agree to \(ProposalWords.what(withPlace))")
        XCTAssertTrue(ProposalWords.agree(withPlace).hasSuffix(", at Grange Social Club"))

        let plain = proposal()
        XCTAssertEqual(ProposalWords.agree(plain), "Agree to \(ProposalWords.what(plain))")
        XCTAssertFalse(ProposalWords.agree(plain).contains(", at "), "no venue: the date alone")
    }

    func testTheCaptainsOwnWordsBecomeTheReasonUnlessTheyWroteOne() {
        XCTAssertEqual(ProposalWords.reason(from: "pub's shut, can we do the 22nd", existing: ""),
                       "pub's shut, can we do the 22nd", "an empty Why? takes the sentence that was read")
        XCTAssertEqual(ProposalWords.reason(from: "pub's shut, can we do the 22nd", existing: "   "),
                       "pub's shut, can we do the 22nd", "whitespace is empty")
        XCTAssertEqual(ProposalWords.reason(from: "pub's shut, can we do the 22nd", existing: "flooded"),
                       "flooded", "a Why? already written is the captain's and is left alone")
    }
}
