import Foundation
import Supabase
@testable import BabeGetThis

/// Stub transport for SupabaseClient: no real network. Records every request and answers each one with
/// the next queued reply (or 500 when the queue is empty).
final class SharedListURLStub: URLProtocol, @unchecked Sendable {
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
        var bodyString: String { String(decoding: body, as: UTF8.self) }

        /// Query items, percent-decoded. A name may repeat (`order`), so this returns every value.
        func query(_ name: String) -> [String] {
            guard let url = request.url,
                  let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems
            else { return [] }
            return items.filter { $0.name == name }.compactMap(\.value)
        }

        func header(_ name: String) -> String? { request.value(forHTTPHeaderField: name) }
    }

    private static let lock = NSLock()
    nonisolated(unsafe) private static var queue: [Reply] = []
    nonisolated(unsafe) private static var captured: [Captured] = []

    static func reset() {
        lock.lock(); defer { lock.unlock() }
        queue = []
        captured = []
    }

    static func enqueue(_ reply: Reply) {
        lock.lock(); defer { lock.unlock() }
        queue.append(reply)
    }

    static var requests: [Captured] {
        lock.lock(); defer { lock.unlock() }
        return captured
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let body = Self.readBody(request)
        Self.lock.lock()
        Self.captured.append(Captured(request: request, body: body))
        let reply = Self.queue.isEmpty ? Reply(status: 500, json: "{\"message\":\"no stubbed reply\"}") : Self.queue.removeFirst()
        Self.lock.unlock()

        let response = HTTPURLResponse(
            url: request.url!, statusCode: reply.status, httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: reply.body)
        client?.urlProtocolDidFinishLoading(self)
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

    /// A SupabaseClient whose every request goes through this stub. Local Docker URL and a dummy key:
    /// never a real project. Auth storage is in memory, so no session and no keychain.
    static func makeClient() -> SupabaseClient {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [SharedListURLStub.self]
        return SupabaseClient(
            supabaseURL: URL(string: "http://127.0.0.1:54321")!,
            supabaseKey: "dummy-anon-key",
            options: SupabaseClientOptions(
                auth: .init(storage: SharedListInMemoryAuthStorage(), autoRefreshToken: false),
                global: .init(session: URLSession(configuration: config))
            )
        )
    }
}

final class SharedListInMemoryAuthStorage: AuthLocalStorage, @unchecked Sendable {
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
