import Foundation
import CoreGraphics
import ImageIO
#if canImport(UniformTypeIdentifiers)
import UniformTypeIdentifiers
#endif

/// What happens to an image somebody supplies (PD-014, closing OD-019).
///
/// The founder answered the four questions this waited on. Two of the four are enforceable on the
/// device and are enforced here; the other two — screening and the copyright warranty — happen where
/// an image is published, and there is nowhere to publish to yet.
///
/// Which of these shapes is legally available to THRØ is not a question this repository answers.
/// What is here is the founder's product intent expressed as behaviour.
public enum ImagePolicy {
    /// The longest edge an image is stored at. Big enough for a badge on a retina screen at the size
    /// the design draws one, small enough that a phone photograph does not become a 12 MB file.
    public static let maxPixel = 512

    /// Bytes are purged within this many days of a deletion. The image stops being *served* at once;
    /// this is the schedule for the bytes, and the difference is why the number is written down.
    public static let purgeWithinDays = 30

    /// Whether somebody of this age band may have a picture at all.
    ///
    /// **No, unless they are recorded as an adult.** A member recorded as a minor wears the initials
    /// mark, and so does one whose age has not been established — treated the same way for the same
    /// reason the announcements are: what is not known is whether this is a child. The point is that
    /// there is no image of a child in the system to leak, mis-serve, cache or have to delete.
    ///
    /// The same rule, word for word, as `ImagePolicy.mayHavePicture` in `packages/organisation`.
    /// `ClubStateTests` holds the two to each other.
    public static func mayHavePicture(ageBand: String) -> Bool { ageBand == "adult" }
}

/// Decoding an image and writing it out again, carrying nothing it came with.
///
/// **Re-encoding is not a founder decision, it is engineering's.** A phone photograph carries the
/// place it was taken, and a club badge uploaded by a fifteen-year-old carries their house. Passing
/// the original bytes through would publish that, and no amount of policy above it would help.
///
/// Done with ImageIO rather than UIKit, for two reasons: it is the same code on every Apple
/// platform, and building the destination with an explicit, empty property dictionary means metadata
/// is dropped *by construction* rather than by remembering to remove each kind.
public enum ImageIntake {
    public enum Failure: Error, Equatable, CustomStringConvertible {
        case notAnImage
        case couldNotEncode

        public var description: String {
            switch self {
            case .notAnImage: return "that file is not an image this device can read"
            case .couldNotEncode: return "the image could not be written out again"
            }
        }
    }

    /// Re-encodes to JPEG at no more than `maxPixel` on the long edge, with no metadata.
    public static func reEncode(_ data: Data, maxPixel: Int = ImagePolicy.maxPixel,
                                quality: Double = 0.82) throws -> Data {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              CGImageSourceGetCount(source) > 0 else {
            throw Failure.notAnImage
        }
        // Thumbnail rather than full decode: it applies the orientation, caps the size, and never
        // allocates the full-resolution bitmap for a photograph that is about to be shrunk anyway.
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel,
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            throw Failure.notAnImage
        }

        let out = NSMutableData()
        let type: CFString
        #if canImport(UniformTypeIdentifiers)
        type = UTType.jpeg.identifier as CFString
        #else
        type = "public.jpeg" as CFString
        #endif
        guard let destination = CGImageDestinationCreateWithData(out as CFMutableData, type, 1, nil) else {
            throw Failure.couldNotEncode
        }
        // The property dictionary is exactly this and nothing else. Anything the source carried —
        // EXIF, GPS, maker notes, IPTC — is not copied because it is never asked for.
        let properties: [CFString: Any] = [kCGImageDestinationLossyCompressionQuality: quality]
        CGImageDestinationAddImage(destination, image, properties as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { throw Failure.couldNotEncode }
        return out as Data
    }

    /// Two whole blocks that exist for nothing but provenance: where it was taken, and who by.
    static let provenanceBlocks: [CFString] = [kCGImagePropertyGPSDictionary, kCGImagePropertyIPTCDictionary]

    /// Provenance keys inside blocks an encoder also writes for its own reasons.
    ///
    /// The EXIF and TIFF blocks are not evidence of anything by themselves: ImageIO writes an EXIF
    /// block containing the pixel dimensions and the colour space of the file it is writing, and a
    /// TIFF block containing the orientation and the resolution. Treating their mere presence as
    /// "carries metadata" would make that phrase mean "was written by an encoder" — true of every
    /// JPEG in the world, and useless in the direction that matters. So the keys are named.
    static let provenanceKeys: [(CFString, [CFString])] = [
        (kCGImagePropertyExifDictionary, [
            kCGImagePropertyExifUserComment, kCGImagePropertyExifDateTimeOriginal,
            kCGImagePropertyExifDateTimeDigitized, kCGImagePropertyExifMakerNote,
            kCGImagePropertyExifSubjectLocation,
        ]),
        (kCGImagePropertyTIFFDictionary, [
            kCGImagePropertyTIFFArtist, kCGImagePropertyTIFFDateTime, kCGImagePropertyTIFFMake,
            kCGImagePropertyTIFFModel, kCGImagePropertyTIFFCopyright,
        ]),
    ]

    /// Whether these bytes carry anything that says where the image came from.
    ///
    /// Not "whether they carry any metadata": see `provenanceKeys`. The test that uses this does not
    /// trust it alone — it also searches the output bytes for text planted in the input, which is the
    /// check a narrowed predicate cannot talk its way around.
    public static func carriesMetadata(_ data: Data) -> Bool {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] else {
            return false
        }
        for block in provenanceBlocks where props[block] != nil { return true }
        for (block, keys) in provenanceKeys {
            guard let dictionary = props[block] as? [CFString: Any] else { continue }
            for key in keys where dictionary[key] != nil { return true }
        }
        return false
    }
}

/// The images this device holds, as files beside the two databases.
///
/// Files rather than blobs in SQLite, for the ordinary reason: an image is read once and drawn many
/// times, and a row that has to be pulled through a query to paint a badge makes every list slower
/// for nothing. The id is a digest of the bytes, so the same picture stored twice costs one file and
/// a changed picture is a different id — which also means a stale reference can never quietly point
/// at somebody else's face.
public final class ImageStore {
    public enum Failure: Error, Equatable, CustomStringConvertible {
        case notStored(String)
        public var description: String {
            switch self { case .notStored(let id): return "no image \(id) on this device" }
        }
    }

    private let directory: URL

    public init(directory: URL) throws {
        self.directory = directory
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    public func url(_ assetId: String) -> URL {
        directory.appendingPathComponent(assetId).appendingPathExtension("jpg")
    }

    /// Re-encodes and stores. Returns the asset id.
    @discardableResult
    public func put(_ original: Data) throws -> String {
        let clean = try ImageIntake.reEncode(original)
        let id = ImageStore.digest(clean)
        let target = url(id)
        if !FileManager.default.fileExists(atPath: target.path) {
            try clean.write(to: target, options: .atomic)
        }
        return id
    }

    public func data(_ assetId: String) -> Data? {
        try? Data(contentsOf: url(assetId))
    }

    /// Removes it. Deleting something that is already gone is not an error: the caller wanted it
    /// gone, and it is.
    public func delete(_ assetId: String) throws {
        let target = url(assetId)
        if FileManager.default.fileExists(atPath: target.path) {
            try FileManager.default.removeItem(at: target)
        }
    }

    /// Every asset id on this device. Used to find files nothing points at any more.
    public func assetIds() throws -> Set<String> {
        let files = try FileManager.default.contentsOfDirectory(atPath: directory.path)
        return Set(files.filter { $0.hasSuffix(".jpg") }.map { String($0.dropLast(4)) })
    }

    /// A hex digest of the bytes. FNV-1a rather than a cryptographic hash, because this names a file
    /// on one device and defends against nothing — a digest that has to be collision-resistant
    /// against an adversary is the one a server computes when the image is published.
    static func digest(_ data: Data) -> String {
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in data {
            hash ^= UInt64(byte)
            hash = hash &* 0x100000001b3
        }
        return String(format: "%016llx%08x", hash, UInt32(truncatingIfNeeded: data.count))
    }
}
