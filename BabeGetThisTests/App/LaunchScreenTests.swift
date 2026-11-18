import UIKit
import XCTest
@testable import BabeGetThis

/// APP-04: the launch screen is Android's splash (`values/splash.xml`, `values-night/splash.xml`): the
/// first-frame background with the monochrome glyph drawn in the primary colour.
final class LaunchScreenTests: XCTestCase {
    func testLaunchColoursMatchAndroidSplash() throws {
        let launch = try XCTUnwrap(Bundle.main.object(forInfoDictionaryKey: "UILaunchScreen") as? [String: Any],
                                   "Info.plist has no UILaunchScreen")
        let colorName = try XCTUnwrap(launch["UIColorName"] as? String, "the launch screen has no background colour")
        let imageName = try XCTUnwrap(launch["UIImageName"] as? String, "the launch screen has no icon")

        let background = try XCTUnwrap(UIColor(named: colorName, in: .main, compatibleWith: nil))
        assertRGB(background.resolvedColor(with: UITraitCollection(userInterfaceStyle: .light)), 0xEDF1F4,
                  "light background")
        assertRGB(background.resolvedColor(with: UITraitCollection(userInterfaceStyle: .dark)), 0x121212,
                  "dark background")

        for (style, icon) in [(UIUserInterfaceStyle.light, 0x607D8B), (.dark, 0xB0BEC5)] {
            let traits = UITraitCollection(userInterfaceStyle: style)
            let image = try XCTUnwrap(UIImage(named: imageName, in: .main, compatibleWith: traits),
                                      "no launch icon for \(style)")
            let colours = Self.opaquePixelColours(of: image)
            XCTAssertFalse(colours.isEmpty, "the \(style) launch icon draws nothing")
            let wrong = colours.filter { !Self.isClose($0, icon) }.map { String(format: "%06X", $0) }.sorted()
            XCTAssertTrue(wrong.isEmpty, "\(style) launch icon has pixels \(wrong.prefix(5)), want " +
                          String(format: "%06X", icon))
        }
    }

    private func assertRGB(_ color: UIColor, _ hex: Int, _ message: String,
                           file: StaticString = #filePath, line: UInt = #line) {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        color.getRed(&r, green: &g, blue: &b, alpha: &a)
        XCTAssertEqual(r * 255, CGFloat((hex >> 16) & 0xFF), accuracy: 0.5, "\(message) red", file: file, line: line)
        XCTAssertEqual(g * 255, CGFloat((hex >> 8) & 0xFF), accuracy: 0.5, "\(message) green", file: file, line: line)
        XCTAssertEqual(b * 255, CGFloat(hex & 0xFF), accuracy: 0.5, "\(message) blue", file: file, line: line)
    }

    /// The distinct colours (0xRRGGBB) of the fully opaque pixels; anti-aliased edges are left out.
    private static func opaquePixelColours(of image: UIImage) -> Set<Int> {
        let width = Int(image.size.width * image.scale), height = Int(image.size.height * image.scale)
        guard width > 0, height > 0,
              let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                                      bytesPerRow: width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
              let data = context.data else { return [] }
        UIGraphicsPushContext(context)
        image.draw(in: CGRect(x: 0, y: 0, width: width, height: height))
        UIGraphicsPopContext()

        let pixels = data.bindMemory(to: UInt8.self, capacity: width * height * 4)
        var colours = Set<Int>()
        for offset in stride(from: 0, to: width * height * 4, by: 4) where pixels[offset + 3] == 255 {
            colours.insert(Int(pixels[offset]) << 16 | Int(pixels[offset + 1]) << 8 | Int(pixels[offset + 2]))
        }
        return colours
    }

    private static func isClose(_ colour: Int, _ want: Int) -> Bool {
        [16, 8, 0].allSatisfy { abs(((colour >> $0) & 0xFF) - ((want >> $0) & 0xFF)) <= 2 }
    }
}
