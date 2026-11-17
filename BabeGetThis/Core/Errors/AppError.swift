import Foundation

/// Every error the app can show, same cases and copy as Android's `AppError`.
/// `message` is rendered straight to the user, so the defaults are product copy.
/// Repositories return `Result<T, AppError>` (Android's `Result.Success` / `Result.Error`).
enum AppError: Error, Equatable, Sendable, LocalizedError {
    // Database (GRDB)
    case database(String = String(localized: .errorDatabase))

    // Network
    case network(String = String(localized: .errorNetwork))
    case server(code: Int, message: String = String(localized: .errorServer))
    case timeout(String = String(localized: .errorTimeout))

    /// No default on purpose: a validation failure that can't say what was wrong is useless.
    case validation(String)

    case notFound(String = String(localized: .errorNotFound))

    /// Login/register failed (wrong credentials, email taken, ...).
    case auth(String = String(localized: .errorAuth))
    /// Server returned 401: the token expired or is invalid.
    case unauthorized(String = String(localized: .errorUnauthorized))

    case unknown(String = String(localized: .errorUnknown))

    var message: String {
        switch self {
        case .database(let m), .network(let m), .timeout(let m), .validation(let m),
             .notFound(let m), .auth(let m), .unauthorized(let m), .unknown(let m):
            m
        case .server(_, let m):
            m
        }
    }

    var errorDescription: String? { message }

    /// The case without its payload: what crash reports group by, and how tests check that
    /// every case has a reporting decision (Android uses `sealedSubclasses`).
    enum Kind: String, CaseIterable, Sendable {
        case database, network, server, timeout, validation, notFound, auth, unauthorized, unknown

        /// Android's class name (`UnknownError`), so reports group the same on both platforms.
        var name: String {
            switch self {
            case .database: "DatabaseError"
            case .network: "NetworkError"
            case .server: "ServerError"
            case .timeout: "TimeoutError"
            case .validation: "ValidationError"
            case .notFound: "NotFoundError"
            case .auth: "AuthError"
            case .unauthorized: "UnauthorizedError"
            case .unknown: "UnknownError"
            }
        }
    }

    var kind: Kind {
        switch self {
        case .database: .database
        case .network: .network
        case .server: .server
        case .timeout: .timeout
        case .validation: .validation
        case .notFound: .notFound
        case .auth: .auth
        case .unauthorized: .unauthorized
        case .unknown: .unknown
        }
    }
}

/// Lets code inside a `safeCall` block raise a specific AppError (validation, not found)
/// so it passes straight through instead of being re-derived from the thrown type.
struct AppErrorException: Error, Equatable, Sendable, LocalizedError {
    let appError: AppError

    init(_ appError: AppError) {
        self.appError = appError
    }

    var message: String { appError.message }
    var errorDescription: String? { message }
}
