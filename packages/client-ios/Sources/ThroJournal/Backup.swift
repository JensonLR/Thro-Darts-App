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

    /// Marks `url` as data that belongs in a backup, then reads the flag back and returns what is
    /// actually in force.
    ///
    /// A journal is **not regenerable** — it is the only copy of what was thrown — so Apple's
    /// guidance to exclude regenerable data does not apply to it, and including it is the decision
    /// rather than the absence of one.
    @discardableResult
    public static func include(_ url: URL) -> State {
        var target = url
        do {
            var values = URLResourceValues()
            values.isExcludedFromBackup = false
            try target.setResourceValues(values)
        } catch {
            // Setting it failed; the read below still says what is true, which is the part that
            // matters. A failure to WRITE the flag while the value is already right is not a problem
            // worth telling a player about.
            return read(url)
        }
        return read(url)
    }

    /// What the file system says right now.
    public static func read(_ url: URL) -> State {
        do {
            let values = try url.resourceValues(forKeys: [.isExcludedFromBackupKey])
            guard let excluded = values.isExcludedFromBackup else {
                // Absent means the flag was never set, which on iOS means *not excluded*. Said as a
                // fact rather than guessed: the absence of an exclusion is an inclusion.
                return .included
            }
            return excluded ? .excluded : .included
        } catch {
            return .unknown("\(error)")
        }
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
