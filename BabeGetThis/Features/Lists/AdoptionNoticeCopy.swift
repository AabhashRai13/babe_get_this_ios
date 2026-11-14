import Foundation

/// The one-time "your lists are now in your account" dialog (Android `adoption_notice*` strings).
enum AdoptionNoticeCopy {
    static let ok = "OK"
    static let privacyPolicy = "Privacy policy"
    /// Android `PRIVACY_POLICY_URL`.
    static let privacyPolicyURL = URL(string: "https://babegetthis.com/privacy-policy.html")!

    /// Android plural: "one" for exactly 1, "other" for everything else.
    static func message(count: Int) -> String {
        if count == 1 {
            return "Your list is now saved to your account, so it's backed up and shows up on any phone you sign in on."
        }
        return "Your \(count) lists are now saved to your account, so they're backed up and show up on any phone you sign in on."
    }
}
