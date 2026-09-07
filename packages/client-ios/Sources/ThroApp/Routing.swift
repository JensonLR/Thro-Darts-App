import Foundation
import SwiftUI
import ThroDesign
import ThroJournal

// One address for every place in THRØ that something outside the app can name.
//
// **A route is an address, not the navigation state.** That distinction is the whole design, and it
// is why this is a new type rather than a rewrite of the two enums that already exist. `ClubRoute`
// and `PlayFlow.Step` are state machines: `Step` carries a live `MatchSession` as an associated
// value, because a match being scored *is* an object, not a string. Forcing those to be
// serialisable so a URL could name any of their cases would make both worse and would let an
// incoming link drop somebody into the middle of a flow they never started.
//
// What an address may name is deliberately smaller: the five tabs, Settings, a match, a person, and
// a club. Everything a widget, a Live Activity, a Spotlight result, an App Intent or a shared link
// can point at, and nothing else.
//
// **The shapes are ADR-011's**, which fixed them before there was anything to serve them:
// `/e/{eventId}`, `/m/{matchId}`, `/p/{playerHandle}`. The same parser reads both the custom scheme
// this build ships and the `https://` paths a domain would serve later, so adopting universal links
// is a hosting decision rather than a code one — and, per the same ADR, the scheme is ASCII: `Ø`
// cannot appear in a URL scheme.

/// Somewhere in THRØ that can be named from outside it.
///
/// The cases and nothing else. Everything that reads or writes one lives in the extension below —
/// not for tidiness, but because `tools/check_screens_reachable.py` reads an enum's body to find
/// the cases it must see assigned, and a `switch` written inside the declaration puts
/// `case let .tab(tab)` in that body. It reported a route named `let`, which is the check working:
/// a route enum whose body is only routes is the shape it can reason about.
public enum ThroRoute: Equatable, Hashable, Sendable {
    /// One of the five tabs.
    case tab(BottomBar.Tab)
    case settings
    /// A match on this device, opened where it left off.
    case match(MatchId)
    /// Somebody this device knows, by their local person id.
    case person(String)
    /// A club, league or tournament this device keeps.
    case club(String)
    /// Start a new match. An action rather than a place, and an address all the same: it is what a
    /// Shortcut, the Action Button and a widget all want to name, and there is nowhere else to send
    /// them that means the same thing.
    case newMatch
    /// The match this phone walked away from, whichever it is.
    ///
    /// Late-bound on purpose: a Shortcut saved in March must still mean *the one I am in the middle
    /// of* in December, so the address names the question and the app answers it. Naming a match id
    /// would freeze the answer at the moment the Shortcut was made.
    case continueLatest
}

extension ThroRoute {
    /// The scheme this build registers. ASCII, and not the product name, for ADR-011's reasons.
    public static let scheme = "thro"

    /// What a segment may contain unescaped. Deliberately narrower than `.urlPathAllowed`, which
    /// permits `/`: an identifier carrying a slash would otherwise forge a second path segment and
    /// name a different place than the one being written down.
    private static let idAllowed = CharacterSet(charactersIn:
        "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")

    /// The link that names this place. The inverse of `init(url:)`, and tested as one.
    ///
    /// **The identifier is escaped, not trusted.** A person's id is generated here, but a club's
    /// comes from a database this device's owner can edit, and a match id is read back off disk.
    /// Interpolating one raw and letting `URL(string:)` refuse it would turn an awkward id into a
    /// link to Home — a wrong address that looks like a working one.
    public var url: URL {
        func escape(_ raw: String) -> String {
            raw.addingPercentEncoding(withAllowedCharacters: Self.idAllowed) ?? ""
        }
        let path: String
        switch self {
        case let .tab(tab): path = "tab/\(tab.rawValue)"
        case .settings: path = "settings"
        case let .match(id): path = "m/\(escape(id.value))"
        case let .person(id): path = "p/\(escape(id))"
        case let .club(id): path = "e/\(escape(id))"
        case .newMatch: path = "new"
        case .continueLatest: path = "continue"
        }
        // Every path above is now percent-encoded, so this cannot fail. The fallback exists because
        // a force-unwrap in a URL builder is how a crash reaches a player through a shared link.
        return URL(string: "\(Self.scheme)://\(path)") ?? URL(fileURLWithPath: "/")
    }

    /// The place a URL names, or nil when it names nothing this app has.
    ///
    /// Accepts `thro://m/ID` and `https://any.host/m/ID` alike, because the path grammar is the
    /// contract and the scheme is not. An unknown path is nil rather than a guess: opening the app
    /// somewhere arbitrary because a link was malformed is worse than not opening it at all.
    public init?(url: URL) {
        guard let parts = Self.segments(of: url), let head = parts.first else { return nil }
        let rest = Array(parts.dropFirst())
        switch (head, rest.first) {
        case ("tab", let name?):
            guard let tab = BottomBar.Tab(rawValue: name) else { return nil }
            self = .tab(tab)
        case ("settings", _):
            self = .settings
        case ("new", _):
            self = .newMatch
        case ("continue", _):
            self = .continueLatest
        case ("m", let id?), ("match", let id?):
            guard !id.isEmpty else { return nil }
            self = .match(MatchId(id))
        case ("p", let id?), ("person", let id?):
            guard !id.isEmpty else { return nil }
            self = .person(id)
        case ("e", let id?), ("club", let id?):
            guard !id.isEmpty else { return nil }
            self = .club(id)
        default:
            return nil
        }
    }

    /// The path segments a URL carries, however it is shaped.
    ///
    /// `thro://m/ID` puts `m` in the host and `/ID` in the path; `https://host/m/ID` puts both in
    /// the path. Dropping empty segments absorbs the leading slash and any trailing one.
    ///
    /// **Split the ENCODED path, then decode each segment — never the other way round.** The first
    /// version read `components.path`, which is already decoded, so an identifier written as
    /// `c1%2F..%2Fm%2F7F2A` came back as `c1/../m/7F2A` and split into four segments: the escaping
    /// done when the link was written was undone before the link was read, and an id containing a
    /// slash could name somewhere else entirely. Caught by the test that asserts a slash in an
    /// identifier cannot forge a path.
    private static func segments(of url: URL) -> [String]? {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }
        func decoded(_ raw: Substring) -> String { raw.removingPercentEncoding ?? String(raw) }
        var parts: [String] = []
        if url.scheme?.lowercased() == scheme,
           let host = components.percentEncodedHost, !host.isEmpty {
            parts.append(decoded(Substring(host)))
        }
        parts.append(contentsOf: components.percentEncodedPath.split(separator: "/").map(decoded))
        return parts.isEmpty ? nil : parts
    }
}

/// Holds the place an incoming link asked for until a screen can go there.
///
/// A link can arrive before the app has finished launching, while the opening is still playing, or
/// while a match is being scored. None of those is a moment to change what is on the screen, so the
/// route waits here and the root view takes it when it can. `take()` rather than a plain read,
/// because a route must be applied exactly once: a second application would send a player back to
/// the same place every time the view re-evaluated.
public final class ThroRouter: ObservableObject {
    /// The one router.
    ///
    /// A singleton is worth justifying. An `AppIntent` — "Hey Siri, start a match", the Action
    /// Button, a Shortcut — runs outside any view and has no way to reach a `@StateObject`, and
    /// neither has a Spotlight result's handler. The alternative is threading a router through
    /// every entry point the system can invoke, which is the same object with more places to get it
    /// wrong. The state it holds is one optional route.
    public static let shared = ThroRouter()

    @Published public private(set) var pending: ThroRoute?

    public init() {}

    /// Records a link, if it names somewhere. An unrecognised URL is ignored in silence — there is
    /// no honest thing to say to a player about a link they did not knowingly follow.
    public func open(_ url: URL) {
        guard let route = ThroRoute(url: url) else { return }
        pending = route
    }

    public func go(_ route: ThroRoute) { pending = route }

    /// The waiting route, cleared as it is handed over.
    public func take() -> ThroRoute? {
        defer { pending = nil }
        return pending
    }
}
