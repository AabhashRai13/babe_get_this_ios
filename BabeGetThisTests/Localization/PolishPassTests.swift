import XCTest

/// UI-08 polish pass, checked on the app's source files: no hard-coded user-facing strings (copy comes from
/// `Localizable.xcstrings`), a VoiceOver label on every icon-only button, and no fixed font sizes, so Dynamic
/// Type reaches all text. The simulator reads the files straight from the source tree.
final class PolishPassTests: XCTestCase {
    /// Files whose prose-looking literals are not copy.
    static let notCopyFiles = [
        "App/SampleListSeeder.swift",            // -sampleData filler items (APP-03, never in prod)
        "Core/Auth/IdToken/",                    // sheet failures for crash reports; users see AuthErrorMapper's
        "Core/Config/",                          // Info.plist keys
        "Core/Database/",                        // SQL, and the seeded category names, which are synced data
        "Core/DesignSystem/AppColors.swift",     // colour asset names
        "Core/Network/",                         // HTTP status lines for logs
        "Core/Remote/",                          // Supabase tables, columns, filters
        "Core/Telemetry/",                       // analytics event and parameter names
        "Core/Voice/TranscribeBearerAuth.swift", // Authorization header
        "Core/Voice/TranscribeClient.swift",     // multipart body
        "Features/VoiceCapture/AVVoiceRecorder.swift", // recorder failures; the voice view model shows its own copy
    ]

    /// The -sampleData lists and items (APP-03): screenshot content, not app copy.
    static let sampleData: Set<String> = [
        "Sunday Roast", "Byron Bay Weekend", "Anniversary Dinner", "Saturday BBQ",
        "Red wine", "1 bottle", "Dan Murphys", "Something that goes with lamb",
        "Lamb leg", "2.5 kg", "The Butcher Block", "Bone in - ask for the shank end",
        "Double cream", "300 ml", "Woolworths", "For the gratin",
        "Baby potatoes", "1.5 kg", "The waxy ones, not floury",
        "Sourdough", "1 loaf", "Get there before 10 or it is gone",
    ]

    /// Lines that hold developer-only text: logs, crashes, queue labels, background-task names.
    static let developerOnlyMarkers = [
        "Logger(", "logger.", "fatalError(", "precondition", "assert", "print(", "DispatchQueue(label:",
        "beginBackgroundTime(", "accessibilityIdentifier(", "forHTTPHeaderField",
    ]

    /// Arguments of these calls match text from elsewhere (server error messages); they are not shown.
    static let matcherCalls = ["has(", "contains(", "hasPrefix(", "hasSuffix(", "range(of:"]

    func testNoHardCodedUserFacingStrings() throws {
        var found: [String] = []
        for source in try AppSource.all() where !Self.notCopyFiles.contains(where: source.path.hasPrefix) {
            for literal in source.literals where SwiftLexer.isProse(literal.text) {
                guard !Self.sampleData.contains(literal.text) else { continue }
                let line = source.line(at: literal.offset)
                guard !Self.developerOnlyMarkers.contains(where: line.contains) else { continue }
                let before = source.textBeforeOnLine(literal.offset)
                guard !Self.matcherCalls.contains(where: before.hasSuffix) else { continue }
                found.append("\(source.path):\(source.lineNumber(at: literal.offset)) \"\(literal.text)\"")
            }
        }
        XCTAssertTrue(found.isEmpty, "hard-coded copy, move it to Localizable.xcstrings:\n" +
                      found.joined(separator: "\n"))
    }

    func testEveryIconOnlyButtonHasAVoiceOverLabel() throws {
        var found: [String] = []
        for source in try AppSource.all() {
            for button in source.buttons() where button.isIconOnly && !button.hasAccessibilityLabel {
                found.append("\(source.path):\(source.lineNumber(at: button.offset))")
            }
        }
        XCTAssertTrue(found.isEmpty, "icon-only buttons without .accessibilityLabel:\n" +
                      found.joined(separator: "\n"))
    }

    func testNoFontSizeIsAFixedNumber() throws {
        var found: [String] = []
        for source in try AppSource.all() {
            for match in source.skeleton.matches(of: /\.system\(\s*size:\s*[0-9]|\.custom\([^)]*size:\s*[0-9][^)]*\)/)
            where !source.skeleton[match.range].contains("relativeTo:") {
                let offset = source.skeleton.distance(from: source.skeleton.startIndex, to: match.range.lowerBound)
                found.append("\(source.path):\(source.lineNumber(at: offset))")
            }
        }
        XCTAssertTrue(found.isEmpty, "fixed font sizes do not follow Dynamic Type; use a text style or " +
                      "@ScaledMetric:\n" + found.joined(separator: "\n"))
    }

    // MARK: - The scanner itself

    func testLexerFindsLiteralsInsideInterpolationsAndSkipsComments() {
        let lexed = SwiftLexer.lex(#"""
        let a = "Hello \(n == 1 ? "item" : "items")" // "Not this"
        /* "Nor this" */ let b = "https://x.y"
        """#)
        XCTAssertEqual(lexed.literals.map(\.text), ["Hello \u{1}", "item", "items", "https://x.y"])
    }

    func testProseRule() {
        for prose in ["Settings", "OK", "COMPLETED", "Sign in", "Version \u{1} (\u{1})", "\u{1} deleted", "Done!"] {
            XCTAssertTrue(SwiftLexer.isProse(prose), prose)
        }
        for notProse in ["telemetry_consent", "square.and.arrow.up", "DatabaseError", "CFBundleVersion",
                         "%d:%02d", "\u{1}%", "https://babegetthis.com/a b", "ABC234", "x"] {
            XCTAssertFalse(SwiftLexer.isProse(notProse), notProse)
        }
    }

    func testButtonScannerTellsIconOnlyButtonsApart() {
        let source = AppSource(path: "X.swift", text: """
        Button(action: close) { Image(systemName: "xmark") }
        Button(action: close) { Image(systemName: "xmark") }
            .accessibilityLabel(Text(.close))
        Button { tap() } label: {
            Image(systemName: "mic.fill").font(.title)
        }
        .padding()
        .accessibilityLabel(Text(.voiceAdd))
        Button(.cancel) { dismiss() }
        Button { tap() } label: { Label(.add, systemImage: "plus") }
        Menu { Text("a") } label: { Image(systemName: "person") }
        """)
        let buttons = source.buttons()
        XCTAssertEqual(buttons.map(\.isIconOnly), [true, true, true, false, false, true])
        XCTAssertEqual(buttons.map(\.hasAccessibilityLabel), [false, true, true, false, false, false])
    }
}

// MARK: - Source access

/// One Swift file of the app target, with its string literals and a skeleton (comments blanked, literal
/// contents replaced) for structural searches.
struct AppSource {
    let path: String
    let text: String
    let literals: [SwiftLexer.Literal]
    let skeleton: String
    private let characters: [Character]
    private let lineStarts: [Int]

    static let appRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()   // Localization
        .deletingLastPathComponent()   // BabeGetThisTests
        .deletingLastPathComponent()   // repository root
        .appending(path: "BabeGetThis")

    static func all() throws -> [AppSource] {
        let enumerator = try XCTUnwrap(FileManager.default.enumerator(at: appRoot, includingPropertiesForKeys: nil),
                                       "cannot read \(appRoot.path)")
        let files = enumerator.compactMap { $0 as? URL }.filter { $0.pathExtension == "swift" }
        XCTAssertGreaterThan(files.count, 50, "expected the app's Swift files under \(appRoot.path)")
        let rootDepth = appRoot.standardizedFileURL.pathComponents.count
        return try files.map { url in
            let path = url.standardizedFileURL.pathComponents.dropFirst(rootDepth).joined(separator: "/")
            return AppSource(path: path, text: try String(contentsOf: url, encoding: .utf8))
        }.sorted { $0.path < $1.path }
    }

    init(path: String, text: String) {
        self.path = path
        // Previews sit at the end of a file and hold sample names; they never ship as copy.
        let shipped = text.range(of: "#Preview").map { String(text[..<$0.lowerBound]) } ?? text
        self.text = shipped
        let lexed = SwiftLexer.lex(shipped)
        literals = lexed.literals
        skeleton = String(lexed.skeleton)
        characters = Array(shipped)
        var starts = [0]
        for (index, character) in characters.enumerated() where character == "\n" { starts.append(index + 1) }
        lineStarts = starts
    }

    func lineNumber(at offset: Int) -> Int {
        (lineStarts.lastIndex { $0 <= offset } ?? 0) + 1
    }

    func line(at offset: Int) -> String {
        let start = lineStarts[lineNumber(at: offset) - 1]
        let end = characters[start...].firstIndex(of: "\n") ?? characters.count
        return String(characters[start..<end])
    }

    func textBeforeOnLine(_ offset: Int) -> String {
        let start = lineStarts[lineNumber(at: offset) - 1]
        return String(characters[start..<offset]).trimmingCharacters(in: .whitespaces)
    }

    struct Button {
        let offset: Int
        let isIconOnly: Bool
        let hasAccessibilityLabel: Bool
    }

    /// `Button` and `Menu` calls with their label content and the modifiers chained after them.
    func buttons() -> [Button] {
        let chars = Array(skeleton)
        var result: [Button] = []
        for match in skeleton.matches(of: /\b(Button|Menu)\s*[({]/) {
            let start = skeleton.distance(from: skeleton.startIndex, to: match.range.lowerBound)
            var index = start + (skeleton[match.range].hasPrefix("Button") ? 6 : 4)
            index = Self.skipSpace(chars, index)
            var arguments = ""
            if index < chars.count, chars[index] == "(" {
                let end = Self.matching(chars, index)
                arguments = String(chars[(index + 1)..<max(index + 1, end - 1)])
                index = end
            }
            var unlabelled: [String] = []
            var labelled: [String: String] = [:]
            while true {
                let next = Self.skipSpace(chars, index)
                if next < chars.count, chars[next] == "{" {
                    let end = Self.matching(chars, next)
                    unlabelled.append(String(chars[next..<end]))
                    index = end
                } else if let (name, open) = Self.closureLabel(chars, next) {
                    let end = Self.matching(chars, open)
                    labelled[name] = String(chars[open..<end])
                    index = end
                } else {
                    break
                }
            }
            let label: String?
            if let range = arguments.range(of: "label:") {
                label = String(arguments[range.upperBound...])
            } else if let closure = labelled["label"] {
                label = closure
            } else if arguments.contains("action:"), let closure = unlabelled.first {
                label = closure
            } else {
                label = nil   // a title: VoiceOver reads it
            }
            let chain = Self.modifierChain(chars, index)
            let iconOnly = label.map { $0.contains("Image(") && !$0.contains("Text(") && !$0.contains("Label(") }
            result.append(Button(offset: start, isIconOnly: iconOnly ?? false,
                                 hasAccessibilityLabel: ((label ?? "") + chain).contains(".accessibilityLabel(")))
        }
        return result
    }

    private static func skipSpace(_ chars: [Character], _ index: Int) -> Int {
        var index = index
        while index < chars.count, chars[index].isWhitespace { index += 1 }
        return index
    }

    /// Index just past the bracket that closes the one at `open`.
    private static func matching(_ chars: [Character], _ open: Int) -> Int {
        let pairs: [Character: Character] = ["(": ")", "{": "}", "[": "]"]
        var stack: [Character] = []
        var index = open
        while index < chars.count {
            let character = chars[index]
            if let close = pairs[character] {
                stack.append(close)
            } else if character == stack.last {
                stack.removeLast()
                if stack.isEmpty { return index + 1 }
            }
            index += 1
        }
        return chars.count
    }

    /// `label: {` → ("label", index of the brace).
    private static func closureLabel(_ chars: [Character], _ index: Int) -> (String, Int)? {
        var end = index
        while end < chars.count, chars[end].isLetter || chars[end].isNumber || chars[end] == "_" { end += 1 }
        guard end > index, end < chars.count, chars[end] == ":" else { return nil }
        let open = skipSpace(chars, end + 1)
        guard open < chars.count, chars[open] == "{" else { return nil }
        return (String(chars[index..<end]), open)
    }

    /// `.modifier(...)`, `.modifier { }` and `.modifier(...) { }` links chained from `index`.
    private static func modifierChain(_ chars: [Character], _ index: Int) -> String {
        var index = index
        var chain = ""
        while true {
            let dot = skipSpace(chars, index)
            guard dot < chars.count, chars[dot] == "." else { return chain }
            var end = dot + 1
            while end < chars.count, chars[end].isLetter || chars[end].isNumber || chars[end] == "_" { end += 1 }
            if end < chars.count, chars[end] == "(" { end = matching(chars, end) }
            let brace = skipSpace(chars, end)
            if brace < chars.count, chars[brace] == "{" { end = matching(chars, brace) }
            chain += String(chars[dot..<end])
            index = end
        }
    }
}

// MARK: - Lexer

/// Just enough of Swift's lexical grammar to find string literals (also inside interpolations) and skip
/// comments.
enum SwiftLexer {
    struct Literal {
        /// The literal's text with each interpolation replaced by U+0001.
        let text: String
        /// Character offset of the opening quote.
        let offset: Int
    }

    static func lex(_ source: String) -> (literals: [Literal], skeleton: [Character]) {
        let chars = Array(source)
        var skeleton = chars
        var literals: [Literal] = []
        var index = 0
        while index < chars.count {
            if chars[index] == "/", index + 1 < chars.count, chars[index + 1] == "/" {
                while index < chars.count, chars[index] != "\n" { skeleton[index] = " "; index += 1 }
            } else if chars[index] == "/", index + 1 < chars.count, chars[index + 1] == "*" {
                var depth = 0
                repeat {
                    if chars[index] == "/", index + 1 < chars.count, chars[index + 1] == "*" { depth += 1 }
                    if chars[index] == "*", index + 1 < chars.count, chars[index + 1] == "/" {
                        depth -= 1
                        skeleton[index] = " "; skeleton[index + 1] = " "
                        index += 2
                        continue
                    }
                    if chars[index] != "\n" { skeleton[index] = " " }
                    index += 1
                } while index < chars.count && depth > 0
            } else if chars[index] == "\"" {
                index = literal(chars, at: index, into: &literals, skeleton: &skeleton)
            } else {
                index += 1
            }
        }
        return (literals.sorted { $0.offset < $1.offset }, skeleton)
    }

    /// Lexes the literal whose opening quote is at `start`; returns the index after its closing quote.
    private static func literal(_ chars: [Character], at start: Int, into literals: inout [Literal],
                                skeleton: inout [Character]) -> Int {
        let multiline = start + 2 < chars.count && chars[start + 1] == "\"" && chars[start + 2] == "\""
        var index = start + (multiline ? 3 : 1)
        var text = ""
        while index < chars.count {
            let character = chars[index]
            if multiline, character == "\"", index + 2 < chars.count, chars[index + 1] == "\"",
               chars[index + 2] == "\"" {
                literals.append(Literal(text: text, offset: start))
                return index + 3
            }
            if !multiline, character == "\"" {
                literals.append(Literal(text: text, offset: start))
                return index + 1
            }
            if !multiline, character == "\n" { break }
            if character == "\\", index + 1 < chars.count {
                if chars[index + 1] == "(" {
                    skeleton[index] = "_"; skeleton[index + 1] = "_"
                    index += 2
                    var depth = 1
                    while index < chars.count, depth > 0 {
                        if chars[index] == "\"" {
                            index = literal(chars, at: index, into: &literals, skeleton: &skeleton)
                            continue
                        }
                        if chars[index] == "(" { depth += 1 }
                        if chars[index] == ")" { depth -= 1 }
                        if chars[index] != "\n" { skeleton[index] = "_" }
                        index += 1
                    }
                    text.append("\u{1}")
                    continue
                }
                let escaped: [Character: Character] = ["n": "\n", "t": "\t", "\"": "\"", "\\": "\\", "'": "'"]
                text.append(escaped[chars[index + 1]] ?? chars[index + 1])
                skeleton[index] = "_"; skeleton[index + 1] = "_"
                index += 2
                continue
            }
            text.append(character)
            if character != "\n" { skeleton[index] = "_" }
            index += 1
        }
        literals.append(Literal(text: text, offset: start))
        return index
    }

    /// Text a person would read: words with spaces, a capitalised word ("Settings") or a capitals-only
    /// word ("OK"). Identifiers, keys, symbol names, URLs and format-only strings are not.
    static func isProse(_ literal: String) -> Bool {
        let text = literal.trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.filter(\.isLetter).count >= 2, !text.contains("://") else { return false }
        if text.contains(where: \.isWhitespace) {
            return text.split(whereSeparator: \.isWhitespace).contains { $0.filter(\.isLetter).count >= 2 }
        }
        return text.wholeMatch(of: /[A-Z][a-z]+[.!?…]*/) != nil || text.wholeMatch(of: /[A-Z]{2,}[.!?…]*/) != nil
    }
}
