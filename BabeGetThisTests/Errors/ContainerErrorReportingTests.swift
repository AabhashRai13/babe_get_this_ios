import GRDB
import XCTest
@testable import BabeGetThis

/// ERR-03 at the composition root: what the container builds reports through the app's crash
/// reporter, behind the policy filter. Nothing here configures Firebase or opens a Supabase client.
@MainActor
final class ContainerErrorReportingTests: XCTestCase {
    private var transmitted: RecordingCrashReporter!
    private var database: AppDatabase!
    private var container: AppContainer!

    override func setUp() async throws {
        try await super.setUp()
        transmitted = RecordingCrashReporter()
        database = try AppDatabase.inMemory()
        container = AppContainer(
            config: .preview, authState: AuthStateManager(tokenStore: InMemoryTokenStore()), database: database,
            ownership: FakeListOwnershipStore(),
            telemetry: TelemetryVendors(analytics: RecordingAnalytics(), crashReporter: transmitted),
            telemetryConsentStore: InMemoryTelemetryConsentStore())
    }

    func testTheContainersCrashReporterIsFiltered() {
        container.crashReporter.recordNonFatal(URLError(.notConnectedToInternet), appError: .network())
        container.crashReporter.recordNonFatal(TestFailure(message: "x"), appError: .unknown())

        XCTAssertEqual([.unknown], transmitted.nonFatals.map(\.kind))
    }

    func testACategoryDatabaseFailureReachesCrashReporting() async throws {
        // Any insert into categories now fails inside SQLite.
        try await database.writer.write { db in
            try db.execute(sql: """
                CREATE TRIGGER fail_category_insert BEFORE INSERT ON categories
                BEGIN SELECT RAISE(ABORT, 'disk on fire'); END
                """)
        }

        let result = try await container.categoryPickerSource.addCategory(name: "Garden")

        guard case .failure(let error) = result else { return XCTFail("expected a failure, got \(result)") }
        XCTAssertEqual(.database, error.kind)
        XCTAssertEqual([.database], transmitted.nonFatals.map(\.kind))
    }

    func testTheSignInReporterReachesCrashReporting() {
        // `makeLoginViewModel()` passes this reporter (LoginViewModel has no silent default, so a
        // call site can't leave it out); building it here would open a Supabase client.
        container.errorReporter.report(TestFailure(message: "misconfigured OAuth client"), mapped: .unknown())

        XCTAssertEqual([.unknown], transmitted.nonFatals.map(\.kind))
    }
}
