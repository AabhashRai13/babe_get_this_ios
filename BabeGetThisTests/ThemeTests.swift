import UIKit
import XCTest
@testable import BabeGetThis

final class ThemeTests: XCTestCase {
    func testEveryColorAssetExistsInLightAndDark() {
        for name in AppColors.assetNames {
            let color = UIColor(named: name, in: .main, compatibleWith: nil)
            XCTAssertNotNil(color, "missing colour asset \(name)")
            let light = color?.resolvedColor(with: UITraitCollection(userInterfaceStyle: .light))
            let dark = color?.resolvedColor(with: UITraitCollection(userInterfaceStyle: .dark))
            XCTAssertNotEqual(light, dark, "\(name) has no dark variant")
        }
    }

    // Expected values are java.lang.String.hashCode() results.
    func testJavaHashCodeMatchesJVM() {
        XCTAssertEqual(javaHashCode(""), 0)
        XCTAssertEqual(javaHashCode("hello"), 99_162_322)
        XCTAssertEqual(javaHashCode("polygenelubricants"), Int32.min)
    }

    func testListAccentMatchesAndroidIndex() {
        XCTAssertEqual(ListAccent(listId: "hello").index, 2)            // 99162322 % 8
        XCTAssertEqual(ListAccent(listId: "polygenelubricants").index, 0) // abs(MIN_VALUE) % 8 on the JVM
        for id in ["a", "list-1", UUID().uuidString] {
            XCTAssertTrue((0..<ListAccent.count).contains(ListAccent(listId: id).index))
        }
    }
}
