import XCTest
import CoreGraphics
import ImageIO
#if canImport(UniformTypeIdentifiers)
import UniformTypeIdentifiers
#endif
@testable import ThroJournal

/// Images somebody supplies (PD-014, closing OD-019).
///
/// These do not describe the intake, they perform it: a real JPEG is built with GPS and EXIF in it,
/// put through the same code path a club badge goes through, and the result is inspected. A comment
/// promising that metadata is stripped is worth nothing next to a test that reads the bytes.
final class ImageTests: XCTestCase {

    private var directory: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("thro-images-\(UUID().uuidString)")
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: directory)
        super.tearDown()
    }

    /// A JPEG of `size`×`size` carrying GPS coordinates and an EXIF block — a phone photograph, in
    /// the one respect that matters here.
    private func photograph(size: Int = 1200) throws -> Data {
        let space = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8,
                                      bytesPerRow: 0, space: space,
                                      bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else {
            throw XCTSkip("this machine cannot make a bitmap")
        }
        context.setFillColor(CGColor(red: 0.06, green: 0.24, blue: 0.18, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: size, height: size))
        guard let image = context.makeImage() else { throw XCTSkip("no image from the context") }

        let out = NSMutableData()
        #if canImport(UniformTypeIdentifiers)
        let type = UTType.jpeg.identifier as CFString
        #else
        let type = "public.jpeg" as CFString
        #endif
        guard let destination = CGImageDestinationCreateWithData(out as CFMutableData, type, 1, nil) else {
            throw XCTSkip("no JPEG encoder here")
        }
        let properties: [CFString: Any] = [
            kCGImagePropertyGPSDictionary: [
                kCGImagePropertyGPSLatitude: 51.5072,
                kCGImagePropertyGPSLongitude: 0.1276,
            ] as [CFString: Any],
            kCGImagePropertyExifDictionary: [
                kCGImagePropertyExifUserComment: "taken at home",
            ] as [CFString: Any],
        ]
        CGImageDestinationAddImage(destination, image, properties as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { throw XCTSkip("could not finalise") }
        return out as Data
    }

    /// The one that matters. A club badge uploaded by a fifteen-year-old carries their house, and
    /// passing the original bytes through would publish it.
    func testWhereTheImageWasTakenDoesNotSurviveIntake() throws {
        let original = try photograph()
        XCTAssertTrue(ImageIntake.carriesMetadata(original), "the fixture is not a photograph without it")

        let clean = try ImageIntake.reEncode(original)
        XCTAssertFalse(ImageIntake.carriesMetadata(clean),
                       "the re-encoded image still carries metadata it came with")
    }

    func testAPhotographIsBroughtDownToTheSizeABadgeIsDrawnAt() throws {
        let clean = try ImageIntake.reEncode(try photograph(size: 1600))
        guard let source = CGImageSourceCreateWithData(clean as CFData, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = props[kCGImagePropertyPixelWidth] as? Int,
              let height = props[kCGImagePropertyPixelHeight] as? Int else {
            return XCTFail("the re-encoded image cannot be read back")
        }
        XCTAssertLessThanOrEqual(max(width, height), ImagePolicy.maxPixel)
        XCTAssertGreaterThan(min(width, height), 0)
        XCTAssertLessThan(clean.count, 400_000, "a badge should not be a megabyte")
    }

    func testSomethingThatIsNotAnImageIsRefusedRatherThanStored() throws {
        let store = try ImageStore(directory: directory)
        let notAnImage = Data("this is a text file".utf8)
        XCTAssertThrowsError(try store.put(notAnImage)) { error in
            XCTAssertEqual(error as? ImageIntake.Failure, .notAnImage)
        }
        XCTAssertEqual(try store.assetIds().count, 0)
    }

    /// The id is a digest of the stored bytes, so the same picture twice is one file — and a
    /// different picture can never land on an id something else already points at.
    func testTheSamePictureStoredTwiceIsOneFileAndADifferentOneIsNot() throws {
        let store = try ImageStore(directory: directory)
        let first = try store.put(try photograph(size: 800))
        let again = try store.put(try photograph(size: 800))
        XCTAssertEqual(first, again)
        XCTAssertEqual(try store.assetIds(), [first])

        let other = try store.put(try photograph(size: 600))
        XCTAssertNotEqual(first, other)
        XCTAssertEqual(try store.assetIds().count, 2)

        XCTAssertNotNil(store.data(first))
        XCTAssertNil(store.data("nothing-here"))

        try store.delete(first)
        XCTAssertNil(store.data(first))
        XCTAssertNoThrow(try store.delete(first), "deleting what is already gone is not an error")
        XCTAssertEqual(try store.assetIds(), [other])
    }

    // MARK: - the safeguarding rule, in its second place

    /// The same rule the announcements keep, applied to pictures: nobody under 18 has one, and
    /// neither does anybody whose age is not established.
    func testOnlyAnAdultMayHaveAPicture() {
        XCTAssertTrue(ImagePolicy.mayHavePicture(ageBand: "adult"))
        XCTAssertFalse(ImagePolicy.mayHavePicture(ageBand: "minor"))
        XCTAssertFalse(ImagePolicy.mayHavePicture(ageBand: "unknown"))
        XCTAssertFalse(ImagePolicy.mayHavePicture(ageBand: "grown-up"),
                       "and anything this build does not recognise is not an adult either")
    }

    /// Refused where it is written, not where it is drawn — so there is no image of a child in the
    /// file to leak, whatever any screen later decides to render.
    func testAPictureForAMinorIsRefusedAtTheWrite() throws {
        let book = try ClubBook(path: directory.appendingPathComponent("book.sqlite").path)
        let club = try book.createClub(name: "The Feathers", kind: "club")
        let adult = try book.addMember(to: club.id, name: "Alex", role: "member", ageBand: "adult")
        let minor = try book.addMember(to: club.id, name: "Jamie", role: "member", ageBand: "minor")
        let unknown = try book.addMember(to: club.id, name: "Sam", role: "member", ageBand: "unknown")

        XCTAssertNoThrow(try book.setAvatar("asset-1", forMember: adult.id, in: club.id))
        XCTAssertThrowsError(try book.setAvatar("asset-2", forMember: minor.id, in: club.id)) { error in
            XCTAssertEqual(error as? ClubBookError, .pictureRefused("minor"))
        }
        XCTAssertThrowsError(try book.setAvatar("asset-3", forMember: unknown.id, in: club.id)) { error in
            XCTAssertEqual(error as? ClubBookError, .pictureRefused("unknown"))
        }

        let members = try book.members(of: club.id)
        XCTAssertEqual(members.first { $0.id == adult.id }?.avatarAssetId, "asset-1")
        XCTAssertNil(members.first { $0.id == minor.id }?.avatarAssetId)
        XCTAssertNil(members.first { $0.id == unknown.id }?.avatarAssetId)
        XCTAssertEqual(try book.referencedAssetIds(), ["asset-1"])
    }

    /// A picture already on file for somebody whose age later reads as anything but adult is not
    /// shown. The read goes through the policy, not around it — the row could come from a later
    /// build, an edited file, or a bug of ours, and none of those is a reason to render it.
    func testAPictureIsNotShownIfTheAgeStopsSayingAdult() throws {
        let book = try ClubBook(path: directory.appendingPathComponent("book.sqlite").path)
        let club = try book.createClub(name: "The Feathers", kind: "club")
        let person = try book.addMember(to: club.id, name: "Alex", role: "member", ageBand: "adult")
        try book.setAvatar("asset-1", forMember: person.id, in: club.id)
        XCTAssertEqual(try book.members(of: club.id).first?.avatarAssetId, "asset-1")

        try book.forTests("UPDATE club_member SET age_band = 'minor' WHERE member_id = '\(person.id)';")
        XCTAssertNil(try book.members(of: club.id).first?.avatarAssetId,
                     "the row still holds it; the read refuses to hand it over")
        XCTAssertEqual(try book.referencedAssetIds(), ["asset-1"],
                       "and it is still referenced, so the file is not swept up while this is unresolved")
    }

    func testABadgeIsSetAndClearedAndAClubThatIsNotHereIsRefused() throws {
        let book = try ClubBook(path: directory.appendingPathComponent("book.sqlite").path)
        let club = try book.createClub(name: "The Feathers", kind: "club")
        XCTAssertNil(try book.clubs().first?.badgeAssetId)

        try book.setBadge("badge-1", on: club.id)
        XCTAssertEqual(try book.clubs().first?.badgeAssetId, "badge-1")
        try book.setBadge(nil, on: club.id)
        XCTAssertNil(try book.clubs().first?.badgeAssetId)

        XCTAssertThrowsError(try book.setBadge("badge-1", on: "nope")) { error in
            XCTAssertEqual(error as? ClubBookError, .noSuchClub("nope"))
        }
    }
}
