import Foundation
import Security

/// Secure storage for the auth token and the cached identity (Android `TokenManager`).
/// The rest of the app never touches the Keychain directly; it goes through this.
protocol TokenStore: AnyObject, Sendable {
    func token() -> String?
    func saveToken(_ token: String)

    func userId() -> String?
    func saveUserId(_ userId: String)

    func userName() -> String?
    func saveUserName(_ name: String)

    func userEmail() -> String?
    func saveUserEmail(_ email: String)

    /// Session loss: drop the dead token but keep who the user is, so the
    /// account's lists stay visible until they sign in again.
    func clearToken()

    /// Explicit sign-out: wipe every field, name and email included, or the
    /// next account inherits them.
    func clear()
}

/// Keychain-backed `TokenStore`: one generic-password item per field, all under
/// `service` (the bundle id). `clear()` deletes only these four accounts, so other
/// Keychain items under the same service (a future PIN store) survive a sign-out,
/// just as Android keeps the session and the PIN in separate prefs files.
final class KeychainTokenStore: TokenStore, @unchecked Sendable {
    enum Account {
        static let authToken = "auth_token"
        static let userId = "user_id"
        static let userName = "user_name"
        static let userEmail = "user_email"
        static let all = [authToken, userId, userName, userEmail]
    }

    static let defaultService = Bundle.main.bundleIdentifier ?? "com.babegetthis.ios"

    let service: String

    init(service: String = KeychainTokenStore.defaultService) {
        self.service = service
    }

    func token() -> String? { read(Account.authToken) }
    func saveToken(_ token: String) { write(Account.authToken, token) }

    func userId() -> String? { read(Account.userId) }
    func saveUserId(_ userId: String) { write(Account.userId, userId) }

    func userName() -> String? { read(Account.userName) }
    func saveUserName(_ name: String) { write(Account.userName, name) }

    func userEmail() -> String? { read(Account.userEmail) }
    func saveUserEmail(_ email: String) { write(Account.userEmail, email) }

    func clearToken() { delete(Account.authToken) }

    func clear() {
        for account in Account.all {
            delete(account)
        }
    }

    // MARK: - Keychain

    private func baseQuery(_ account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }

    // An unreadable item (missing, or bytes that aren't UTF-8) reads as nil:
    // losing the session is cheap compared with an app that fails every launch.
    private func read(_ account: String) -> String? {
        var query = baseQuery(account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data
        else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private func write(_ account: String, _ value: String) {
        let data = Data(value.utf8)
        let attributes: [String: Any] = [kSecValueData as String: data]
        let status = SecItemUpdate(baseQuery(account) as CFDictionary, attributes as CFDictionary)
        guard status == errSecItemNotFound else { return }
        var item = baseQuery(account)
        item[kSecValueData as String] = data
        // Readable by background refreshes after the first unlock, never restored
        // to another device (Android excludes these prefs from backup).
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemAdd(item as CFDictionary, nil)
    }

    private func delete(_ account: String) {
        SecItemDelete(baseQuery(account) as CFDictionary)
    }
}

/// In-memory `TokenStore` for previews, sample data and tests
/// (Android's `inMemoryTokenManager`).
final class InMemoryTokenStore: TokenStore, @unchecked Sendable {
    private let lock = NSLock()
    private var values: [String: String] = [:]

    init() {}

    func token() -> String? { get(KeychainTokenStore.Account.authToken) }
    func saveToken(_ token: String) { set(KeychainTokenStore.Account.authToken, token) }

    func userId() -> String? { get(KeychainTokenStore.Account.userId) }
    func saveUserId(_ userId: String) { set(KeychainTokenStore.Account.userId, userId) }

    func userName() -> String? { get(KeychainTokenStore.Account.userName) }
    func saveUserName(_ name: String) { set(KeychainTokenStore.Account.userName, name) }

    func userEmail() -> String? { get(KeychainTokenStore.Account.userEmail) }
    func saveUserEmail(_ email: String) { set(KeychainTokenStore.Account.userEmail, email) }

    func clearToken() {
        lock.withLock { values[KeychainTokenStore.Account.authToken] = nil }
    }

    func clear() {
        lock.withLock { values.removeAll() }
    }

    private func get(_ key: String) -> String? {
        lock.withLock { values[key] }
    }

    private func set(_ key: String, _ value: String) {
        lock.withLock { values[key] = value }
    }
}
