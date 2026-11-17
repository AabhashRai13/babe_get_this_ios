import Foundation

/// Error categories the voice flow can surface, same set and copy as Android's AppError.
enum VoiceError: Error, Equatable, Sendable {
    case network(String = String(localized: .errorNetwork))
    case timeout(String = String(localized: .errorTimeout))
    case unauthorized(String = String(localized: .errorUnauthorized))
    case server(code: Int, message: String = String(localized: .errorServer))
    case unknown(String = String(localized: .errorUnknown))

    var message: String {
        switch self {
        case .network(let m), .timeout(let m), .unauthorized(let m), .unknown(let m): m
        case .server(_, let m): m
        }
    }

    static var recordingProblem: String { String(localized: .voiceErrorRecording) }

    /// Maps an HTTP status like Android's safeCall, with transcribe's 4xx override.
    static func fromStatus(_ code: Int) -> VoiceError {
        switch code {
        case 401: .unauthorized()
        case 400...499: .server(code: code, message: recordingProblem)
        case 500...599: .server(code: code, message: String(localized: .errorServer))
        default: .server(code: code, message: String(localized: .errorUnexpectedResponse))
        }
    }

    /// Maps a transport or other thrown error. Never passes the raw message through.
    static func fromThrown(_ error: Error) -> VoiceError {
        if let voice = error as? VoiceError { return voice }
        if let url = error as? URLError {
            switch url.code {
            case .timedOut: return .timeout()
            case .cannotConnectToHost: return .network(String(localized: .errorCannotReachServer))
            case .secureConnectionFailed, .serverCertificateUntrusted, .serverCertificateHasBadDate,
                 .serverCertificateHasUnknownRoot, .serverCertificateNotYetValid, .clientCertificateRejected,
                 .clientCertificateRequired:
                return .network(String(localized: .errorSecureConnection))
            default: return .network()
            }
        }
        return .unknown()
    }
}
