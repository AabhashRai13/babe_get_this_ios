import XCTest
@testable import BabeGetThis

/// STR-01…STR-15 and UI-08: `Localizable.xcstrings` uses Android's `strings.xml` keys with Android's English
/// wording. `android-strings.xml` next to this file is a byte-for-byte copy of
/// `app/src/main/res/values/strings.xml` on `origin/feat/got-this` (38eec7c). `scripts/check-android-strings.sh`
/// fails when Android's file has moved on, and prints the command that re-copies it.
final class StringCatalogTests: XCTestCase {
    /// String groups that are not in iOS v1: STR-12 (PIN and lock), STR-13 (reminders), STR-15 (Got This).
    static let excludedPrefixes = [
        "settings_pin_", "pin_", "recovery_", "lock_", "unlock_list",
        "reminder_", "settings_reminders_",
        "settings_got_this_", "got_this_",
    ]

    /// Where iOS says something else on purpose (STR-11: the App Store, not Google Play).
    static let iOSWording = ["settings_rate_subtitle": "Leave a review on the App Store"]

    private static let missing = "\u{FFFF}missing"

    func testEveryAndroidStringKeyIsInTheCatalog() throws {
        let android = try AndroidStrings.load()
        let strings = android.strings.filter { !Self.isExcluded($0.key) }
        XCTAssertGreaterThan(strings.count, 100, "the fixture should hold Android's v1 strings")

        for (key, androidValue) in strings.sorted(by: { $0.key < $1.key }) {
            let value = Bundle.main.localizedString(forKey: key, value: Self.missing, table: "Localizable")
            XCTAssertNotEqual(value, Self.missing, "\(key) is not in Localizable.xcstrings")
            guard value != Self.missing else { continue }
            let expected = Self.iOSWording[key] ?? AndroidStrings.iOSFormat(androidValue)
            XCTAssertEqual(value, expected, "\(key) differs from Android's wording")
        }
    }

    func testAndroidPluralsKeepBothForms() throws {
        let android = try AndroidStrings.load()
        let plurals = android.plurals.filter { !Self.isExcluded($0.key) }
        XCTAssertGreaterThanOrEqual(plurals.count, 6, "the fixture should hold Android's v1 plurals")

        for (key, forms) in plurals.sorted(by: { $0.key < $1.key }) {
            let format = Bundle.main.localizedString(forKey: key, value: Self.missing, table: "Localizable")
            XCTAssertNotEqual(format, Self.missing, "\(key) is not in Localizable.xcstrings")
            guard format != Self.missing else { continue }
            // Every argument gets the same number, so "one" and "other" both pick their own form, whichever
            // argument the plural hangs on (shopping_list_items_progress pluralises on the second).
            for (quantity, count) in [("one", 1), ("other", 2)] {
                let androidForm = try XCTUnwrap(forms[quantity], "\(key) has no \(quantity) form on Android")
                let arguments = Array(repeating: count, count: AndroidStrings.specifierCount(androidForm))
                let formatted = String(format: format, locale: Locale(identifier: "en"),
                                       arguments: arguments.isEmpty ? [count] : arguments)
                XCTAssertEqual(formatted, AndroidStrings.filled(androidForm, with: count),
                               "\(key) (\(quantity)) differs from Android")
            }
        }
    }

    static func isExcluded(_ key: String) -> Bool {
        excludedPrefixes.contains { key.hasPrefix($0) }
    }
}

/// Parses the copy of Android's `strings.xml`: plain strings, and plurals by quantity.
struct AndroidStrings {
    var strings: [String: String] = [:]
    var plurals: [String: [String: String]] = [:]

    static func load() throws -> AndroidStrings {
        let url = try XCTUnwrap(Bundle(for: StringCatalogTests.self).url(forResource: "android-strings",
                                                                       withExtension: "xml"),
                                "android-strings.xml is not in the test bundle")
        let parser = Parser()
        let xml = XMLParser(data: try Data(contentsOf: url))
        xml.delegate = parser
        XCTAssertTrue(xml.parse(), "android-strings.xml did not parse: \(String(describing: xml.parserError))")
        return parser.result
    }

    /// Android resource escapes and positional specifiers, written the way the String Catalog stores them.
    static func iOSFormat(_ android: String) -> String {
        var value = android
            .replacingOccurrences(of: "\\'", with: "'")
            .replacingOccurrences(of: "\\\"", with: "\"")
        value = value.replacingOccurrences(of: #"%(\d+\$)?s"#, with: "%$1@", options: .regularExpression)
        value = value.replacingOccurrences(of: #"%(\d+\$)?d"#, with: "%$1lld", options: .regularExpression)
        return value
    }

    static func specifierCount(_ android: String) -> Int {
        android.ranges(of: /%(\d+\$)?[ds]/).count
    }

    static func filled(_ android: String, with count: Int) -> String {
        iOSFormat(android).replacingOccurrences(of: #"%(\d+\$)?lld"#, with: "\(count)", options: .regularExpression)
    }

    private final class Parser: NSObject, XMLParserDelegate {
        var result = AndroidStrings()
        private var stringName: String?
        private var pluralName: String?
        private var quantity: String?
        private var text = ""

        func parser(_ parser: XMLParser, didStartElement element: String, namespaceURI: String?,
                    qualifiedName: String?, attributes: [String: String] = [:]) {
            switch element {
            case "string": stringName = attributes["name"]
            case "plurals": pluralName = attributes["name"]
            case "item": quantity = attributes["quantity"]
            default: break
            }
            text = ""
        }

        func parser(_ parser: XMLParser, foundCharacters string: String) {
            text += string
        }

        func parser(_ parser: XMLParser, didEndElement element: String, namespaceURI: String?,
                    qualifiedName: String?) {
            switch element {
            case "string":
                if let stringName { result.strings[stringName] = text }
                stringName = nil
            case "item":
                if let pluralName, let quantity { result.plurals[pluralName, default: [:]][quantity] = text }
                quantity = nil
            case "plurals":
                pluralName = nil
            default: break
            }
        }
    }
}
