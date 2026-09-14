import Foundation

// What happens to a player's darts when the phone does not survive (PD-017).
//
// PD-012 put everything on the phone, which means a lost, broken or wiped phone loses every match
// ever played on it. The founder chose both answers: the ordinary device backup, which needs no
// discipline from the player, and an export they control, which is the one that makes the record
// theirs. This file is the first. `Export.swift` is the second.

/// Whether the app's own data is included in the device backup, stated rather than defaulted.
///
/// **It already was.** Application Support is backed up by iOS unless something excludes it, so on
/// paper there was nothing to do. That is exactly the situation this repository has been caught by
/// before: the durability probe measured a configuration SQLite had refused, because nobody read the
/// pragmas back. A default that nothing states and nothing checks is a default that changes.
///
/// So the flag is set explicitly and **read back**, and the app can say what it found rather than
/// what it asked for. If a future change ever excludes the container — for a cache, for a temporary
/// file, for a reason that seemed local at the time — this is what notices.
public enum BackupPolicy {

    public enum State: Equatable, Sendable {
        /// Included in the device backup. What THRØ wants for a journal.
        case included
        /// Excluded. A journal here would not survive a new phone.
        case excluded
        /// The file system would not say. Reported, never assumed either way.
        case unknown(String)

        public var isIncluded: Bool { self == .included }
    }

    /// The extended attribute the flag actually **is**.
    ///
    /// `isExcludedFromBackup` is not a property of a `URL`; it is the presence or absence of this
    /// attribute on the file. iOS's backup reads the attribute and nothing else about its contents,
    /// which is why presence alone decides here.
    static let attribute = "com.apple.metadata:com_apple_backup_excludeItem"

    /// What the write said, when it had something to say.
    public struct WriteFailed: Error, Equatable, CustomStringConvertible {
        public let code: Int32
        public var description: String { "errno \(code)" }
    }

    /// Marks `url` as data that belongs in a backup, then reads the flag back and returns what is
    /// actually in force.
    ///
    /// A journal is **not regenerable** — it is the only copy of what was thrown — so Apple's
    /// guidance to exclude regenerable data does not apply to it, and including it is the decision
    /// rather than the absence of one.
    @discardableResult
    public static func include(_ url: URL) -> State { including(url).state }

    /// The same, and what the write itself said.
    ///
    /// **The two failures look identical from the outside, and that cost a round.** When this comes
    /// back `.excluded`, either the write failed or the write succeeded and changed nothing. Settings
    /// wants the state and nothing else; a test wants to tell those apart.
    @discardableResult
    static func including(_ url: URL) -> (state: State, wrote: Error?) {
        // **Removing the attribute is the inclusion.** There is no value to write and therefore no
        // format to get wrong: absence is the state every folder starts in, and it is what "in the
        // backup" means.
        if removexattr(url.path, attribute, 0) != 0, errno != ENOATTR {
            return (read(url), WriteFailed(code: errno))
        }
        return (read(url), nil)
    }

    /// What the file system says right now.
    ///
    /// **Asked of the file, not of a `URL`, and this took five rounds to arrive at.** `URL`
    /// memoises resource values on the value itself, so the obvious implementation answered with
    /// what a URL had last been told rather than with what is on disk — and Settings told a player
    /// their matches were *not* in this phone's backup about a folder that was. Three attempts to
    /// clear that cache each removed one participant and each left the answer intermittent: on the
    /// same commit, one CI run green and the next red, and in one red run three reads of a single
    /// path within a millisecond disagreeing with each other.
    ///
    /// **The cause, once it was finally measured, is a skipped write.** A `URL` caches the resource
    /// values it has seen, and that cache does not notice the file changing underneath it. Ask such
    /// a URL to set the value it already believes is in force and Foundation skips the write and
    /// reports success — so a folder whose attribute was removed by something else stays removed
    /// while the caller is told it was set. Every version of this defect was one write silently not
    /// happening, and the intermittency was simply whether the cache happened to match.
    ///
    /// `getxattr` reads the file and `removexattr` writes it. There is no cache on a `URL`, none in
    /// Foundation and no daemon between this and the answer, and on iOS this is the same mechanism
    /// the backup itself uses.
    ///
    /// The cost is stated rather than hidden: on **macOS** this no longer reflects Time Machine's
    /// path-based exclusions. That is the right trade for a type that exists to describe the iOS
    /// device backup of an iOS-only app.
    public static func read(_ url: URL) -> State {
        guard FileManager.default.fileExists(atPath: url.path) else {
            return .unknown("there is nothing at \(url.path) to have a flag")
        }
        let size = getxattr(url.path, attribute, nil, 0, 0, 0)
        guard size >= 0 else {
            // Not there is what *included* is: the absence of an exclusion is an inclusion. Any
            // other failure is reported rather than guessed — reading a flag and assuming a flag
            // are the two things this type exists to keep apart.
            guard errno == ENOATTR else {
                return .unknown("the backup flag could not be read: errno \(errno)")
            }
            return .included
        }
        guard size > 0 else { return .included }
        var bytes = [UInt8](repeating: 0, count: size)
        guard getxattr(url.path, attribute, &bytes, bytes.count, 0, 0) == size else {
            return .unknown("the backup flag could not be read: errno \(errno)")
        }
        return excludes(Data(bytes)) ? .excluded : .included
    }

    /// What the attribute's contents mean.
    ///
    /// **Presence is not exclusion, and assuming it was cost another round.** The obvious rule —
    /// the attribute is there, so the folder is excluded — is what the pre-Foundation technique
    /// wrote (a single byte, 1) and what most code that touches this expects. It is not what
    /// `URL.setResourceValues(isExcludedFromBackup: false)` does: rather than removing the
    /// attribute, Foundation writes an explicit **false** into it, so a folder somebody had just
    /// *included* through the framework read back as excluded here. CI caught it on the one
    /// assertion in the suite that writes the flag off through Foundation and reads it back through
    /// this type — which is precisely why that cross-check was kept when the rest of the fixture
    /// moved to the file system.
    ///
    /// So the contents decide, in both forms: a property list holding a boolean, and the single
    /// byte. The plist is tried first — a `false` plist is mostly non-zero bytes, so the byte rule
    /// would read it as *excluded*, which is the same mistake one layer down.
    static func excludes(_ data: Data) -> Bool {
        if let plist = try? PropertyListSerialization.propertyList(from: data, options: [],
                                                                  format: nil),
           let number = plist as? NSNumber {
            return number.boolValue
        }
        return data.contains { $0 != 0 }
    }

    /// What Settings says about it, in words rather than a flag.
    ///
    /// Both halves are told, because a player who learns their darts are in iCloud from a support
    /// article rather than from the app has been failed twice.
    public static func sentence(_ state: State) -> String {
        switch state {
        case .included:
            return "Your matches are on this phone and are included in its backup, so restoring a "
                 + "backup to a new phone brings them with it. That also means they are in iCloud if "
                 + "you back up to iCloud."
        case .excluded:
            return "Your matches are on this phone and are NOT included in its backup, so a new "
                 + "phone would start empty. Export them to keep a copy."
        case let .unknown(why):
            return "Your matches are on this phone. Whether they are included in its backup could "
                 + "not be read: \(why). Export them to be sure of a copy."
        }
    }
}
