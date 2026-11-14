import AuthenticationServices
import XCTest
@testable import BabeGetThis

// MARK: - Fakes

/// The Google SDK: records the hashed nonce it was given and answers with `outcome`.
final class IdTokenFakeGoogleSheet: GoogleSignInSheet, @unchecked Sendable {
    private let lock = NSLock()
    private var recorded: [(clientID: String, hashedNonce: String)] = []
    var outcome: Result<GoogleSheetIdToken?, any Error> = .success(GoogleSheetIdToken(idToken: "google-id-token", nonceApplied: true))

    var calls: [(clientID: String, hashedNonce: String)] { lock.withLock { recorded } }

    @MainActor
    func idToken(clientID: String, hashedNonce: String) async throws -> GoogleSheetIdToken? {
        lock.withLock { recorded.append((clientID, hashedNonce)) }
        return try outcome.get()
    }
}

/// Supabase's id-token sign-in: records each call and answers with `result`.
final class IdTokenFakeRemote: AuthIdTokenRemote, @unchecked Sendable {
    struct Call: Equatable {
        let provider: IdTokenProvider
        let idToken: String
        let rawNonce: String?
    }

    private let lock = NSLock()
    private var recorded: [Call] = []
    var result: Result<AuthRemoteSession, any Error> = .success(
        AuthRemoteSession(accessToken: "access-id", user: AuthRemoteUser(id: "user-9", email: "ann@icloud.com", metadataName: nil)))

    var calls: [Call] { lock.withLock { recorded } }

    func signInWithIdToken(provider: IdTokenProvider, idToken: String, rawNonce: String?) async throws -> AuthRemoteSession {
        lock.withLock { recorded.append(Call(provider: provider, idToken: idToken, rawNonce: rawNonce)) }
        return try result.get()
    }
}

final class IdTokenFakeAppleAuth: LoginAppleAuthenticating, @unchecked Sendable {
    private let lock = NSLock()
    private var recorded: [AppleSignInCredential] = []
    var result: Result<AuthUser, AppError> = .success(AuthUser(id: "u1", email: "a@b.com", name: "Ann"))

    var calls: [AppleSignInCredential] { lock.withLock { recorded } }

    func signInWithApple(idToken: String, rawNonce: String, fullName: String?) async -> Result<AuthUser, AppError> {
        lock.withLock { recorded.append(AppleSignInCredential(idToken: idToken, rawNonce: rawNonce, fullName: fullName)) }
        return result
    }
}

private extension Result {
    var failure: Failure? {
        if case .failure(let error) = self { error } else { nil }
    }
}

// MARK: - Tests (AUTH-05 Google, AUTH-06 Apple; port of Android GoogleSignInTest)

@MainActor
final class IdTokenSignInTests: XCTestCase {
    private var sheet: IdTokenFakeGoogleSheet!
    private var path: AuthRepositoryFakePathSource!
    private var remote: AuthRepositoryFakeRemote!
    private var idTokenRemote: IdTokenFakeRemote!
    private var authState: AuthStateManager!
    private var repository: SupabaseAuthRepository!

    override func setUp() async throws {
        sheet = IdTokenFakeGoogleSheet()
        path = AuthRepositoryFakePathSource()
        remote = AuthRepositoryFakeRemote()
        idTokenRemote = IdTokenFakeRemote()
        authState = AuthStateManager(tokenStore: InMemoryTokenStore())
        authState.initialize()
        repository = SupabaseAuthRepository(remote: remote, authStateManager: authState,
                                            networkMonitor: NetworkMonitor(source: path), idTokenRemote: idTokenRemote)
    }

    private func requester(clientID: String? = "client-1.apps.googleusercontent.com") -> GoogleIdTokenRequester {
        GoogleIdTokenRequester(clientID: clientID, networkMonitor: NetworkMonitor(source: path), sheet: sheet,
                               makeRawNonce: { "raw-nonce-1" })
    }

    private func loginViewModel(googleTokens: any LoginGoogleTokenRequester, apple: IdTokenFakeAppleAuth,
                                reporter: LoginTestReporter = LoginTestReporter(),
                                analytics: LoginTestAnalytics = LoginTestAnalytics()) -> LoginViewModel {
        let repo = LoginTestAuthRepository()
        return LoginViewModel(authRepository: repo, googleAuth: repo, googleTokens: googleTokens, appleAuth: apple,
                              analytics: analytics, reporter: reporter, makeRawNonce: { "apple-raw-nonce" })
    }

    // MARK: Nonce

    // Supabase hashes the raw nonce as lowercase SHA-256 hex and compares it with the nonce the
    // provider signed into the token. Any encoding slip (missing zero-padding, uppercase, base64)
    // fails every sign-in. "abc" is the FIPS 180-2 vector; its digest has bytes < 0x10.
    func testNonceIsSha256Hashed() async throws {
        XCTAssertEqual(IdTokenNonce.sha256Hex("abc"),
                       "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")

        // Google gets the hash, Supabase gets the raw nonce.
        let token = try await requester().request()
        XCTAssertEqual(sheet.calls.first?.hashedNonce, IdTokenNonce.sha256Hex("raw-nonce-1"))
        XCTAssertEqual(token, GoogleSignInToken(idToken: "google-id-token", rawNonce: "raw-nonce-1"))

        // Apple gets the hash too, and so does its request.
        let vm = loginViewModel(googleTokens: requester(), apple: IdTokenFakeAppleAuth())
        let hash = vm.prepareAppleSignIn()
        XCTAssertEqual(hash, IdTokenNonce.sha256Hex("apple-raw-nonce"))
        let request = ASAuthorizationAppleIDProvider().createRequest()
        AppleIdTokenSignIn.configure(request, nonceHash: hash)
        XCTAssertEqual(request.nonce, hash)
        XCTAssertEqual(request.requestedScopes, [.fullName, .email])

        // Fresh random nonces, never reused.
        XCTAssertNotEqual(IdTokenNonce.random(), IdTokenNonce.random())
    }

    func testRawNonceReachesSupabaseForGoogle() async {
        let result = await repository.signInWithGoogle(idToken: "google-id-token", rawNonce: "raw-nonce-1")

        XCTAssertEqual(idTokenRemote.calls, [.init(provider: .google, idToken: "google-id-token", rawNonce: "raw-nonce-1")])
        XCTAssertEqual(try? result.get(), AuthUser(id: "user-9", email: "ann@icloud.com", name: "ann"))
        XCTAssertEqual(authState.authState, .authenticated(userId: "user-9"))
    }

    // GoogleSignIn-iOS 8.0.0 can't put a nonce into the token; sending one anyway is rejected.
    func testTokenWithoutNonceSendsNoNonceToSupabase() async throws {
        sheet.outcome = .success(GoogleSheetIdToken(idToken: "google-id-token", nonceApplied: false))
        let token = try await requester().request()
        XCTAssertEqual(token?.rawNonce, "")

        _ = await repository.signInWithGoogle(idToken: "google-id-token", rawNonce: "")
        XCTAssertEqual(idTokenRemote.calls.first?.rawNonce, nil)
    }

    // MARK: Cancel

    func testCancelIsNotAnError() async throws {
        // Google: closing the sheet gives nil, not a failure.
        sheet.outcome = .failure(NSError(domain: GoogleIdTokenRequester.cancelDomain, code: GoogleIdTokenRequester.cancelCode))
        let token = try await requester().request()
        XCTAssertNil(token)

        // Apple: `ASAuthorizationError.canceled` gives no credential either.
        let cancel = ASAuthorizationError(.canceled)
        XCTAssertNil(try AppleIdTokenSignIn.credential(from: .failed(cancel), rawNonce: "raw"))

        // And the login screen stays quiet for both.
        let apple = IdTokenFakeAppleAuth()
        let reporter = LoginTestReporter()
        let vm = loginViewModel(googleTokens: requester(), apple: apple, reporter: reporter)
        vm.signInWithGoogle()
        await vm.inFlight?.value
        XCTAssertNil(vm.errorMessage)
        _ = vm.prepareAppleSignIn()
        vm.completeAppleSignIn(.failed(cancel))
        await vm.inFlight?.value
        XCTAssertNil(vm.errorMessage)
        XCTAssertFalse(vm.isLoading)
        XCTAssertTrue(apple.calls.isEmpty)
        XCTAssertTrue(reporter.reports.isEmpty)
    }

    // MARK: Apple name

    func testAppleFullNameIsSentAsUserMetadataName() async throws {
        var parts = PersonNameComponents()
        parts.givenName = "Ann"
        parts.familyName = "Lee"
        let credential = try XCTUnwrap(AppleIdTokenSignIn.credential(
            from: .authorized(identityToken: Data("apple-id-token".utf8), fullName: parts), rawNonce: "raw"))
        XCTAssertEqual(credential, AppleSignInCredential(idToken: "apple-id-token", rawNonce: "raw", fullName: "Ann Lee"))
        remote.updateNameResult = .success(AuthRemoteUser(id: "user-9", email: "ann@icloud.com", metadataName: "Ann Lee"))

        let result = await repository.signInWithApple(idToken: credential.idToken, rawNonce: credential.rawNonce,
                                                      fullName: credential.fullName)

        XCTAssertEqual(idTokenRemote.calls, [.init(provider: .apple, idToken: "apple-id-token", rawNonce: "raw")])
        XCTAssertEqual(remote.calls, ["updateName(Ann Lee)"])
        XCTAssertEqual(try? result.get().name, "Ann Lee")
        XCTAssertEqual(authState.authState, .authenticated(userId: "user-9"))
    }

    // Every later authorisation comes without a name: the stored one must not be overwritten.
    func testAppleWithoutNameLeavesMetadataNameAlone() async throws {
        let empty = PersonNameComponents()
        let credential = try XCTUnwrap(AppleIdTokenSignIn.credential(
            from: .authorized(identityToken: Data("apple-id-token".utf8), fullName: empty), rawNonce: "raw"))
        XCTAssertNil(credential.fullName)

        let blank = await repository.signInWithApple(idToken: "apple-id-token", rawNonce: "raw", fullName: "  ")
        let missing = await repository.signInWithApple(idToken: "apple-id-token", rawNonce: "raw", fullName: nil)

        XCTAssertNoThrow(try blank.get())
        XCTAssertNoThrow(try missing.get())
        XCTAssertEqual(remote.calls, [])
    }

    // A failed name update must not undo a successful sign-in.
    func testAppleNameUpdateFailureKeepsSignIn() async {
        remote.updateNameResult = .failure(AuthRepositoryProviderFailure(message: "boom"))
        let result = await repository.signInWithApple(idToken: "apple-id-token", rawNonce: "raw", fullName: "Ann Lee")
        XCTAssertEqual(try? result.get().id, "user-9")
        XCTAssertEqual(authState.authState, .authenticated(userId: "user-9"))
    }

    func testAppleSuccessBehavesLikeGoogle() async {
        let apple = IdTokenFakeAppleAuth()
        let analytics = LoginTestAnalytics()
        let vm = loginViewModel(googleTokens: requester(), apple: apple, analytics: analytics)
        var successes = 0
        vm.onLoginSuccess = { successes += 1 }

        _ = vm.prepareAppleSignIn()
        vm.completeAppleSignIn(.authorized(identityToken: Data("apple-id-token".utf8), fullName: nil))
        await vm.inFlight?.value

        XCTAssertEqual(apple.calls, [AppleSignInCredential(idToken: "apple-id-token", rawNonce: "apple-raw-nonce", fullName: nil)])
        XCTAssertEqual(successes, 1)
        XCTAssertEqual(analytics.count, 1)
        XCTAssertNil(vm.errorMessage)
        XCTAssertFalse(vm.isLoading)
    }

    // MARK: Error mapping

    func testRejectedIdTokenShowsProviderMessage() async {
        idTokenRemote.result = .failure(AuthRepositoryProviderFailure(message: "Bad ID token"))
        let google = await repository.signInWithGoogle(idToken: "t", rawNonce: "n")
        idTokenRemote.result = .failure(AuthRepositoryProviderFailure(message: "Something else entirely"))
        let googleOther = await repository.signInWithGoogle(idToken: "t", rawNonce: "n")
        let apple = await repository.signInWithApple(idToken: "t", rawNonce: "n", fullName: "Ann")

        XCTAssertEqual(google.failure, .auth("Google sign-in failed. Please try again."))
        XCTAssertEqual(googleOther.failure, .auth("Google sign-in failed. Please try again."))
        XCTAssertEqual(apple.failure, .auth("Apple sign-in failed. Please try again."))
        XCTAssertEqual(remote.calls, [], "no name update after a failed sign-in")
        XCTAssertEqual(authState.authState, .unauthenticated)
    }

    func testTransportFailureDuringIdTokenSignInIsNetwork() async {
        idTokenRemote.result = .failure(URLError(.notConnectedToInternet))
        let result = await repository.signInWithGoogle(idToken: "t", rawNonce: "n")
        XCTAssertEqual(result.failure, .network())
    }

    func testGoogleSheetFailuresMapToFailed() async {
        sheet.outcome = .failure(NSError(domain: GoogleIdTokenRequester.cancelDomain, code: -1))
        do {
            _ = try await requester().request()
            XCTFail("expected a failure")
        } catch let failure as GoogleSheetFailure {
            guard case .failed = failure else { return XCTFail("got \(failure)") }
        } catch {
            XCTFail("unexpected \(error)")
        }

        sheet.outcome = .success(nil)
        do {
            _ = try await requester().request()
            XCTFail("expected a failure")
        } catch let failure as GoogleSheetFailure {
            guard case .failed = failure else { return XCTFail("got \(failure)") }
        } catch {
            XCTFail("unexpected \(error)")
        }
    }

    func testAppleMissingTokenIsShownAndReported() async {
        XCTAssertThrowsError(try AppleIdTokenSignIn.credential(
            from: .authorized(identityToken: nil, fullName: nil), rawNonce: "raw"))
        XCTAssertThrowsError(try AppleIdTokenSignIn.credential(
            from: .failed(ASAuthorizationError(.failed)), rawNonce: "raw"))

        let apple = IdTokenFakeAppleAuth()
        let reporter = LoginTestReporter()
        let vm = loginViewModel(googleTokens: requester(), apple: apple, reporter: reporter)
        _ = vm.prepareAppleSignIn()
        vm.completeAppleSignIn(.failed(ASAuthorizationError(.failed)))
        await vm.inFlight?.value

        XCTAssertEqual(vm.errorMessage, "Apple sign-in failed. Please try again.")
        XCTAssertEqual(reporter.reports.first?.1, .unknown("Apple sign-in failed. Please try again."))
        XCTAssertTrue(apple.calls.isEmpty)
    }

    // MARK: Offline

    func testOfflineFailsBeforeTheSheetOpens() async {
        path.isOnline = false
        do {
            _ = try await requester().request()
            XCTFail("expected offline")
        } catch {
            XCTAssertEqual(error as? GoogleSheetFailure, .offline)
        }
        XCTAssertTrue(sheet.calls.isEmpty)

        let google = await repository.signInWithGoogle(idToken: "t", rawNonce: "n")
        let apple = await repository.signInWithApple(idToken: "t", rawNonce: "n", fullName: "Ann")
        XCTAssertEqual(google.failure, .network())
        XCTAssertEqual(apple.failure, .network())
        XCTAssertTrue(idTokenRemote.calls.isEmpty)

        let vm = loginViewModel(googleTokens: requester(), apple: IdTokenFakeAppleAuth())
        vm.signInWithGoogle()
        await vm.inFlight?.value
        XCTAssertEqual(vm.errorMessage, "No internet connection.")
    }

    // MARK: Not configured (iOS only)

    func testMissingGoogleClientIdIsNotConfigured() async {
        for clientID in [nil, "", "  ", "$(BGT_GOOGLE_IOS_CLIENT_ID)"] {
            do {
                _ = try await requester(clientID: clientID).request()
                XCTFail("expected notConfigured for \(String(describing: clientID))")
            } catch {
                XCTAssertEqual(error as? GoogleSheetFailure, .notConfigured)
            }
        }
        // Checked before the network: no client id means no sheet either way.
        path.isOnline = false
        do {
            _ = try await requester(clientID: "").request()
        } catch {
            XCTAssertEqual(error as? GoogleSheetFailure, .notConfigured)
        }
        XCTAssertTrue(sheet.calls.isEmpty, "the SDK must never be called without a client id")

        XCTAssertEqual(GoogleIdTokenRequester.clientID(infoDictionary: ["GIDClientID": "abc"]), "abc")
        XCTAssertNil(GoogleIdTokenRequester.clientID(infoDictionary: [:]))
        XCTAssertNil(GoogleIdTokenRequester.clientID(infoDictionary: nil))

        let reporter = LoginTestReporter()
        let vm = loginViewModel(googleTokens: requester(clientID: ""), apple: IdTokenFakeAppleAuth(), reporter: reporter)
        vm.signInWithGoogle()
        await vm.inFlight?.value
        XCTAssertEqual(vm.errorMessage, "Google sign-in isn't set up in this build yet.")
        XCTAssertTrue(reporter.reports.isEmpty)
    }
}
