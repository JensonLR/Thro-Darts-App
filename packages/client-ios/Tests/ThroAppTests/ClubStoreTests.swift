import XCTest
import CoreGraphics
import ImageIO
@testable import ThroJournal
@testable import ThroApp

/// The Clubs tab reading the book that holds it. These hold the mapping — the one place a stored row
/// becomes something a screen draws — to the rules the domain states, because a mapping is where a
/// guarantee quietly stops being kept.
final class ClubStoreTests: XCTestCase {

    private var path: String!

    override func setUp() {
        super.setUp()
        path = NSTemporaryDirectory() + "thro-clubstore-\(UUID().uuidString).sqlite"
    }

    override func tearDown() {
        for suffix in ["", "-wal", "-shm", "-journal"] {
            try? FileManager.default.removeItem(atPath: path + suffix)
        }
        super.tearDown()
    }

    private func store() throws -> ClubStore { ClubStore(book: try ClubBook(path: path)) }

    func testAClubStartedOnThisPhoneIsOneYouKeep() throws {
        let s = try store()
        XCTAssertTrue(s.createClub(name: "The Feathers", kind: .club, accentHex: "#0F3D2E"))

        XCTAssertEqual(s.clubs.count, 1)
        let club = s.clubs[0]
        XCTAssertEqual(club.name, "The Feathers")
        XCTAssertEqual(club.kind, .club)
        XCTAssertEqual(club.accentHex, "0F3D2E")
        XCTAssertEqual(club.yourRole, .admin,
                       "a club nobody else can see is one its keeper keeps; the server decides this when there is one")
        XCTAssertFalse(club.verified, "nothing on this device has been verified by anybody")
        XCTAssertEqual(club.announcements.count, 0, "nothing has been sent, because there is nowhere to send it")
        XCTAssertEqual(club.meta, "No members yet")
        XCTAssertEqual(club.initials, "F", "\"The\" carries no information at badge size")
    }

    /// A club is counted in people, and a league is counted in **teams** (PD-019).
    ///
    /// This test used to make a league and assert it said "2 members", which was the whole defect
    /// the founder called out in one line: the three kinds were one screen with three labels, so
    /// nobody noticed a league describing itself by the size of the wrong list. A league of eight
    /// teams run by two officials is not "2 members".
    func testTheMetaLineCountsWhatIsActuallyThere() throws {
        let s = try store()
        _ = s.createClub(name: "The Feathers", kind: .club, accentHex: nil)
        let club = s.clubs[0].id
        XCTAssertEqual(s.clubs[0].meta, "No members yet")
        _ = s.addMember(to: club, name: "Alex", role: .member, ageBand: .adult)
        XCTAssertEqual(s.clubs[0].meta, "1 member")
        _ = s.addMember(to: club, name: "Sam", role: .official, ageBand: .adult)
        XCTAssertEqual(s.clubs[0].meta, "2 members", "and it is plural when it should be")
    }

    /// The same line for a league, which counts something else entirely.
    func testALeagueIsCountedInTeamsAndNotInItsOfficials() throws {
        let s = try store()
        _ = s.createClub(name: "Crediton & District", kind: .league, accentHex: nil)
        let league = s.clubs[0].id
        XCTAssertEqual(s.clubs[0].meta, "No teams yet")

        // Two people who run it. They are members, and they are not what a league is measured in.
        _ = s.addMember(to: league, name: "Alex", role: .admin, ageBand: .adult)
        _ = s.addMember(to: league, name: "Sam", role: .official, ageBand: .adult)
        XCTAssertEqual(s.clubs[0].meta, "No teams yet", "two officials are not two teams")

        XCTAssertTrue(s.addTeam(to: league, name: "The Feathers A"))
        XCTAssertEqual(s.clubs[0].meta, "1 team")
        XCTAssertTrue(s.addTeam(to: league, name: "The Feathers B"))
        XCTAssertEqual(s.clubs[0].meta, "2 teams")
        XCTAssertEqual(s.clubs[0].teams.map(\.name), ["The Feathers A", "The Feathers B"],
                       "and the letter that tells them apart survives")
        XCTAssertEqual(s.clubs[0].members.count, 2, "the people are still there, under their own name")
    }

    /// The direction that matters. A band the mapping cannot read has to become `unknown`, which is
    /// hidden and withheld — never `adult`, which is listed and messaged.
    func testAnAgeBandTheMappingCannotReadIsUnknownAndIsWithheld() throws {
        let book = try ClubBook(path: path)
        let club = try book.createClub(name: "The Feathers", kind: "club")
        try book.addMember(to: club.id, name: "Alex", role: "member", ageBand: "adult")
        try book.forTests("UPDATE club_member SET age_band = 'grown-up' WHERE club_id = '\(club.id)';")

        let s = ClubStore(book: book)
        XCTAssertEqual(s.clubs[0].members.map(\.ageBand), [.unknown])
        let d = s.clubs[0].delivery
        XCTAssertEqual(d.reaches, 0, "an unreadable age is treated exactly as a child's")
        XCTAssertEqual(d.withheld.ageNotGiven, 1)
    }

    /// PD-009's boundary, through the mapping rather than in the abstract: a minor is on the roster,
    /// counted, and reached by nothing.
    func testAMinorIsHeldAndCountedAndReachedByNothing() throws {
        let s = try store()
        _ = s.createClub(name: "The Feathers", kind: .club, accentHex: nil)
        let id = s.clubs[0].id
        _ = s.addMember(to: id, name: "Alex", role: .member, ageBand: .adult)
        _ = s.addMember(to: id, name: "Jamie", role: .member, ageBand: .minor)

        let club = s.clubs[0]
        XCTAssertEqual(club.members.count, 2)
        XCTAssertEqual(club.meta, "2 members")
        XCTAssertEqual(club.visibleMembers.count, 2, "the keeper of the phone is this club's admin")
        XCTAssertEqual(club.delivery.reaches, 1)
        XCTAssertEqual(club.delivery.withheld.minors, 1)
        XCTAssertEqual(club.delivery.withheld.lines.count, 1)
    }

    func testFixturesComeBackSoonestFirstWithTheirStateAndSurviveTheMapping() throws {
        let s = try store()
        _ = s.createClub(name: "The Feathers", kind: .club, accentHex: nil)
        let id = s.clubs[0].id
        let base = Date(timeIntervalSince1970: 1_700_000_000)
        _ = s.addFixture(to: id, title: "Away at The Crown", when: base + 172_800, venue: "The Crown")
        _ = s.addFixture(to: id, title: "Home to The Bell", when: base + 86_400, venue: "The Feathers")

        XCTAssertEqual(s.clubs[0].fixtures.map(\.title), ["Home to The Bell", "Away at The Crown"])
        XCTAssertEqual(s.clubs[0].fixtures.map(\.state), [.scheduled, .scheduled])
        XCTAssertFalse(s.clubs[0].fixtures[0].when.isEmpty, "a fixture without a readable time is not a fixture")

        let first = s.clubs[0].fixtures[0].id
        XCTAssertTrue(s.move(first, in: id, to: .played))
        XCTAssertEqual(s.clubs[0].fixtures[0].state, .played)
        XCTAssertFalse(s.move(first, in: id, to: .scheduled), "played is terminal, in the client too")
        XCTAssertNotNil(s.writeProblem, "and the refusal is kept rather than dropped")
        XCTAssertEqual(s.clubs[0].fixtures[0].state, .played)
    }

    /// A write that does not happen must say so. The screen stays open on the refusal rather than
    /// dismissing over the top of it, which is what the boolean is for.
    func testARefusedWriteIsReportedAndChangesNothing() throws {
        let s = try store()
        XCTAssertFalse(s.createClub(name: "   ", kind: .club, accentHex: nil))
        XCTAssertEqual(s.clubs.count, 0)
        XCTAssertNotNil(s.writeProblem)
        XCTAssertTrue(s.writeProblem?.contains("name") == true, "and it says what was wrong: \(s.writeProblem ?? "")")

        XCTAssertTrue(s.createClub(name: "The Feathers", kind: .club, accentHex: nil))
        XCTAssertNil(s.writeProblem, "a write that works clears the last refusal")
    }

    func testAnAccentThatIsNotAColourIsRefusedRatherThanShown() throws {
        let s = try store()
        XCTAssertFalse(s.createClub(name: "The Feathers", kind: .club, accentHex: "greenish"))
        XCTAssertEqual(s.clubs.count, 0)
        XCTAssertNotNil(s.writeProblem)
    }

    /// The figures on a member's page. Nothing on this device is attributed to anybody, so every one
    /// of them is a dash with the reason under it — never a zero, which would read as "they are bad".
    func testAMembersFiguresAreDashesWithReasonsRatherThanZeroes() {
        let m = ClubMember(id: "m1", name: "Alex", role: .member, joined: "Mar 2026")
        let figures = ClubsFlow.figures(for: m)
        XCTAssertEqual(figures.count, 3)
        XCTAssertEqual(figures.map(\.value), ["—", "—", "—"])
        for f in figures {
            XCTAssertNotNil(f.unavailable, "\(f.label) is a dash and does not say why")
            XCTAssertTrue(f.unavailable?.contains("account") == true)
        }
    }

    func testRemovingAMemberAndDeletingAClubBothTakeEffect() throws {
        let s = try store()
        _ = s.createClub(name: "The Feathers", kind: .club, accentHex: nil)
        let id = s.clubs[0].id
        _ = s.addMember(to: id, name: "Alex", role: .member, ageBand: .adult)
        _ = s.addMember(to: id, name: "Sam", role: .member, ageBand: .adult)
        _ = s.addFixture(to: id, title: "Home to The Bell", when: Date(), venue: "The Feathers")

        let alex = s.clubs[0].members.first { $0.name == "Alex" }!
        XCTAssertTrue(s.removeMember(alex.id, from: id))
        XCTAssertEqual(s.clubs[0].members.map(\.name), ["Sam"])

        XCTAssertTrue(s.delete(id))
        XCTAssertEqual(s.clubs.count, 0)
        XCTAssertNil(s.club(id), "and the flow can tell a club has gone rather than drawing an empty one")
    }


    // MARK: - pictures (PD-014)

    /// A badge round-trips: picked bytes are re-encoded, stored, and come back as the club's image.
    /// And removing it removes the file, rather than leaving a folder that only ever grows.
    func testABadgeIsStoredReEncodedAndSweptUpWhenItIsRemoved() throws {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("thro-store-images-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let images = try ImageStore(directory: dir)
        let s = ClubStore(book: try ClubBook(path: path), images: images)
        XCTAssertTrue(s.createClub(name: "The Feathers", kind: .club, accentHex: nil))
        let id = s.clubs[0].id
        XCTAssertNil(s.clubs[0].badgeAssetId)

        XCTAssertTrue(s.setBadge(try ClubStoreTests.picture(), on: id))
        let asset = s.clubs[0].badgeAssetId
        XCTAssertNotNil(asset)
        XCTAssertEqual(try images.assetIds().count, 1)
        XCTAssertNotNil(s.image(asset), "and it decodes")

        XCTAssertTrue(s.setBadge(nil, on: id))
        XCTAssertNil(s.clubs[0].badgeAssetId)
        XCTAssertEqual(try images.assetIds().count, 0, "nothing points at it, so the file is gone")
    }

    /// The safeguarding rule reaches the store, not just the book: a picture for a member who is not
    /// recorded as an adult is refused, and the refusal is kept rather than dropped.
    func testAPictureForAMinorIsRefusedThroughTheStoreToo() throws {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("thro-store-images-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let s = ClubStore(book: try ClubBook(path: path), images: try ImageStore(directory: dir))
        XCTAssertTrue(s.createClub(name: "The Feathers", kind: .club, accentHex: nil))
        let club = s.clubs[0].id
        XCTAssertTrue(s.addMember(to: club, name: "Jamie", role: .member, ageBand: .minor))
        XCTAssertTrue(s.addMember(to: club, name: "Alex", role: .member, ageBand: .adult))

        let jamie = s.clubs[0].members.first { $0.name == "Jamie" }!
        let alex = s.clubs[0].members.first { $0.name == "Alex" }!
        let picture = try ClubStoreTests.picture()

        XCTAssertFalse(s.setAvatar(picture, forMember: jamie.id, in: club))
        XCTAssertNotNil(s.writeProblem)
        XCTAssertNil(s.clubs[0].members.first { $0.id == jamie.id }?.avatarAssetId)

        XCTAssertTrue(s.setAvatar(picture, forMember: alex.id, in: club))
        XCTAssertNotNil(s.clubs[0].members.first { $0.id == alex.id }?.avatarAssetId)
    }

    /// A tiny real JPEG, so the intake is exercised rather than described.
    static func picture(size: Int = 64) throws -> Data {
        let space = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8,
                                      bytesPerRow: 0, space: space,
                                      bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue),
              let image = { () -> CGImage? in
                  context.setFillColor(CGColor(red: 0.06, green: 0.24, blue: 0.18, alpha: 1))
                  context.fill(CGRect(x: 0, y: 0, width: size, height: size))
                  return context.makeImage()
              }() else {
            throw XCTSkip("this machine cannot make a bitmap")
        }
        let out = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(out as CFMutableData,
                                                                "public.jpeg" as CFString, 1, nil) else {
            throw XCTSkip("no JPEG encoder here")
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { throw XCTSkip("could not finalise") }
        return out as Data
    }
}
