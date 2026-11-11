import XCTest
@testable import BabeGetThis

final class AppConfigTests: XCTestCase {
    private let valid: [String: Any] = [
        "BGTEnvironment": "dev",
        "BGTSupabaseURL": "http://127.0.0.1:54321",
        "BGTSupabaseAnonKey": "anon",
        "BGTApiBaseURL": "http://127.0.0.1:8080/",
    ]

    func testParsesValidInfoDictionary() throws {
        let config = try AppConfig(infoDictionary: valid)
        XCTAssertEqual(config.environment, .dev)
        XCTAssertEqual(config.supabaseURL.absoluteString, "http://127.0.0.1:54321")
        XCTAssertEqual(config.supabaseAnonKey, "anon")
        XCTAssertEqual(config.apiBaseURL.absoluteString, "http://127.0.0.1:8080/")
    }

    func testMissingKeyThrows() {
        var info = valid
        info["BGTSupabaseURL"] = nil
        XCTAssertThrowsError(try AppConfig(infoDictionary: info)) { error in
            XCTAssertEqual(error as? AppConfig.ConfigError, .missing("BGTSupabaseURL"))
        }
    }

    func testUnknownEnvironmentThrows() {
        var info = valid
        info["BGTEnvironment"] = "qa"
        XCTAssertThrowsError(try AppConfig(infoDictionary: info)) { error in
            XCTAssertEqual(error as? AppConfig.ConfigError, .invalid("BGTEnvironment"))
        }
    }

    func testURLWithoutHostThrows() {
        var info = valid
        info["BGTApiBaseURL"] = "http:"
        XCTAssertThrowsError(try AppConfig(infoDictionary: info)) { error in
            XCTAssertEqual(error as? AppConfig.ConfigError, .invalid("BGTApiBaseURL"))
        }
    }

    /// Unit tests run hosted in the app, so Bundle.main is the app built with Dev.xcconfig.
    func testHostAppIsBuiltForDev() throws {
        let config = try AppConfig(infoDictionary: Bundle.main.infoDictionary ?? [:])
        XCTAssertEqual(config.environment, .dev)
        XCTAssertEqual(config.supabaseURL.absoluteString, "http://127.0.0.1:54321")
        XCTAssertEqual(config.apiBaseURL.absoluteString, "http://127.0.0.1:8080/")
    }
}

final class LaunchRouteTests: XCTestCase {
    func testOpenListFindsSampleList() {
        let path = LaunchRoute.initialPath(arguments: ["app", "-sampleData", "-openList", "sample-sunday-roast"])
        XCTAssertEqual(path.map(\.id), ["sample-sunday-roast"])
    }

    func testMissingOrUnknownListGivesEmptyPath() {
        XCTAssertTrue(LaunchRoute.initialPath(arguments: ["app", "-sampleData"]).isEmpty)
        XCTAssertTrue(LaunchRoute.initialPath(arguments: ["app", "-openList"]).isEmpty)
        XCTAssertTrue(LaunchRoute.initialPath(arguments: ["app", "-openList", "nope"]).isEmpty)
    }
}
