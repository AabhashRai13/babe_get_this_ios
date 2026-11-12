import Foundation
import GRDB
import os
import Supabase

/// Wraps every database/network call a repository makes and maps whatever it throws to an
/// AppError, so view models only ever see a `Result<T, AppError>`. Port of Android's `SafeCall`.
///
/// `onUnauthorized` overrides the 401 mapping (default "Session expired..."); login and register
/// pass `.auth("Invalid email or password.")` because a 401 there means wrong credentials.
/// `onClientError` maps other 4xx codes; the default is auth-flavoured, so non-auth callers
/// override it.
struct SafeCall: Sendable {
    private let reporter: any AppErrorReporter

    init(reporter: any AppErrorReporter) {
        self.reporter = reporter
    }

    /// Cancellation is rethrown, never mapped: a cancelled task (dismissing the voice sheet)
    /// is a user gesture, not a failed operation, and is not reported. Like Android, only
    /// structured cancellation counts; a transport-level cancel of a live task is a failure.
    func callAsFunction<T>(
        isolation: isolated (any Actor)? = #isolation,
        onUnauthorized: () -> AppError = { .unauthorized() },
        onClientError: (Int) -> AppError = { _ in .auth("Request failed.") },
        _ block: () async throws -> T
    ) async throws(CancellationError) -> Result<T, AppError> {
        do {
            return .success(try await block())
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as URLError where error.code == .cancelled && Task.isCancelled {
            // Only real task cancellation. URLSession also reports .cancelled for a rejected
            // challenge or an invalidated session while our task is live: that maps to .network.
            throw CancellationError()
        } catch {
            let mapped = Self.map(error, onUnauthorized: onUnauthorized, onClientError: onClientError)
            reporter.report(error, mapped: mapped)
            return .failure(mapped)
        }
    }

    private static let logger = Logger(subsystem: "com.babegetthis.ios", category: "SafeCall")

    static func map(
        _ error: any Error,
        onUnauthorized: () -> AppError,
        onClientError: (Int) -> AppError
    ) -> AppError {
        switch error {
        // An AppError the caller chose deliberately: pass it straight through.
        case let error as AppErrorException:
            return error.appError
        case let error as AppError:
            return error

        case is DatabaseError:
            return .database()

        case let error as URLError:
            return map(error)

        // Our own URLSession clients (Retrofit's HttpException on Android).
        case let error as HTTPStatusFailure:
            switch error.statusCode {
            case 401: return onUnauthorized()
            case 400...499: return onClientError(error.statusCode)
            case 500...599: return .server(code: error.statusCode, message: "Server error. Please try later.")
            default: return .server(code: error.statusCode, message: error.statusLine)
            }

        // Supabase errors carrying a status. Their messages can embed request details,
        // so they are mapped by status only and the message is never passed through.
        case let error as AuthError:
            if case .api(_, _, _, let response) = error {
                return mapSupabaseStatus(response.statusCode, onUnauthorized, onClientError)
            }
            return unrecognised(error)
        case let error as FunctionsError:
            if case .httpError(let code, _) = error {
                return mapSupabaseStatus(code, onUnauthorized, onClientError)
            }
            return unrecognised(error)
        // PostgREST (tables, RPC). A body that doesn't decode as a PostgREST error keeps its status.
        case let error as HTTPError:
            return mapSupabaseStatus(error.response.statusCode, onUnauthorized, onClientError)
        // A decoded PostgREST error carries the code but not the status; derive the status
        // PostgREST answers with for that code (Android maps the RestException's status).
        case let error as PostgrestError:
            return mapSupabaseStatus(postgrestStatus(forCode: error.code), onUnauthorized, onClientError)

        default:
            return unrecognised(error)
        }
    }

    /// Transport failures. supabase-swift rethrows these unwrapped, so this covers it too.
    private static func map(_ error: URLError) -> AppError {
        switch error.code {
        case .timedOut:
            return .timeout()
        case .cannotConnectToHost:
            return .network("Cannot reach server.")
        case .secureConnectionFailed, .serverCertificateUntrusted, .serverCertificateHasBadDate,
             .serverCertificateHasUnknownRoot, .serverCertificateNotYetValid, .clientCertificateRejected,
             .clientCertificateRequired:
            return .network("Secure connection failed.")
        default:
            return .network()
        }
    }

    private static func mapSupabaseStatus(
        _ code: Int,
        _ onUnauthorized: () -> AppError,
        _ onClientError: (Int) -> AppError
    ) -> AppError {
        switch code {
        case 401: onUnauthorized()
        case 400...499: onClientError(code)
        default: .server(code: code, message: "Server error. Please try later.")
        }
    }

    /// The HTTP status PostgREST answers with for an error code (PostgREST "Errors" reference):
    /// its own `PGRSTxxx` codes, or the PostgreSQL SQLSTATE of a failed statement.
    static func postgrestStatus(forCode code: String?) -> Int {
        guard let code else { return 500 }
        switch code {
        case "PGRST301", "PGRST302", "PGRST303": return 401   // JWT invalid/expired, anonymous disabled
        case "PGRST116": return 406                           // .single() matched 0 or many rows
        case "42501": return 403                              // insufficient privilege (RLS)
        case "42883", "42P01": return 404                     // undefined function / table
        case "23503", "23505": return 409                     // foreign key / unique violation
        case "40001": return 409                              // serialization failure
        case "P0001": return 400                              // raise_exception from a function
        default: break
        }
        if code.hasPrefix("PGRST0") { return 503 }            // database connection
        if code.hasPrefix("PGRST1") || code.hasPrefix("PGRST2") { return 400 }  // request / schema cache
        if code.hasPrefix("PGRST") { return 500 }
        if code.hasPrefix("08") || code.hasPrefix("53") { return 503 }
        if code.hasPrefix("28") || code.hasPrefix("0L") || code.hasPrefix("0P") { return 403 }
        if code.hasPrefix("22") || code.hasPrefix("23") || code.hasPrefix("42") { return 400 }
        return 500
    }

    /// Deliberately does NOT pass the error's text through: it is rendered in the UI, and an
    /// unrecognised error's text is internal detail (a file path, a header). Logged instead.
    private static func unrecognised(_ error: any Error) -> AppError {
        logger.error("Unrecognised error mapped to unknown: \(String(describing: error), privacy: .private)")
        return .unknown()
    }
}
