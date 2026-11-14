import Foundation
import GoogleSignIn
import UIKit

/// What the Google sheet returns: the id token, and whether the hashed nonce went into it.
struct GoogleSheetIdToken: Equatable, Sendable {
    let idToken: String
    let nonceApplied: Bool
}

/// The Google SDK behind a seam, so the requester is tested without a real sheet.
/// Returns nil only if the SDK hands back no result and no error.
protocol GoogleSignInSheet: Sendable {
    @MainActor func idToken(clientID: String, hashedNonce: String) async throws -> GoogleSheetIdToken?
}

/// AUTH-05: opens the Google sheet and hands back the id token with its raw nonce
/// (Android `CredentialManagerTokenRequester`).
struct GoogleIdTokenRequester: LoginGoogleTokenRequester {
    /// `GIDClientID` from Info.plist; empty until the owner adds a Google client.
    let clientID: String?
    let networkMonitor: NetworkMonitor
    let sheet: any GoogleSignInSheet
    var makeRawNonce: @Sendable () -> String = IdTokenNonce.random

    /// The SDK's "user cancelled" error, as `NSError` domain and code.
    static let cancelDomain = kGIDSignInErrorDomain
    static let cancelCode = GIDSignInError.Code.canceled.rawValue

    func request() async throws -> GoogleSignInToken? {
        // Calling the SDK without a client id crashes the app, so stop here.
        guard let clientID, Self.isConfigured(clientID) else { throw GoogleSheetFailure.notConfigured }
        // Offline the sheet can open but never return a token, so it isn't opened at all.
        guard networkMonitor.isOnline() else { throw GoogleSheetFailure.offline }
        let rawNonce = makeRawNonce()
        let result: GoogleSheetIdToken?
        do {
            result = try await sheet.idToken(clientID: clientID, hashedNonce: IdTokenNonce.sha256Hex(rawNonce))
        } catch let error as CancellationError {
            throw error
        } catch let error as GoogleSheetFailure {
            throw error
        } catch {
            // Closing the sheet is a choice, not a failure.
            if Self.isCancel(error) { return nil }
            throw GoogleSheetFailure.failed(String(describing: error))
        }
        guard let result, !result.idToken.isEmpty else {
            throw GoogleSheetFailure.failed("Google returned no id token")
        }
        // A token without the nonce must reach Supabase without one, or it is rejected.
        return GoogleSignInToken(idToken: result.idToken, rawNonce: result.nonceApplied ? rawNonce : "")
    }

    static func isCancel(_ error: any Error) -> Bool {
        let error = error as NSError
        return error.domain == cancelDomain && error.code == cancelCode
    }

    /// Empty, blank or an unexpanded `$(...)` build setting all mean "no client yet".
    static func isConfigured(_ clientID: String) -> Bool {
        let trimmed = clientID.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmed.isEmpty && !trimmed.hasPrefix("$(")
    }

    static func clientID(infoDictionary: [String: Any]?) -> String? {
        infoDictionary?["GIDClientID"] as? String
    }
}

/// The real Google sheet (GoogleSignIn-iOS).
struct LiveGoogleSignInSheet: GoogleSignInSheet {
    @MainActor
    func idToken(clientID: String, hashedNonce: String) async throws -> GoogleSheetIdToken? {
        guard let presenter = PresentingViewController.top() else {
            throw GoogleSheetFailure.failed("No view controller to present the Google sheet from")
        }
        let signIn = GIDSignIn.sharedInstance
        signIn.configuration = GIDConfiguration(clientID: clientID)
        // GoogleSignIn-iOS 8.0.0 has no nonce parameter (later versions add
        // `signIn(withPresenting:hint:additionalScopes:nonce:)`), so the token carries none and
        // `nonceApplied` is false. Pass `hashedNonce` there once the package is upgraded.
        return try await withCheckedThrowingContinuation { continuation in
            signIn.signIn(withPresenting: presenter, hint: nil, additionalScopes: nil) { result, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    let token = result?.user.idToken?.tokenString
                    continuation.resume(returning: token.map { GoogleSheetIdToken(idToken: $0, nonceApplied: false) })
                }
            }
        }
    }
}

/// Finds the view controller to present a sign-in sheet from, at request time: the key
/// window's root, walked up to whatever is on screen (the login itself is a sheet).
@MainActor
enum PresentingViewController {
    static func top() -> UIViewController? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let windows = scenes.flatMap(\.windows)
        var top = (windows.first { $0.isKeyWindow } ?? windows.first)?.rootViewController
        while let presented = top?.presentedViewController {
            top = presented
        }
        return top
    }
}
