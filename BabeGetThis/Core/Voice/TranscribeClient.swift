import Foundation

/// Uploads a recorded .m4a to POST {apiBaseURL}transcribe and maps the response to TranscribedItems.
/// No recording and no UI here: the caller hands in a file URL.
struct TranscribeClient: Sendable {
    static let timeout: TimeInterval = 60

    private let baseURL: URL
    private let session: URLSession
    private let accessToken: @Sendable () async -> String?
    private let isOnline: @Sendable () -> Bool

    /// - Parameters:
    ///   - session: inject a session whose configuration carries a stub URLProtocol in tests.
    ///   - accessToken: the current Supabase access token.
    ///   - isOnline: proactive offline guard; fails fast instead of waiting for a timeout.
    init(
        baseURL: URL,
        session: URLSession = .shared,
        accessToken: @escaping @Sendable () async -> String?,
        isOnline: @escaping @Sendable () -> Bool = { true }
    ) {
        self.baseURL = baseURL
        self.session = session
        self.accessToken = accessToken
        self.isOnline = isOnline
    }

    func transcribeAndParse(audioFile: URL) async throws -> [TranscribedItem] {
        guard isOnline() else { throw VoiceError.network() }
        do {
            let audio = try Data(contentsOf: audioFile)
            guard let token = await accessToken() else { throw VoiceError.unauthorized() }

            let boundary = "Boundary-\(UUID().uuidString)"
            var request = URLRequest(url: baseURL.appending(path: "transcribe"), timeoutInterval: Self.timeout)
            request.httpMethod = "POST"
            request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

            let body = Self.multipartBody(audio: audio, filename: audioFile.lastPathComponent, boundary: boundary)
            let (data, response) = try await session.upload(for: request, from: body)

            guard let http = response as? HTTPURLResponse else { throw VoiceError.unknown() }
            guard (200...299).contains(http.statusCode) else { throw VoiceError.fromStatus(http.statusCode) }

            let dto = try JSONDecoder().decode(TranscribeResponseDto.self, from: data)
            return dto.items.map { $0.toTranscribedItem() }
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as URLError where error.code == .cancelled {
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
