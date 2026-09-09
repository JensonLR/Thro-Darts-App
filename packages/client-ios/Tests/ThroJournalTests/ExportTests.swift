import XCTest
import ThroEngine
@testable import ThroJournal

/// PD-017: a lost phone must not lose a season.
///
/// The founder chose both answers — the ordinary device backup, which needs no discipline, and an
/// export the player controls, which is the one that makes the record theirs. These hold the second,
/// and the parts of the first that are a decision rather than a default.
final class ExportTests: XCTestCase {

    private var dir: URL!
    private var journal: Journal!

    override func setUpWithError() throws {
        try super.setUpWithError()
        dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("thro-export-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        journal = try Journal(path: dir.appendingPathComponent("journal.sqlite").path,
                              deviceId: DeviceId("export-tests"))
    }

    override func tearDown() {
        journal = nil
        try? FileManager.default.removeItem(at: dir)
        super.tearDown()
    }

    /// What is on disk underneath Foundation, in words.
    ///
    /// **Every other statement in these backup tests goes through `URL`, and `URL` is the thing
    /// under suspicion.** `isExcludedFromBackup` is backed by an extended attribute; `getxattr`
    /// reads that attribute and consults no cache on a URL, in Foundation, or in any daemon. It is
    /// here only to be quoted in failure messages: three rounds were spent on this defect arguing
    /// about what the file system said, and none of them asked the file system.
    /// Sets or clears the exclusion **on the file**, for use as a fixture.
    ///
    /// **Not `URL.setResourceValues`, and that is the whole finding of this file.** A `URL` caches
    /// the resource values it has seen and the cache does not notice the file changing underneath
    /// it, so asking such a URL to set the value it already believes is there skips the write and
    /// reports success. Round 19 of the loop below caught it: `excluded` set through a URL written
    /// through eighteen times, the attribute absent afterwards, nothing raised. A test whose
    /// fixture is unreliable cannot say anything about the code under it.
    @discardableResult
    private func setExclusion(_ on: Bool, at path: String) -> Bool {
        let key = "com.apple.metadata:com_apple_backup_excludeItem"
        if on {
            var one: UInt8 = 1
            return setxattr(path, key, &one, 1, 0, 0) == 0
        }
        return removexattr(path, key, 0) == 0 || errno == ENOATTR
    }

    /// Whether the attribute is on the file at all, and whether it is the single byte this
    /// fixture writes.
    ///
    /// **Content-independent on purpose.** `BackupPolicy.read` decides by the attribute's contents,
    /// so a test helper that classified contents would be a second copy of the thing under test and
    /// every assertion built on it would be a tautology. This asks two questions the reader does not
    /// ask: is it there, and is it ours.
    private func exclusionShape(_ path: String) -> (present: Bool, ours: Bool) {
        let key = "com.apple.metadata:com_apple_backup_excludeItem"
        let size = getxattr(path, key, nil, 0, 0, 0)
        guard size >= 0 else { return (false, false) }
        var bytes = [UInt8](repeating: 0, count: size)
        guard getxattr(path, key, &bytes, bytes.count, 0, 0) >= 0 else { return (true, false) }
        return (true, bytes == [1])
    }

    private func exclusionOnDisk(_ path: String) -> String {
        let key = "com.apple.metadata:com_apple_backup_excludeItem"
        let size = getxattr(path, key, nil, 0, 0, 0)
        guard size >= 0 else { return "no such attribute (errno \(errno))" }
        var bytes = [UInt8](repeating: 0, count: size)
        guard getxattr(path, key, &bytes, bytes.count, 0, 0) >= 0 else {
            return "attribute present, unreadable (errno \(errno))"
        }
        let text = String(decoding: bytes, as: UTF8.self)
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespaces)
        return "attribute present, \(size) bytes: \(text.prefix(120))"
    }

    @discardableResult
    private func aMatch(person: String? = nil) throws -> MatchRecord {
        let m = try journal.createMatch(NewMatch(homeName: "Jenson", awayName: "Alex",
                                                 homePlayerId: person))
        try journal.append(.visit(Seat.home.playerId, 180), to: m.id)
        try journal.append(.visit(Seat.away.playerId, 60), to: m.id)
        return m
    }

    // MARK: the export

    /// Everything, including the rows a tidier export would drop. The whole point of an append-only
    /// journal is that the corrections are in it, so an export without them is a neater record of a
    /// different match.
    func testTheExportCarriesEveryRowAsWrittenIncludingTheStruckOnes() throws {
        let m = try aMatch()
        try journal.retractLastVisit(in: m.id)
        try journal.attest(m.id, seat: .home, agrees: true)

        let doc = try Export.make(journal)
        XCTAssertEqual(doc.matches.count, 1)
        XCTAssertEqual(doc.journal.count, 4, "two visits, a retraction and a confirmation")
        XCTAssertEqual(Set(doc.journal.map(\.kind)), ["visit", "retraction", "confirmation"])
        XCTAssertEqual(doc.journal.map(\.deviceSeq), [1, 2, 3, 4], "in the order committed")
        XCTAssertNotNil(doc.journal.first { $0.kind == "retraction" }?.correctsSeq,
                        "and a retraction still says what it struck")
    }

    /// PD-016 travels with it: a file that recorded a retirement as an ordinary finish would hand
    /// somebody a win they were never given.
    func testAnEndingIsInTheFileAndSaysWhichKindItWas() throws {
        let retired = try aMatch()
        try journal.end(retired.id, as: .retired(by: .away))
        let abandoned = try aMatch()
        try journal.end(abandoned.id, as: .abandoned)
        let played = try aMatch()

        let doc = try Export.make(journal)
        func row(_ id: MatchId) throws -> ExportDocument.Match {
            try XCTUnwrap(doc.matches.first { $0.id == id.value })
        }
        XCTAssertEqual(try row(retired.id).ending, "retired-away")
        XCTAssertEqual(try row(abandoned.id).ending, "abandoned")
        XCTAssertNil(try row(played.id).ending, "a match played out claims no ending")
    }

    /// A file must survive the round trip byte for byte in meaning, or it is not a backup.
    func testAnExportReadsBackAsItself() throws {
        try aMatch(person: "person-1")
        let written = try Export.make(journal, people: [LocalPerson(id: "person-1", name: "Jenson")])
        let recovered = try Export.read(try Export.data(written))
        XCTAssertEqual(recovered, written)
        XCTAssertEqual(recovered.people.map(\.name), ["Jenson"])
    }

    /// The digest detects a file that changed between the phone and wherever it ended up. It proves
    /// nothing about who wrote the rows — the doc comment says so — but this is the part it does do,
    /// and a digest nobody checks is a digest that is not there.
    func testAnEditedFileIsRefusedRatherThanReadAsGenuine() throws {
        try aMatch()
        let data = try Export.data(try Export.make(journal))
        var text = String(decoding: data, as: UTF8.self)
        XCTAssertTrue(text.contains("\"visitTotal\" : 180"), "the visit this test is about to forge")
        text = text.replacingOccurrences(of: "\"visitTotal\" : 180", with: "\"visitTotal\" : 140")

        XCTAssertThrowsError(try Export.read(Data(text.utf8))) { error in
            guard case ExportError.digestMismatch = error else {
                return XCTFail("a forged file must be refused as forged, got \(error)")
            }
        }
    }

    /// The same lesson as the journal's `unknown` row kind: a reader that does not know a format
    /// refuses rather than half-reading it into something that looks right and is not.
    func testAFileFromALaterBuildIsRefusedRatherThanGuessedAt() throws {
        try aMatch()
        let data = try Export.data(try Export.make(journal))
        let bumped = String(decoding: data, as: UTF8.self)
            .replacingOccurrences(of: "\"format\" : 1", with: "\"format\" : 99")

        XCTAssertThrowsError(try Export.read(Data(bumped.utf8))) { error in
            XCTAssertEqual(error as? ExportError, .unknownFormat(99))
        }
        XCTAssertThrowsError(try Export.read(Data("not json".utf8))) { error in
            guard case ExportError.notAnExport = error else { return XCTFail("got \(error)") }
        }
    }

    /// Two exports of the same device state are the same file. Without this a player cannot tell
    /// whether anything changed between two copies, which is most of what a kept file is for.
    func testTheSameDeviceStateExportsToTheSameDigest() throws {
        try aMatch()
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let a = try Export.make(journal, at: now)
        let b = try Export.make(journal, at: now.addingTimeInterval(3600))
        XCTAssertEqual(a.digest, b.digest, "the header is not hashed, so the time is not")
        XCTAssertNotEqual(a.exportedAt, b.exportedAt)

        try aMatch()
        XCTAssertNotEqual(try Export.make(journal, at: now).digest, a.digest, "but the content is")
    }

    /// Images are not in the file. Naming what is missing is the difference between an incomplete
    /// export and a silently incomplete one.
    func testTheFileNamesTheAssetsItDoesNotCarry() throws {
        let doc = try Export.make(journal, assetsNotIncluded: ["asset-a", "asset-b"])
        XCTAssertEqual(doc.assetsNotIncluded, ["asset-a", "asset-b"])
    }

    /// There is deliberately no function that writes an export into a live journal. Merging two
    /// append-only journals with their own gapless sequences is the reconciliation ADR-006 specifies
    /// for sync, and sync is not built; an import that pretended to do it would produce a journal
    /// whose sequence lies. This asserts the absence, because an absence with a reason is a design
    /// decision and an absence without one is an oversight.
    func testReadingAnExportWritesNothingIntoTheJournal() throws {
        let m = try aMatch()
        let data = try Export.data(try Export.make(journal))
        let before = try journal.entries(for: m.id)

        _ = try Export.read(data)
        XCTAssertEqual(try journal.entries(for: m.id), before)
        XCTAssertEqual(try journal.matches().count, 1, "reading a file does not add matches")
    }

    // MARK: the backup flag

    /// A journal is the only copy of what was thrown, so it belongs in the device backup. Set
    /// explicitly and read back, for the same reason the durability pragmas are: a default that
    /// nothing states and nothing checks is a default that changes.
    func testTheDataFolderIsMarkedForBackupAndTheFlagIsReadBack() throws {
        XCTAssertEqual(BackupPolicy.include(dir), .included)
        XCTAssertEqual(BackupPolicy.read(dir), .included)
        XCTAssertTrue(BackupPolicy.sentence(.included).contains("included in its backup"))
    }

    /// And it notices when something has excluded it — which is the whole reason the flag is read
    /// rather than assumed, since the failure is silent and only shows up on a new phone.
    func testAnExcludedFolderIsReportedRatherThanAssumedSafe() throws {
        var excluded = dir!
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try excluded.setResourceValues(values)

        XCTAssertEqual(BackupPolicy.read(excluded), .excluded)
        XCTAssertFalse(BackupPolicy.read(excluded).isIncluded)
        XCTAssertTrue(BackupPolicy.sentence(.excluded).contains("NOT included"))
        XCTAssertTrue(BackupPolicy.sentence(.excluded).contains("Export"), "and says what to do about it")

        // And including it again puts it back, so the app can repair what it finds.
        //
        // **Through `including`, so a failed write and a lost write are told apart.** This line
        // failed on CI with `("excluded") is not equal to ("included")` and nothing else, and the
        // two stories behind that read identically from `include`: either `setResourceValues` threw
        // — swallowed, until now — or it returned success and the flag was still on disk.
        let repair = BackupPolicy.including(excluded)
        let disk = exclusionOnDisk(dir.path)
        XCTAssertNil(repair.wrote, "setting the flag threw: \(String(describing: repair.wrote)); "
                                 + "on disk: \(disk)")
        XCTAssertEqual(repair.state, .included,
                       "the write reported success and the flag is still set — on disk: \(disk)")
    }

    /// **The answer comes from the file, and five rounds went into making that true.**
    ///
    /// `URL` memoises resource values on the value itself, so the obvious implementation answered
    /// with what a URL had last been told rather than with what is on disk — and Settings told a
    /// player their matches were **not** in this phone's backup about a folder that was. Three
    /// attempts to clear that cache each removed one participant and each left this test
    /// intermittent: the same commit went green on one CI run and red on the next, and in one red
    /// run three reads of a single path within a millisecond disagreed with each other.
    ///
    /// `BackupPolicy` now reads the extended attribute the flag actually is, so there is no cache
    /// on a URL to go stale and nothing between the question and the file. The flag is still written
    /// through a `URL` here, deliberately, because Foundation's own writer is what the app used to
    /// rely on and cross-checking it against the raw attribute is stronger than trusting either
    /// alone — and because `BackupPolicy` misreading Foundation's property-list form is a defect
    /// that shipped here once already.
    ///
    /// The `url` is the one written through repeatedly, because a fresh `URL` has nothing cached and
    /// would have passed either way — which is why CI found the original defect only intermittently.
    ///
    /// **The Foundation half is now twenty rounds too, and this is the sixth round on this flag.**
    /// It was four straight-line assertions, and CI went red on the second of them on a commit that
    /// touched nothing near it — then green on the same commit on the other run of the same push.
    /// The loop lower down had already been rewritten for exactly that reason and this block had
    /// not been; it is now, on the same terms. What it demands of `BackupPolicy` did not go down:
    /// every round still asserts that the file decides, and the two claims that need the fixture to
    /// have held are counted with a floor of one rather than dropped.
    func testTheAnswerComesFromTheFileSystemAndNotFromWhatTheURLRemembers() throws {
        var url = dir!

        // **Round eight, and this is the version that names the mechanism instead of working
        // around it.** Rounds 10, 13 and 15 of the last one failed like this:
        //
        //   round 10: the file carries no exclusion at all and BackupPolicy claimed one —
        //             attribute present, 61 bytes: bplist00_…com.apple.backupd…
        //
        // The shape was read, found ABSENT, and `BackupPolicy.read` — microseconds later — found it
        // PRESENT. Not a stale cache and not a wrong comparison: `com.apple.backupd` writes its own
        // exclusion onto folders under `/var/folders` continuously, so **two reads of this file
        // milliseconds apart can honestly disagree**. Every previous version asserted across a pair
        // of reads and so had a rate of failure rather than a bug.
        //
        // `readWhileStill` closes it by construction: it observes the file, asks `BackupPolicy`,
        // observes the file again, and returns nothing at all if those two observations differ. A
        // round that could not see a still file says nothing about this type; it is counted, and
        // floors below fail the test if the host ate every round.
        var rememberedAnExclusion = 0
        var sawOurOwnFlag = 0
        var sawItAbsent = 0
        var theHostPutItBack = 0
        var theHostMovedIt = 0

        for round in 1...20 {
            // Foundation's writer, so the URL has a belief of its own for `read` to ignore.
            var exclude = URLResourceValues()
            exclude.isExcludedFromBackup = true
            try? url.setResourceValues(exclude)
            if (try? url.resourceValues(forKeys: [.isExcludedFromBackupKey]))?
                .isExcludedFromBackup == true { rememberedAnExclusion += 1 }

            // The fixture's own single byte, which is unambiguous and ours.
            XCTAssertTrue(setExclusion(true, at: dir.path), "round \(round): setxattr failed")
            if let seen = readWhileStill(url) {
                if seen.shape.ours {
                    sawOurOwnFlag += 1
                    XCTAssertEqual(seen.answer, .excluded,
                                   "round \(round): the file carries this test's own exclusion byte "
                                 + "and BackupPolicy did not see it — \(exclusionOnDisk(dir.path))")
                }
            } else { theHostMovedIt += 1 }

            // Off again with a raw `removexattr`, which cannot touch a `URL`'s cache.
            XCTAssertTrue(setExclusion(false, at: dir.path), "round \(round): removexattr failed")
            if let seen = readWhileStill(url) {
                if seen.shape.present {
                    // The daemon's own flag, back on the file after a successful removal. That
                    // folder really is excluded and `BackupPolicy` saying so is correct — it is
                    // simply not a round that says anything about a stale `URL` cache.
                    theHostPutItBack += 1
                } else {
                    sawItAbsent += 1
                    XCTAssertEqual(seen.answer, .included,
                                   "round \(round): the file carried no exclusion across the whole "
                                 + "read and BackupPolicy claimed one — \(exclusionOnDisk(dir.path))")
                }
            } else { theHostMovedIt += 1 }
        }
        XCTAssertGreaterThan(sawOurOwnFlag, 0,
                             "not one of twenty rounds saw this test's own flag on a still file, so "
                           + "nothing above asserted that BackupPolicy can see one — the host moved "
                           + "it in \(theHostMovedIt) reads")
        XCTAssertGreaterThan(sawItAbsent, 0,
                             "not one of twenty rounds saw the file still and with no exclusion on "
                           + "it, so nothing above asserted that BackupPolicy reports its absence — "
                           + "the host wrote its own in \(theHostPutItBack) and moved it under "
                           + "\(theHostMovedIt) reads")
        XCTAssertGreaterThan(rememberedAnExclusion, 0,
                             "not one of twenty rounds left the URL believing it was excluded, so "
                           + "nothing here tested a stale cache at all")

        // **And the same through the policy's own writer**, on the same terms.
        //
        // `including` removes the attribute and reads the state back. Two claims survive whatever
        // the daemon does: the removal must not **fail**, and this test's own byte must be **gone**
        // afterwards. Whether the daemon has since written its own is not `including`'s business,
        // and the round is counted rather than asserted on when it has.
        var disagreements: [String] = []
        var startedExcluded = 0
        var includeSawAStillFile = 0
        for round in 1...20 {
            setExclusion(true, at: dir.path)
            if exclusionShape(dir.path).ours { startedExcluded += 1 }

            let attempt = BackupPolicy.including(dir)
            guard attempt.wrote == nil else {
                disagreements.append("round \(round): include threw "
                                   + "\(String(describing: attempt.wrote))")
                continue
            }
            guard let seen = readWhileStill(URL(fileURLWithPath: dir.path)) else {
                theHostMovedIt += 1
                continue
            }
            if seen.shape.ours {
                disagreements.append("round \(round): include left this test's own exclusion byte "
                                   + "on the file — on disk: \(exclusionOnDisk(dir.path))")
                continue
            }
            if seen.shape.present { theHostPutItBack += 1; continue }
            includeSawAStillFile += 1
            if seen.answer != .included {
                // Both halves worked out before the message. An interpolation is not the place for
                // a concatenation broken across lines — Swift's lexer cannot read one, and there is
                // no compiler on the machine this is written on to say so.
                let threw = attempt.wrote.map { "\($0)" } ?? "no"
                disagreements.append(
                    "round \(round): include→\(attempt.state), after→\(seen.answer), "
                  + "threw→\(threw), on disk: \(exclusionOnDisk(dir.path))")
            }
        }
        XCTAssertEqual(disagreements, [],
                       "including does not leave it included — \(disagreements.count) of 20 rounds "
                     + "disagreed. First: \(disagreements.prefix(3).joined(separator: " ⁄ "))")
        XCTAssertGreaterThan(startedExcluded, 0,
                             "no round of twenty started from an exclusion, so the transition this "
                           + "test exists for was never exercised — on disk: "
                           + "\(exclusionOnDisk(dir.path))")
        XCTAssertGreaterThan(includeSawAStillFile, 0,
                             "not one of twenty rounds saw a still file after include, so nothing "
                           + "asserted what it leaves behind — the host wrote its own in "
                           + "\(theHostPutItBack) rounds and moved it under \(theHostMovedIt) reads")
    }

    /// `BackupPolicy.read`, with the file observed either side of it.
    ///
    /// **Nil when the host changed the attribute across the read.** `com.apple.metadata:` is the
    /// Spotlight daemon's namespace and `com.apple.backupd` writes its own exclusion onto folders
    /// under `/var/folders`, so two reads of this one file milliseconds apart can honestly
    /// disagree — which is what made every earlier version of the test above fail at a rate rather
    /// than fail outright. Asserting only across a window the file provably did not move in is the
    /// only structure that is sound here, and it costs nothing: the caller counts the rounds it
    /// could not use, and fails if that was all of them.
    private func readWhileStill(_ url: URL)
        -> (answer: BackupPolicy.State, shape: (present: Bool, ours: Bool))? {
        let before = exclusionShape(url.path)
        let answer = BackupPolicy.read(url)
        let after = exclusionShape(url.path)
        guard before.present == after.present, before.ours == after.ours else { return nil }
        return (answer, before)
    }

    // MARK: reading one back

    /// The reason this exists. `Export.read` and `Export.summary` had ten tests and no caller, and
    /// `summary`'s own doc comment described a screen that did not exist — so a player had to
    /// *trust* their export worked. These hold what the screen is told.
    func testAGoodFileDescribesItselfInWordsAPlayerCanCheck() throws {
        try aMatch(person: "person-1")
        try aMatch()
        let data = try Export.data(try Export.make(
            journal, people: [LocalPerson(id: "person-1", name: "Jenson")],
            assetsNotIncluded: ["badge-a"]))

        guard case let .readable(file) = ExportInspection.of(data, thisDevice: DeviceId("export-tests")) else {
            return XCTFail("a file this device just wrote must read back")
        }
        XCTAssertEqual(file.matches, 2)
        XCTAssertEqual(file.visits, 4, "two visits in each")
        XCTAssertEqual(file.people, 1)
        XCTAssertEqual(file.assetsNotIncluded, 1)
        XCTAssertTrue(file.fromThisDevice)
        XCTAssertTrue(file.summary.contains("2 matches"), file.summary)
        XCTAssertTrue(file.summary.contains("4 visits"), file.summary)
    }

    /// A file from a phone somebody no longer has is the ordinary case, not an error — it is most of
    /// the point of keeping one. Said either way rather than assumed, and never claimed when there
    /// is no device to compare against.
    func testAFileFromAnotherPhoneIsReadableAndSaysSo() throws {
        try aMatch()
        let data = try Export.data(try Export.make(journal))

        guard case let .readable(mine) = ExportInspection.of(data, thisDevice: DeviceId("export-tests")),
              case let .readable(theirs) = ExportInspection.of(data, thisDevice: DeviceId("some-other-phone")),
              case let .readable(unknown) = ExportInspection.of(data)
        else { return XCTFail("all three readings must succeed") }
        XCTAssertTrue(mine.fromThisDevice)
        XCTAssertFalse(theirs.fromThisDevice, "a different device is not this one")
        XCTAssertFalse(unknown.fromThisDevice, "and with nothing to compare against, no claim is made")
        XCTAssertEqual(mine.matches, theirs.matches, "the file says the same thing either way")
        XCTAssertEqual(mine.deviceId, "export-tests", "and it names who wrote it")
    }

    /// A refusal is an answer, and it reaches the screen as a sentence rather than an error the view
    /// has to interpret. `of` never throws, so there is no path where a bad file shows nothing.
    func testABadFileIsRefusedInWordsRatherThanThrowing() throws {
        try aMatch()
        let good = String(decoding: try Export.data(try Export.make(journal)), as: UTF8.self)

        let forged = good.replacingOccurrences(of: "\"visitTotal\" : 180", with: "\"visitTotal\" : 140")
        guard case let .refused(why) = ExportInspection.of(Data(forged.utf8)) else {
            return XCTFail("a forged file must be refused")
        }
        XCTAssertTrue(why.contains("changed since it was exported"), why)

        guard case let .refused(notOurs) = ExportInspection.of(Data("{}".utf8)) else {
            return XCTFail("a json file that is not an export must be refused")
        }
        XCTAssertFalse(notOurs.isEmpty, "and it says why, in a sentence")

        guard case .refused = ExportInspection.of(Data("not json at all".utf8)) else {
            return XCTFail("and so must something that is not json")
        }
    }

    /// **Presence is not exclusion.** The attribute the backup flag *is* comes in two forms, and
    /// the obvious rule — it is there, so the folder is excluded — is wrong about one of them.
    ///
    /// The pre-Foundation technique writes a single byte. `URL.setResourceValues` writes a property
    /// list, and for `isExcludedFromBackup = false` it writes an explicit **false** into the
    /// attribute rather than removing it — so a folder somebody had just *included* through the
    /// framework read back as excluded. CI caught that on the one assertion in this file that writes
    /// the flag off through Foundation and reads it back through `BackupPolicy`, which is why that
    /// cross-check was kept when the rest of the fixture moved to the file system.
    ///
    /// The plist is tried before the byte rule on purpose: a `false` plist is mostly non-zero bytes,
    /// so reading it as a byte would call it excluded — the same mistake one layer down.
    func testTheFlagIsWhatTheAttributeSaysAndNotMerelyThatItIsThere() throws {
        // The single byte, both ways round.
        XCTAssertTrue(BackupPolicy.excludes(Data([1])))
        XCTAssertFalse(BackupPolicy.excludes(Data([0])))

        // Foundation's own form, both ways round.
        for (value, excluded) in [(true, true), (false, false)] {
            let plist = try PropertyListSerialization.data(fromPropertyList: NSNumber(value: value),
                                                          format: .binary, options: 0)
            XCTAssertEqual(BackupPolicy.excludes(plist), excluded,
                           "a property list holding \(value) means excluded: \(excluded)")
        }

        // Nothing at all asserts nothing, and is not an exclusion.
        XCTAssertFalse(BackupPolicy.excludes(Data()))
    }
}
