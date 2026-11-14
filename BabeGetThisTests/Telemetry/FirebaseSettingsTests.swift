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

    func testAMalformedAppIDKeepsFirebaseOff() {
        // FirebaseApp.configure(options:) raises an uncatchable exception on these.
        let malformed = [
            "1:123:android:abc",        // the Android app id pasted by mistake
            "1:123:web:abc",            // the Web app id
            "1:123:ios:xyz",            // not hex
            "1:abc:ios:abc",            // no project number
            "1:123:ios:",               // no hashed bundle id
            "1:123:ios:abc:def",        // an extra part
            "2:123:ios:abc",            // a version Firebase doesn't know
            "1:123:ios:ａｂｃ",          // fullwidth hex
            "1:123:IOS:abc",
            "123:ios:abc",
        ]
        for appID in malformed {
            var settings = complete
            settings[FirebaseSettings.googleAppIDKey] = appID
            XCTAssertNil(FirebaseSettings.resolve(infoDictionary: settings, environment: .prod), appID)
        }
        // Surrounding whitespace is trimmed, as for every setting.
        var padded = complete
        padded[FirebaseSettings.googleAppIDKey] = " 1:123:ios:abc "
        XCTAssertEqual("1:123:ios:abc", FirebaseSettings.resolve(infoDictionary: padded, environment: .prod)?.googleAppID)
    }

    func testARealShapedAppIDIsAccepted() {
        XCTAssertTrue(FirebaseSettings.isValidGoogleAppID("1:1234567890:ios:0a1b2c3d4e5f6a7b8c9dEF"))
    }

    func testANonNumericSenderIDKeepsFirebaseOff() {
        var settings = complete
        settings[FirebaseSettings.gcmSenderIDKey] = "12a"
        XCTAssertNil(FirebaseSettings.resolve(infoDictionary: settings, environment: .staging))
    }

    func testWithoutSettingsTheVendorsAreNoOps() {
        let vendors = TelemetryVendors.make(settings: nil)

        XCTAssertTrue(vendors.analytics is NoOpAnalyticsRepository)
        XCTAssertTrue((vendors.crashReporter as? PolicyFilteredCrashReporter)?.wrapped is NoOpCrashReporter)
    }
}
