import Foundation

/// Error categories the voice flow can surface, same set and copy as Android's AppError.
enum VoiceError: Error, Equatable, Sendable {
    case network(String = "No internet connection.")
    case timeout(String = "Request timed out. Please try again.")
    case unauthorized(String = "Session expired. Please log in again.")
    case server(code: Int, message: String = "Server error. Please try later.")
    case unknown(String = "An unexpected error occurred.")

    var message: String {
        switch self {
        case .network(let m), .timeout(let m), .unauthorized(let m), .unknown(let m): m
        case .server(_, let m): m
        }
    }

    static let recordingProblem = "Couldn't process that recording. Please try again."

    /// Maps an HTTP status like Android's safeCall, with transcribe's 4xx override.
    static func fromStatus(_ code: Int) -> VoiceError {
        switch code {
        case 401: .unauthorized()
        case 400...499: .server(code: code, message: recordingProblem)
        case 500...599: .server(code: code, message: "Server error. Please try later.")
        default: .server(code: code, message: "Unexpected server response.")
        }
    }

    /// Maps a transport or other thrown error. Never passes the raw message through.
    static func fromThrown(_ error: Error) -> VoiceError {
        if let voice = error as? VoiceError { return voice }
        if let url = error as? URLError {
            switch url.code {
            case .timedOut: return .timeout()
            case .cannotConnectToHost: return .network("Cannot reach server.")
            case .secureConnectionFailed, .serverCertificateUntrusted, .serverCertificateHasBadDate,
                 .serverCertificateHasUnknownRoot, .serverCertificateNotYetValid, .clientCertificateRejected,
                 .clientCertificateRequired:
                return .network("Secure connection failed.")
            default: return .network()
            }
        }
        return .unknown()
    }
}
