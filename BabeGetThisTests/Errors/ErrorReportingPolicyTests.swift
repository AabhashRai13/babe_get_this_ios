import Foundation
import XCTest
@testable import BabeGetThis

/// Port of Android's ErrorReportingPolicyTest (ERR-03). The policy's job is to send less, so the
/// tests that matter assert what does NOT get reported.
final class ErrorReportingPolicyTests: XCTestCase {

    /// One of every AppError case.
    private let all: [AppError] = [
        .unknown(), .database(), .network(), .timeout(), .validation("x"),
        .auth(), .unauthorized(), .notFound(), .server(code: 500),
    ]

    func testUnexpectedFailuresAreReported() {
        // safeCall met an error it had no mapping for.
        XCTAssertTrue(ErrorReportingPolicy.shouldReport(.unknown()))
        // The local database failed, which is never the user's fault.
        XCTAssertTrue(ErrorReportingPolicy.shouldReport(.database()))
    }

    func testOfflineFirstFailuresAreNeverReported() {
        XCTAssertFalse(ErrorReportingPolicy.shouldReport(.network()))
        XCTAssertFalse(ErrorReportingPolicy.shouldReport(.timeout()))
    }

    func testUserFacingConditionsWithUserFacingRecoveryAreNotReported() {
        XCTAssertFalse(ErrorReportingPolicy.shouldReport(.validation("bad")))
        XCTAssertFalse(ErrorReportingPolicy.shouldReport(.auth()))
        XCTAssertFalse(ErrorReportingPolicy.shouldReport(.unauthorized()))
        // A share code that matched no list is a typo, not a defect.
        XCTAssertFalse(ErrorReportingPolicy.shouldReport(.notFound()))
    }

    func testServerErrorsAreLeftToTheServersOwnMonitoring() {
        XCTAssertFalse(ErrorReportingPolicy.shouldReport(.server(code: 500)))
        XCTAssertFalse(ErrorReportingPolicy.shouldReport(.server(code: 503)))
    }

    func testEveryAppErrorCaseHasAnExplicitDecision() {
        // The policy's switch has no default, so a new case won't compile. This guards the other
        // direction: the list above must keep covering the real set.
        XCTAssertEqual(
            AppError.Kind.allCases.count,
            Set(all.map(\.kind)).count,
            "AppError gained or lost a case: decide about it in ErrorReportingPolicy")
    }

    func testTheReportedSetStaysSmall() {
        // Widening the whitelist costs dashboard signal, so it should trip this test.
        XCTAssertEqual(2, all.filter(ErrorReportingPolicy.shouldReport).count)
    }

    // MARK: - The composition, end to end: real errors through SafeCall with the app's wiring.

    /// The app's composition: `TelemetryVendors` puts the shipped `PolicyFilteredCrashReporter`
    /// in front of the vendor (here a recorder standing in for Crashlytics), and the container
    /// hands that reporter to SafeCall.
    private func policedSafeCall(_ transmitted: RecordingCrashReporter) -> SafeCall {
        let vendors = TelemetryVendors(analytics: RecordingAnalytics(), crashReporter: transmitted)
        return SafeCall(reporter: ErrorReporter(crashReporter: vendors.crashReporter))
    }

    func testASessionOfflineProducesNoNonFatalsAtAll() async throws {
        let transmitted = RecordingCrashReporter()
        let safeCall = policedSafeCall(transmitted)

        // A user on a train: every call fails, over and over.
        for _ in 0..<20 {
            _ = try await safeCall { throw URLError(.cannotFindHost) }
            _ = try await safeCall { throw URLError(.timedOut) }
        }

        XCTAssertTrue(transmitted.nonFatals.isEmpty, "offline noise reached Crashlytics: \(transmitted.nonFatals)")
    }

    func testOneUnmappedErrorProducesExactlyOneNonFatal() async throws {
        let transmitted = RecordingCrashReporter()
        let safeCall = policedSafeCall(transmitted)

        _ = try await safeCall { throw TestFailure(message: "nobody mapped this") }

        XCTAssertEqual([.unknown], transmitted.nonFatals.map(\.kind))
    }

    func testEveryVendorTheAppCanRunWithIsFiltered() {
        let transmitted = RecordingCrashReporter()
        let reporter = TelemetryVendors(analytics: RecordingAnalytics(), crashReporter: transmitted).crashReporter

        for error in all {
            reporter.recordNonFatal(TestFailure(message: "x"), appError: error)
        }

        XCTAssertEqual([.unknown, .database], transmitted.nonFatals.map(\.kind))
    }

    func testTheFilterForwardsEverythingElse() {
        let transmitted = RecordingCrashReporter()
        let reporter = PolicyFilteredCrashReporter(wrapped: transmitted)

        reporter.breadcrumb("b")
        reporter.setKey(.flavor, value: "prod")
        reporter.setUser("u1")
        reporter.setCollectionEnabled(false)

        XCTAssertEqual(["b"], transmitted.breadcrumbs)
        XCTAssertEqual(["prod"], transmitted.values(for: .flavor))
        XCTAssertEqual(["u1"], transmitted.users)
        XCTAssertEqual([false], transmitted.collection)
    }
}
