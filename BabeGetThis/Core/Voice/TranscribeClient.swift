import Foundation

/// Uploads a recorded .m4a to POST {apiBaseURL}transcribe and maps the response to TranscribedItems.
/// No recording and no UI here: the caller hands in a file URL.
struct TranscribeClient: Sendable {
    static let timeout: TimeInterval = 60

    private let baseURL: URL
    private let session: URLSession
    private let auth: TranscribeBearerAuth
    private let isOnline: @Sendable () -> Bool

    /// - Parameters:
    ///   - session: inject a session whose configuration carries a stub URLProtocol in tests.
    ///   - auth: attaches the current access token and expires the session on a 401.
    ///   - isOnline: proactive offline guard; fails fast instead of waiting for a timeout.
    init(
        baseURL: URL,
        session: URLSession = .shared,
        auth: TranscribeBearerAuth,
        isOnline: @escaping @Sendable () -> Bool = { true }
    ) {
        self.baseURL = baseURL
        self.session = session
        self.auth = auth
        self.isOnline = isOnline
    }

    func transcribeAndParse(audioFile: URL) async throws -> [TranscribedItem] {
        guard isOnline() else { throw VoiceError.network() }
        do {
            let audio = try Data(contentsOf: audioFile)

            let boundary = "Boundary-\(UUID().uuidString)"
            var request = URLRequest(url: baseURL.appending(path: "transcribe"), timeoutInterval: Self.timeout)
            request.httpMethod = "POST"
            request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
            request = auth.authorize(request)

            let body = Self.multipartBody(audio: audio, filename: audioFile.lastPathComponent, boundary: boundary)
            let (data, response) = try await session.upload(for: request, from: body)

            guard let http = response as? HTTPURLResponse else { throw VoiceError.unknown() }
            auth.handle(http, to: request)
            guard (200...299).contains(http.statusCode) else { throw VoiceError.fromStatus(http.statusCode) }

            let dto = try JSONDecoder().decode(TranscribeResponseDto.self, from: data)
            return dto.items.map { $0.toTranscribedItem() }
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as URLError where error.code == .cancelled && Task.isCancelled {
            // Only real task cancellation (same rule as SafeCall). URLSession also reports
            // .cancelled for a rejected challenge or an invalidated session: that's a failure.
            throw CancellationError()
        } catch {
            throw VoiceError.fromThrown(error)
        }
    }

    static func multipartBody(audio: Data, filename: String, boundary: String) -> Data {
        var body = Data()
        body.append(Data("--\(boundary)\r\n".utf8))
        body.append(Data("Content-Disposition: form-data; name=\"audio\"; filename=\"\(filename)\"\r\n".utf8))
        body.append(Data("Content-Type: audio/mp4\r\n\r\n".utf8))
        body.append(audio)
        body.append(Data("\r\n--\(boundary)--\r\n".utf8))
        return body
    }
}
