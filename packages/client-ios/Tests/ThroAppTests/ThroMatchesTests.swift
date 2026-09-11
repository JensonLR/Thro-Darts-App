import Foundation
import XCTest
@testable import ThroApp
@testable import ThroNet

/// A sent match, onward, on the phone (PD-043): the list, the code, the claim and the answer against a
/// scripted server — and the words, which are the part a person actually reads.
@MainActor
final class ThroMatchesTests: XCTestCase {

    private let config = ServerConfiguration(baseURL: URL(string: "https://api.example")!, googleClientID: nil)
    private let session = Session(accountId: UUID(), playerId: nil, accessToken: "acc", refreshToken: "ref", accessExpiresAt: .distantFuture, created: false)
    private let matchId = UUID(uuidString: "5c4ee45e-0000-4000-8000-0000000000b1")!

    private func api(_ answers: [(Int, String)]) -> (ThroAPI, NetTests.Script) {
        let script = NetTests.Script(answers)
        return (ThroAPI(configuration: config, deviceId: UUID(), store: MemorySessionStore(session), transport: script), script)
    }

    /// A match as the server answers it. `you` is the reader's seat; `sentBy` is whose word it is.
    private func wire(you: String = "home", sentBy: String? = "home", theirName: String? = nil, claimable: Bool = true,
                      legs: (Int, Int) = (3, 1), winner: String? = "home", ending: String? = nil, retired: String? = nil,
                      answers: (String?, String?) = (nil, nil), standing: String = "self-reported") -> String {
        func q(_ s: String?) -> String { s.map { "\"\($0)\"" } ?? "null" }
        let home = you == "home" ? #"{"seat":"home","you":true,"name":"Jenson R.","claimable":false}"#
                                 : #"{"seat":"home","you":false,"name":\#(q(theirName)),"claimable":\#(claimable)}"#
        let away = you == "away" ? #"{"seat":"away","you":true,"name":"Jenson R.","claimable":false}"#
                                 : #"{"seat":"away","you":false,"name":\#(q(theirName)),"claimable":\#(claimable)}"#
        return #"{"matchId":"\#(matchId.uuidString.lowercased())","openedAt":"2026-09-10T19:30:00Z","format":{"startingScore":501,"inRule":"straight","outRule":"double","legsMode":"first_to","legsTarget":3},"selfReported":\#(standing != "recorded"),"seats":[\#(home),\#(away)],"legs":{"home":\#(legs.0),"away":\#(legs.1)},"visits":41,"ending":\#(q(ending)),"retired":\#(q(retired)),"winner":\#(q(winner)),"sentBy":\#(q(sentBy)),"answers":{"home":\#(q(answers.0)),"away":\#(q(answers.1))},"standing":"\#(standing)"}"#
    }

    private func record(_ json: String) throws -> MatchOnRecord {
        try Wire.decoder.decode(MatchOnRecord.self, from: Data(json.utf8))
    }

    // MARK: - the model, against a scripted server

    func testTheListIsReadAndAMatchSentHereOffersACodeAndNoAnswer() async throws {
        let (server, script) = api([(200, #"{"matches":["# + wire() + "]}")])
        let model = ThroMatchesModel()
        await model.load(server, signedIn: true)
        XCTAssertEqual(script.seen.first?.url?.path, "/v1/me/matches")
        let sent = try XCTUnwrap(model.records.first)
        XCTAssertTrue(sent.youSent)
        XCTAssertTrue(sent.canGiveCode, "the other seat is nobody's, so the sender can give a code for it")
        XCTAssertFalse(sent.canAnswer, "the sender's word is the match; they do not answer for it")
        XCTAssertEqual(sent.yourLegs, 3); XCTAssertEqual(sent.theirLegs, 1); XCTAssertEqual(sent.youWon, true)
    }

    func testSignedOutReadsNothingAndAsksTheServerNothing() async {
        let (server, script) = api([])
        let model = ThroMatchesModel()
        await model.load(server, signedIn: false)
        XCTAssertEqual(model.list, .idle)
        XCTAssertTrue(script.seen.isEmpty)
    }

    func testACodeIsKeptForItsOwnMatchOnly() async {
        let (server, script) = api([(200, #"{"code":"M4TC7H2Q","seat":"away","expiresAt":"2026-09-18T12:00:00Z"}"#)])
        let model = ThroMatchesModel()
        await model.makeCode(for: matchId, server)
        XCTAssertEqual(script.seen.first?.url?.path, "/v1/matches/\(matchId.uuidString.lowercased())/code")
        XCTAssertEqual(script.seen.first?.httpMethod, "POST")
        XCTAssertEqual(model.code(for: matchId)?.spoken, "M4TC 7H2Q")
        XCTAssertNil(model.code(for: UUID()), "a code made for one match is never shown on another's page")
    }

    func testAClaimSendsTheCodeAsItIsWrittenAndOpensTheMatchAsTheClaimerReadsIt() async throws {
        let (server, script) = api([(200, wire(you: "away", theirName: "Ethan T.", claimable: false))])
        let model = ThroMatchesModel()
        let taken = await model.claim(code: "m4tc-7h2q", server)
        let body = try XCTUnwrap(script.seen.first?.httpBody).flatMap { try JSONSerialization.jsonObject(with: $0) as? [String: String] }
        XCTAssertEqual(body?["code"], "M4TC7H2Q", "case, spaces and dashes are how a code is said, not part of it")
        XCTAssertEqual(script.seen.first?.url?.path, "/v1/matches/claim")
        XCTAssertEqual(taken?.canAnswer, true)
        XCTAssertEqual(model.records.map(\.matchId), [matchId], "the match taken is in the list at once")
    }

    func testARefusedCodeIsTheServersOwnSentence() async {
        let (server, _) = api([(422, #"{"error":"That code has been used already. Ask for a new one."}"#)])
        let model = ThroMatchesModel()
        let taken = await model.claim(code: "M4TC7H2Q", server)
        XCTAssertNil(taken)
        XCTAssertEqual(model.note, "That code has been used already. Ask for a new one.")
    }

    func testAnAnswerReplacesTheMatchInPlace() async throws {
        let first = wire(you: "away", theirName: "Ethan T.", claimable: false)
        let confirmed = wire(you: "away", theirName: "Ethan T.", claimable: false, answers: (nil, "confirmed"), standing: "confirmed")
        let (server, script) = api([(200, #"{"matches":["# + first + "]}"), (200, confirmed)])
        let model = ThroMatchesModel()
        await model.load(server, signedIn: true)
        await model.answer(matchId, agree: true, server)
        let body = try XCTUnwrap(script.seen.last?.httpBody).flatMap { try JSONSerialization.jsonObject(with: $0) as? [String: Bool] }
        XCTAssertEqual(body?["agree"], true)
        XCTAssertEqual(script.seen.last?.url?.path, "/v1/matches/\(matchId.uuidString.lowercased())/answer")
        XCTAssertEqual(model.records.count, 1)
        XCTAssertEqual(model.records.first?.standing, "confirmed")
        XCTAssertEqual(model.records.first?.yourAnswer, "confirmed")
    }

    func testAFailedRefreshKeepsTheListOnScreen() async {
        let (server, _) = api([(200, #"{"matches":["# + wire() + "]}"), (503, #"{"error":"THRØ is resting."}"#)])
        let model = ThroMatchesModel()
        await model.load(server, signedIn: true)
        await model.load(server, signedIn: true)
        XCTAssertEqual(model.records.count, 1, "a list already shown is not swapped for an error")
        XCTAssertEqual(model.note, "THRØ is resting.")
    }

    // MARK: - the words

    func testTheBadgeSaysWhoseWordItIsAndWhatIsAskedOfTheReader() throws {
        XCTAssertEqual(ThroMatchWords.badge(try record(wire())), .yourWord)
        XCTAssertEqual(ThroMatchWords.badge(try record(wire(you: "away", claimable: false))), .needsYourAnswer)
        XCTAssertEqual(ThroMatchWords.badge(try record(wire(you: "away", claimable: false, winner: nil, ending: "abandoned"))), .theirWord)
        XCTAssertEqual(ThroMatchWords.badge(try record(wire(answers: (nil, "confirmed"), standing: "confirmed"))), .confirmed)
        XCTAssertEqual(ThroMatchWords.badge(try record(wire(answers: (nil, "contested"), standing: "disputed"))), .disputed)
        XCTAssertEqual(ThroMatchWords.badge(try record(wire(sentBy: nil, standing: "recorded"))), .scoredLive)
    }

    func testANameIsTheServersWhereItMayShowOneThenThisPhonesOwnThenNobodys() throws {
        let unnamed = try record(wire())
        XCTAssertEqual(ThroMatchWords.title(unnamed), "You v your opponent")
        XCTAssertEqual(ThroMatchWords.title(unnamed, typed: "Dave"), "You v Dave", "the name typed at the oche is this phone's own")
        XCTAssertEqual(ThroMatchWords.title(try record(wire(theirName: "Sam Cross", claimable: false)), typed: "Dave"), "You v Sam Cross")
        XCTAssertEqual(ThroMatchWords.title(unnamed, typed: "   "), "You v your opponent")
    }

    func testTheResultIsReadFromTheReadersSide() throws {
        XCTAssertEqual(ThroMatchWords.result(try record(wire())), "Won 3–1")
        XCTAssertEqual(ThroMatchWords.result(try record(wire(you: "away", claimable: false))), "Lost 1–3")
        XCTAssertEqual(ThroMatchWords.result(try record(wire(legs: (1, 1), winner: nil))), "1–1, not finished")
        XCTAssertEqual(ThroMatchWords.result(try record(wire(legs: (1, 0), winner: "home", ending: "retired", retired: "away"))), "Won 1–0, they retired")
        XCTAssertEqual(ThroMatchWords.result(try record(wire(you: "away", claimable: false, legs: (1, 0), winner: "home", ending: "retired", retired: "away"))), "Lost 0–1, you retired")
        XCTAssertEqual(ThroMatchWords.result(try record(wire(legs: (1, 1), winner: nil, ending: "abandoned"))), "Abandoned at 1–1")
    }

    func testEveryStandingIsExplainedAndNothingPromisesWhatIsNotBuilt() throws {
        let cases = [
            wire(), wire(claimable: false), wire(winner: nil, ending: "abandoned"),
            wire(you: "away", claimable: false), wire(you: "away", claimable: false, winner: nil, ending: "abandoned"),
            wire(answers: (nil, "confirmed"), standing: "confirmed"), wire(you: "away", claimable: false, answers: (nil, "confirmed"), standing: "confirmed"),
            wire(answers: (nil, "contested"), standing: "disputed"), wire(you: "away", claimable: false, answers: (nil, "contested"), standing: "disputed"),
            wire(sentBy: nil, standing: "recorded"),
        ]
        for json in cases {
            let words = ThroMatchWords.explanation(try record(json))
            XCTAssertFalse(words.isEmpty)
            // A disputed match's next step is not decided (PD-043), so nothing says anybody will look at it.
            XCTAssertFalse(words.localizedCaseInsensitiveContains("review"), words)
            XCTAssertFalse(words.localizedCaseInsensitiveContains("looked at"), words)
        }
        XCTAssertTrue(ThroMatchWords.explanation(try record(wire())).contains("give them a code"))
        XCTAssertFalse(ThroMatchWords.explanation(try record(wire(winner: nil, ending: "abandoned"))).contains("confirms"),
                       "an abandoned match has no result for anybody to confirm")
    }

    func testTheShareNamesTheControlTheCodeIsEnteredUnder() {
        let share = ThroMatchWords.share(MatchCode(code: "M4TC7H2Q", seat: "away", expiresAt: Date()))
        XCTAssertTrue(share.contains("M4TC 7H2Q"))
        XCTAssertTrue(share.contains("Live → Enter a code"), "the Live tab's button is called Enter a code")
    }

    func testTheFormatIsSaidAsAPlayerWouldSayIt() throws {
        XCTAssertEqual(ThroMatchWords.format(try record(wire()).format), "501 · first to 3 · double out")
    }
}
