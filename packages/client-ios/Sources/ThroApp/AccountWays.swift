import ThroNet

/// One kind of way into an account.
public enum WayIn: String, CaseIterable, Sendable {
    case apple, google, passkey

    public var title: String {
        switch self {
        case .apple: return "Sign in with Apple"
        case .google: return "Sign in with Google"
        case .passkey: return "Passkey"
        }
    }
}

/// The ways into an account as the account screen shows them (PD-102).
///
/// **The screen used to show a count and three buttons that never changed.** The founder added a passkey, Apple and
/// Google, and the page looked the same afterwards — one sentence went from "two ways" to "three" — so there was no way
/// to tell that anything had been kept. It had been, every time. Now each way held is a row with its name, and only
/// what is missing is offered: Apple and Google once each, and a passkey always, because every phone keeps its own.
public struct WaysIn: Equatable, Sendable {
    /// The ways held, in a fixed order, each once.
    public let held: [WayIn]
    /// How many credentials there are, which can be more than `held` — two passkeys on two phones are two.
    public let count: Int

    public init(profile: Profile) {
        let kinds = Set(profile.ways ?? [])
        held = WayIn.allCases.filter { kinds.contains($0.rawValue) }
        count = profile.credentials ?? max(held.count, 1)
    }

    public func has(_ way: WayIn) -> Bool { held.contains(way) }

    /// What to offer to add. A profile from an older server names no ways, and then everything is offered, as before.
    public func offers(googleConfigured: Bool) -> [WayIn] {
        WayIn.allCases.filter { way in
            switch way {
            case .passkey: return true
            case .apple: return !has(.apple)
            case .google: return googleConfigured && !has(.google)
            }
        }
    }
}
