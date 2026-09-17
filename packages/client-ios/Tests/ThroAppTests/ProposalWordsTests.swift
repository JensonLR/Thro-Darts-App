import XCTest
@testable import ThroApp
import ThroNet

/// A proposal to move a fixture says when, and where when it names somewhere else (PD-128). The pub being shut is the
/// commonest reason a game moves, and a proposal that could only carry a date left the place to a text message.
final class ProposalWordsTests: XCTestCase {

    private let mine = UUID(uuidString: "aaaaaaaa-0000-4000-8000-000000000001")!
    private func proposal(state: String = "proposed", by: UUID? = nil, venue: String? = nil, reason: String? = nil) -> FixtureProposal {
        let json = """
        {"proposalId":"\(UUID().uuidString)","fixtureId":"\(UUID().uuidString)","leagueSeasonId":"\(UUID().uuidString)","state":"\(state)",
         "to":"2026-11-19T19:30:00Z","reason":\(reason.map { "\"\($0)\"" } ?? "null"),"byTeamId":"\((by ?? UUID()).uuidString)","byTeam":"Grange A",
         "toTeamId":"\(UUID().uuidString)","toTeam":"Riverside A","proposedAt":"2026-11-01T10:00:00Z","answeredAt":null,
         "scheduledAt":"2026-11-12T19:30:00Z","fixtureVersion":1\(venue.map { ",\"venue\":{\"venueId\":\"\(UUID().uuidString)\",\"name\":\"\($0)\",\"locality\":\"Stockton-on-Tees\"}" } ?? "")}
        """
        return try! Wire.decoder.decode(FixtureProposal.self, from: Data(json.utf8))
    }

    func testAProposalSaysWhereWhenItNamesSomewhereElse() {
        let when = RearrangementTaskActions.when(proposal().to)
        XCTAssertEqual(ProposalWords.what(proposal(venue: "Grange Social Club")), "\(when), at Grange Social Club")
        XCTAssertEqual(ProposalWords.what(proposal()), when, "no venue named: the place stays as it was, and nothing is said about it")
    }

    func testTheFixtureScreenSaysWhoProposedWhatAndWhereItStands() {
        let when = RearrangementTaskActions.when(proposal().to)
        XCTAssertEqual(ProposalWords.line(proposal(by: mine, venue: "Grange Social Club", reason: "the pub is shut"), viewing: mine),
                       "Grange A proposed \(when), at Grange Social Club — the pub is shut · waiting for Riverside A")
        XCTAssertEqual(ProposalWords.line(proposal(), viewing: mine), "Grange A proposed \(when) · waiting for your answer — it is in your inbox")
        XCTAssertEqual(ProposalWords.line(proposal(state: "accepted"), viewing: mine), "Grange A proposed \(when) · \(RearrangementTaskActions.standing("accepted"))")
    }

    func testAnOlderServerSendsNoVenueAndTheProposalStillReads() {
        XCTAssertNil(proposal().venue)
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
    }

    func testASentenceThatCouldNotBeUsedSaysWhyAndPointsAtTheForm() {
        XCTAssertEqual(ProposalWords.read(reading(ready: false, say: "That does not read as a new date for this fixture.", doubt: "move", to: nil)),
                       "That does not read as a new date for this fixture. Pick the date below.")
        XCTAssertEqual(ProposalWords.read(reading(ready: false, say: "A move, but to when?", doubt: "date", to: nil)), "A move, but to when? Pick the date below.")
        XCTAssertEqual(ProposalWords.read(reading(ready: false, say: "Thu 2 Jul, 8:30 pm is outside the season", doubt: "date", to: "2027-07-02T19:30:00Z")),
                       "Thu 2 Jul, 8:30 pm is outside the season. Pick the date below.")
    }

    func testOnlyAReadyReadingFillsTheForm() {
        XCTAssertNotNil(ProposalWords.fills(reading(ready: true, say: "s", doubt: nil, to: "2026-10-22T19:30:00Z")))
        XCTAssertNil(ProposalWords.fills(reading(ready: false, say: "s", doubt: "date", to: "2027-07-02T19:30:00Z")), "outside the season: said, not filled in")
    }
}
