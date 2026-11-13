import Foundation
import Supabase
import XCTest
@testable import BabeGetThis

/// SupabaseAuthRemote through a stubbed transport: the endpoints and payloads it sends.
/// Local Docker URL and a dummy key only; no request leaves the process.
final class SupabaseAuthRemoteTests: XCTestCase {
    private var remote: SupabaseAuthRemote!

    private static let userJSON = """
    {"id":"8F6C2B1E-0000-4000-8000-000000000001","aud":"authenticated","email":"ann@example.com",\
    "created_at":"2026-11-13T09:00:00Z","updated_at":"2026-11-13T09:00:00Z","user_metadata":{"name":"Ann"}}
    """

    private static let sessionJSON = """
    {"access_token":"access-1","token_type":"bearer","expires_in":3600,"expires_at":4102444800,\
    "refresh_token":"refresh-1","user":\(userJSON)}
    """

    override func setUp() {
        super.setUp()
        AuthRemoteURLStub.reset()
        remote = SupabaseAuthRemote(client: AuthRemoteURLStub.makeClient())
    }

    override func tearDown() {
        remote = nil
        AuthRemoteURLStub.reset()
        super.tearDown()
    }

    private func json(_ data: Data) throws -> [String: Any] {
        try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    func testSignInPostsAPasswordGrantAndReturnsTheSession() async throws {
        AuthRemoteURLStub.enqueue(.init(json: Self.sessionJSON))

        let session = try await remote.signIn(email: "ann@example.com", password: "secret1")

        XCTAssertEqual(session, AuthRemoteSession(
            accessToken: "access-1",
            user: AuthRemoteUser(id: "8f6c2b1e-0000-4000-8000-000000000001", email: "ann@example.com", metadataName: "Ann")
        ))
        XCTAssertEqual(remote.currentSession(), session)
        let request = try XCTUnwrap(AuthRemoteURLStub.requests.first)
        XCTAssertEqual(request.method, "POST")
        XCTAssertEqual(request.path, "/auth/v1/token")
        XCTAssertEqual(request.query("grant_type"), ["password"])
        let body = try json(request.body)
        XCTAssertEqual(body["email"] as? String, "ann@example.com")
        XCTAssertEqual(body["password"] as? String, "secret1")
    }

    func testSignUpSendsTheNameAsMetadataAndReturnsNilWithoutASession() async throws {
        AuthRemoteURLStub.enqueue(.init(json: Self.userJSON))

        let session = try await remote.signUp(email: "ann@example.com", password: "secret1", name: "Ann")

        XCTAssertNil(session, "confirm email ON: no session yet")
        let request = try XCTUnwrap(AuthRemoteURLStub.requests.first)
        XCTAssertEqual(request.path, "/auth/v1/signup")
        let body = try json(request.body)
        XCTAssertEqual(body["email"] as? String, "ann@example.com")
        XCTAssertEqual((body["data"] as? [String: Any])?["name"] as? String, "Ann")
    }

    func testRequestPasswordResetPostsToRecover() async throws {
        AuthRemoteURLStub.enqueue(.init(json: "{}"))

        try await remote.requestPasswordReset(email: "ann@example.com")

        let request = try XCTUnwrap(AuthRemoteURLStub.requests.first)
        XCTAssertEqual(request.method, "POST")
        XCTAssertEqual(request.path, "/auth/v1/recover")
        XCTAssertEqual(try json(request.body)["email"] as? String, "ann@example.com")
    }

    func testVerifyRecoveryCodeSendsARecoveryOtp() async throws {
        AuthRemoteURLStub.enqueue(.init(json: Self.sessionJSON))

        try await remote.verifyRecoveryCode(email: "ann@example.com", code: "12345678")

        let request = try XCTUnwrap(AuthRemoteURLStub.requests.first)
        XCTAssertEqual(request.path, "/auth/v1/verify")
        let body = try json(request.body)
        XCTAssertEqual(body["type"] as? String, "recovery")
        XCTAssertEqual(body["token"] as? String, "12345678")
        XCTAssertEqual(body["email"] as? String, "ann@example.com")
        XCTAssertNotNil(remote.currentSession(), "verifying the code signs the user in")
    }

    func testDeleteUserCallsTheRpcWithTheUsersToken() async throws {
        AuthRemoteURLStub.enqueue(.init(json: Self.sessionJSON))
        AuthRemoteURLStub.enqueue(.init(status: 204, json: ""))
        _ = try await remote.signIn(email: "ann@example.com", password: "secret1")

        try await remote.deleteUser()

        let request = try XCTUnwrap(AuthRemoteURLStub.requests.last)
        XCTAssertEqual(request.method, "POST")
        XCTAssertEqual(request.path, "/rest/v1/rpc/delete_user")
        XCTAssertEqual(request.header("Authorization"), "Bearer access-1")
    }

    // Offline sign-out: the stored session is gone even though /logout failed.
    func testAFailedSignOutStillClearsTheStoredSession() async throws {
        AuthRemoteURLStub.enqueue(.init(json: Self.sessionJSON))
        _ = try await remote.signIn(email: "ann@example.com", password: "secret1")
        AuthRemoteURLStub.failNext(URLError(.notConnectedToInternet))

        try? await remote.signOut()

        XCTAssertNil(remote.currentSession())
        XCTAssertEqual(AuthRemoteURLStub.requests.last?.path, "/auth/v1/logout")
    }
}

/// Stub transport for the auth client: records requests and answers each with the next
/// queued reply, or a transport error, or 500 when nothing is queued.
final class AuthRemoteURLStub: URLProtocol, @unchecked Sendable {
    struct Reply {
        let status: Int
        let body: Data

        init(status: Int = 200, json: String) {
            self.status = status
            self.body = Data(json.utf8)
        }
    }

    struct Captured {
        let request: URLRequest
        let body: Data

        var method: String { request.httpMethod ?? "" }
        var path: String { request.url?.path ?? "" }

        func query(_ name: String) -> [String] {
            guard let url = request.url,
                  let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems
            else { return [] }
            return items.filter { $0.name == name }.compactMap(\.value)
        }

        func header(_ name: String) -> String? { request.value(forHTTPHeaderField: name) }
    }

    private enum Next {
        case reply(Reply)
        case failure(URLError)
    }

    private static let lock = NSLock()
    nonisolated(unsafe) private static var queue: [Next] = []
    nonisolated(unsafe) private static var captured: [Captured] = []

    static func reset() {
        lock.withLock {
            queue = []
            captured = []
        }
    }

    static func enqueue(_ reply: Reply) {
        lock.withLock { queue.append(.reply(reply)) }
    }

    static func failNext(_ error: URLError) {
        lock.withLock { queue.append(.failure(error)) }
    }

    static var requests: [Captured] {
        lock.withLock { captured }
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let body = Self.readBody(request)
        let next: Next = Self.lock.withLock {
            Self.captured.append(Captured(request: request, body: body))
            return Self.queue.isEmpty ? .reply(Reply(status: 500, json: "{\"message\":\"no stubbed reply\"}")) : Self.queue.removeFirst()
        }
        switch next {
        case .failure(let error):
            client?.urlProtocol(self, didFailWithError: error)
        case .reply(let reply):
            let response = HTTPURLResponse(
                url: request.url!, statusCode: reply.status, httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "application/json"]
            )!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: reply.body)
            client?.urlProtocolDidFinishLoading(self)
        }
    }

    override func stopLoading() {}

    private static func readBody(_ request: URLRequest) -> Data {
        if let body = request.httpBody { return body }
        guard let stream = request.httpBodyStream else { return Data() }
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while stream.hasBytesAvailable {
            let n = stream.read(&buffer, maxLength: buffer.count)
            if n <= 0 { break }
            data.append(buffer, count: n)
        }
        return data
    }

    static func makeClient() -> SupabaseClient {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [AuthRemoteURLStub.self]
        return SupabaseClient(
            supabaseURL: URL(string: "http://127.0.0.1:54321")!,
            supabaseKey: "dummy-anon-key",
            options: SupabaseClientOptions(
                auth: .init(storage: AuthRemoteInMemoryStorage(), autoRefreshToken: false),
                global: .init(session: URLSession(configuration: config))
            )
        )
    }
}

final class AuthRemoteInMemoryStorage: AuthLocalStorage, @unchecked Sendable {
    private let lock = NSLock()
    private var values: [String: Data] = [:]

    func store(key: String, value: Data) throws {
        lock.withLock { values[key] = value }
    }

    func retrieve(key: String) throws -> Data? {
        lock.withLock { values[key] }
    }

    func remove(key: String) throws {
        lock.withLock { values[key] = nil }
    }
}
