import Foundation

// The link contract, in the module the app shares with its extensions.
//
// **Why it is here and not with the routes.** `ThroRoute` lives in `ThroApp`, at the top of the
// graph, because it names tabs and screens. But a Live Activity's `widgetURL` is built in
// `ThroPlay`, and a widget's is built in an extension — both below `ThroApp`, neither able to see
// it. The alternative was for each of them to write `"thro://m/" + id` for itself, which is two
// more copies of an escaping rule that has already been wrong once.
//
// So the scheme and the escaping live at the bottom, where everything can reach them, and
// `ThroRoute` is built on top of this rather than beside it. One implementation, whoever is asking.

public enum ThroLink {
    /// ASCII, and not the product name: ADR-011 fixes both, because `Ø` cannot appear in a URL
    /// scheme and a rename must not invalidate every link ever shared.
    public static let scheme = "thro"

    /// What a path segment may contain unescaped.
    ///
    /// Narrower than `.urlPathAllowed`, which permits `/`. An identifier carrying a slash would
    /// otherwise forge a second path segment and name a different place than the one being written
    /// down — and identifiers here come off disk and out of a database the device's owner can edit.
    static let allowed = CharacterSet(charactersIn:
        "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")

    public static func escape(_ raw: String) -> String {
        raw.addingPercentEncoding(withAllowedCharacters: allowed) ?? ""
    }

    /// A link to one path, already escaped. Never force-unwrapped: a crash reaching a player
    /// through a shared link is the worst way to learn an identifier was unusual.
    public static func url(path: String) -> URL {
        URL(string: "\(scheme)://\(path)") ?? URL(fileURLWithPath: "/")
    }

    /// ADR-011's `/m/{matchId}`.
    public static func match(_ id: String) -> URL { url(path: "m/\(escape(id))") }
}
