import SwiftUI
import XCTest
import ThroEngine
import ThroJournal
import ThroStatistics
@testable import ThroPlay

/// The one picture THRØ makes that leaves the phone.
///
/// Everywhere else, a figure this app shows is one a player can tap for its basis and its sample. An
/// image cannot be tapped, cannot be corrected, and outlives the app that drew it — so what the
/// honesty layer normally keeps one tap away has to be **on the card**. These hold the four rules
/// that follow from that.
///
/// Built on a real journal rather than a hand-made `Copy`, for the reason `MatchSessionTests` gives
/// for its profile tests: a fixture proves the formatter, and the formatter is not the part that
/// breaks. The legs are written straight to the journal and the session opened on top of them,
/// because driving the keypad's prompt-and-announcement state machine would be testing that instead.
final class ShareCardTests: XCTestCase {

    private var path: String!
    private var journal: Journal!

    override func setUpWithError() throws {
        try super.setUpWithError()
        path = NSTemporaryDirectory() + "thro-share-\(UUID().uuidString).sqlite"
        journal = try Journal(path: path, deviceId: DeviceId("share-tests"))
    }

    override func tearDown() {
        journal = nil
        for suffix in ["", "-wal", "-shm"] { try? FileManager.default.removeItem(atPath: path + suffix) }
        super.tearDown()
    }

    private func match(legs: Int = 1, inRule: InRule = .straight) throws -> MatchRecord {
        try journal.createMatch(NewMatch(homeName: "Ann", awayName: "Bea", inRule: inRule,
                                         legsMode: .firstTo, legsTarget: legs))
    }

    /// One 501 leg to Ann: two 180s each, then 141 in three darts with one at a double.
    private func annTakesALeg(_ id: MatchId) throws {
        try journal.append(.visit(Seat.home.playerId, 180), to: id)
        try journal.append(.visit(Seat.away.playerId, 60), to: id)
        try journal.append(.visit(Seat.home.playerId, 180), to: id)
        try journal.append(.visit(Seat.away.playerId, 60), to: id)
        try journal.append(.visit(Seat.home.playerId, 141, dartsUsed: 3, dartsAtDouble: 1), to: id)
    }

    /// A finished match Ann won 1–0.
    private func annWon() throws -> MatchSession {
        let record = try match()
        try annTakesALeg(record.id)
        let session = try MatchSession.open(record.id, in: journal)
        XCTAssertTrue(session.isComplete)
        XCTAssertEqual(session.winner, .home)
        return session
    }

    // MARK: rule 1 — the card carries how the result is verified

    /// **Never nothing.** A shared scoreline with no provenance is exactly the artefact PD-002
    /// exists to prevent: a claim with no basis, in a group chat, with nobody able to check it.
    func testEveryCardSaysHowTheResultIsVerified() throws {
        let copy = ThroShareCard.copy(for: try annWon())
        XCTAssertFalse(copy.provenance.isEmpty)
        XCTAssertTrue(copy.provenance.lowercased().contains("self-reported"), copy.provenance)
    }

    /// Both players agreeing changes the sentence, and the sentence still says it was one phone.
    /// Two people at one device is the weakest form of participant-confirmed, and a card that
    /// presented it as corroboration by two independent devices would be overstating the evidence
    /// to exactly the audience least able to check it.
    func testAConfirmedResultSaysItWasTwoPeopleAndNotTwoDevices() throws {
        let session = try annWon()
        session.attest(.home, agrees: true)
        session.attest(.away, agrees: true)
        let copy = ThroShareCard.copy(for: session)
        XCTAssertTrue(copy.provenance.contains("Both players confirmed"), copy.provenance)
        XCTAssertTrue(copy.provenance.lowercased().contains("not two devices"), copy.provenance)
    }

    /// **A dispute goes on the card.** Sharing a contested result as though it were agreed is the
    /// one failure here somebody might actually want, so the card is marked rather than quietly
    /// leaving the disagreement behind on the phone.
    func testADisputedResultSaysSoOnTheCard() throws {
        let session = try annWon()
        session.attest(.home, agrees: true)
        session.attest(.away, agrees: false)
        XCTAssertEqual(session.verification, .disputed)
        let copy = ThroShareCard.copy(for: session)
        XCTAssertTrue(copy.provenance.hasPrefix("Disputed"), copy.provenance)
        XCTAssertTrue(copy.provenance.contains("Nothing has been deleted"), copy.provenance)
    }

    /// An agreement the result outran afterwards is not an agreement about what the card shows, so
    /// the card falls back to self-reported rather than carrying a confirmation nobody gave to this
    /// version of the result. The undo-and-throw-again below is how that actually happens.
    func testAnAgreementTheResultOutranIsNotClaimedOnTheCard() throws {
        let record = try match()
        try annTakesALeg(record.id)
        let agreed = try MatchSession.open(record.id, in: journal)
        agreed.attest(.home, agrees: true)
        agreed.attest(.away, agrees: true)
        XCTAssertTrue(ThroShareCard.copy(for: agreed).provenance.contains("Both players confirmed"))

        try journal.retractLastVisit(in: record.id)
        try journal.append(.visit(Seat.home.playerId, 141, dartsUsed: 3, dartsAtDouble: 2), to: record.id)

        let again = try MatchSession.open(record.id, in: journal)
        XCTAssertTrue(again.isComplete)
        XCTAssertTrue(again.standing.stale, "the result moved after it was agreed")
        let copy = ThroShareCard.copy(for: again)
        XCTAssertTrue(copy.provenance.lowercased().contains("self-reported"), copy.provenance)
        XCTAssertFalse(copy.provenance.contains("Both players confirmed"), copy.provenance)
    }

    // MARK: rule 2 — the card carries its sample

    func testTheCardSaysHowManyVisitsItsFiguresComeFrom() throws {
        XCTAssertEqual(ThroShareCard.copy(for: try annWon()).sample,
                       "From 5 visits across 1 leg recorded in this match.")
    }

    /// One of each, because "1 visits across 1 legs" is the kind of thing that survives review and
    /// then sits in somebody's group chat for a year.
    func testTheSampleSentenceCountsInSingularAndPlural() {
        XCTAssertEqual(ThroShareCard.sample(visits: 1, legs: 1),
                       "From 1 visit across 1 leg recorded in this match.")
        XCTAssertEqual(ThroShareCard.sample(visits: 2, legs: 3),
                       "From 2 visits across 3 legs recorded in this match.")
        XCTAssertEqual(ThroShareCard.sample(visits: 4, legs: 0),
                       "From 4 visits recorded in this match.")
    }

    // MARK: rule 3 — a figure appears only when it is known for both

    /// A dash on one side of a shared image reads as a zero to somebody who cannot tap it for the
    /// reason, so the row is dropped for both rather than shown for one.
    func testAFigureOnlyOnePlayerHasIsOnTheCardForNeither() {
        let both = ThroShareCard.figures(
            home: [StatLine(label: "Checkout %", value: "50%", note: nil, confidence: .exact)],
            away: [StatLine(label: "Checkout %", value: "33%", note: nil, confidence: .exact)])
        XCTAssertEqual(both, [ThroShareCard.Figure(label: "Checkout %", home: "50%", away: "33%")])

        let one = ThroShareCard.figures(
            home: [StatLine(label: "Checkout %", value: "50%", note: nil, confidence: .exact)],
            away: [StatLine(label: "Checkout %", value: "—", note: "No darts at a double.",
                            confidence: .unavailable)])
        XCTAssertTrue(one.isEmpty, "a figure one player does not have is on the card for neither")
    }

    /// A bounded figure goes on the card as its range. Collapsing it to a point value is the exact
    /// lie the statistics layer was built to make impossible, and an image is the worst place for it.
    func testABoundedFigureKeepsItsRange() {
        let figures = ThroShareCard.figures(
            home: [StatLine(label: "3-dart average", value: "58.2–61.0", note: "Range",
                            confidence: .range)],
            away: [StatLine(label: "3-dart average", value: "54.1", note: nil, confidence: .exact)])
        XCTAssertEqual(figures.first?.home, "58.2–61.0")
        XCTAssertEqual(figures.first?.away, "54.1")
    }

    /// **Rule 3, on a real leg rather than a hand-made figure.** Ann checked out; Bea never threw
    /// from a finish at all, so a checkout percentage of hers is a figure with no sample — and the
    /// row is dropped for *both*, because a card reading "Ann 100% · Bea —" invites a reader who
    /// cannot tap it for the reason to fill in a zero.
    ///
    /// This test asserted all three labels when it was written. CI was right and the expectation was
    /// wrong, which is the rule firing on the first real match it saw.
    func testTheCardDropsAFigureOnlyOnePlayerCouldHave() throws {
        let session = try annWon()
        XCTAssertEqual(session.statistics(for: .home).first { $0.label == "Checkout %" }?.confidence,
                       .exact, "Ann checked out, so hers is a real figure")
        XCTAssertEqual(session.statistics(for: .away).first { $0.label == "Checkout %" }?.confidence,
                       .unavailable, "Bea never threw from a finish")
        XCTAssertEqual(ThroShareCard.copy(for: session).figures.map(\.label),
                       ["3-dart average", "180s"],
                       "the checkout row is on the card for neither, not for one")
    }

    /// No figure reaches the card that this build would not show inside the app, and none of them is
    /// the form figure — which is not a rating (PD-018, OD-001) and must not become one by being
    /// shared with people who cannot see the label that says so.
    func testTheCardCarriesNoFigureTheAppWouldNotShow() throws {
        let copy = ThroShareCard.copy(for: try annWon())
        XCTAssertTrue(copy.figures.map(\.label)
                        .allSatisfy(["3-dart average", "Checkout %", "180s"].contains),
                      "\(copy.figures.map(\.label))")
        let text = (copy.figures.map(\.label) + [copy.headline, copy.provenance, copy.sample, copy.format])
            .joined(separator: " ").lowercased()
        for banned in ["rating", "rank", "form", "elo"] {
            XCTAssertFalse(text.contains(banned), "\(banned) reached the card in: \(text)")
        }
    }

    // MARK: rule 4 — a match with no result carries no scoreline

    func testAnAbandonedMatchCarriesNoScorelineAndClaimsNothing() throws {
        let record = try match(legs: 3)
        try journal.append(.visit(Seat.home.playerId, 180), to: record.id)
        try journal.end(record.id, as: .abandoned)
        let session = try MatchSession.open(record.id, in: journal)

        let copy = ThroShareCard.copy(for: session)
        XCTAssertEqual(copy.headline, "No result")
        XCTAssertNil(copy.score, "there is no number that would be true there")
        XCTAssertNil(copy.winner)
        XCTAssertTrue(copy.provenance.contains("counts for nobody"), copy.provenance)
        XCTAssertFalse(copy.provenance.lowercased().contains("self-reported"),
                       "a match nobody won has no result to self-report")
        XCTAssertEqual(copy.caveat, session.resultDetail, "the abandonment sentence goes on the card")
    }

    /// A retirement *does* have a winner, so the card keeps its scoreline — and says it was a
    /// retirement, rather than letting "Ann wins · 1–0" stand as a match played out.
    func testARetirementCarriesItsScorelineAndSaysItWasARetirement() throws {
        let record = try match(legs: 3)
        try annTakesALeg(record.id)
        try journal.end(record.id, as: .retired(by: .away))
        let session = try MatchSession.open(record.id, in: journal)

        let copy = ThroShareCard.copy(for: session)
        XCTAssertEqual(copy.headline, "Ann wins")
        XCTAssertEqual(copy.winner, .home)
        XCTAssertEqual(copy.score, "1–0")
        XCTAssertEqual(copy.caveat?.contains("retired"), true, copy.caveat ?? "no caveat")
    }

    // MARK: the rest of the card

    /// The format is spelled out rather than abbreviated: a card is read by people who were not
    /// there, and "Bo3" is jargon to half of them.
    func testTheFormatIsSpelledOutForSomebodyWhoWasNotThere() throws {
        let record = try match(legs: 3)
        try annTakesALeg(record.id)
        XCTAssertEqual(ThroShareCard.copy(for: try MatchSession.open(record.id, in: journal)).format,
                       "501 · First to 3 · Double out")
    }

    /// Double-in changes what every figure on the card means, so it is named on the card.
    func testDoubleInIsNamedBecauseItChangesWhatTheFiguresMean() throws {
        let record = try match(inRule: .double)
        let copy = ThroShareCard.copy(for: try MatchSession.open(record.id, in: journal))
        XCTAssertTrue(copy.format.contains("Double in"), copy.format)
    }

    func testTheNamesAndTheLegsAreTheOnesTheMatchHolds() throws {
        let copy = ThroShareCard.copy(for: try annWon())
        XCTAssertEqual(copy.homeName, "Ann")
        XCTAssertEqual(copy.awayName, "Bea")
        XCTAssertEqual(copy.score, "1–0")
        XCTAssertEqual(copy.headline, "Ann wins")
        XCTAssertEqual(copy.winner, .home)
    }

    /// The card renders, at the size it claims. `ImageRenderer` is the whole delivery mechanism, so
    /// a card that produced nothing would be a share button that silently did nothing — and a
    /// picture at the wrong aspect gets cropped by whatever it is sent to.
    @MainActor func testTheCardRendersAtTheSizeItClaims() throws {
        let renderer = ImageRenderer(content: ThroShareCardView(copy: ThroShareCard.copy(for: try annWon())))
        renderer.scale = ThroShareCard.scale
        guard let image = renderer.cgImage else {
            return XCTFail("the share card drew nothing")
        }
        XCTAssertEqual(image.width, Int(ThroShareCard.size.width * ThroShareCard.scale))
        XCTAssertEqual(image.height, Int(ThroShareCard.size.height * ThroShareCard.scale))
    }
}
