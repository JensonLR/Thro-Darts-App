import Foundation
import Security

/// Where the session lives between launches. The refresh token is a credential; it belongs in the
/// keychain and nowhere a backup or a debugger reads as plain text.
public protocol SessionStore: Sendable {
    func load() -> Session?
    func save(_ session: Session)
    func clear()
}

/// The app's: one generic-password item in the app's own keychain, this device only, never in a
/// backup that could restore it to another phone (`kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`).
public struct KeychainSessionStore: SessionStore {
    private let service: String
    private let account = "session"

    public init(service: String = "app.thro.darts.session") { self.service = service }

    public func load() -> Session? {
        var query = base
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var out: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &out) == errSecSuccess, let data = out as? Data else { return nil }
        return try? JSONDecoder().decode(Session.self, from: data)
    }

    public func save(_ session: Session) {
        guard let data = try? JSONEncoder().encode(session) else { return }
        var item = base
        item[kSecValueData as String] = data
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let status = SecItemAdd(item as CFDictionary, nil)
        if status == errSecDuplicateItem {
            SecItemUpdate(base as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        }
    }

    public func clear() { SecItemDelete(base as CFDictionary) }

    private var base: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: account]
    }
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
