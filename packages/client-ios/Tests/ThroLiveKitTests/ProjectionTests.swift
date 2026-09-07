import XCTest
@testable import ThroLiveKit

/// The small file a widget reads instead of the journal.
///
/// The journal stays where ADR-006 measured it; this is a regenerable projection of it in the App
/// Group container. What is worth testing is what happens when it is **wrong** — missing, half
/// written, or written by a build that knew a different shape — because every one of those ends
/// with a widget drawing something, and the only acceptable something is nothing.
final class ProjectionTests: XCTestCase {

    private var folder: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        folder = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("thro-projection-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: folder)
        super.tearDown()
    }

    private var url: URL { folder.appendingPathComponent(ThroProjectionStore.filename) }

    private let leg = ThroLiveState(homeName: "Ann", awayName: "Bea",
                                    homeRemaining: 141, awayRemaining: 220,
                                    homeLegs: 1, awayLegs: 2, thrower: .home)

    private func projection(at writtenAt: Date = Date()) -> ThroProjection {
        ThroProjection(writtenAt: writtenAt, live: leg, liveFormat: "501 · Best of 5 · Double out",
                       nextFixture: ThroProjectedFixture(title: "Home to The Bell",
                                                         at: writtenAt.addingTimeInterval(86_400),
                                                         venue: "The Red Lion"),
                       matches: 12, legsThisWeek: 9)
    }

    func testWhatIsWrittenIsWhatIsRead() {
        let written = projection()
        XCTAssertTrue(ThroProjectionStore.write(written, to: url))
        XCTAssertEqual(ThroProjectionStore.read(from: url), written)
    }

    /// A widget on a phone with no App Group entitlement — a package test, a build without the
    /// capability — has no container, and every path treats that as *nothing to say* rather than as
    /// an error. Nothing here may throw or trap.
    func testWithNoContainerNothingIsWrittenAndNothingIsRead() {
        XCTAssertFalse(ThroProjectionStore.write(projection(), to: nil))
        XCTAssertNil(ThroProjectionStore.read(from: nil))
        ThroProjectionStore.clear(at: nil)
    }

    func testThereIsNothingToReadBeforeAnythingIsWritten() {
        XCTAssertNil(ThroProjectionStore.read(from: url))
    }

    /// **A file this build cannot read is nothing, not half a scoreboard.** A widget extension and
    /// its app are separate processes that the system reloads on its own schedule, so a newer app
    /// writing a shape an older loaded extension does not know is a real state and not a
    /// hypothetical one. Decoding what fits and drawing the rest as zeroes is the one outcome worse
    /// than an empty widget.
    func testAFileFromAnotherFormatIsRefusedRatherThanPartlyRead() throws {
        let future = ThroProjection(version: ThroProjection.format + 1, writtenAt: Date(),
                                    live: leg, matches: 12)
        XCTAssertTrue(ThroProjectionStore.write(future, to: url))
        XCTAssertNil(ThroProjectionStore.read(from: url), "a shape this build does not know is nothing")
        XCTAssertFalse(future.isReadable)
    }

    func testRubbishInTheFileIsNothingRatherThanACrash() throws {
        try Data("not json, and never was".utf8).write(to: url)
        XCTAssertNil(ThroProjectionStore.read(from: url))
    }

    /// Clearing takes the file away, so a widget stops showing a match that has been deleted rather
    /// than holding the last one it saw.
    func testClearingLeavesNothingBehind() {
        XCTAssertTrue(ThroProjectionStore.write(projection(), to: url))
        ThroProjectionStore.clear(at: url)
        XCTAssertNil(ThroProjectionStore.read(from: url))
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
    }

    /// The system refreshes a widget when it feels like it, not when the app writes. What is on the
    /// Home Screen can be hours behind the phone it is on and looks exactly as current as something
    /// written a second ago, so the file carries when it was written and the surface can say so.
    func testAProjectionGoesStaleAndSaysWhen() {
        let written = Date()
        let p = projection(at: written)
        XCTAssertFalse(p.isStale(now: written.addingTimeInterval(60)))
        XCTAssertFalse(p.isStale(now: written.addingTimeInterval(ThroProjection.freshness - 1)))
        XCTAssertTrue(p.isStale(now: written.addingTimeInterval(ThroProjection.freshness + 1)))
    }

    /// **A widget's window is longer than a Live Activity's, and that is a decision.** A Live
    /// Activity is renewed by the app on every visit while the app is on screen; a widget is
    /// renewed by the system. Two surfaces with different refresh mechanics need different windows,
    /// and giving them the same number would make one of them wrong.
    func testTheWidgetsWindowIsLongerThanTheLockScreensOnPurpose() {
        XCTAssertGreaterThan(ThroProjection.freshness, ThroVenue.freshness)
        XCTAssertEqual(ThroProjection.freshness, 900, accuracy: 0.001)
    }

    /// **No figure without its sample.** Everything countable on this surface is a count — matches,
    /// legs — because a count carries its own sample, and there is no room on a widget for the
    /// basis an average would need. A `3-dart average` field appearing here would be a claim on a
    /// surface none of the honesty layer's machinery can reach.
    func testNothingOnTheProjectionIsAFigureThatNeedsABasis() throws {
        let data = try ThroProjectionStore.encoder.encode(projection())
        let object = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        for key in object.keys {
            let lowered = key.lowercased()
            for banned in ["average", "avg", "checkout", "percent", "rating", "form", "rank"] {
                XCTAssertFalse(lowered.contains(banned), "\(key) is a figure that needs a basis")
            }
        }
        XCTAssertEqual(object["matches"] as? Int, 12)
        XCTAssertEqual(object["legsThisWeek"] as? Int, 9)
    }

    /// The group id is written down in three places — here, and the two entitlements files — and a
    /// typo in any of them is a widget that is permanently empty with no error anywhere. This holds
    /// the one in code; `tools/check_app_group.py` holds all three against each other.
    func testTheGroupIdIsTheOneTheEntitlementsName() {
        XCTAssertEqual(ThroProjectionStore.groupId, "group.app.thro.darts")
        XCTAssertTrue(ThroProjectionStore.groupId.hasPrefix("group."),
                      "the system requires the prefix and returns nil without it")
    }
}
