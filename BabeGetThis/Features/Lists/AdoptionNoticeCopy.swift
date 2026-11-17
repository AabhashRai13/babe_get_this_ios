import Foundation

/// The one-time "your lists are now in your account" dialog (Android `adoption_notice*` strings).
enum AdoptionNoticeCopy {
    static var ok: String { String(localized: .adoptionNoticeOk) }
    static var privacyPolicy: String { String(localized: .adoptionNoticePrivacy) }
    /// Android `PRIVACY_POLICY_URL`.
    static let privacyPolicyURL = URL(string: "https://babegetthis.com/privacy-policy.html")!

    /// Android plural `adoption_notice`: "one" for exactly 1, "other" for everything else.
    static func message(count: Int) -> String {
        String(localized: .adoptionNotice(count))
    }
}
