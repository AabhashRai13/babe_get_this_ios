// Builds the three 1024×1024 app icons (Prod, Dev, Staging) from the Android
// Play Store icon. Dev and Staging get a coloured banner so builds are easy to tell apart.
// Uses CoreGraphics/ImageIO only (AppKit drawing crashes when run headless).
//
// Usage: swift scripts/make-app-icons.swift <source.png> <Assets.xcassets>
import CoreGraphics
import CoreText
import Foundation
import ImageIO
import UniformTypeIdentifiers

let args = CommandLine.arguments
guard args.count == 3,
      let src = CGImageSourceCreateWithURL(URL(fileURLWithPath: args[1]) as CFURL, nil),
      let source = CGImageSourceCreateImageAtIndex(src, 0, nil) else {
    FileHandle.standardError.write("usage: make-app-icons.swift <source.png> <Assets.xcassets>\n".data(using: .utf8)!)
    exit(1)
}
let catalog = URL(fileURLWithPath: args[2])
let size = 1024
let rgb = CGColorSpace(name: CGColorSpace.sRGB)!

func color(_ hex: Int) -> CGColor {
    CGColor(colorSpace: rgb, components: [CGFloat((hex >> 16) & 0xFF) / 255, CGFloat((hex >> 8) & 0xFF) / 255,
                                          CGFloat(hex & 0xFF) / 255, 1])!
}

func render(banner: (text: String, color: Int)?) -> CGImage {
    // noneSkipLast = opaque RGB, which the App Store requires.
    let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
                        space: rgb, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
    ctx.interpolationQuality = .high
    let rect = CGRect(x: 0, y: 0, width: size, height: size)
    ctx.setFillColor(color(0xFFFFFF))
    ctx.fill(rect)
    ctx.draw(source, in: rect)

    if let banner {
        let band = CGRect(x: 0, y: 0, width: size, height: 200)
        ctx.setFillColor(color(banner.color))
        ctx.fill(band)
        let font = CTFontCreateWithName("HelveticaNeue-Bold" as CFString, 120, nil)
        let attrs: [NSAttributedString.Key: Any] = [
            NSAttributedString.Key(kCTFontAttributeName as String): font,
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): color(0xFFFFFF),
            NSAttributedString.Key(kCTKernAttributeName as String): 8,
        ]
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: banner.text, attributes: attrs))
        let bounds = CTLineGetBoundsWithOptions(line, .useOpticalBounds)
        ctx.textPosition = CGPoint(x: (CGFloat(size) - bounds.width) / 2 - bounds.minX,
                                   y: (band.height - bounds.height) / 2 - bounds.minY)
        CTLineDraw(line, ctx)
    }
    return ctx.makeImage()!
}

let variants: [(set: String, banner: (text: String, color: Int)?)] = [
    ("AppIcon", nil),
    ("AppIcon-Dev", ("DEV", 0x795548)),          // brand secondary (brown)
    ("AppIcon-Staging", ("STAGING", 0x5F8B85)),  // brand tertiary (teal)
]

for variant in variants {
    let dir = catalog.appendingPathComponent("\(variant.set).appiconset")
    try? FileManager.default.removeItem(at: dir)
    try! FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    let png = dir.appendingPathComponent("icon-1024.png")
    let dest = CGImageDestinationCreateWithURL(png as CFURL, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(dest, render(banner: variant.banner), nil)
    precondition(CGImageDestinationFinalize(dest))
    let contents = """
    {
      "images" : [
        { "filename" : "icon-1024.png", "idiom" : "universal", "platform" : "ios", "size" : "1024x1024" }
      ],
      "info" : { "author" : "xcode", "version" : 1 }
    }

    """
    try! contents.write(to: dir.appendingPathComponent("Contents.json"), atomically: true, encoding: .utf8)
    print("wrote \(variant.set)")
}
