import Foundation
import XCTest
@testable import BabeGetThis

/// Port of Android's SafeCallReportingTest. SafeCall is the funnel every repository failure
/// passes through, so its reporter decides whether a handled error ever leaves the device. The
/// interesting assertions count reports that must NOT happen.
final class SafeCallReportingTests: XCTestCase {
    private let reported = ReportLog()
    private lazy var safeCall = SafeCall(reporter: ErrorReporter { [reported] error, mapped in
        reported.append(error, mapped)
    })

    func testAnUnrecognisedErrorIsOfferedToTheReporter() async throws {
        let boom = TestFailure(message: "something nobody mapped")

        _ = try await safeCall { throw boom }

        XCTAssertEqual(1, reported.count)
        XCTAssertEqual(boom, reported.errors.first as? TestFailure)
        XCTAssertEqual(.unknown, reported.mapped.first?.kind)
    }

    func testTheOriginalErrorIsOfferedNotTheUserFacingMessage() async throws {
        // AppError.message is scrubbed copy; the original error is what a report needs.
        let boom = TestFailure(message: "/var/mobile/Containers/Data/voice.m4a (No such file)")

        _ = try await safeCall { throw boom }

        XCTAssertEqual(boom, reported.errors.first as? TestFailure)
    }

    func testOfflineFailuresStillReachTheReporterWhereThePolicyDropsThem() async throws {
        // SafeCall does not filter; ErrorReportingPolicy does, behind CrashReporter.recordNonFatal.
        _ = try await safeCall { throw URLError(.cannotFindHost) }
        _ = try await safeCall { throw URLError(.timedOut) }

        XCTAssertEqual(2, reported.count)
        XCTAssertTrue(reported.mapped.allSatisfy { $0.kind == .network || $0.kind == .timeout })
    }

    func testACancelledTaskIsNeverReported() async {
        // Dismissing the voice sheet cancels the transcribe call: a gesture, not a failure.
        _ = try? await safeCall { throw CancellationError() }

        XCTAssertTrue(reported.mapped.isEmpty, "a cancellation was reported")
    }

    func testASuccessfulCallReportsNothing() async throws {
        _ = try await safeCall { "fine" }

        XCTAssertTrue(reported.mapped.isEmpty)
    }

    func testAReporterThatThrowsCannotTurnAHandledErrorIntoACrash() async throws {
        let safeCall = SafeCall(reporter: ErrorReporter { _, _ in throw TestFailure(message: "reporter down") })

        let result = try await safeCall { throw TestFailure(message: "original") }

        guard case .failure(let error) = result else { return XCTFail("got \(result)") }
        XCTAssertEqual(.unknown, error.kind)
    }

    func testADeliberatelyRaisedAppErrorReachesTheReporterWithItsOwnType() async throws {
        // The policy needs the real case, not unknown.
        _ = try await safeCall { throw AppErrorException(.database()) }

        XCTAssertEqual([.database], reported.mapped.map(\.kind))
    }
}

struct TestFailure: Error, Equatable {
    let message: String
}

/// What a reporter was handed, in order.
final class ReportLog: @unchecked Sendable {
    private let lock = NSLock()
    private var _errors: [any Error] = []
    private var _mapped: [AppError] = []

    var errors: [any Error] { lock.withLock { _errors } }
    var mapped: [AppError] { lock.withLock { _mapped } }
    var count: Int { mapped.count }

    func append(_ error: any Error, _ mapped: AppError) {
        lock.withLock {
            _errors.append(error)
            _mapped.append(mapped)
        }
    }
}
