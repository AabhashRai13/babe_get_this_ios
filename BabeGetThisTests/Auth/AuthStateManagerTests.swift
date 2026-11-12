import UIKit
import XCTest
@testable import BabeGetThis

// Port of Android's AuthStateManagerTest. Android mocks TokenManager for the first
// group; here every test runs against InMemoryTokenStore and checks what it stored.
final class AuthStateManagerTests: XCTestCase {
    private var tokens: InMemoryTokenStore!
    private var manager: AuthStateManager!

    override func setUp() {
        super.setUp()
        tokens = InMemoryTokenStore()
        manager = AuthStateManager(tokenStore: tokens)
    }

    func testStartsInLoadingBeforeInitialize() {
        XCTAssertEqual(manager.authState, .loading)
    }

    func testInitializeWithASavedTokenAndUserIdBecomesAuthenticated() {
        tokens.saveToken("token-123")
        tokens.saveUserId("u1")

        manager.initialize()

        XCTAssertEqual(manager.authState, .authenticated(userId: "u1"))
    }

    func testInitializeWithAUserIdButNoTokenBecomesSessionExpired() {
        tokens.saveUserId("u1")

        manager.initialize()

        XCTAssertEqual(manager.authState, .sessionExpired(userId: "u1"))
    }

    func testInitializeWithNeitherTokenNorUserIdBecomesUnauthenticated() {
        manager.initialize()

        XCTAssertEqual(manager.authState, .unauthenticated)
    }

    func testInitializeWithAMissingUserIdBecomesUnauthenticated() {
        tokens.saveToken("token-123")

        manager.initialize()

        XCTAssertEqual(manager.authState, .unauthenticated)
    }

    // iOS only: before the first unlock after a reboot the Keychain answers
    // errSecInteractionNotAllowed. That is "can't read yet", not "signed out".
    func testALockedTokenStoreKeepsLoadingInsteadOfSigningOut() {
        tokens.saveToken("token-123")
        tokens.saveUserId("u1")
        tokens.isLocked = true

        manager.initialize()

        XCTAssertEqual(manager.authState, .loading)
        XCTAssertNil(manager.dataOwnerId)
    }

    func testInitializeRetriesWhenProtectedDataBecomesAvailable() {
        let center = NotificationCenter()
        let manager = AuthStateManager(tokenStore: tokens, notificationCenter: center)
        tokens.saveToken("token-123")
        tokens.saveUserId("u1")
        tokens.saveUserName("Aabhash")
        tokens.isLocked = true
        manager.initialize()

        tokens.isLocked = false
        center.post(name: UIApplication.protectedDataDidBecomeAvailableNotification, object: nil)

        XCTAssertEqual(manager.authState, .authenticated(userId: "u1"))
        XCTAssertEqual(manager.userName, "Aabhash")
    }

    func testALoginWhileWaitingForUnlockIsNotOverwrittenByTheRetry() {
        let center = NotificationCenter()
        let manager = AuthStateManager(tokenStore: tokens, notificationCenter: center)
        tokens.isLocked = true
        manager.initialize()
        tokens.isLocked = false
        manager.login(token: "t", userId: "u2", userName: "B", userEmail: "b@c.d")

        tokens.clear()
        center.post(name: UIApplication.protectedDataDidBecomeAvailableNotification, object: nil)

        XCTAssertEqual(manager.authState, .authenticated(userId: "u2"))
    }

    func testLoginPersistsAllFieldsAndBecomesAuthenticated() {
        manager.login(token: "token-123", userId: "u1", userName: "Ann", userEmail: "a@b.com")

        XCTAssertEqual(tokens.token(), "token-123")
        XCTAssertEqual(tokens.userId(), "u1")
        XCTAssertEqual(tokens.userName(), "Ann")
        XCTAssertEqual(tokens.userEmail(), "a@b.com")
        XCTAssertEqual(manager.authState, .authenticated(userId: "u1"))
    }

    func testLogoutClearsStorageAndBecomesUnauthenticated() {
        manager.login(token: "token-123", userId: "u1", userName: "Ann", userEmail: "a@b.com")

        manager.logout()

        XCTAssertNil(tokens.token())
        XCTAssertNil(tokens.userId())
        XCTAssertNil(tokens.userName())
        XCTAssertNil(tokens.userEmail())
        XCTAssertEqual(manager.authState, .unauthenticated)
    }

    // MARK: - The helpers that keep the repo from reaching around this class

    func testUpdateNameWritesOnlyTheCachedName() {
        manager.updateName("New Name")

        XCTAssertEqual(tokens.userName(), "New Name")
        XCTAssertNil(tokens.token())
        XCTAssertNil(tokens.userId())
        XCTAssertNil(tokens.userEmail())
    }

    func testCurrentEmailReturnsTheCachedEmail() {
        tokens.saveUserEmail("a@b.com")

        XCTAssertEqual(manager.currentEmail(), "a@b.com")
    }

    func testCurrentEmailReturnsNilWhenNothingIsCached() {
        XCTAssertNil(manager.currentEmail())
    }

    // MARK: - refreshToken

    // Supabase rotates the access token in the background. Only the token is
    // persisted: authState and the cached name/email must not churn, or the UI
    // would flicker on every silent refresh.
    func testRefreshTokenPersistsOnlyTheToken() {
        manager.login(token: "old-token", userId: "u1", userName: "Aabhash", userEmail: "a@b.c")

        manager.refreshToken("new-token")

        XCTAssertEqual(manager.authState, .authenticated(userId: "u1"))
        XCTAssertEqual(manager.userName, "Aabhash")
        XCTAssertEqual(manager.userEmail, "a@b.c")
    }

    func testARefreshedTokenIsWhatLaterReadsSee() {
        manager.login(token: "old-token", userId: "u1", userName: "Aabhash", userEmail: "a@b.c")

        manager.refreshToken("new-token")

        XCTAssertEqual(tokens.token(), "new-token")
    }

    // MARK: - Round-trips against a real backing store

    func testInitializeRestoresWhatLoginPersisted() {
        AuthStateManager(tokenStore: tokens).login(token: "t", userId: "u1", userName: "Aabhash", userEmail: "a@b.c")

        let reopened = AuthStateManager(tokenStore: tokens)
        reopened.initialize()

        XCTAssertEqual(reopened.authState, .authenticated(userId: "u1"))
        XCTAssertEqual(reopened.userName, "Aabhash")
        XCTAssertEqual(reopened.userEmail, "a@b.c")
    }

    // The logout bug this app already fixed once: a lingering session must not
    // survive into the next launch.
    func testInitializeAfterLogoutStaysUnauthenticated() {
        manager.login(token: "t", userId: "u1", userName: "Aabhash", userEmail: "a@b.c")
        manager.logout()

        let reopened = AuthStateManager(tokenStore: tokens)
        reopened.initialize()

        XCTAssertEqual(reopened.authState, .unauthenticated)
        XCTAssertNil(reopened.userName)
        XCTAssertNil(reopened.userEmail)
    }

    func testSwitchingAccountsReplacesTheCachedIdentity() {
        manager.login(token: "t1", userId: "u1", userName: "First", userEmail: "first@b.c")

        manager.login(token: "t2", userId: "u2", userName: "Second", userEmail: "second@b.c")

        XCTAssertEqual(manager.authState, .authenticated(userId: "u2"))
        XCTAssertEqual(manager.userName, "Second")
        XCTAssertEqual(manager.userEmail, "second@b.c")
    }

    // MARK: - Session expiry (Android decision 008)
    //
    // A lost session must not look like a sign-out: the account's lists stay on
    // screen, so the user id has to survive while the token goes.

    func testExpireSessionKeepsTheUserIdAndClearsOnlyTheToken() {
        manager.login(token: "t", userId: "u1", userName: "Aabhash", userEmail: "a@b.c")

        manager.expireSession()

        XCTAssertEqual(manager.authState, .sessionExpired(userId: "u1"))
        XCTAssertNil(tokens.token())
        XCTAssertEqual(tokens.userId(), "u1")
        XCTAssertEqual(manager.userName, "Aabhash")
    }

    func testAnExpiredSessionIsStillExpiredAfterARestart() {
        let first = AuthStateManager(tokenStore: tokens)
        first.login(token: "t", userId: "u1", userName: "Aabhash", userEmail: "a@b.c")
        first.expireSession()

        let reopened = AuthStateManager(tokenStore: tokens)
        reopened.initialize()

        XCTAssertEqual(reopened.authState, .sessionExpired(userId: "u1"))
    }

    func testExpireSessionIsANoOpWhenNoUserIdIsStored() {
        manager.initialize()

        manager.expireSession()

        XCTAssertEqual(manager.authState, .unauthenticated)
    }

    // Supabase can report the lost session before the app has called initialize().
    // The state must stay Loading and let initialize() derive SessionExpired from storage.
    func testExpireSessionBeforeInitializeLeavesLoadingAndInitializeFindsTheExpiredSession() {
        AuthStateManager(tokenStore: tokens).login(token: "t", userId: "u1", userName: "Aabhash", userEmail: "a@b.c")

        manager.expireSession()
        XCTAssertEqual(manager.authState, .loading)

        manager.initialize()
        XCTAssertEqual(manager.authState, .sessionExpired(userId: "u1"))
    }

    // An explicit sign-out clears Supabase's session too, which fires the same
    // "session lost" event. Whichever arrives first, sign-out must win.
    func testExplicitLogoutWinsWhenTheSessionEventArrivesFirst() {
        manager.login(token: "t", userId: "u1", userName: "Aabhash", userEmail: "a@b.c")

        manager.expireSession()
        manager.logout()

        XCTAssertEqual(manager.authState, .unauthenticated)
    }

    func testExplicitLogoutWinsWhenTheSessionEventArrivesLast() {
        manager.login(token: "t", userId: "u1", userName: "Aabhash", userEmail: "a@b.c")

        manager.logout()
        manager.expireSession()

        XCTAssertEqual(manager.authState, .unauthenticated)
    }

    // The real race: Supabase reports the lost session on a background thread while
    // the explicit sign-out runs on the main actor. Here the sign-out lands right in
    // the middle of expireSession, after it read the user id and before it set the
    // state. Without one lock over both, the stale write wins and a signed-out user
    // ends up "session expired" as the old account.
    func testAnExplicitSignOutRacingTheSessionLostEventStillEndsSignedOut() {
        let hooked = UserIdHookTokenStore()
        let manager = AuthStateManager(tokenStore: hooked)
        manager.login(token: "t", userId: "u1", userName: "Aabhash", userEmail: "a@b.c")
        let signOut = DispatchGroup()
        hooked.onUserIdRead = {
            signOut.enter()
            Thread {
                manager.logout()
                signOut.leave()
            }.start()
            _ = signOut.wait(timeout: .now() + 0.2) // unlocked, the sign-out finishes in here
        }

        manager.expireSession()
        signOut.wait()

        XCTAssertEqual(manager.authState, .unauthenticated)
    }

    // MARK: - Data owner: whose lists the device shows

    func testDataOwnerIdIsTheUserIdWhileSignedInOrExpiredAndNilOtherwise() {
        XCTAssertNil(manager.dataOwnerId) // Loading

        manager.initialize()
        XCTAssertNil(manager.dataOwnerId) // Unauthenticated

        manager.login(token: "t", userId: "u1", userName: "Aabhash", userEmail: "a@b.c")
        XCTAssertEqual(manager.dataOwnerId, "u1")

        manager.expireSession()
        XCTAssertEqual(manager.dataOwnerId, "u1")
    }

    // Server work (push, share) needs a live token, not just a known user: after a
    // lost session a push would only 401.
    func testLiveSessionUserIdIsTheUserIdOnlyWhileTheSessionIsLive() {
        manager.initialize()
        XCTAssertNil(manager.liveSessionUserId)

        manager.login(token: "t", userId: "u1", userName: "Aabhash", userEmail: "a@b.c")
        XCTAssertEqual(manager.liveSessionUserId, "u1")

        manager.expireSession()
        XCTAssertNil(manager.liveSessionUserId)
    }

    func testDataOwnerSkipsLoadingAndEmitsOnlyWhenTheOwnerChanges() {
        let owners = Recorder<String?>()
        let subscription = manager.observeDataOwner { owners.append($0) }
        XCTAssertEqual(owners.values, []) // still Loading

        manager.initialize()
        XCTAssertEqual(owners.values, [nil])

        manager.login(token: "t", userId: "u1", userName: "Aabhash", userEmail: "a@b.c")
        XCTAssertEqual(owners.values, [nil, "u1"])

        manager.expireSession() // same owner: the lists on screen don't change
        XCTAssertEqual(owners.values, [nil, "u1"])

        manager.logout()
        XCTAssertEqual(owners.values, [nil, "u1", nil])
        subscription.cancel()
    }

    // Signing out (or deleting the account) takes the account's lists off the
    // phone, so the app returns to Welcome. A lost session keeps them, so it
    // must not count.
    func testSignOutsEmitsWhenAnAccountSignsOutNotWhenItsSessionExpires() {
        manager.initialize()
        let signOuts = Recorder<Int>()
        let subscription = manager.observeSignOuts { signOuts.append(1) }

        manager.login(token: "t", userId: "u1", userName: "Aabhash", userEmail: "a@b.c")
        manager.expireSession()
        XCTAssertEqual(signOuts.values.count, 0)

        manager.logout()
        XCTAssertEqual(signOuts.values.count, 1)

        manager.login(token: "t", userId: "u1", userName: "Aabhash", userEmail: "a@b.c")
        manager.logout()
        XCTAssertEqual(signOuts.values.count, 2)
        subscription.cancel()
    }

    func testSignOutsStaysQuietForAGuest() {
        let signOuts = Recorder<Int>()
        let subscription = manager.observeSignOuts { signOuts.append(1) }

        manager.initialize()
        manager.logout()

        XCTAssertEqual(signOuts.values.count, 0)
        subscription.cancel()
    }

    func testUpdateNameIsVisibleToALaterRead() {
        manager.login(token: "t", userId: "u1", userName: "Aabhash", userEmail: "a@b.c")

        manager.updateName("Renamed")

        XCTAssertEqual(manager.userName, "Renamed")
        XCTAssertEqual(tokens.userName(), "Renamed")
    }

    // MARK: - iOS-only: threading

    // Supabase reports a lost session on a background thread; SwiftUI observes authState and
    // expects view-driving state to change on the main actor.
    func testObservationChangesFromABackgroundThreadArePublishedOnMain() {
        manager.login(token: "t", userId: "u1", userName: "Aabhash", userEmail: "a@b.c")
        let changed = expectation(description: "authState change published")
        let onMain = Recorder<Bool>()
        withObservationTracking {
            _ = manager.authState
        } onChange: {
            onMain.append(Thread.isMainThread)
            changed.fulfill()
        }

        let manager = manager!
        Thread { manager.expireSession() }.start()
        wait(for: [changed], timeout: 2)

        XCTAssertEqual(onMain.values, [true])
        XCTAssertEqual(manager.authState, .sessionExpired(userId: "u1"))
    }

    // Handlers used to run under the lock: one that hopped to main synchronously deadlocked
    // against a main-thread login waiting for that lock.
    func testAHandlerThatHopsToMainDoesNotBlockAMainThreadTransition() {
        manager.login(token: "t", userId: "u1", userName: "Aabhash", userEmail: "a@b.c")
        let handlerRunning = DispatchSemaphore(value: 0)
        let hopped = expectation(description: "handler hopped to main")
        let subscription = manager.observeSignOuts {
            handlerRunning.signal()
            DispatchQueue.main.sync {}
            hopped.fulfill()
        }

        let manager = manager!
        Thread { manager.logout() }.start()
        XCTAssertEqual(handlerRunning.wait(timeout: .now() + 2), .success)
        manager.login(token: "t2", userId: "u2", userName: "B", userEmail: "b@c.d") // needs the lock
        wait(for: [hopped], timeout: 2)

        XCTAssertEqual(manager.authState, .authenticated(userId: "u2"))
        subscription.cancel()
    }

    func testHandlersSeeChangesInOrderEvenWhenAHandlerMakesAChange() {
        let owners = Recorder<String?>()
        manager.initialize()
        let first = manager.observeDataOwner { [manager] owner in
            if owner == "u1" { manager?.logout() } // a change made from inside a handler
        }
        let second = manager.observeDataOwner { owners.append($0) }

        manager.login(token: "t", userId: "u1", userName: "Aabhash", userEmail: "a@b.c")

        XCTAssertEqual(owners.values, [nil, "u1", nil])
        XCTAssertEqual(manager.authState, .unauthenticated)
        first.cancel()
        second.cancel()
    }

    // MARK: - iOS-only: the async-sequence wrappers and cancellation

    func testDataOwnerStreamDeliversTheSameSequence() async {
        var iterator = manager.dataOwner.makeAsyncIterator()

        manager.initialize()
        manager.login(token: "t", userId: "u1", userName: "Aabhash", userEmail: "a@b.c")
        manager.expireSession()
        manager.logout()

        let first = await iterator.next()
        let second = await iterator.next()
        let third = await iterator.next()
        XCTAssertEqual(first, .some(nil))
        XCTAssertEqual(second, .some("u1"))
        XCTAssertEqual(third, .some(nil))
    }

    func testACancelledSubscriptionHearsNothingMore() {
        let owners = Recorder<String?>()
        let subscription = manager.observeDataOwner { owners.append($0) }
        manager.initialize()

        subscription.cancel()
        manager.login(token: "t", userId: "u1", userName: "Aabhash", userEmail: "a@b.c")

        XCTAssertEqual(owners.values, [nil])
    }
}

/// Thread-safe list of everything a handler received.
private final class Recorder<Value: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: [Value] = []

    var values: [Value] { lock.withLock { stored } }

    func append(_ value: Value) {
        lock.withLock { stored.append(value) }
    }
}

/// InMemoryTokenStore that runs a hook (once) when the user id is read, so a test
/// can land another transition in the middle of expireSession.
private final class UserIdHookTokenStore: TokenStore, @unchecked Sendable {
    private let backing = InMemoryTokenStore()
    private let lock = NSLock()
    private var hook: (() -> Void)?

    var onUserIdRead: (() -> Void)? {
        get { lock.withLock { hook } }
        set { lock.withLock { hook = newValue } }
    }

    func token() -> String? { backing.token() }
    func saveToken(_ token: String) { backing.saveToken(token) }

    func userId() -> String? {
        let pending = lock.withLock {
            defer { hook = nil }
            return hook
        }
        pending?()
        // Like the Android test, report the id read before the sign-out landed.
        return pending == nil ? backing.userId() : "u1"
    }

    func saveUserId(_ userId: String) { backing.saveUserId(userId) }

    func userName() -> String? { backing.userName() }
    func saveUserName(_ name: String) { backing.saveUserName(name) }

    func userEmail() -> String? { backing.userEmail() }
    func saveUserEmail(_ email: String) { backing.saveUserEmail(email) }

    func clearToken() { backing.clearToken() }
    func clear() { backing.clear() }
}
