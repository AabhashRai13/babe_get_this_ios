import Security
import XCTest
@testable import BabeGetThis

// Port of Android's TokenManagerTest against the real Keychain. Each test uses its
// own service so runs never see each other's (or the app's) items.
final class TokenStoreTests: XCTestCase {
    private var service = ""
    private var tokenStore: KeychainTokenStore!

    override func setUp() {
        super.setUp()
        service = "com.babegetthis.ios.tests.TokenStoreTests-\(UUID().uuidString)"
        tokenStore = KeychainTokenStore(service: service)
        tokenStore.clear()
    }

    override func tearDown() {
        let everything: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
        ]
        SecItemDelete(everything as CFDictionary)
        super.tearDown()
    }

    func testAFreshStoreHoldsNothing() {
        XCTAssertNil(tokenStore.token())
        XCTAssertNil(tokenStore.userId())
        XCTAssertNil(tokenStore.userName())
        XCTAssertNil(tokenStore.userEmail())
    }

    func testEveryFieldRoundTrips() {
        tokenStore.saveToken("token")
        tokenStore.saveUserId("u1")
        tokenStore.saveUserName("Aabhash")
        tokenStore.saveUserEmail("a@b.c")

        XCTAssertEqual(tokenStore.token(), "token")
        XCTAssertEqual(tokenStore.userId(), "u1")
        XCTAssertEqual(tokenStore.userName(), "Aabhash")
        XCTAssertEqual(tokenStore.userEmail(), "a@b.c")
    }

    func testSavingAgainOverwrites() {
        tokenStore.saveToken("first")
        tokenStore.saveToken("second")

        XCTAssertEqual(tokenStore.token(), "second")
    }

    // The logout bug this app fixed once already: clear() must take the name and
    // email with it, not just the token, or the next account inherits them.
    func testClearWipesEveryField() {
        tokenStore.saveToken("token")
        tokenStore.saveUserId("u1")
        tokenStore.saveUserName("Aabhash")
        tokenStore.saveUserEmail("a@b.c")

        tokenStore.clear()

        XCTAssertNil(tokenStore.token())
        XCTAssertNil(tokenStore.userId())
        XCTAssertNil(tokenStore.userName())
        XCTAssertNil(tokenStore.userEmail())
    }

    // Session loss: only the token goes; who the user is stays.
    func testClearTokenKeepsTheIdentity() {
        tokenStore.saveToken("token")
        tokenStore.saveUserId("u1")
        tokenStore.saveUserName("Aabhash")
        tokenStore.saveUserEmail("a@b.c")

        tokenStore.clearToken()

        XCTAssertNil(tokenStore.token())
        XCTAssertEqual(tokenStore.userId(), "u1")
        XCTAssertEqual(tokenStore.userName(), "Aabhash")
        XCTAssertEqual(tokenStore.userEmail(), "a@b.c")
    }

    func testASecondInstanceSeesPersistedValues() {
        tokenStore.saveToken("token")

        let reopened = KeychainTokenStore(service: service)

        XCTAssertEqual(reopened.token(), "token")
    }

    // Android keeps the session and the device PIN in separate prefs files so that
    // clearing the session on logout cannot take the PIN with it. Here they may share
    // the bundle-id service, so clear() must delete only its own accounts.
    func testClearingTheSessionLeavesOtherItemsInTheServiceAlone() {
        XCTAssertEqual(addRawItem(account: "pin_hash", data: Data("pin-hash".utf8)), errSecSuccess)
        tokenStore.saveToken("token")

        tokenStore.clear()

        XCTAssertEqual(readRawItem(account: "pin_hash"), Data("pin-hash".utf8))
    }

    // Android: a store whose Keystore key is gone starts empty instead of crashing.
    // The Keychain counterpart is an item whose bytes can't be decoded.
    func testAnUnreadableItemReadsAsNilInsteadOfCrashing() {
        XCTAssertEqual(
            addRawItem(account: KeychainTokenStore.Account.authToken, data: Data([0xFF, 0xFE, 0xFD])),
            errSecSuccess
        )

        XCTAssertNil(KeychainTokenStore(service: service).token())
    }

    func testRestoreReadsEveryField() throws {
        tokenStore.saveToken("token")
        tokenStore.saveUserId("u1")

        XCTAssertEqual(try tokenStore.restore(), StoredIdentity(token: "token", userId: "u1"))
    }

    // Only a missing item is "no value". A locked Keychain (before the first unlock after a
    // reboot) must not read as a signed-out user.
    func testOnlyAMissingItemReadsAsNoValue() throws {
        XCTAssertNil(try KeychainTokenStore.value(status: errSecItemNotFound, result: nil))
        XCTAssertEqual(try KeychainTokenStore.value(status: errSecSuccess, result: Data("t".utf8) as NSData), "t")
        XCTAssertThrowsError(try KeychainTokenStore.value(status: errSecInteractionNotAllowed, result: nil)) { error in
            XCTAssertEqual(error as? TokenStoreError, .unavailable(errSecInteractionNotAllowed))
        }
        XCTAssertThrowsError(try KeychainTokenStore.value(status: errSecIO, result: nil))
    }

    func testTheDefaultServiceIsTheBundleId() {
        XCTAssertEqual(KeychainTokenStore().service, Bundle.main.bundleIdentifier)
    }

    // MARK: - Helpers

    private func addRawItem(account: String, data: Data) -> OSStatus {
        let item: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
        ]
        return SecItemAdd(item as CFDictionary, nil)
    }

    private func readRawItem(account: String) -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess else { return nil }
        return result as? Data
    }
}
