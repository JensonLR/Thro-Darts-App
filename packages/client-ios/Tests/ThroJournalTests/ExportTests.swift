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
    /// on a URL to go stale and nothing between the question and the file. The test is unchanged in
    /// what it demands: the flag is written through a `URL` here, deliberately, because Foundation's
    /// own writer is what the app used to rely on and cross-checking it against the raw attribute is
    /// stronger than trusting either alone.
    ///
    /// The `url` is the one written through repeatedly, because a fresh `URL` has nothing cached and
    /// would have passed either way — which is why CI found the original defect only intermittently.
    func testTheAnswerComesFromTheFileSystemAndNotFromWhatTheURLRemembers() throws {
        var url = dir!

        var exclude = URLResourceValues()
        exclude.isExcludedFromBackup = true
        try url.setResourceValues(exclude)
        XCTAssertEqual(BackupPolicy.read(url), .excluded)

        var include = URLResourceValues()
        include.isExcludedFromBackup = false
        try url.setResourceValues(include)
        XCTAssertEqual(BackupPolicy.read(url), .included,
                       "the URL remembers being excluded; the file system does not")

        // And the same through the policy's own writer.
        //
        // **The fixture changes mechanism here, deliberately.** `include` clears the flag with
        // `removexattr`, which does not — and cannot — update the cache on `url`; asking `url` to
        // set a value its cache already holds is precisely the skipped write this whole file is
        // about. The two Foundation writes above are kept because they *are* reliable and they
        // cross-check Foundation's writer against this type's reader; from here the fixture goes on
        // the file, so what is being tested is `BackupPolicy` and not `URL`'s memory.
        //
        // **Four assertions rather than one, each naming a different layer.** There is no Swift on
        // the machine this is written on, so CI is the only way to run it, and a failure that says
        // only `("excluded") is not equal to ("included")` costs a whole round to learn nothing
        // from — this failed exactly that way twice before the messages were worth reading.
        XCTAssertTrue(setExclusion(true, at: dir.path), "the fixture for this half did not take")
        XCTAssertEqual(BackupPolicy.read(url), .excluded)

        let attempt = BackupPolicy.including(url)
        let reported = attempt.state
        let independent = BackupPolicy.read(URL(fileURLWithPath: dir.path))
        let throughTheCaller = BackupPolicy.read(dir)
        // Asked of the file system directly, once, and quoted by all four assertions below. If the
        // attribute is gone and Foundation still says `excluded`, the defect is a read; if it is
        // there, the write is what failed. Three rounds went by without either being established.
        let disk = exclusionOnDisk(dir.path)
        let paths = "wrote through \(url.path); read \(dir.path); on disk: \(disk)"

        XCTAssertNil(attempt.wrote, "setting the flag threw: \(String(describing: attempt.wrote)) "
                                  + "— \(paths)")
        XCTAssertEqual(independent, .included,
                       "the write did not land on disk at all — \(paths)")
        XCTAssertEqual(reported, .included,
                       "include reported \(reported) while an independent read of the same path "
                     + "says \(independent) — \(paths)")
        XCTAssertEqual(throughTheCaller, .included,
                       "two reads of the same path disagree: \(throughTheCaller) here, "
                     + "\(independent) a line earlier — \(paths)")

        // **Twenty rounds, because one pass was a coin toss** — the same commit went green on one
        // CI run and red on the next, and a test that fails half the time can neither confirm a fix
        // nor be trusted to catch a regression.
        //
        // Round 19 of an earlier version is what finally named the cause, and it was not in
        // `BackupPolicy`: `set→included, on disk: no such attribute`. The **fixture** had failed,
        // because it set the flag through a URL that had been written through eighteen times. See
        // `setExclusion`. Every message below still carries what the file system says, which is the
        // only reason that round said anything useful.
        var disagreements: [String] = []
        for round in 1...20 {
            // The fixture goes on the file, not through a URL. See `setExclusion`: writing it
            // through a URL is the thing that turned out to be unreliable, and a fixture that
            // sometimes does not take is a test that sometimes tests nothing.
            XCTAssertTrue(setExclusion(true, at: dir.path), "round \(round): the fixture failed")
            let fixture = BackupPolicy.read(URL(fileURLWithPath: dir.path))

            let attempt = BackupPolicy.including(dir)
            let later = BackupPolicy.read(URL(fileURLWithPath: dir.path))
            guard fixture == .excluded, attempt.wrote == nil,
                  attempt.state == .included, later == .included else {
                // Both halves worked out before the message. An interpolation is not the place for
                // a concatenation broken across lines — Swift's lexer cannot read one, and there is
                // no compiler on the machine this is written on to say so.
                let threw = attempt.wrote.map { "\($0)" } ?? "no"
                disagreements.append(
                    "round \(round): set→\(fixture), include→\(attempt.state), "
                  + "after→\(later), threw→\(threw), "
                  + "on disk: \(exclusionOnDisk(dir.path))")
                continue
            }
        }
        XCTAssertEqual(disagreements, [],
                       "the flag does not settle — \(disagreements.count) of 20 rounds disagreed. "
                     + "First: \(disagreements.prefix(3).joined(separator: " ⁄ "))")
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
