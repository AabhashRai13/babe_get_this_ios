import Foundation
import GRDB
import Supabase
import XCTest
@testable import BabeGetThis

/// Port of Android's SafeCallTest. Android exception types map to their iOS counterparts:
/// SQLiteException -> GRDB DatabaseError, java.net/SSL -> URLError, Retrofit HttpException ->
/// HTTPStatusFailure, Supabase RestException -> AuthError.api / PostgREST HTTPError / PostgrestError
/// (status derived from its code), Supabase transport and timeout ->
/// URLError (supabase-swift rethrows transport errors unwrapped).
final class SafeCallTests: XCTestCase {

    // Mapping only: nothing is reported.
    private let safeCall = SafeCall(reporter: SilentAppErrorReporter())

    func testReturnsSuccessWhenBlockCompletesNormally() async throws {
        let result = try await safeCall { 42 }
        XCTAssertEqual(.success(42), result)
    }

    func testMapsDatabaseErrorToDatabase() async throws {
        let result = try await safeCall { throw DatabaseError(resultCode: .SQLITE_ERROR, message: "db died") }
        guard case .database = error(of: result) else { return XCTFail("got \(result)") }
    }

    func testMapsHostNotFoundToNetwork() async throws {
        let result = try await safeCall { throw URLError(.cannotFindHost) }
        XCTAssertEqual(.network(), error(of: result))
    }

    func testMapsCannotConnectToNetworkWithReachabilityMessage() async throws {
        let result = try await safeCall { throw URLError(.cannotConnectToHost) }
        guard case .network(let message) = error(of: result) else { return XCTFail("got \(result)") }
        XCTAssertEqual("Cannot reach server.", message)
    }

    func testMapsSecureConnectionFailureToNetworkWithSecureConnectionMessage() async throws {
        let result = try await safeCall { throw URLError(.serverCertificateUntrusted) }
        guard case .network(let message) = error(of: result) else { return XCTFail("got \(result)") }
        XCTAssertEqual("Secure connection failed.", message)
    }

    func testMapsTimedOutToTimeout() async throws {
        let result = try await safeCall { throw URLError(.timedOut) }
        guard case .timeout = error(of: result) else { return XCTFail("got \(result)") }
    }

    func testDefault401MappingReturnsUnauthorized() async throws {
        let result = try await safeCall { throw HTTPStatusFailure(statusCode: 401) }
        guard case .unauthorized = error(of: result) else { return XCTFail("got \(result)") }
    }

    func testCustomOnUnauthorizedOverrides401Mapping() async throws {
        let custom = AppError.auth("Invalid email or password.")
        let result = try await safeCall(onUnauthorized: { custom }) {
            throw HTTPStatusFailure(statusCode: 401)
        }
        XCTAssertEqual(custom, error(of: result))
    }

    func testMaps4xxHTTPErrorToAuth() async throws {
        let result = try await safeCall { throw HTTPStatusFailure(statusCode: 404) }
        guard case .auth = error(of: result) else { return XCTFail("got \(result)") }
    }

    func testMaps5xxHTTPErrorToServerCarryingTheCode() async throws {
        let result = try await safeCall { throw HTTPStatusFailure(statusCode: 503) }
        guard case .server(let code, _) = error(of: result) else { return XCTFail("got \(result)") }
        XCTAssertEqual(503, code)
    }

    func testMapsUnrecognizedErrorToUnknown() async throws {
        let result = try await safeCall { throw CocoaError(.fileNoSuchFile) }
        XCTAssertEqual(.unknown(), error(of: result))
    }

    // A block that genuinely suspends is the real-world case: every caller awaits a DAO or the network.
    func testABlockThatGenuinelySuspendsStillSucceeds() async throws {
        let result = try await safeCall {
            try await Task.sleep(nanoseconds: 10_000_000)
            return 42
        }

        XCTAssertEqual(.success(42), result)
    }

    func testABlockThatThrowsAfterSuspendingIsStillMapped() async throws {
        let result = try await safeCall {
            try await Task.sleep(nanoseconds: 10_000_000)
            throw URLError(.cannotFindHost)
        }

        guard case .network = error(of: result) else { return XCTFail("got \(result)") }
    }

    func testBothOverridesSuppliedExplicitly() async throws {
        let result = try await safeCall(
            onUnauthorized: { .auth("explicit unauthorized") },
            onClientError: { .validation("explicit client \($0)") }
        ) { 7 }

        XCTAssertEqual(.success(7), result)
    }

    func testExplicitOnClientErrorIsUsedForA4xx() async throws {
        let result = try await safeCall(
            onUnauthorized: { .auth("u") },
            onClientError: { .validation("client \($0)") }
        ) { throw HTTPStatusFailure(statusCode: 422) }

        XCTAssertEqual("client 422", error(of: result)?.message)
    }

    // The default arm of the status mapping: a status outside 400...599.
    func testAStatusAboveTheServerRangeStillMapsToServer() async throws {
        let result = try await safeCall { throw HTTPStatusFailure(statusCode: 600) }

        guard case .server(let code, _) = error(of: result) else { return XCTFail("got \(result)") }
        XCTAssertEqual(600, code)
    }

    // Unlike the unrecognised-error arm, this one DOES pass text through: it is a status line,
    // not internal detail. Pinned so the difference stays deliberate.
    func testTheOutOfRangeArmCarriesTheHTTPStatusLine() async throws {
        let result = try await safeCall { throw HTTPStatusFailure(statusCode: 600) }

        XCTAssertTrue(error(of: result)?.message.contains("600") == true)
    }

    // Supabase raises its own error types; they are mapped by status like ours.
    func testMapsASupabase401ThroughOnUnauthorized() async throws {
        let result = try await safeCall { throw supabaseError(401) }

        guard case .unauthorized = error(of: result) else { return XCTFail("got \(result)") }
    }

    func testMapsASupabase4xxThroughOnClientError() async throws {
        let result = try await safeCall(onClientError: { .validation("client \($0)") }) {
            throw supabaseError(403)
        }

        XCTAssertEqual("client 403", error(of: result)?.message)
    }

    func testMapsASupabase5xxToServerCarryingTheCode() async throws {
        let result = try await safeCall { throw supabaseError(502) }

        guard case .server(let code, _) = error(of: result) else { return XCTFail("got \(result)") }
        XCTAssertEqual(502, code)
    }

    func testASupabaseErrorMessageNeverReachesTheUserFacingError() async throws {
        let result = try await safeCall { throw supabaseError(600) }

        let message = try XCTUnwrap(error(of: result)?.message)
        XCTAssertFalse(message.contains("Bearer"))
    }

    // supabase-swift rethrows transport failures (no DNS, refused, reset) as plain URLErrors.
    func testMapsASupabaseTransportFailureToNetwork() async throws {
        let result = try await safeCall { throw URLError(.networkConnectionLost) }

        guard case .network = error(of: result) else { return XCTFail("got \(result)") }
    }

    func testMapsASupabaseRequestTimeoutToTimeout() async throws {
        let result = try await safeCall { throw URLError(.timedOut, userInfo: [NSURLErrorFailingURLStringErrorKey: "https://x.supabase.co"]) }

        guard case .timeout = error(of: result) else { return XCTFail("got \(result)") }
    }

    // MARK: - iOS specifics

    // Cancellation is rethrown, never mapped or reported: dismissing the voice sheet is a gesture.
    func testCancellationIsRethrownAndNotReported() async {
        let reporter = RecordingAppErrorReporter()
        let reporting = SafeCall(reporter: reporter)

        do {
            _ = try await reporting { throw CancellationError() }
            XCTFail("cancellation must be rethrown")
        } catch {}
        do {
            _ = try await reporting { throw URLError(.cancelled) }
            XCTFail("a cancelled URL task must be rethrown as cancellation")
        } catch {}

        XCTAssertEqual(0, reporter.count)
    }

    // MARK: - PostgREST (supabase-swift throws PostgrestError, or HTTPError for an undecodable body)

    func testMapsAPostgrestHTTPError401ThroughOnUnauthorized() async throws {
        let result = try await safeCall { throw httpError(401) }

        guard case .unauthorized = error(of: result) else { return XCTFail("got \(result)") }
    }

    func testMapsAPostgrestHTTPError4xxThroughOnClientError() async throws {
        let result = try await safeCall(onClientError: { .validation("client \($0)") }) {
            throw httpError(404)
        }

        XCTAssertEqual("client 404", error(of: result)?.message)
    }

    func testMapsAPostgrestHTTPError5xxToServerCarryingTheCode() async throws {
        let result = try await safeCall { throw httpError(503) }

        guard case .server(let code, _) = error(of: result) else { return XCTFail("got \(result)") }
        XCTAssertEqual(503, code)
    }

    func testMapsAnExpiredJWTPostgrestErrorThroughOnUnauthorized() async throws {
        let result = try await safeCall { throw postgrestError("PGRST301") }

        guard case .unauthorized = error(of: result) else { return XCTFail("got \(result)") }
    }

    func testMapsAnRLSDenialPostgrestErrorThroughOnClientError403() async throws {
        let result = try await safeCall(onClientError: { .validation("client \($0)") }) {
            throw postgrestError("42501")
        }

        XCTAssertEqual("client 403", error(of: result)?.message)
    }

    func testMapsAUniqueViolationPostgrestErrorThroughOnClientError409() async throws {
        let result = try await safeCall(onClientError: { .validation("client \($0)") }) {
            throw postgrestError("23505")
        }

        XCTAssertEqual("client 409", error(of: result)?.message)
    }

    func testMapsAServerSidePostgrestErrorToServer() async throws {
        let result = try await safeCall { throw postgrestError("XX000") }

        guard case .server(let code, _) = error(of: result) else { return XCTFail("got \(result)") }
        XCTAssertEqual(500, code)
    }

    func testAPostgrestErrorWithoutACodeMapsToServer() async throws {
        let result = try await safeCall { throw PostgrestError(message: "boom") }

        guard case .server = error(of: result) else { return XCTFail("got \(result)") }
    }

    func testAPostgrestErrorMessageNeverReachesTheUserFacingError() async throws {
        let result = try await safeCall { throw postgrestError("42501") }

        let message = try XCTUnwrap(error(of: result)?.message)
        XCTAssertFalse(message.contains("secret"))
    }

    func testPostgrestStatusForCodes() {
        let cases: [(String?, Int)] = [
            ("PGRST301", 401), ("PGRST302", 401), ("PGRST300", 500), ("PGRST116", 406),
            ("PGRST100", 400), ("PGRST204", 400), ("PGRST000", 503), ("42501", 403),
            ("42P01", 404), ("42703", 400), ("23505", 409), ("23503", 409), ("23502", 400),
            ("22P02", 400), ("P0001", 400), ("28000", 403), ("08006", 503), ("XX000", 500), (nil, 500),
        ]
        for (code, status) in cases {
            XCTAssertEqual(status, SafeCall.postgrestStatus(forCode: code), "code \(code ?? "nil")")
        }
    }

    func testAMappedErrorIsReportedWithItsMapping() async throws {
        let reporter = RecordingAppErrorReporter()

        let reporting = SafeCall(reporter: reporter)

        _ = try await reporting { throw HTTPStatusFailure(statusCode: 503) }

        XCTAssertEqual([.server(code: 503)], reporter.mapped)
    }

    func testADeliberateAppErrorPassesStraightThrough() async throws {
        let result = try await safeCall { throw AppErrorException(.notFound("No such list.")) }

        XCTAssertEqual(.notFound("No such list."), error(of: result))
    }

    // MARK: - Helpers

    private func error<T>(of result: Result<T, AppError>) -> AppError? {
        if case .failure(let error) = result { return error }
        return nil
    }

    private func httpError(_ code: Int) -> HTTPError {
        HTTPError(
            data: Data("<html>secret upstream page</html>".utf8),
            response: HTTPURLResponse(url: URL(string: "https://x.supabase.co/rest/v1/lists")!, statusCode: code, httpVersion: nil, headerFields: nil)!
        )
    }

    private func postgrestError(_ code: String) -> PostgrestError {
        PostgrestError(details: "secret detail", hint: nil, code: code, message: "secret message for \(code)")
    }

    private func supabaseError(_ code: Int) -> AuthError {
        .api(
            message: "boom\nHeaders: [Authorization=[Bearer secret]]",
            errorCode: .unknown,
            underlyingData: Data(),
            underlyingResponse: HTTPURLResponse(
                url: URL(string: "https://x.supabase.co")!,
                statusCode: code,
                httpVersion: nil,
                headerFields: ["Authorization": "Bearer secret"]
            )!
        )
    }
}

private final class RecordingAppErrorReporter: AppErrorReporter, @unchecked Sendable {
    private let lock = NSLock()
    private var _mapped: [AppError] = []

    var mapped: [AppError] { lock.withLock { _mapped } }
    var count: Int { mapped.count }

    func report(_ error: any Error, mapped: AppError) {
        lock.withLock { _mapped.append(mapped) }
    }
}
