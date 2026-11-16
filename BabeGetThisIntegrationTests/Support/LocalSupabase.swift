import Foundation
import Supabase
import XCTest
@testable import BabeGetThis

/// This repo's own local Supabase in Docker (`supabase start` from the repo root: supabase/config.toml,
/// project babe-get-this-ios, migrations 001-006). Its ports are 553xx, apart from the Android repo's
/// stack on 543xx, which the Dev app config points at. The tests use this fixed loopback URL, never the
/// app's, so they can reach neither the Android stack nor a hosted project.
enum LocalSupabase {
    /// config.toml `[api] port`.
    static let apiURL = URL(string: "http://127.0.0.1:55321")!

    /// Mailpit, the local stack's mail catcher (config.toml `[local_smtp] port`).
    static let mailURL = URL(string: "http://127.0.0.1:55324")!

    /// The key every Supabase CLI stack issues for its default JWT secret (config.toml sets none): public
    /// and only valid on a local stack.
    static let localAnonKey =
        "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0"

    enum SetupError: Error, CustomStringConvertible {
        case notLocal(String)
        case unreachable(String)

        var description: String {
            switch self {
            case .notLocal(let detail), .unreachable(let detail): detail
            }
        }
    }

    struct Endpoint: Sendable {
        let url: URL
        let anonKey: String
    }

    /// This repo's stack and its anon key. Throws unless the host app was built with the Dev config and
    /// the stack's URLs are loopback addresses.
    static func endpoint() throws -> Endpoint {
        let config = try AppConfig(infoDictionary: Bundle.main.infoDictionary ?? [:])
        guard config.environment == .dev else {
            throw SetupError.notLocal(
                "Integration tests only run in a Dev build (this one is \(config.environment.rawValue)); "
                    + "use the BabeGetThis-Dev scheme.")
        }
        for url in [apiURL, mailURL] {
            guard ["127.0.0.1", "localhost", "::1"].contains(url.host() ?? "") else {
                throw SetupError.notLocal(
                    "Integration tests only run against the local Docker Supabase, not \(url).")
            }
        }
        return Endpoint(url: apiURL, anonKey: localAnonKey)
    }

    /// Fails (never skips) when the stack is down or lacks the migrations: an integration run that
    /// silently skips would read as a pass.
    static func requireRunning() async throws -> Endpoint {
        let endpoint = try endpoint()
        let hint = "Start this repo's stack (babe-get-this-ios, ports 553xx) from the repo root with "
            + "`supabase start`, then `supabase db reset --local`."
        let session = URLSession(configuration: .ephemeral)
        for (path, what) in [("auth/v1/health", "Auth"), ("rest/v1/lists?select=id&limit=1", "the lists table")] {
            var request = URLRequest(url: URL(string: path, relativeTo: endpoint.url)!, timeoutInterval: 5)
            request.setValue(endpoint.anonKey, forHTTPHeaderField: "apikey")
            let status: Int
            do {
                let (_, response) = try await session.data(for: request)
                status = (response as? HTTPURLResponse)?.statusCode ?? 0
            } catch {
                throw SetupError.unreachable(
                    "Local Supabase is not reachable at \(endpoint.url) (\(error.localizedDescription)). \(hint)")
            }
            guard status == 200 else {
                throw SetupError.unreachable(
                    "Local Supabase at \(endpoint.url) answered \(status) for \(what). Is this repo's stack "
                        + "running with migrations 001-006? \(hint)")
            }
        }
        return endpoint
    }

    /// A client with its own in-memory session, so several signed-in users can act side by side.
    static func makeClient(_ endpoint: Endpoint) -> SupabaseClient {
        SupabaseClient(
            supabaseURL: endpoint.url,
            supabaseKey: endpoint.anonKey,
            options: SupabaseClientOptions(
                auth: .init(storage: InMemoryAuthStorage(), autoRefreshToken: false)
            )
        )
    }
}

/// One signed-up user with their own client, talking to the server through the app's own remotes.
struct TestUser: Sendable {
    let id: String
    let email: String
    let password: String
    let client: SupabaseClient
    let remote: SupabaseSharedListRemote
    let auth: SupabaseAuthRemote

    init(id: String, email: String, password: String, client: SupabaseClient) {
        self.id = id
        self.email = email
        self.password = password
        self.client = client
        self.remote = SupabaseSharedListRemote(client: client)
        self.auth = SupabaseAuthRemote(client: client)
    }
}

/// Base class: every test needs the stack up, and every user it makes is deleted afterwards.
class LocalSupabaseTestCase: XCTestCase {
    private(set) var endpoint: LocalSupabase.Endpoint!
    private var setupError: (any Error)?

    override func setUp() async throws {
        try await super.setUp()
        do {
            endpoint = try await LocalSupabase.requireRunning()
        } catch {
            // A failure, then the test's first makeUser throws. Not rethrown here: XCTest reports an error
            // thrown from setUp as a skipped test.
            XCTFail("\(error)")
            setupError = error
        }
    }

    /// Signs up a fresh user (email confirmations are off locally, so this signs them in) and deletes the
    /// account, with its solo lists, when the test ends. Every test starts with one.
    func makeUser(_ label: String = "user") async throws -> TestUser {
        if let setupError { throw setupError }
        let client = LocalSupabase.makeClient(endpoint)
        let email = "ios-it-\(label)-\(UUID().uuidString.prefix(8).lowercased())@example.com"
        let password = "Passw0rd-\(UUID().uuidString.prefix(8))"
        let auth = SupabaseAuthRemote(client: client)
        let session = try await auth.signUp(email: email, password: password, name: label)
        let signedIn = try XCTUnwrap(session, "sign-up returned no session: config.toml must keep enable_confirmations = false")
        let user = TestUser(id: signedIn.user.id, email: email, password: password, client: client)
        addTeardownBlock {
            // Already gone when the test deleted the account itself.
            try? await user.auth.deleteUser()
        }
        return user
    }

    /// A new list row as SyncEngine pushes it (`createdBy` = the pusher).
    func newList(_ name: String, by user: TestUser, shareCode: String? = nil) -> ListRow {
        ListRow(
            id: UUID().uuidString.lowercased(),
            name: name,
            shareCode: shareCode,
            createdBy: user.id,
            createdAt: Int64(Date().timeIntervalSince1970 * 1000).millisToIso()
        )
    }

    func newItem(_ name: String, in list: ListRow, isPickedUp: Bool = false) -> ItemRow {
        ItemRow(id: UUID().uuidString.lowercased(), listId: list.id, name: name, quantity: "1", isPickedUp: isPickedUp)
    }

    /// A code in the app's alphabet, unique enough for one run.
    func newShareCode() -> String {
        String((0..<ShareRepository.codeLength).map { _ in ShareRepository.alphabet.randomElement()! })
    }

    /// Creates `list` on the server as its first push does (plain INSERT) and fails the test otherwise.
    @discardableResult
    func create(_ list: ListRow, by user: TestUser, file: StaticString = #filePath, line: UInt = #line) async throws -> ListRow {
        let inserted = try await user.remote.insertList(list)
        XCTAssertTrue(inserted, "the first push of \(list.name) should insert it", file: file, line: line)
        return list
    }

    /// A list `owner` made and shared, joined by `partner` through the join RPC.
    func sharedList(_ name: String, owner: TestUser, partner: TestUser) async throws -> ListRow {
        let list = try await create(newList(name, by: owner, shareCode: newShareCode()), by: owner)
        let joined = try await partner.remote.joinListByCode(try XCTUnwrap(list.shareCode))
        XCTAssertEqual(joined, list.id)
        return list
    }

    /// Asserts `body` throws a PostgREST error with the given SQLSTATE (42501 = RLS / privilege denial).
    func assertPostgrestError(
        _ code: String,
        _ message: String,
        file: StaticString = #filePath,
        line: UInt = #line,
        _ body: () async throws -> Void
    ) async {
        do {
            try await body()
            XCTFail("\(message): expected PostgREST error \(code), but it succeeded", file: file, line: line)
        } catch let error as PostgrestError {
            XCTAssertEqual(error.code, code, "\(message): \(error.message)", file: file, line: line)
        } catch {
            XCTFail("\(message): expected PostgREST error \(code), got \(error)", file: file, line: line)
        }
    }
}

final class InMemoryAuthStorage: AuthLocalStorage, @unchecked Sendable {
    private let lock = NSLock()
    private var values: [String: Data] = [:]

    func store(key: String, value: Data) throws {
        lock.lock(); defer { lock.unlock() }
        values[key] = value
    }

    func retrieve(key: String) throws -> Data? {
        lock.lock(); defer { lock.unlock() }
        return values[key]
    }

    func remove(key: String) throws {
        lock.lock(); defer { lock.unlock() }
        values[key] = nil
    }
}

/// Counts what a stream yields, from a background task, so a test can wait on it with a timeout.
actor EventCounter {
    private(set) var count = 0
    private(set) var failure: (any Error)?

    func increment() { count += 1 }
    func fail(_ error: any Error) { failure = error }
}

/// Polls `condition` every 100 ms; true once it holds, false when `seconds` pass first.
func eventually(within seconds: Double, _ condition: () async throws -> Bool) async throws -> Bool {
    let deadline = Date().addingTimeInterval(seconds)
    while Date() < deadline {
        if try await condition() { return true }
        try await Task.sleep(nanoseconds: 100_000_000)
    }
    return try await condition()
}
