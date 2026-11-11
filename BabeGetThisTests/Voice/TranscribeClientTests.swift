import XCTest
@testable import BabeGetThis

/// Stub transport: no real network. Records requests and replies with a canned result.
final class StubURLProtocol: URLProtocol, @unchecked Sendable {
    enum Reply {
        case response(status: Int, body: Data)
        case failure(URLError)
    }

    struct Captured {
        let request: URLRequest
        let body: Data
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
        let reply = Self.queue.isEmpty ? nil : Self.queue.removeFirst()
        Self.lock.unlock()

        switch reply {
        case .response(let status, let data):
            let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: "HTTP/1.1", headerFields: nil)!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        case .failure(let error):
            client?.urlProtocol(self, didFailWithError: error)
        case nil:
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
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
}

final class TranscribeClientTests: XCTestCase {
    private let baseURL = URL(string: "https://api.example.test/")!
    private var audio: URL!
    private var online = true

    override func setUp() {
        super.setUp()
        StubURLProtocol.reset()
        online = true
        audio = FileManager.default.temporaryDirectory.appending(path: "voice-\(UUID().uuidString).m4a")
        // 64 distinct bytes, so the multipart test can tell them apart from padding.
        try? Data((0..<64).map { UInt8($0 + 1) }).write(to: audio)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: audio)
        super.tearDown()
    }

    private func makeClient(isOnline: Bool = true) -> TranscribeClient {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubURLProtocol.self]
        return TranscribeClient(
            baseURL: baseURL,
            session: URLSession(configuration: config),
            accessToken: { "test-token" },
            isOnline: { isOnline }
        )
    }

    private func respond(_ status: Int, _ body: String = "{}") {
        StubURLProtocol.enqueue(.response(status: status, body: Data(body.utf8)))
    }

    private func expectError(
        _ client: TranscribeClient,
        file: URL? = nil,
        line: UInt = #line
    ) async -> VoiceError? {
        do {
            _ = try await client.transcribeAndParse(audioFile: file ?? audio)
            XCTFail("expected an error", line: line)
            return nil
        } catch let error as VoiceError {
            return error
        } catch {
            XCTFail("unexpected error type \(error)", line: line)
            return nil
        }
    }

    // MARK: happy path

    func testTranscribedResponseMapsToDrafts() async throws {
        respond(200, """
        {"transcript":"milk and eggs","items":[
          {"name":"Milk","quantity":2,"unit":"litres","category":"dairy","location":"Aldi","note":"semi"},
          {"name":"Eggs"}
        ]}
        """)

        let drafts = try await makeClient().transcribeAndParse(audioFile: audio)

        XCTAssertEqual(drafts.count, 2)
        XCTAssertEqual(drafts[0].name, "Milk")
        XCTAssertEqual(drafts[0].quantity, "2 litres")
        XCTAssertEqual(drafts[0].category, "dairy")
        XCTAssertEqual(drafts[0].shop, "Aldi")
        XCTAssertEqual(drafts[0].note, "semi")
        XCTAssertNil(drafts[1].quantity)
    }

    func testEmptyItemListComesBackAsEmptySuccess() async throws {
        respond(200, #"{"transcript":"","items":[]}"#)
        let drafts = try await makeClient().transcribeAndParse(audioFile: audio)
        XCTAssertTrue(drafts.isEmpty)
    }

    func testUnknownResponseFieldsAreIgnored() async throws {
        respond(200, #"{"items":[{"name":"Milk","somethingNew":true}],"futureField":1}"#)
        let drafts = try await makeClient().transcribeAndParse(audioFile: audio)
        XCTAssertEqual(drafts.first?.name, "Milk")
        XCTAssertEqual(drafts.count, 1)
    }

    func testAudioIsUploadedAsMultipartUnderAudioPartName() async throws {
        respond(200, #"{"items":[]}"#)

        _ = try await makeClient().transcribeAndParse(audioFile: audio)

        let sent = try XCTUnwrap(StubURLProtocol.requests.first)
        XCTAssertEqual(sent.request.httpMethod, "POST")
        XCTAssertEqual(sent.request.url?.path, "/transcribe")
        XCTAssertEqual(sent.request.value(forHTTPHeaderField: "Authorization"), "Bearer test-token")
        XCTAssertEqual(sent.request.timeoutInterval, 60)
        let contentType = try XCTUnwrap(sent.request.value(forHTTPHeaderField: "Content-Type"))
        let prefix = "multipart/form-data; boundary="
        XCTAssertTrue(contentType.hasPrefix(prefix))
        let boundary = String(contentType.dropFirst(prefix.count))
        XCTAssertFalse(boundary.isEmpty)

        // The whole body, byte for byte: opening delimiter, part headers, a blank
        // line, the exact audio bytes, then the closing delimiter.
        var expected = Data("--\(boundary)\r\n".utf8)
        expected.append(Data("Content-Disposition: form-data; name=\"audio\"; filename=\"\(audio.lastPathComponent)\"\r\n".utf8))
        expected.append(Data("Content-Type: audio/mp4\r\n\r\n".utf8))
        let audioBytes = try Data(contentsOf: audio)
        XCTAssertEqual(audioBytes.count, 64)
        expected.append(audioBytes)
        expected.append(Data("\r\n--\(boundary)--\r\n".utf8))
        XCTAssertEqual(sent.body, expected)
        XCTAssertTrue(sent.body.starts(with: Data("--\(boundary)\r\n".utf8)))
        XCTAssertTrue(sent.body.suffix(boundary.count + 8) == Data("\r\n--\(boundary)--\r\n".utf8))
    }

    // MARK: offline guard

    func testOfflineIsRefusedWithoutTouchingTheNetwork() async {
        let error = await expectError(makeClient(isOnline: false))
        guard case .network = error else { return XCTFail("expected network, got \(String(describing: error))") }
        XCTAssertEqual(StubURLProtocol.requests.count, 0)
    }

    // MARK: status mapping

    func testA400BlamesTheRecordingRatherThanCredentials() async {
        respond(400)
        let error = await expectError(makeClient())
        guard case .server(let code, _) = error else { return XCTFail("expected server") }
        XCTAssertEqual(code, 400)
        XCTAssertEqual(error?.message, "Couldn't process that recording. Please try again.")
    }

    func testA413IsAlsoARecordingProblem() async {
        respond(413)
        let error = await expectError(makeClient())
        XCTAssertEqual(error?.message, "Couldn't process that recording. Please try again.")
    }

    func testA401StaysUnauthorized() async {
        respond(401)
        let error = await expectError(makeClient())
        guard case .unauthorized = error else { return XCTFail("expected unauthorized") }
    }

    func testA500IsAServerError() async {
        respond(500)
        let error = await expectError(makeClient())
        guard case .server(let code, let message) = error else { return XCTFail("expected server") }
        XCTAssertEqual(code, 500)
        XCTAssertEqual(message, "Server error. Please try later.")
    }

    func testDroppedConnectionIsANetworkError() async {
        StubURLProtocol.enqueue(.failure(URLError(.networkConnectionLost)))
        let error = await expectError(makeClient())
        guard case .network = error else { return XCTFail("expected network") }
    }

    func testMalformedBodyDoesNotEscapeAsAnException() async {
        respond(200, "this is not json")
        let error = await expectError(makeClient())
        XCTAssertEqual(error, .unknown())
    }

    func testMissingAudioFileDoesNotLeakItsPath() async {
        respond(200, #"{"items":[]}"#)
        let gone = FileManager.default.temporaryDirectory.appending(path: "definitely-not-here-\(UUID().uuidString).m4a")

        let error = await expectError(makeClient(), file: gone)

        let message = error?.message ?? ""
        XCTAssertFalse(message.contains(".m4a"), "leaked path: \(message)")
        XCTAssertFalse(message.contains("/var"), "leaked path: \(message)")
        XCTAssertFalse(message.contains("/tmp"), "leaked path: \(message)")
    }

    // MARK: quantity + unit flattening

    func testQuantityAndUnitFlatten() {
        XCTAssertEqual(TranscribeItemDto(name: "a", quantity: 2, unit: "bottles").toTranscribedItem().quantity, "2 bottles")
        XCTAssertEqual(TranscribeItemDto(name: "a", quantity: 2).toTranscribedItem().quantity, "2")
        XCTAssertEqual(TranscribeItemDto(name: "a", unit: "kg").toTranscribedItem().quantity, "kg")
        XCTAssertNil(TranscribeItemDto(name: "a").toTranscribedItem().quantity)
    }
}
