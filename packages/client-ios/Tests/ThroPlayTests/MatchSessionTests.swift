import XCTest
import ThroEngine
import ThroJournal
import ThroStatistics
@testable import ThroPlay

final class MatchSessionTests: XCTestCase {

    private var path: String!
    private var journal: Journal!

    override func setUpWithError() throws {
        try super.setUpWithError()
        path = NSTemporaryDirectory() + "thro-play-\(UUID().uuidString).sqlite"
        journal = try Journal(path: path, deviceId: DeviceId("play-tests"))
    }

    override func tearDown() {
        journal = nil
        for suffix in ["", "-wal", "-shm"] { try? FileManager.default.removeItem(atPath: path + suffix) }
        super.tearDown()
    }

    private func session(legs: Int = 3) throws -> MatchSession {
        try MatchSession.start(NewMatch(homeName: "Jenson", awayName: "Alex", legsTarget: legs), in: journal)
    }

    /// home 501 → 141 with two 180s while away scores twice; home is then on a finish.
    private func bringHomeToAFinish(_ s: MatchSession) {
        s.quick(180); s.quick(60)
        s.quick(180); s.quick(60)
        XCTAssertEqual(s.remaining(.home), 141)
        XCTAssertEqual(s.thrower, .home)
    }

    // MARK: entry

    func testEntryTakesAtMostThreeDigits() throws {
        let s = try session()
        for d in ["1", "8", "0", "5"] { s.digit(d) }
        XCTAssertEqual(s.entry, "180")
        s.clearEntry()
        XCTAssertEqual(s.entry, "")
    }

    func testAQuickTotalAwayFromAFinishCommitsWithoutAQuestion() throws {
        let s = try session()
        s.quick(60)
        XCTAssertNil(s.prompt)
        XCTAssertEqual(s.remaining(.home), 441)
        XCTAssertEqual(s.thrower, .away, "the turn rotates")
        XCTAssertEqual(try journal.entries(for: s.record.id).count, 1, "the visit is in the journal")
        XCTAssertEqual(s.visits.count, 1)
        XCTAssertNil(s.visits[0].dartsAtDouble, "not asked, so unknown — not zero")
    }

    // MARK: PD-001

    func testAVisitThatBeginsOnAFinishAsksDartsAtDoubleEvenWhenItMisses() throws {
        let s = try session()
        bringHomeToAFinish(s)
        s.digit("1"); s.digit("0"); s.digit("0"); s.enter()
        XCTAssertEqual(s.prompt, .dartsAtDouble(total: 100, dartsUsed: nil, finished: false))
        XCTAssertEqual(s.prompt?.options, [0, 1, 2, 3])
        XCTAssertEqual(s.prompt?.preset, 0)
        XCTAssertEqual(try journal.entries(for: s.record.id).count, 4, "nothing is written while the question is open")
        s.answer(0)
        XCTAssertNil(s.prompt)
        XCTAssertEqual(s.remaining(.home), 41)
        XCTAssertEqual(s.visits.last?.dartsAtDouble, 0, "a genuine none is zero")
        XCTAssertEqual(try journal.entries(for: s.record.id).last?.dartsAtDouble, 0)
    }

    func testAVisitAwayFromAFinishIsNotAsked() throws {
        let s = try session()
        s.quick(180)                      // 321 is not a checkout
        XCTAssertNil(s.prompt)
        s.quick(26); s.quick(140)         // home to 181 — not a checkout either
        XCTAssertNil(s.prompt)
    }

    func testAFinishAsksDartsUsedThenDartsAtDouble() throws {
        let s = try session()
        bringHomeToAFinish(s)
        s.digit("1"); s.digit("4"); s.digit("1"); s.enter()
        XCTAssertEqual(s.prompt, .dartsUsed(total: 141))
        XCTAssertEqual(s.prompt?.options, [1, 2, 3])
        XCTAssertEqual(s.prompt?.preset, 3)
        s.answer(3)
        XCTAssertEqual(s.prompt, .dartsAtDouble(total: 141, dartsUsed: 3, finished: true))
        XCTAssertEqual(s.prompt?.options, [1, 2, 3])
        XCTAssertEqual(s.prompt?.preset, 1)
        s.answer(1)
        XCTAssertNil(s.prompt)
        XCTAssertEqual(s.legsWon(.home), 1)
        XCTAssertEqual(s.visits.last?.wonLeg, true)
        XCTAssertEqual(s.visits.last?.dartsUsed, 3)
        XCTAssertEqual(s.visits.last?.dartsAtDouble, 1)
        XCTAssertNil(s.notice)
        XCTAssertEqual(s.announcement, .legWon(leg: 1, winner: .home, legsHome: 1, legsAway: 0, next: .away),
                       "the won leg is announced over the screen for both players (PD-005)")
        XCTAssertEqual(s.thrower, .away, "away starts leg 2")
        XCTAssertEqual(s.state.currentLeg, 2)
    }

    func testDartsAtDoubleOptionsNeverExceedDartsUsed() throws {
        let s = try session()
        bringHomeToAFinish(s)
        s.quick(100); s.answer(0)         // home to 41, no double attempted
        s.quick(60)                       // away
        s.digit("4"); s.digit("1"); s.enter()
        XCTAssertEqual(s.prompt, .dartsUsed(total: 41))
        s.answer(2)
        XCTAssertEqual(s.prompt, .dartsAtDouble(total: 41, dartsUsed: 2, finished: true))
        XCTAssertEqual(s.prompt?.options, [1, 2], "two darts thrown, so at most two at a double")
        s.answer(1)
        XCTAssertNil(s.prompt)
        XCTAssertEqual(s.legsWon(.home), 1)
        XCTAssertEqual(s.visits.last?.dartsUsed, 2)

        // When darts used is left unknown, every option stays open.
        let s2 = try MatchSession.start(NewMatch(homeName: "A", awayName: "B"), in: journal)
        bringHomeToAFinish(s2)
        s2.quick(100); s2.answer(0); s2.quick(60)
        s2.digit("4"); s2.digit("1"); s2.enter(); s2.answer(nil)
        XCTAssertEqual(s2.prompt?.options, [1, 2, 3])
    }

    func testNotSureIsRecordedAsUnknownNeverZero() throws {
        let s = try session()
        bringHomeToAFinish(s)
        s.quick(100)                      // from 141: on a finish, asks darts at a double
        XCTAssertNotNil(s.prompt)
        s.answer(nil)
        XCTAssertNil(s.visits.last?.dartsAtDouble)
        XCTAssertNil(try journal.entries(for: s.record.id).last?.dartsAtDouble)
        XCTAssertEqual(s.remaining(.home), 41)
    }

    func testCancellingTheQuestionSubmitsNothingAndKeepsTheEntry() throws {
        let s = try session()
        bringHomeToAFinish(s)
        s.digit("1"); s.digit("0"); s.digit("0"); s.enter()
        XCTAssertNotNil(s.prompt)
        s.cancelPrompt()
        XCTAssertNil(s.prompt)
        XCTAssertEqual(s.entry, "100", "kept so it can be corrected")
        XCTAssertEqual(s.remaining(.home), 141)
        XCTAssertEqual(try journal.entries(for: s.record.id).count, 4)
    }

    // MARK: refusals and busts

    func testARejectedVisitLeavesTheJournalAndTheStateUntouched() throws {
        let s = try session()
        s.digit("1"); s.digit("7"); s.digit("9"); s.enter()
        XCTAssertEqual(s.notice, MatchSession.Notice(text: "179 cannot be scored with three darts.", tone: .error))
        XCTAssertEqual(s.entry, "179", "the refused entry stays on screen")
        XCTAssertEqual(s.remaining(.home), 501)
        XCTAssertEqual(s.thrower, .home)
        XCTAssertTrue(try journal.entries(for: s.record.id).isEmpty)
    }

    func testABustFromAFinishStillAsksAndThenRestores() throws {
        let s = try session()
        bringHomeToAFinish(s)
        s.quick(180)
        // 141 is checkable, so PD-001 asks first; the answer then submits and the engine busts it.
        XCTAssertEqual(s.prompt, .dartsAtDouble(total: 180, dartsUsed: nil, finished: false))
        s.answer(0)
        XCTAssertEqual(s.bust, MatchSession.BustDisplay(seat: .home, restored: 141))
        XCTAssertEqual(s.remaining(.home), 141)
        XCTAssertEqual(s.thrower, .away)
        XCTAssertNil(s.notice)
        XCTAssertEqual(s.announcement, .bust(seat: .home, restored: 141, reason: nil, next: .away))
        XCTAssertEqual(s.visits.last?.bust, true)
        XCTAssertEqual(s.visits.last?.remainingAfter, 141)
        s.acknowledge()
        XCTAssertNil(s.announcement)
        XCTAssertEqual(s.bust?.restored, 141, "the red hero stays until the next key")
        s.digit("6")
        XCTAssertNil(s.bust, "the next key clears the bust display")
    }

    func testABustAwayFromAFinishNamesItsReason() throws {
        let s = try session()
        s.quick(180); s.quick(60)         // home 321
        s.quick(140); s.quick(60)         // home 181
        s.quick(180)                      // 181 - 180 = 1 → REMAINDER_ONE; 181 is not a checkout so no question
        XCTAssertNil(s.prompt)
        XCTAssertEqual(s.announcement, .bust(seat: .home, restored: 181, reason: "That leaves 1.", next: .away))
        XCTAssertEqual(s.remaining(.home), 181)
    }

    // MARK: durability and replay

    func testTheSessionNeverDisagreesWithTheJournal() throws {
        let s = try session()
        bringHomeToAFinish(s)
        s.quick(100); s.answer(1)         // home 41, one dart at a double
        s.quick(100)                      // away 281
        s.digit("4"); s.digit("1"); s.enter(); s.answer(2); s.answer(1)   // home finishes 41 in two darts
        let replayed = try journal.replayVisits(s.record.id)
        XCTAssertEqual(replayed.visits, s.visits)
        XCTAssertEqual(replayed.state.remaining, s.state.remaining)
        XCTAssertEqual(replayed.state.thrower, s.state.thrower)
        XCTAssertEqual(replayed.state.currentLeg, s.state.currentLeg)
        XCTAssertEqual(replayed.state.legsWonTotal, s.state.legsWonTotal)
    }

    func testReopeningResumesWhereItLeftOff() throws {
        let s = try session()
        bringHomeToAFinish(s)
        let reopened = try MatchSession.open(s.record.id, in: journal)
        XCTAssertEqual(reopened.remaining(.home), 141)
        XCTAssertEqual(reopened.remaining(.away), 381)
        XCTAssertEqual(reopened.thrower, .home)
        XCTAssertEqual(reopened.visits, s.visits)
        XCTAssertTrue(reopened.throwerOnAFinish)
    }

    func testAMatchCompletesAndTheKeypadIsRefused() throws {
        let s = try session(legs: 1)      // best of 1: first leg wins
        bringHomeToAFinish(s)
        s.digit("1"); s.digit("4"); s.digit("1"); s.enter(); s.answer(3); s.answer(1)
        XCTAssertTrue(s.isComplete)
        XCTAssertEqual(s.winner, .home)
        XCTAssertNil(s.thrower)
        s.quick(60)
        XCTAssertEqual(s.visits.count, 5, "nothing more is recorded after the match")
    }

    // MARK: statistics presentation

    /// The confidence is named on every expectation here, not left to the default. It was the
    /// default that made this test weaker than it looked: `StatLine` gained the field for PD-015 and
    /// every literal below silently claimed `.exact`, including the one whose value is a range.
    func testStatisticsAreHonestAboutTheirBasis() {
        XCTAssertEqual(StatPresentation.line("3-dart average", .exact(89.44, n: 12), kind: .average),
                       StatLine(label: "3-dart average", value: "89.4", note: nil, confidence: .exact))
        XCTAssertEqual(StatPresentation.line("Checkout %", .bounded(lower: 30, upper: 50, n: 4, note: "Two attempts were not recorded."), kind: .percent),
                       StatLine(label: "Checkout %", value: "30%–50%", note: "Two attempts were not recorded.",
                                confidence: .range),
                       "a range is drawn as a range, not as a fact that happens to have a dash in it")
        XCTAssertEqual(StatPresentation.line("180s", .exact(3, n: 20), kind: .count),
                       StatLine(label: "180s", value: "3", note: nil, confidence: .exact))
        let disclosed = Stat(basis: .exact, value: 95.0, sampleSize: 2, note: "1 leg(s) ended before nine darts and are excluded.")
        XCTAssertEqual(StatPresentation.line("First 9", disclosed, kind: .average).note,
                       "1 leg(s) ended before nine darts and are excluded.", "an exact figure keeps its disclosure")
        let unavailable = StatPresentation.line("Checkout %", .unavailable("No darts at a double were recorded for this player."), kind: .percent)
        XCTAssertEqual(unavailable.value, "—")
        XCTAssertEqual(unavailable.note, "No darts at a double were recorded for this player.")
        XCTAssertEqual(unavailable.confidence, .unavailable, "and it reaches the view saying so")
        // The drawn form the view actually receives. The basis used to stop at StatLine, which is
        // why all three were drawn identically until PD-015.
        XCTAssertEqual(unavailable.item.confidence, .unavailable)
        XCTAssertNotNil(unavailable.item.note, "a dash always arrives with its reason")
    }

    func testTheResultFiguresComeFromTheReplayedVisits() throws {
        let s = try session(legs: 1)
        bringHomeToAFinish(s)                                             // 180, 180
        s.digit("1"); s.digit("4"); s.digit("1"); s.enter(); s.answer(3); s.answer(1)
        let home = s.statistics(for: .home)
        XCTAssertEqual(home.map(\.label), ["3-dart average", "First 9", "Checkout %", "180s", "Highest checkout", "140+"])
        XCTAssertEqual(home[0].value, "167.0", "501 in nine darts")
        XCTAssertEqual(home[3].value, "2")
        XCTAssertEqual(home[4].value, "141")
        XCTAssertEqual(home[5].value, "3")
        let away = s.statistics(for: .away)
        XCTAssertEqual(away[0].value, "60.0")
    }

    // MARK: undo (PD-004)

    func testTheUndoKeyClearsATypedEntryFirst() throws {
        let s = try session()
        s.digit("6")
        s.undoKey()
        XCTAssertEqual(s.entry, "")
        XCTAssertNil(s.retraction)
    }

    func testTheUndoKeyWithNothingTypedProposesStrikingTheLastVisit() throws {
        let s = try session()
        s.quick(60)
        s.undoKey()
        XCTAssertEqual(s.retraction, MatchSession.RetractionProposal(seat: .home, visitTotal: 60, restoresTo: 501))
        s.confirmRetraction()
        XCTAssertNil(s.retraction)
        XCTAssertEqual(s.remaining(.home), 501)
        XCTAssertEqual(s.thrower, .home)
        XCTAssertTrue(s.visits.isEmpty)
        XCTAssertEqual(s.notice, MatchSession.Notice(text: "Undone: Jenson's 60. Jenson to throw.", tone: .neutral))
        XCTAssertEqual(try journal.entries(for: s.record.id).count, 2, "the visit and its retraction both stand in the record")
    }

    func testUndoWithNoVisitsSaysSo() throws {
        let s = try session()
        s.undoKey()
        XCTAssertNil(s.retraction)
        XCTAssertEqual(s.notice?.text, "Nothing to undo.")
    }

    func testKeepingTheVisitChangesNothing() throws {
        let s = try session()
        s.quick(60)
        s.proposeRetraction()
        s.cancelRetraction()
        XCTAssertNil(s.retraction)
        XCTAssertEqual(s.remaining(.home), 441)
        XCTAssertEqual(try journal.entries(for: s.record.id).count, 1)
    }

    /// The mis-key that ends a match is the one that most needs undoing.
    func testUndoReopensAFinishedMatch() throws {
        let s = try session(legs: 1)
        bringHomeToAFinish(s)
        s.digit("1"); s.digit("4"); s.digit("1"); s.enter(); s.answer(3); s.answer(1)
        XCTAssertTrue(s.isComplete)
        s.proposeRetraction()
        s.confirmRetraction()
        XCTAssertFalse(s.isComplete)
        XCTAssertEqual(s.remaining(.home), 141)
        XCTAssertEqual(s.thrower, .home)
        XCTAssertEqual(s.legsWon(.home), 0)
    }

    func testTheStatisticsNeverSeeAStruckVisit() throws {
        let s = try session()
        s.quick(180)
        s.proposeRetraction(); s.confirmRetraction()
        s.quick(60)
        XCTAssertEqual(s.statistics(for: .home)[3].value, "0", "the struck 180 is not a 180")
        XCTAssertEqual(s.statistics(for: .home)[0].value, "60.0")
    }

    func testTheSessionStillAgreesWithTheJournalAfterUndos() throws {
        let s = try session()
        bringHomeToAFinish(s)
        s.proposeRetraction(); s.confirmRetraction()      // strikes away's second 60
        XCTAssertEqual(s.thrower, .away)
        s.quick(45)
        let replayed = try journal.replayVisits(s.record.id)
        XCTAssertEqual(replayed.visits, s.visits)
        XCTAssertEqual(replayed.state.remaining, s.state.remaining)
        XCTAssertEqual(replayed.state.thrower, s.state.thrower)
    }

    func testNoKeyWorksWhileAnUndoIsProposed() throws {
        let s = try session()
        s.quick(60)
        s.proposeRetraction()
        s.quick(100); s.digit("5"); s.enter(); s.miss()
        XCTAssertEqual(s.visits.count, 1)
        XCTAssertEqual(s.entry, "")
        XCTAssertNotNil(s.retraction)
    }

    // MARK: announcements (PD-005)

    func testTheKeypadWaitsForTheAnnouncementToBeAcknowledged() throws {
        let s = try session()
        bringHomeToAFinish(s)
        s.quick(180); s.answer(0)                 // bust from 141
        XCTAssertNotNil(s.announcement)
        s.quick(60); s.digit("5"); s.enter(); s.miss(); s.undoKey()
        XCTAssertEqual(s.visits.count, 5, "nothing is scored while the card is up")
        XCTAssertNil(s.retraction)
        s.acknowledge()
        s.quick(60)
        XCTAssertEqual(s.visits.count, 6)
    }

    func testARefusalClearsOnTheNextKeyAndTakesNoAnnouncement() throws {
        let s = try session()
        s.digit("1"); s.digit("7"); s.digit("9"); s.enter()
        XCTAssertNotNil(s.notice)
        XCTAssertNil(s.announcement)
        s.clearEntry()
        XCTAssertNil(s.notice)
    }

    func testAMatchWinIsNotAnnouncedBecauseTheResultScreenIs() throws {
        let s = try session(legs: 1)
        bringHomeToAFinish(s)
        s.digit("1"); s.digit("4"); s.digit("1"); s.enter(); s.answer(3); s.answer(1)
        XCTAssertTrue(s.isComplete)
        XCTAssertNil(s.announcement)
    }

    // MARK: double in (PD-008)

    /// The founder asked for double-in because leagues and tournaments play it. The scorer records
    /// what counted — the score from the opening double onward — and zero when it did not come. The
    /// screen has to say so, because a player whose 60 does not go on the board and is not told why
    /// will believe the app is broken, and they will be right to.
    func testUnderDoubleInTheScreenSaysWhoIsNotInAndRefusesATotalThatCannotOpen() throws {
        let s = try MatchSession.start(
            NewMatch(homeName: "Jenson", awayName: "Alex", inRule: .double, legsTarget: 3), in: journal)
        XCTAssertEqual(s.inRuleLabel, "Double in", "and the format row says which match this is")
        XCTAssertTrue(s.throwerMustOpen, "nobody is in at the start")

        // 180 is three trebles, so it cannot be the counted total of a visit that opened.
        s.quick(180)
        XCTAssertNotNil(s.notice, "a refusal is shown, not swallowed")
        XCTAssertTrue(s.notice!.text.contains("starting on a double"), s.notice!.text)
        XCTAssertEqual(s.remaining(.home), 501, "and nothing was scored")
        XCTAssertEqual(s.thrower, .home, "nor did the turn move")

        // A visit that did not open is a real visit: it scores nothing, and the turn rotates.
        s.quick(0)
        XCTAssertEqual(s.remaining(.home), 501)
        XCTAssertEqual(s.thrower, .away)
        XCTAssertTrue(s.throwerMustOpen, "and the away player is not in either")

        // Opening scores from the double onward and the message goes away for that player.
        s.quick(60)
        XCTAssertEqual(s.remaining(.away), 441)
        XCTAssertEqual(s.thrower, .home)
        XCTAssertTrue(s.throwerMustOpen, "home still has to open")
        s.quick(40)
        XCTAssertEqual(s.remaining(.home), 461)
        XCTAssertFalse(s.throwerMustOpen, "away is in, so nothing is said about them")

        // Once in, 180 is fine — the same total the same player was refused three visits ago.
        s.quick(180)
        XCTAssertEqual(s.remaining(.away), 261)
        XCTAssertNil(s.notice)

        // A straight-in match says nothing about opening at all.
        let plain = try MatchSession.start(NewMatch(homeName: "A", awayName: "B"), in: journal)
        XCTAssertNil(plain.inRuleLabel)
        XCTAssertFalse(plain.throwerMustOpen)
        plain.quick(180)
        XCTAssertEqual(plain.remaining(.home), 321, "and 180 opens a straight-in leg like any other visit")
    }

    // MARK: - checkout routes (PD-013)

    /// The screen shows a route only when there is one, and it is the route the generator derived
    /// for exactly that number. Which route is best is a preference the founder decided to take a
    /// position on; that the route is a legal finish of this number is not, and both engines check
    /// that arithmetically for every entry in the table.
    func testTheRouteAppearsOnlyOnAFinishAndIsTheOneDerivedForThatNumber() throws {
        let s = try session()
        XCTAssertTrue(s.throwerRoute.isEmpty, "501 is not a finish, so nothing is suggested")

        bringHomeToAFinish(s)
        XCTAssertTrue(s.throwerOnAFinish)
        XCTAssertEqual(s.throwerRoute, ["T20", "T19", "D12"], "141 under double-out")
        XCTAssertEqual(s.throwerRoute, RuleTables.route(141, .double))
    }

    /// The route follows the match's OWN out-rule, not a fixed one. This is the same failure the
    /// statistics had once — replayed under a hardcoded 501/double-out while the scoreboard used the
    /// stored format — so it is held here rather than assumed.
    func testTheRouteFollowsTheMatchsOwnOutRule() throws {
        let straight = try MatchSession.start(
            NewMatch(homeName: "A", awayName: "B", outRule: .straight), in: journal)
        straight.quick(180); straight.quick(60)
        straight.quick(180); straight.quick(60)
        XCTAssertEqual(straight.remaining(.home), 141)
        XCTAssertEqual(straight.thrower, .home)
        XCTAssertEqual(straight.throwerRoute, RuleTables.route(141, .straight))

        // And the parameter genuinely matters: the two rules answer differently for a number a
        // single dart can finish outright.
        XCTAssertEqual(RuleTables.route(20, .double), ["D10"], "double-out must finish on a double")
        XCTAssertEqual(RuleTables.route(20, .straight), ["20"], "straight-out is thrown at twenty")
    }


    // MARK: - attestation (PD-011)

    /// Brings a best-of-one to a finished state: home takes 141 out and the match is over.
    private func finished() throws -> MatchSession {
        let s = try session(legs: 1)
        bringHomeToAFinish(s)
        s.digit("1"); s.digit("4"); s.digit("1"); s.enter(); s.answer(3); s.answer(1)
        XCTAssertTrue(s.isComplete)
        return s
    }

    /// A finished match is self-reported until both players say otherwise, on the phone, by name.
    ///
    /// Both are asked rather than one, because on a single phone nothing records who was keeping
    /// score — and a confirmation from whoever happened to be holding it is one person's word twice.
    func testAResultIsSelfReportedUntilBothPlayersHaveSaidSo() throws {
        let s = try finished()
        XCTAssertEqual(s.verification, .selfReported)
        XCTAssertEqual(s.awaitingAttestation, [.home, .away])

        s.attest(.home, agrees: true)
        XCTAssertEqual(s.verification, .selfReported, "one player agreeing is not two")
        XCTAssertEqual(s.awaitingAttestation, [.away])

        s.attest(.away, agrees: true)
        XCTAssertEqual(s.verification, .participantConfirmed)
        XCTAssertTrue(s.awaitingAttestation.isEmpty)
    }

    /// A refusal marks; it never removes. And it outranks the other player's agreement, because a
    /// result one competitor does not accept is disputed whatever the other said.
    func testARefusalMarksTheResultAndDeletesNothing() throws {
        let s = try finished()
        let visitsBefore = try journal.entries(for: s.record.id).filter { $0.kind == .visit }.count

        s.attest(.home, agrees: true)
        s.attest(.away, agrees: false)
        XCTAssertEqual(s.verification, .disputed)
        XCTAssertEqual(try journal.entries(for: s.record.id).filter { $0.kind == .visit }.count, visitsBefore,
                       "a disagreement removes no evidence")
        XCTAssertEqual(s.legsWon(.home), 1, "and the result still stands as recorded")
    }

    /// Undoing a visit after the result was agreed is the case this exists for: what was confirmed
    /// is no longer what is recorded, so the label falls back rather than claiming an agreement
    /// nobody gave to this version of it.
    func testAnUndoAfterAnAgreementDropsTheLabelBackRatherThanKeepingIt() throws {
        let s = try finished()
        s.attest(.home, agrees: true)
        s.attest(.away, agrees: true)
        XCTAssertEqual(s.verification, .participantConfirmed)

        s.proposeRetraction()
        s.confirmRetraction()
        XCTAssertEqual(s.verification, .selfReported, "the agreement no longer describes this result")
        XCTAssertTrue(s.standing.stale)
        XCTAssertEqual(s.standing.confirmed, [.home, .away], "and it is still on the record, not deleted")
    }

    // MARK: - a person's figures across matches (ADR-016)

    /// The profile's numbers come from the same audited honesty layer a match's do, over the
    /// person's pooled visits — not a second arithmetic written for profiles.
    func testAPersonsFiguresAreComputedFromTheirOwnMatches() throws {
        for _ in 0..<2 {
            let m = try journal.createMatch(NewMatch(homeName: "Jenson", awayName: "Alex", startingScore: 101,
                                                     legsTarget: 1, homePlayerId: "p-jenson", awayPlayerId: "p-alex"))
            try journal.append(.visit(Seat.home.playerId, 60), to: m.id)
            try journal.append(.visit(Seat.away.playerId, 20), to: m.id)
            try journal.append(.visit(Seat.home.playerId, 41, dartsUsed: 2, dartsAtDouble: 1), to: m.id)
        }

        let figures = try PersonSummary.figures(for: "p-jenson", in: journal)
        let by = Dictionary(uniqueKeysWithValues: figures.map { ($0.label, $0) })
        XCTAssertEqual(by["Matches"]?.value, "2")
        XCTAssertEqual(by["Legs won"]?.value, "2")
        // 101 in five darts, twice: 202 scored off 10 darts = 60.6 per three.
        XCTAssertEqual(by["3-dart average"]?.value, "60.6")
        XCTAssertEqual(by["Highest checkout"]?.value, "41")
        // 101 is itself a finish (T17 Bull), so the opening visit of each match began on one without
        // recording its darts at a double — the honesty layer answers with a range and says why,
        // rather than a point value it cannot support. Pooling does not change that.
        XCTAssertTrue(by["Checkout %"]?.value.contains("–") == true,
                      "expected a range, got \(by["Checkout %"]?.value ?? "")")
        XCTAssertNotNil(by["Checkout %"]?.note)
        XCTAssertNil(by["Matches"]?.note, "nothing unreadable, so nothing to say about it")
    }

    /// Checkout percentage is refused across mixed out-rules rather than pooled into a number that
    /// is not a checkout percentage of anything: whether a visit began on a finish depends on the
    /// rule, and this person played under two.
    func testCheckoutPercentageIsRefusedAcrossMixedOutRules() throws {
        let a = try journal.createMatch(NewMatch(homeName: "Jenson", awayName: "Alex", startingScore: 101,
                                                 outRule: .double, legsTarget: 1, homePlayerId: "p-jenson"))
        try journal.append(.visit(Seat.home.playerId, 60), to: a.id)
        let b = try journal.createMatch(NewMatch(homeName: "Jenson", awayName: "Alex", startingScore: 101,
                                                 outRule: .straight, legsTarget: 1, homePlayerId: "p-jenson"))
        try journal.append(.visit(Seat.home.playerId, 60), to: b.id)

        let figures = try PersonSummary.figures(for: "p-jenson", in: journal)
        let checkout = figures.first { $0.label == "Checkout %" }
        XCTAssertEqual(checkout?.value, "—")
        XCTAssertTrue(checkout?.note?.contains("out-rules") == true, "and it says why: \(checkout?.note ?? "")")
        // The rule-independent figure is still given, because it is still true.
        XCTAssertEqual(figures.first { $0.label == "3-dart average" }?.value, "60.0")
    }

    func testSomebodyWithNoMatchesGetsDashesAndAReasonRatherThanZeroes() throws {
        let figures = try PersonSummary.figures(for: "p-nobody", in: journal)
        XCTAssertEqual(figures.first { $0.label == "Matches" }?.value, "0")
        XCTAssertEqual(figures.first { $0.label == "3-dart average" }?.value, "—")
        XCTAssertNotNil(figures.first { $0.label == "3-dart average" }?.note)
    }

    // MARK: - ending a match short (PD-016)

    /// Not one tap. An ending is final, so the offer and the confirmation are separate steps and
    /// `Back` from the confirmation returns to the choice rather than out of the flow — otherwise
    /// the destructive button is the only way forward from there.
    func testEndingIsTwoStepsAndBackReturnsToTheChoice() throws {
        let s = try session()
        s.quick(60)
        XCTAssertNil(s.endFlow)

        s.offerToEnd()
        XCTAssertEqual(s.endFlow, .choosing)
        s.proposeEnding(.retired(by: .home))
        XCTAssertEqual(s.endFlow, .confirming(.retired(by: .home)))
        XCTAssertNil(s.ending, "proposing writes nothing")

        s.cancelEnding()
        XCTAssertEqual(s.endFlow, .choosing, "back goes to the choice, not out")
        s.cancelEnding()
        XCTAssertNil(s.endFlow)
        XCTAssertNil(s.ending, "and still nothing was written")
    }

    /// Offered only while there is something to end. A match nobody has thrown a dart in is left,
    /// not retired: there is no result to protect and no darts to keep.
    func testEndingShortIsNotOfferedBeforeADartOrAfterTheMatchIsOver() throws {
        let s = try session(legs: 1)
        XCTAssertFalse(s.mayEndShort, "no darts thrown yet")
        s.offerToEnd()
        XCTAssertNil(s.endFlow, "and the offer does not open")

        s.quick(60)
        XCTAssertTrue(s.mayEndShort)

        s.offerToEnd()
        s.proposeEnding(.abandoned)
        s.confirmEnding()
        XCTAssertEqual(s.ending, .abandoned)
        XCTAssertFalse(s.mayEndShort, "an ended match is not ended again")
    }

    /// A retirement produces a winner and so has a result to stand behind; an abandonment produces
    /// none, so there is nothing to confirm and nothing to dispute.
    func testARetirementHasAResultToConfirmAndAnAbandonmentDoesNot() throws {
        let retire = try session()
        retire.quick(60)
        retire.offerToEnd(); retire.proposeEnding(.retired(by: .away)); retire.confirmEnding()
        XCTAssertTrue(retire.isComplete)
        XCTAssertFalse(retire.wasPlayedOut, "it was ended, not played out")
        XCTAssertEqual(retire.winner, .home, "the seat that did not stop")
        XCTAssertTrue(retire.hasResult)
        XCTAssertEqual(retire.awaitingAttestation, Seat.allCases, "both are still asked")

        let abandon = try session()
        abandon.quick(60)
        abandon.offerToEnd(); abandon.proposeEnding(.abandoned); abandon.confirmEnding()
        XCTAssertTrue(abandon.isComplete)
        XCTAssertNil(abandon.winner)
        XCTAssertFalse(abandon.hasResult)
        XCTAssertEqual(abandon.awaitingAttestation, [], "there is no result to attest to")
    }

    /// The headline an abandoned match must NOT show. `winner ?? "In progress"` collapses "nobody
    /// won" into "still playing", and a match that is over reading as live is the wrong answer in
    /// the one place a player looks for the answer.
    func testAnAbandonedMatchReadsAsNoResultRatherThanInProgress() throws {
        let s = try session()
        s.quick(60)
        XCTAssertEqual(s.resultHeadline, "In progress")
        XCTAssertNil(s.resultDetail)

        s.offerToEnd(); s.proposeEnding(.abandoned); s.confirmEnding()
        XCTAssertEqual(s.resultHeadline, "No result")
        XCTAssertEqual(s.resultDetail?.isEmpty, false, "and it says what happened")
    }

    /// The two sentences that are the whole difference between the endings. A screen that showed
    /// them the wrong way round would record the opposite of what the players said happened.
    func testTheConsequenceSaysWhoWinsAndWhoDoesNot() throws {
        let s = try session()
        let retiring = s.endingConsequence(.retired(by: .home))
        XCTAssertTrue(retiring.contains("Jenson stops"), retiring)
        XCTAssertTrue(retiring.contains("Alex wins"), retiring)

        let abandoning = s.endingConsequence(.abandoned)
        XCTAssertTrue(abandoning.contains("Nobody wins"), abandoning)
        // The property, not the wording: an abandonment names nobody, because naming somebody in
        // the sentence that ends a match with no winner is how a win gets handed out by accident.
        XCTAssertFalse(abandoning.contains("Jenson"), abandoning)
        XCTAssertFalse(abandoning.contains("Alex"), abandoning)
    }

    /// The darts are real either way, so a person's figures include them. Only the result differs.
    func testAnEndedMatchKeepsTheDartsThrownInIt() throws {
        let s = try session()
        s.quick(180); s.quick(60)
        let before = s.visits.count
        s.offerToEnd(); s.proposeEnding(.abandoned); s.confirmEnding()

        let reopened = try MatchSession.open(s.record.id, in: journal)
        XCTAssertEqual(reopened.visits.count, before, "an ending strikes nothing")
        XCTAssertEqual(reopened.ending, .abandoned, "and is read back from the journal, not assumed")
        XCTAssertEqual(reopened.remaining(.home), 321)
    }

    // MARK: - the form figure (PD-018)

    /// One 501 leg won in nine darts, written straight to the journal.
    ///
    /// Through the journal rather than through the session on purpose: these tests are about what a
    /// PROFILE says, and driving the keypad's prompt-and-announcement state machine four times over
    /// would test that instead, and break the moment a starting score happened to be a checkout.
    private func completeALeg(in matchId: MatchId) throws {
        try journal.append(.visit(Seat.home.playerId, 180), to: matchId)
        try journal.append(.visit(Seat.away.playerId, 60), to: matchId)
        try journal.append(.visit(Seat.home.playerId, 180), to: matchId)
        try journal.append(.visit(Seat.away.playerId, 60), to: matchId)
        try journal.append(.visit(Seat.home.playerId, 141, dartsUsed: 3, dartsAtDouble: 1), to: matchId)
    }

    private func oneLegMatch(for personId: String) throws -> MatchRecord {
        try journal.createMatch(NewMatch(homeName: "Jenson", awayName: "Alex",
                                         legsMode: .firstTo, legsTarget: 1, homePlayerId: personId))
    }

    /// The label is the guarantee. OD-001 leaves the rating model open because no model here has
    /// been validated, and the difference between "what you have been scoring" and "how good you
    /// are" is the whole reason this is allowed to ship while that stays open.
    func testTheFormFigureIsNeverCalledARating() throws {
        let me = "person-form"
        for _ in 0 ..< 4 { try completeALeg(in: try oneLegMatch(for: me).id) }

        let figures = try PersonSummary.figures(for: me, in: journal)
        let form = figures.first { $0.label == "Recent form" }
        XCTAssertNotNil(form, "the profile shows it")
        XCTAssertFalse(figures.contains { $0.label.lowercased().contains("rating") },
                       "nothing on a profile is called a rating while OD-001 is open")
        XCTAssertEqual(form?.note?.contains("Not a rating."), true, form?.note ?? "no note")
        XCTAssertEqual(form?.note?.contains("last 4 completed legs"), true, form?.note ?? "no note")
        XCTAssertEqual(form?.confidence, .exact)
        XCTAssertEqual(form?.value, "167.0", "501 in nine darts, four times over")
    }

    /// Below the floor it is unavailable and says how many more legs are needed — never a thin
    /// number presented as form, and never a zero.
    func testFormIsUnavailableUntilThereAreEnoughLegs() throws {
        let me = "person-thin"
        try completeALeg(in: try oneLegMatch(for: me).id)

        let form = try PersonSummary.figures(for: me, in: journal).first { $0.label == "Recent form" }
        XCTAssertEqual(form?.value, "—", "a dash, never a zero")
        XCTAssertEqual(form?.confidence, .unavailable, "and drawn as the fact it is not (PD-015)")
        XCTAssertEqual(form?.note?.contains("2 more"), true, form?.note ?? "no note")
    }

    /// PD-016 again, from the profile's side: a match that ended short is counted and named, because
    /// "played 12" meaning "nine played out and three walked away from" is a different claim.
    func testTheMatchCountNamesTheOnesThatEndedShort() throws {
        let me = "person-ended"
        try completeALeg(in: try oneLegMatch(for: me).id)

        for ending in [Ending.retired(by: .away), .abandoned] {
            let m = try journal.createMatch(NewMatch(homeName: "Jenson", awayName: "Alex", homePlayerId: me))
            try journal.append(.visit(Seat.home.playerId, 60), to: m.id)
            try journal.end(m.id, as: ending)
        }

        let matches = try PersonSummary.figures(for: me, in: journal).first { $0.label == "Matches" }
        XCTAssertEqual(matches?.value, "3")
        XCTAssertEqual(matches?.note?.contains("1 ended in a retirement"), true, matches?.note ?? "no note")
        XCTAssertEqual(matches?.note?.contains("1 abandoned with no result"), true, matches?.note ?? "no note")
    }

    // MARK: - per-dart entry

    func testThreeDartsCommitAsOneVisitWithTheSameTotalATypedTotalWouldHave() throws {
        let s = try session()
        s.dart(.treble(20)!); s.dart(.treble(20)!); s.dart(.treble(20)!)
        XCTAssertEqual(s.darts.total, 180)
        XCTAssertEqual(s.darts.written, "T20 T20 T20")
        s.enterDarts()
        XCTAssertEqual(s.remaining(.home), 321)
        XCTAssertEqual(s.visits.count, 1)
        XCTAssertEqual(s.visits[0].visitTotal, 180)
        XCTAssertTrue(s.darts.isEmpty, "the entry is spent")
        XCTAssertEqual(s.thrower, .away)
    }

    func testAFourthDartIsRefused() throws {
        let s = try session()
        for _ in 0..<4 { s.dart(.single(1)!) }
        XCTAssertEqual(s.darts.darts.count, 3)
    }

    func testACheckoutEnteredAsDartsIsNotAskedPDZeroZeroOnesQuestions() throws {
        // **What per-dart entry is for.** Typed as a total, a 141 finish stops the player twice —
        // how many darts, and how many at a double — mid-celebration. Entered as darts it answers
        // both from the evidence and asks nothing.
        let s = try session()
        bringHomeToAFinish(s)
        s.dart(.treble(20)!); s.dart(.treble(19)!); s.dart(.double(12)!)
        XCTAssertTrue(s.dartsMayBeEntered)
        s.enterDarts()
        XCTAssertNil(s.prompt, "the player was not stopped and asked what they had just told the app")
        XCTAssertEqual(s.visits.count, 5)
        XCTAssertEqual(s.visits[4].dartsUsed, 3)
        XCTAssertEqual(s.visits[4].dartsAtDouble, 1, "one dart at a double: 141, 81 and then 24")
        XCTAssertTrue(s.visits[4].wonLeg)
    }

    func testAThreeDartCheckoutOnTheLastDartRecordsOneDartAtADouble() throws {
        // The same finish typed as a total answers "3" and "1" only if the player remembers to; the
        // point of the evidence path is that the two answers now agree by construction.
        let s = try session()
        bringHomeToAFinish(s)
        s.quick(141)
        XCTAssertNotNil(s.prompt, "typed, it still asks")
        s.answer(3)
        s.answer(1)
        XCTAssertEqual(s.visits.last?.dartsUsed, 3)
        XCTAssertEqual(s.visits.last?.dartsAtDouble, 1)
    }

    func testAOneDartCheckoutCarriesOneDart() throws {
        let s = try session()
        s.quick(180); s.quick(60)
        s.quick(180); s.quick(60)
        s.quick(101)                       // home 141 → 40
        XCTAssertNotNil(s.prompt)
        s.answer(0)                        // darts at a double, not a finish
        XCTAssertEqual(s.remaining(.home), 40)
        s.quick(60)                        // away throws
        XCTAssertEqual(s.thrower, .home)
        s.dart(.double(20)!)
        XCTAssertTrue(s.dartsMayBeEntered, "a finish may be entered before the hand is spent")
        s.enterDarts()
        XCTAssertNil(s.prompt)
        XCTAssertEqual(s.visits.last?.dartsUsed, 1)
        XCTAssertEqual(s.visits.last?.dartsAtDouble, 1)
        XCTAssertTrue(s.visits.last?.wonLeg ?? false)
    }

    func testAPartEnteredVisitCannotBeCommitted() throws {
        // Two darts that neither finish nor bust is a visit the engine refuses, so Enter is out of
        // the light rather than a dead end the player has to discover.
        let s = try session()
        s.dart(.treble(20)!); s.dart(.treble(20)!)
        XCTAssertFalse(s.dartsMayBeEntered)
        s.enterDarts()
        XCTAssertEqual(s.visits.count, 0, "nothing was written")
        XCTAssertEqual(s.darts.darts.count, 2, "and nothing was lost")
        s.dart(.miss)
        XCTAssertTrue(s.dartsMayBeEntered)
        s.enterDarts()
        XCTAssertEqual(s.visits.count, 1)
        XCTAssertEqual(s.visits[0].visitTotal, 120)
        XCTAssertEqual(s.visits[0].dartsUsed, 3)
    }

    func testABustAfterOneDartMayBeEnteredAndRecordsNoDartCount() throws {
        // On 20 a double 20 goes below zero. The player stops; the record does not claim one dart,
        // because the engine's convention is that a bust consumed the whole hand.
        let s = try session()
        s.quick(180); s.quick(60)
        s.quick(180); s.quick(60)
        s.quick(121)                       // home 141 → 20
        s.answer(0)
        s.quick(60)
        XCTAssertEqual(s.remaining(.home), 20)
        s.dart(.double(20)!)
        XCTAssertTrue(s.dartsMayBeEntered, "a bust settles the visit; there is nothing more to throw")
        s.enterDarts()
        XCTAssertEqual(s.remaining(.home), 20, "the score is restored")
        XCTAssertTrue(s.visits.last?.bust ?? false)
        XCTAssertNil(s.visits.last?.dartsUsed)
    }

    func testUndoTakesBackOneDartBeforeItTakesBackTheRecord() throws {
        let s = try session()
        s.dart(.treble(20)!); s.dart(.single(5)!)
        s.undoKey()
        XCTAssertEqual(s.darts.written, "T20", "one dart, not the hand")
        XCTAssertNil(s.retraction)
        s.undoKey()
        XCTAssertTrue(s.darts.isEmpty)
        XCTAssertNil(s.retraction, "still nothing on the record to strike")
        s.undoKey()
        XCTAssertNil(s.retraction, "and no visit yet, so nothing is proposed")
    }

    func testTakingBackADartTakesBackEverythingAfterIt() throws {
        // What a player means when they point at the middle dart: that one was wrong, and the one
        // after it was entered on top of a wrong number.
        let s = try session()
        s.dart(.treble(20)!); s.dart(.double(16)!); s.dart(.single(5)!)
        s.takeBackDarts(from: 1)
        XCTAssertEqual(s.darts.written, "T20")
        s.takeBackDarts(from: 5)
        XCTAssertEqual(s.darts.written, "T20", "an index that is not there changes nothing")
        s.takeBackDarts(from: 0)
        XCTAssertTrue(s.darts.isEmpty)
    }

    func testSwitchingNotationMidVisitLeavesNothingBehind() throws {
        // The screen calls `clearEntry` when the keypad changes, because three darts have a total
        // but a total does not have three darts.
        let s = try session()
        s.dart(.treble(20)!)
        s.digit("6"); s.digit("0")
        s.clearEntry()
        XCTAssertTrue(s.darts.isEmpty)
        XCTAssertEqual(s.entry, "")
    }

    func testAVisitEnteredAsDartsLandsOnTheLedgerLikeAnyOther() throws {
        let s = try session()
        s.dart(.treble(20)!); s.dart(.treble(20)!); s.dart(.treble(20)!)
        s.enterDarts()
        XCTAssertEqual(s.ledger.count, 1)
        XCTAssertEqual(s.ledger[0].visitTotal, 180)
        XCTAssertEqual(s.ledger[0].remainingAfter, 321)
        XCTAssertFalse(s.ledger[0].struck)
    }

}
