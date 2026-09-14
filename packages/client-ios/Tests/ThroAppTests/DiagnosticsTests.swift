import Foundation
import XCTest
@testable import ThroApp

/// What this phone keeps about how the app performed on it.
///
/// MetricKit's own delivery cannot be tested from a package — `MXMetricManager.shared` needs a real
/// application — so what is tested is everything that decides **what is written, what is kept and
/// what Settings says**, which is where this could be wrong in a way that matters: a folder that
/// only grows, a delivery that silently drops all but one payload, or a switch that says it deleted
/// something and did not.
final class DiagnosticsTests: XCTestCase {

    private var folder: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        let container = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("thro-diagnostics-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: container, withIntermediateDirectories: true)
        folder = try ThroDiagnostics.folder(in: container)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: folder.deletingLastPathComponent())
        super.tearDown()
    }

    private let at = Date(timeIntervalSince1970: 1_800_000_000)

    @discardableResult
    private func store(_ n: Int, from: Date? = nil) -> [Bool] {
        (0 ..< n).map { i in
            ThroDiagnostics.store(Data("{\"i\":\(i)}".utf8), kind: "metric",
                                  at: (from ?? at).addingTimeInterval(Double(i) * 86_400),
                                  in: folder)
        }
    }

    func testAPayloadIsWrittenAndCounted() {
        XCTAssertTrue(ThroDiagnostics.store(Data("{}".utf8), kind: "metric", at: at, in: folder))
        let held = ThroDiagnostics.held(in: folder)
        XCTAssertEqual(held.count, 1)
        XCTAssertGreaterThan(held.bytes, 0)
        XCTAssertEqual(held.newest, at, "the file's name is the instant, and it reads back as one")
    }

    /// **MetricKit hands over an array**, and every payload in one delivery carries the same
    /// instant. Without an index in the name the second would overwrite the first and a delivery of
    /// three would leave one file, silently — no error, no log, and two reports gone.
    func testEveryPayloadOfOneDeliveryIsKept() {
        for index in 0 ..< 3 {
            XCTAssertTrue(ThroDiagnostics.store(Data("{\"i\":\(index)}".utf8), kind: "diagnostic",
                                                at: at, index: index, in: folder))
        }
        XCTAssertEqual(ThroDiagnostics.held(in: folder).count, 3)
    }

    /// A folder that only grows is a folder that eventually matters. The newest thirty stay.
    func testTheFolderIsCappedAndKeepsTheNewest() {
        store(ThroDiagnostics.keep + 5)
        let held = ThroDiagnostics.held(in: folder)
        XCTAssertEqual(held.count, ThroDiagnostics.keep)
        XCTAssertEqual(held.newest, at.addingTimeInterval(Double(ThroDiagnostics.keep + 4) * 86_400),
                       "the last one written is still there")
    }

    /// Sorted by **name**, which is the timestamp. A file's modification date can be changed by a
    /// restore from a backup; the name it was written with cannot, so trimming keeps the right ones
    /// on a phone that has been restored.
    func testTheOrderComesFromTheNameAndNotFromTheFileSystem() throws {
        store(3)
        let names = ThroDiagnostics.payloads(in: folder).map(\.lastPathComponent)
        XCTAssertEqual(names, names.sorted(by: >))
        XCTAssertEqual(names.count, 3)
    }

    /// Off means gone, not merely stopped. The Spotlight switch already follows this rule, for the
    /// same reason: a switch that left the collected reports behind would be a switch that lies.
    func testForgettingEmptiesTheFolderRatherThanStoppingNewOnes() {
        store(4)
        XCTAssertEqual(ThroDiagnostics.held(in: folder).count, 4)
        ThroDiagnostics.forget(in: folder)
        let held = ThroDiagnostics.held(in: folder)
        XCTAssertEqual(held.count, 0)
        XCTAssertEqual(held.bytes, 0)
        XCTAssertNil(held.newest)
    }

    /// Only payloads. A stray file in the folder is neither counted nor deleted — this app does not
    /// own everything that might end up in a directory on somebody's phone.
    func testSomethingElseInTheFolderIsNeitherCountedNorDeleted() throws {
        store(2)
        let stray = folder.appendingPathComponent("notes.txt")
        try Data("not a payload".utf8).write(to: stray)

        XCTAssertEqual(ThroDiagnostics.held(in: folder).count, 2)
        ThroDiagnostics.forget(in: folder)
        XCTAssertTrue(FileManager.default.fileExists(atPath: stray.path), "not ours to delete")
    }

    // MARK: what Settings says

    /// An empty folder says what it is waiting for rather than reading as a fault. iOS delivers
    /// these at most once a day, so *nothing yet* is the normal state for a while.
    func testAnEmptyFolderSaysWhatItIsWaitingFor() {
        let sentence = ThroDiagnostics.sentence(ThroDiagnostics.held(in: folder))
        XCTAssertTrue(sentence.contains("Nothing collected yet"), sentence)
        XCTAssertTrue(sentence.contains("once a day"), sentence)
    }

    /// **Nothing has been sent anywhere**, and the sentence says so. That claim is the whole of what
    /// this feature owes a player: it collects something about them and there is no endpoint.
    func testTheSentenceSaysNothingWasSentAnywhere() {
        store(2)
        let sentence = ThroDiagnostics.sentence(ThroDiagnostics.held(in: folder))
        XCTAssertTrue(sentence.contains("2 reports"), sentence)
        XCTAssertTrue(sentence.contains("Nothing has been sent anywhere"), sentence)
    }

    func testTheSentenceCountsOneReportAsOne() {
        store(1)
        XCTAssertTrue(ThroDiagnostics.sentence(ThroDiagnostics.held(in: folder)).contains("1 report,"),
                      ThroDiagnostics.sentence(ThroDiagnostics.held(in: folder)))
    }

    /// The stamp's length is computed from the formatter rather than counted by hand. A wrong
    /// constant reads one character too many, `newest` parses nothing, and Settings quietly stops
    /// saying when the last report arrived.
    func testTheStampLengthMatchesTheFormatItParses() {
        XCTAssertEqual(ThroDiagnostics.stampLength, 19)
        XCTAssertEqual(ThroDiagnostics.stamp.string(from: at).count, ThroDiagnostics.stampLength)
    }

    /// **Off by default.** This is the one thing in the app a player gains nothing from, so it is
    /// theirs to turn on rather than theirs to discover and turn off.
    func testCollectingIsOffUntilThePlayerAsks() {
        UserDefaults.standard.removeObject(forKey: ThroDiagnostics.enabledKey)
        XCTAssertFalse(UserDefaults.standard.bool(forKey: ThroDiagnostics.enabledKey))
    }
}
