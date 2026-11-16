import Supabase
import XCTest
@testable import BabeGetThis

/// AUTH-04: the password reset code is 8 digits (supabase/config.toml `[auth.email] otp_length = 8`, like
/// the hosted projects). The whole Forgot password flow runs through the app's SupabaseAuthRemote; the
/// email is read from the local stack's mail catcher (Mailpit).
final class PasswordResetIntegrationTests: LocalSupabaseTestCase {
    private struct MailSearch: Decodable {
        struct Summary: Decodable { let ID: String }
        let messages: [Summary]
    }

    private struct Mail: Decodable {
        let Text: String
        let HTML: String
    }

    func testResetCodeIsEightDigitsAndSignsTheUserInToSetANewPassword() async throws {
        let user = try await makeUser("reset")
        try await user.auth.signOut()

        try await user.auth.requestPasswordReset(email: user.email)

        let mail = try await waitForMail(to: user.email)
        let codes = Self.digitRuns(in: mail.Text)
        XCTAssertEqual(codes.count, 1, "expected one code in the reset email (supabase/templates/recovery.html): \(mail.Text)")
        let code = try XCTUnwrap(codes.first)
        XCTAssertEqual(code.count, 8, "the reset code must be 8 digits (otp_length = 8)")

        // Entering the code signs the user in; then they choose a new password.
        try await user.auth.verifyRecoveryCode(email: user.email, code: code)
        XCTAssertEqual(user.auth.currentSession()?.user.id, user.id)
        let newPassword = "N3w-\(UUID().uuidString.prefix(10))"
        try await user.auth.updatePassword(newPassword)

        let fresh = SupabaseAuthRemote(client: LocalSupabase.makeClient(endpoint))
        let session = try await fresh.signIn(email: user.email, password: newPassword)
        XCTAssertEqual(session.user.id, user.id)
        try await fresh.signOut()
    }

    // MARK: - Helpers

    /// Whole words made only of digits, links left out: the email's code, whatever its length. (A link's
    /// port or token hash would otherwise look like one.)
    private static func digitRuns(in text: String) -> [String] {
        let withoutLinks = text.replacingOccurrences(of: #"https?://\S+"#, with: " ", options: .regularExpression)
        let regex = try! NSRegularExpression(pattern: "(?<![0-9A-Za-z_])[0-9]{4,}(?![0-9A-Za-z_])")
        let range = NSRange(withoutLinks.startIndex..., in: withoutLinks)
        return regex.matches(in: withoutLinks, range: range).compactMap {
            Range($0.range, in: withoutLinks).map { String(withoutLinks[$0]) }
        }
    }

    private func waitForMail(to address: String) async throws -> Mail {
        let session = URLSession(configuration: .ephemeral)
        var search = URLComponents(url: LocalSupabase.mailURL.appending(path: "api/v1/search"), resolvingAgainstBaseURL: false)!
        search.queryItems = [URLQueryItem(name: "query", value: "to:\"\(address)\"")]
        var found: String?
        _ = try await eventually(within: 15) {
            let (data, _) = try await session.data(from: search.url!)
            found = try JSONDecoder().decode(MailSearch.self, from: data).messages.first?.ID
            return found != nil
        }
        let id = try XCTUnwrap(found, "no reset email reached Mailpit at \(LocalSupabase.mailURL) for \(address)")
        let (data, _) = try await session.data(from: LocalSupabase.mailURL.appending(path: "api/v1/message/\(id)"))
        return try JSONDecoder().decode(Mail.self, from: data)
    }
}
