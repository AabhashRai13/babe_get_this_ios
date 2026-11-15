import XCTest
@testable import BabeGetThis

/// What `FirebaseCrashlyticsCrashReporter` asks of the SDK, against a fake client. Nothing here
/// configures Firebase or calls `Crashlytics.crashlytics()`.
final class FirebaseCrashlyticsCrashReporterTests: XCTestCase {
    private let client = RecordingCrashlyticsClient()

    private var reporter: FirebaseCrashlyticsCrashReporter {
        let client = client
        return FirebaseCrashlyticsCrashReporter(client: { client })
    }

    func testOptingOutDeletesTheReportsWrittenWhileCollectionWasOff() {
        // With collection off, Crashlytics keeps reports on disk and sends them if collection is
        // turned back on: an opt-out must delete them.
        reporter.setCollectionEnabled(false)

        XCTAssertEqual(["collection false", "deleteUnsentReports"], client.calls)
    }

    func testOptingInDeletesNothing() {
        reporter.setCollectionEnabled(true)

        XCTAssertEqual(["collection true"], client.calls)
    }

    func testANonFatalCarriesItsAppErrorKind() {
        reporter.recordNonFatal(TestFailure(message: "x"), appError: .database())

        XCTAssertEqual(["key app_error=\(AppError.database().kind.name)", "record"], client.calls)
    }

    func testSigningOutClearsTheUserWithAnEmptyString() {
        reporter.setUser("user-1")
        reporter.setUser(nil)

        XCTAssertEqual(["user user-1", "user "], client.calls)
    }

    func testBreadcrumbsAndKeysGoStraightThrough() {
        reporter.breadcrumb("sync failed")
        reporter.setKey(.flavor, value: "staging")

        XCTAssertEqual(["log sync failed", "key flavor=staging"], client.calls)
    }
}

/// Records each SDK call as a short string, in order.
final class RecordingCrashlyticsClient: CrashlyticsClient, @unchecked Sendable {
    private let lock = NSLock()
    private var _calls: [String] = []

    var calls: [String] { lock.withLock { _calls } }

    private func record(_ call: String) { lock.withLock { _calls.append(call) } }

    func log(_ msg: String) { record("log \(msg)") }
    func setCustomValue(_ value: Any?, forKey key: String) { record("key \(key)=\(value ?? "nil")") }
    func record(error: any Error) { record("record") }
    func setUserID(_ userID: String?) { record("user \(userID ?? "nil")") }
    func setCrashlyticsCollectionEnabled(_ enabled: Bool) { record("collection \(enabled)") }
    func deleteUnsentReports() { record("deleteUnsentReports") }
}
