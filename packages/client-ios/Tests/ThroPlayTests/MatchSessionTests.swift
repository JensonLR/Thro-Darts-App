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

    func testStatisticsAreHonestAboutTheirBasis() {
        XCTAssertEqual(StatPresentation.line("3-dart average", .exact(89.44, n: 12), kind: .average),
                       StatLine(label: "3-dart average", value: "89.4", note: nil))
        XCTAssertEqual(StatPresentation.line("Checkout %", .bounded(lower: 30, upper: 50, n: 4, note: "Two attempts were not recorded."), kind: .percent),
                       StatLine(label: "Checkout %", value: "30%–50%", note: "Two attempts were not recorded."))
        XCTAssertEqual(StatPresentation.line("180s", .exact(3, n: 20), kind: .count),
                       StatLine(label: "180s", value: "3", note: nil))
        let disclosed = Stat(basis: .exact, value: 95.0, sampleSize: 2, note: "1 leg(s) ended before nine darts and are excluded.")
        XCTAssertEqual(StatPresentation.line("First 9", disclosed, kind: .average).note,
                       "1 leg(s) ended before nine darts and are excluded.", "an exact figure keeps its disclosure")
        let unavailable = StatPresentation.line("Checkout %", .unavailable("No darts at a double were recorded for this player."), kind: .percent)
        XCTAssertEqual(unavailable.value, "—")
        XCTAssertEqual(unavailable.note, "No darts at a double were recorded for this player.")
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
}
