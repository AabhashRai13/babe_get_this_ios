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

    private func policedSafeCall(_ transmitted: RecordingCrashReporter) -> SafeCall {
        SafeCall(reporter: ErrorReporter(crashReporter: PolicedCrashReporter(sink: transmitted)))
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
}

/// Applies the policy the way `FirebaseCrashlyticsCrashReporter.recordNonFatal` does, then
/// records what would have been sent.
private struct PolicedCrashReporter: CrashReporter {
    let sink: RecordingCrashReporter

    func breadcrumb(_ message: String) {}
    func setKey(_ key: CrashKey, value: String) {}
    func recordNonFatal(_ error: any Error, appError: AppError) {
        guard ErrorReportingPolicy.shouldReport(appError) else { return }
        sink.recordNonFatal(error, appError: appError)
    }
    func setUser(_ userId: String?) {}
    func setCollectionEnabled(_ enabled: Bool) {}
}
