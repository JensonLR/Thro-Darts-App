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
        XCTAssertEqual(BackupPolicy.include(excluded), .included)
    }
}
