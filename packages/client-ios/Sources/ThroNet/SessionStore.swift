import Foundation
import Security

/// Where the session lives between launches. The refresh token is a credential; it belongs in the
/// keychain and nowhere a backup or a debugger reads as plain text.
public protocol SessionStore: Sendable {
    func load() -> Session?
    func save(_ session: Session)
    func clear()
}

/// One generic-password item in the app's own keychain, this device only, never in a backup that
/// could restore it to another phone (`kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`). The
/// session is one of these and the profile cache is another; the keychain code is written once.
struct KeychainItem: Sendable {
    let service: String
    let account: String

    func load() -> Data? {
        var query = base
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var out: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &out) == errSecSuccess else { return nil }
        return out as? Data
    }

    func save(_ data: Data) {
        var item = base
        item[kSecValueData as String] = data
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        if SecItemAdd(item as CFDictionary, nil) == errSecDuplicateItem {
            SecItemUpdate(base as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        }
    }

    func clear() { SecItemDelete(base as CFDictionary) }

    private var base: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: account]
    }
}

/// The app's session store: one keychain item.
public struct KeychainSessionStore: SessionStore {
    private let item: KeychainItem

    public init(service: String = "app.thro.darts.session") { item = KeychainItem(service: service, account: "session") }

    public func load() -> Session? { item.load().flatMap { try? JSONDecoder().decode(Session.self, from: $0) } }
    public func save(_ session: Session) { if let data = try? JSONEncoder().encode(session) { item.save(data) } }
    public func clear() { item.clear() }
}

/// Tests, and previews: a session that lives as long as the object.
public final class MemorySessionStore: SessionStore, @unchecked Sendable {
    private let lock = NSLock()
    private var held: Session?
    public init(_ initial: Session? = nil) { held = initial }
    public func load() -> Session? { lock.withLock { held } }
    public func save(_ session: Session) { lock.withLock { held = session } }
    public func clear() { lock.withLock { held = nil } }
}

/// Who this phone was last told is signed in on it.
///
/// **Why it exists.** The founder, on a cold start: *"Loaded me to home screen and when i checked
/// profile tab it said checking."* Knowing who is signed in took a round trip to a free server that
/// sleeps, so a signed-in person was shown as nobody for up to a minute — and offline, in a pub,
/// for as long as the signal stayed away. Offline-first means the phone already knows who you are.
///
/// **It is a cache, never an authority.** The held session decides whether anybody is signed in and
/// the server decides who; this only lets the phone say it at once. It is read only for the account
/// the session names, it is corrected the moment the server answers, and it goes with the session.
public protocol ProfileCache: Sendable {
    func load() -> Profile?
    func save(_ profile: Profile)
    func clear()
}

/// The app's: beside the session in the keychain. A name and an age band are about a person, and
/// the keychain is where this app keeps what is about a person — not `UserDefaults`, which is plain
/// text in the app's container and travels in a backup.
public struct KeychainProfileCache: ProfileCache {
    private let item: KeychainItem

    public init(service: String = "app.thro.darts.profile") { item = KeychainItem(service: service, account: "profile") }

    public func load() -> Profile? { item.load().flatMap { try? JSONDecoder().decode(Profile.self, from: $0) } }
    public func save(_ profile: Profile) { if let data = try? JSONEncoder().encode(profile) { item.save(data) } }
    public func clear() { item.clear() }
}

/// Tests: a cache that lives as long as the object.
public final class MemoryProfileCache: ProfileCache, @unchecked Sendable {
    private let lock = NSLock()
    private var held: Profile?
    public init(_ initial: Profile? = nil) { held = initial }
    public func load() -> Profile? { lock.withLock { held } }
    public func save(_ profile: Profile) { lock.withLock { held = profile } }
    public func clear() { lock.withLock { held = nil } }
}
