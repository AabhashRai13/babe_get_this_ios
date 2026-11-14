import XCTest
@testable import BabeGetThis

/// TEL-01: Firebase is configured only in Staging and Prod with all four settings present.
/// Dev never touches it. Nothing here configures Firebase.
final class FirebaseSettingsTests: XCTestCase {
    private let complete: [String: Any] = [
        FirebaseSettings.googleAppIDKey: "1:123:ios:abc",
        FirebaseSettings.gcmSenderIDKey: "123",
        FirebaseSettings.apiKeyKey: "key",
        FirebaseSettings.projectIDKey: "babe-get-this",
    ]

    func testDevNeverConfiguresFirebaseEvenWithEverySetting() {
        XCTAssertNil(FirebaseSettings.resolve(infoDictionary: complete, environment: .dev))
    }

    func testStagingAndProdWithEverySettingConfigureFirebase() {
        let expected = FirebaseSettings(googleAppID: "1:123:ios:abc", gcmSenderID: "123", apiKey: "key", projectID: "babe-get-this")
        XCTAssertEqual(expected, FirebaseSettings.resolve(infoDictionary: complete, environment: .staging))
        XCTAssertEqual(expected, FirebaseSettings.resolve(infoDictionary: complete, environment: .prod))
    }

    func testAnyMissingOrBlankSettingKeepsFirebaseOff() {
        for key in complete.keys {
            var missing = complete
            missing[key] = nil
            XCTAssertNil(FirebaseSettings.resolve(infoDictionary: missing, environment: .prod), "without \(key)")
            var blank = complete
            blank[key] = "  "
            XCTAssertNil(FirebaseSettings.resolve(infoDictionary: blank, environment: .prod), "blank \(key)")
        }
    }

    func testWithoutSettingsTheVendorsAreNoOps() {
        let vendors = TelemetryVendors.make(settings: nil)

        XCTAssertTrue(vendors.analytics is NoOpAnalyticsRepository)
        XCTAssertTrue(vendors.crashReporter is NoOpCrashReporter)
    }
}
