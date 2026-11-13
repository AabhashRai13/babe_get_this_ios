import XCTest
@testable import BabeGetThis

// A real URLSession over a stub URLProtocol, so the bearer and 401 handling are exercised
// through the actual request pipeline rather than by inspecting a hand-built request.
final class AuthNetworkTests: XCTestCase {
    private let baseURL = URL(string: "https://api.example.test/")!
    private var audio: URL!
    private var session: URLSession!

    override func setUp() {
        super.setUp()
        StubURLProtocol.reset()
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubURLProtocol.self]
        session = URLSession(configuration: config)
        audio = FileManager.default.temporaryDirectory.appending(path: "auth-\(UUID().uuidString).m4a")
        try? Data([1, 2, 3, 4]).write(to: audio)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: audio)
        session.invalidateAndCancel()
        super.tearDown()
    }

    private func respond(_ status: Int, _ body: String = #"{"items":[]}"#) {
        StubURLProtocol.enqueue(.response(status: status, body: Data(body.utf8)))
    }

    /// A signed-in user: a token and an id, restored into a real manager.
    private func signedIn() -> (InMemoryTokenStore, AuthStateManager) {
        let tokens = InMemoryTokenStore()
        tokens.saveToken("abc123")
        tokens.saveUserId("u1")
        let manager = AuthStateManager(tokenStore: tokens)
        manager.initialize()
        XCTAssertEqual(manager.authState, .authenticated(userId: "u1"))
        return (tokens, manager)
    }

    private func client(_ auth: TranscribeBearerAuth) -> TranscribeClient {
        TranscribeClient(baseURL: baseURL, session: session, auth: auth)
    }

    @discardableResult
    private func transcribe(_ auth: TranscribeBearerAuth) async -> Result<[TranscribedItem], any Error> {
        do {
            return .success(try await client(auth).transcribeAndParse(audioFile: audio))
        } catch {
            return .failure(error)
        }
    }

    /// Sends `request` through the session the way the client does: authorize, send, handle.
    private func send(_ request: URLRequest, with auth: TranscribeBearerAuth) async throws {
        let signed = auth.authorize(request)
        let (_, response) = try await session.data(for: signed)
        auth.handle(try XCTUnwrap(response as? HTTPURLResponse), to: signed)
    }

    private var sentAuthorization: String? {
        StubURLProtocol.requests.first?.request.value(forHTTPHeaderField: "Authorization")
    }

    // MARK: - Bearer header (AuthInterceptor)

    func testASavedTokenIsAttachedAsABearerHeader() async {
        let (tokens, manager) = signedIn()
        respond(200)

        await transcribe(TranscribeBearerAuth(tokenStore: tokens, authStateManager: manager))

        XCTAssertEqual(sentAuthorization, "Bearer abc123")
    }

    func testNoTokenMeansNoHeaderRatherThanAnEmptyOne() async {
        let tokens = InMemoryTokenStore()
        respond(200)

        await transcribe(TranscribeBearerAuth(tokenStore: tokens, authStateManager: AuthStateManager(tokenStore: tokens)))

        XCTAssertEqual(StubURLProtocol.requests.count, 1)
        XCTAssertNil(sentAuthorization)
    }

    func testTheRequestIsOtherwiseUntouched() async throws {
        let (tokens, manager) = signedIn()
        respond(200)
        var request = URLRequest(url: baseURL.appending(path: "thing"))
        request.setValue("kept", forHTTPHeaderField: "X-Custom")

        try await send(request, with: TranscribeBearerAuth(tokenStore: tokens, authStateManager: manager))

        let recorded = try XCTUnwrap(StubURLProtocol.requests.first?.request)
        XCTAssertEqual(recorded.value(forHTTPHeaderField: "X-Custom"), "kept")
        XCTAssertEqual(recorded.url?.path, "/thing")
    }

    // Setting the header replaces rather than appends, so a caller-supplied Authorization is
    // overwritten by the saved token. Pinned as current behaviour: worth knowing before anyone
    // adds a call that signs itself.
    func testACallerSuppliedAuthorizationHeaderIsOverwritten() async throws {
        let (tokens, manager) = signedIn()
        respond(200)
        var request = URLRequest(url: baseURL.appending(path: "thing"))
        request.setValue("Basic other", forHTTPHeaderField: "Authorization")

        try await send(request, with: TranscribeBearerAuth(tokenStore: tokens, authStateManager: manager))

        XCTAssertEqual(sentAuthorization, "Bearer abc123")
    }

    // MARK: - 401 handling (AuthAuthenticator)

    // The session expires but the account is kept, so its lists stay on screen
    // (Android decision 008).
    func testA401OnAnAuthenticatedRequestExpiresTheSessionButKeepsTheAccount() async {
        let (tokens, manager) = signedIn()
        respond(401)

        await transcribe(TranscribeBearerAuth(tokenStore: tokens, authStateManager: manager))

        XCTAssertEqual(manager.authState, .sessionExpired(userId: "u1"))
        XCTAssertNil(tokens.token())
        XCTAssertEqual(tokens.userId(), "u1")
    }

    // Only one attempt: no retry, no refresh.
    func testA401IsNotRetried() async {
        let (tokens, manager) = signedIn()
        respond(401)
        respond(200)

        let result = await transcribe(TranscribeBearerAuth(tokenStore: tokens, authStateManager: manager))

        guard case .failure(let error) = result, case .unauthorized = error as? VoiceError else {
            return XCTFail("expected unauthorized, got \(result)")
        }
        XCTAssertEqual(StubURLProtocol.requests.count, 1)
    }

    // With no token no header is attached, so there is no session to clear: a signed-in
    // manager must stay exactly as it was (neither expired nor logged out).
    func testA401OnAnUnauthenticatedRequestDoesNotTouchAuthState() async {
        let (tokens, manager) = signedIn()
        respond(401)

        await transcribe(TranscribeBearerAuth(currentToken: { nil }, expireSession: { manager.expireSession() }))

        XCTAssertNil(sentAuthorization)
        XCTAssertEqual(manager.authState, .authenticated(userId: "u1"))
        XCTAssertEqual(tokens.token(), "abc123")
    }

    func testASuccessfulResponseNeverExpiresTheSession() async {
        let (tokens, manager) = signedIn()
        respond(200)

        let result = await transcribe(TranscribeBearerAuth(tokenStore: tokens, authStateManager: manager))

        guard case .success = result else { return XCTFail("expected success, got \(result)") }
        XCTAssertEqual(manager.authState, .authenticated(userId: "u1"))
        XCTAssertEqual(tokens.token(), "abc123")
    }

    // A 500 is a server problem, not an auth problem: the session must survive.
    func testA500NeitherSignsTheUserOutNorExpiresTheSession() async {
        let (tokens, manager) = signedIn()
        respond(500)

        let result = await transcribe(TranscribeBearerAuth(tokenStore: tokens, authStateManager: manager))

        guard case .failure(let error) = result, case .server(500, _) = error as? VoiceError else {
            return XCTFail("expected a server error, got \(result)")
        }
        XCTAssertEqual(manager.authState, .authenticated(userId: "u1"))
        XCTAssertEqual(tokens.token(), "abc123")
    }
}
