import Foundation
import Supabase

/// The decision-making half of `SupabaseAuthRepository`'s error handling, split out so it
/// can be tested directly (Android `AuthErrorMapper.kt`): walking an error's cause chain,
/// and mapping provider messages to the copy the user sees.
enum AuthErrorMapper {
    /// One wording for every Google failure, whether Supabase rejected the token or the
    /// account sheet failed.
    static var googleSignInFailed: String { String(localized: .authErrorGoogleFailed) }
    /// iOS only (AUTH-06): the same wording for Apple.
    static var appleSignInFailed: String { String(localized: .authErrorAppleFailed) }
    /// iOS only: the build has no Google client id yet.
    static var googleSignInNotConfigured: String { String(localized: .authErrorGoogleNotConfigured) }
    static var genericFailure: String { String(localized: .authErrorGeneric) }

    /// More causes than any real wrapper produces; stops a cycle the identity check can't see.
    private static let maxChainDepth = 32

    /// True if any error in the cause chain (`NSUnderlyingErrorKey`) is a transport failure.
    ///
    /// The chain walk is the point: a connection can drop mid-request and the transport
    /// error ends up wrapped, so a top-level type check would report it as bad credentials.
    static func isNetworkFailure(_ error: any Error) -> Bool {
        var current: (any Error)? = error
        var seen = Set<ObjectIdentifier>()
        var depth = 0
        while let candidate = current, depth < maxChainDepth {
            // Guard against a self-referential or cyclic chain, which would spin forever.
            if type(of: candidate) is AnyClass {
                guard seen.insert(ObjectIdentifier(candidate as AnyObject)).inserted else { return false }
            }
            if isTransport(candidate) { return true }
            current = (candidate as NSError).userInfo[NSUnderlyingErrorKey] as? any Error
            depth += 1
        }
        return false
    }

    /// URLSession failures (Android's IOException family) and socket-level POSIX errors.
    private static func isTransport(_ error: any Error) -> Bool {
        if error is URLError || error is POSIXError { return true }
        // A plain Swift error bridges to its own domain, so this only matches real NSErrors.
        let domain = (error as NSError).domain
        return domain == NSURLErrorDomain || domain == NSPOSIXErrorDomain
    }

    /// Maps known Supabase messages to friendly copy, checked in order.
    ///
    /// The fallback NEVER returns the raw provider text: an unrecognised failure gets a
    /// generic message so internal wording cannot leak to the user.
    static func friendlyMessage(for error: any Error) -> String {
        friendlyMessage(raw: rawMessage(of: error))
    }

    static func friendlyMessage(raw: String?) -> String {
        guard let raw else { return genericFailure }
        func has(_ needle: String) -> Bool { raw.localizedCaseInsensitiveContains(needle) }
        // Google ID-token sign-in. Checked first: these messages also contain
        // "token"/"expired" and would otherwise get the email-code wording.
        if has("id_token") || has("ID token") || has("nonce") { return googleSignInFailed }
        if has("Invalid login") { return String(localized: .authErrorInvalidLogin) }
        if has("already registered") || has("already been registered") {
            return String(localized: .authErrorEmailRegistered)
        }
        if has("Email not confirmed") { return String(localized: .authErrorEmailNotConfirmed) }
        // Before "token": an expired token reads as expired, not as an invalid code.
        if has("expired") { return String(localized: .authErrorCodeExpired) }
        if has("otp") || has("token") { return String(localized: .authErrorInvalidCode) }
        return genericFailure
    }

    /// The provider's message, like Kotlin's `Throwable.message`. Nil when the error has none.
    private static func rawMessage(of error: any Error) -> String? {
        if let error = error as? AuthError { return error.message }
        if let error = error as? PostgrestError { return error.message }
        if let error = error as? any LocalizedError { return error.errorDescription }
        return nil
    }
}
