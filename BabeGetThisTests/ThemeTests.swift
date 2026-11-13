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

    func testFixedColorAssetsExistAndMatchAndroidInBothModes() {
        let expected: [String: (CGFloat, CGFloat, CGFloat)] = [
            "SwipeDelete": (0xE5, 0x39, 0x35), "SwipeComplete": (0x43, 0xA0, 0x47), "OnSwipe": (0xFF, 0xFF, 0xFF),
        ]
        XCTAssertEqual(Set(AppColors.fixedAssetNames), Set(expected.keys))
        for name in AppColors.fixedAssetNames {
            let color = UIColor(named: name, in: .main, compatibleWith: nil)
            XCTAssertNotNil(color, "missing colour asset \(name)")
            for style in [UIUserInterfaceStyle.light, .dark] {
                var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
                color?.resolvedColor(with: UITraitCollection(userInterfaceStyle: style)).getRed(&r, green: &g, blue: &b, alpha: &a)
                let want = expected[name]!
                XCTAssertEqual(r * 255, want.0, accuracy: 0.5, "\(name) red")
                XCTAssertEqual(g * 255, want.1, accuracy: 0.5, "\(name) green")
                XCTAssertEqual(b * 255, want.2, accuracy: 0.5, "\(name) blue")
            }
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
