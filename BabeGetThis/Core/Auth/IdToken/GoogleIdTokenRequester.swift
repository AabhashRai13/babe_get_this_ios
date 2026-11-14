import Foundation
import GoogleSignIn
import UIKit

/// The Google SDK behind a seam, so the requester is tested without a real sheet.
/// `hashedNonce` goes into the sheet's request, and Google signs it into the id token.
/// Returns the id token, or nil only if the SDK hands back no result and no error.
protocol GoogleSignInSheet: Sendable {
    @MainActor func idToken(clientID: String, hashedNonce: String) async throws -> String?
}

/// AUTH-05: opens the Google sheet and hands back the id token with its raw nonce
/// (Android `CredentialManagerTokenRequester`).
struct GoogleIdTokenRequester: LoginGoogleTokenRequester {
    /// `GIDClientID` from Info.plist; empty until the owner adds a Google client.
    let clientID: String?
    /// Every `CFBundleURLSchemes` entry in Info.plist, lowercased. The SDK needs the reversed
    /// client id among them.
    let urlSchemes: Set<String>
    let networkMonitor: NetworkMonitor
    let sheet: any GoogleSignInSheet
    let makeRawNonce: @Sendable () -> String

    init(clientID: String?, urlSchemes: Set<String>, networkMonitor: NetworkMonitor,
         sheet: any GoogleSignInSheet, makeRawNonce: @escaping @Sendable () -> String = IdTokenNonce.random) {
        self.clientID = clientID
        self.urlSchemes = Set(urlSchemes.map { $0.lowercased() })
        self.networkMonitor = networkMonitor
        self.sheet = sheet
        self.makeRawNonce = makeRawNonce
    }

    /// Reads both Google values from an Info.plist dictionary (`Bundle.main.infoDictionary`).
    init(infoDictionary: [String: Any]?, networkMonitor: NetworkMonitor, sheet: any GoogleSignInSheet,
         makeRawNonce: @escaping @Sendable () -> String = IdTokenNonce.random) {
        self.init(clientID: Self.clientID(infoDictionary: infoDictionary),
                  urlSchemes: Self.urlSchemes(infoDictionary: infoDictionary),
                  networkMonitor: networkMonitor, sheet: sheet, makeRawNonce: makeRawNonce)
    }

    /// The SDK's "user cancelled" error, as `NSError` domain and code.
    static let cancelDomain = kGIDSignInErrorDomain
    static let cancelCode = GIDSignInError.Code.canceled.rawValue

    func request() async throws -> GoogleSignInToken? {
        // Calling the SDK without a client id, or without its callback URL scheme, raises an
        // uncaught exception and kills the app, so stop here.
        guard let clientID, Self.isConfigured(clientID: clientID, urlSchemes: urlSchemes) else {
            throw GoogleSheetFailure.notConfigured
        }
        // Offline the sheet can open but never return a token, so it isn't opened at all.
        guard networkMonitor.isOnline() else { throw GoogleSheetFailure.offline }
        // Google gets the hash and signs it into the token; Supabase gets the raw nonce, hashes
        // it and compares, so a token lifted from elsewhere can't be replayed.
        let rawNonce = makeRawNonce()
        let idToken: String?
        do {
            idToken = try await sheet.idToken(clientID: clientID, hashedNonce: IdTokenNonce.sha256Hex(rawNonce))
        } catch let error as CancellationError {
            throw error
        } catch let error as GoogleSheetFailure {
            throw error
        } catch {
            // Closing the sheet is a choice, not a failure.
            if Self.isCancel(error) { return nil }
            throw GoogleSheetFailure.failed(String(describing: error))
        }
        guard let idToken, !idToken.isEmpty else {
            throw GoogleSheetFailure.failed("Google returned no id token")
        }
        return GoogleSignInToken(idToken: idToken, rawNonce: rawNonce)
    }

    static func isCancel(_ error: any Error) -> Bool {
        let error = error as NSError
        return error.domain == cancelDomain && error.code == cancelCode
    }

    /// Configured means a real client id AND its reversed form registered as a URL scheme.
    /// The two are separate secrets; one without the other makes the SDK throw an uncaught
    /// `NSInvalidArgumentException` ("Your app is missing support for the following URL schemes").
    static func isConfigured(clientID: String, urlSchemes: Set<String>) -> Bool {
        let trimmed = clientID.trimmingCharacters(in: .whitespacesAndNewlines)
        // Empty, blank or an unexpanded `$(...)` build setting all mean "no client yet".
        guard !trimmed.isEmpty, !trimmed.hasPrefix("$(") else { return false }
        return urlSchemes.contains(callbackScheme(clientID: trimmed))
    }

    /// The scheme the SDK requires, computed as it does (`GIDSignInCallbackSchemes`): the client
    /// id split on ".", reversed, joined and lowercased.
    static func callbackScheme(clientID: String) -> String {
        clientID.split(separator: ".", omittingEmptySubsequences: false).reversed().joined(separator: ".").lowercased()
    }

    static func clientID(infoDictionary: [String: Any]?) -> String? {
        infoDictionary?["GIDClientID"] as? String
    }

    static func urlSchemes(infoDictionary: [String: Any]?) -> Set<String> {
        let types = infoDictionary?["CFBundleURLTypes"] as? [[String: Any]] ?? []
        return Set(types.flatMap { ($0["CFBundleURLSchemes"] as? [String]) ?? [] }.map { $0.lowercased() })
    }
}

/// The real Google sheet (GoogleSignIn-iOS 10).
struct LiveGoogleSignInSheet: GoogleSignInSheet {
    @MainActor
    func idToken(clientID: String, hashedNonce: String) async throws -> String? {
        guard let presenter = PresentingViewController.top() else {
            throw GoogleSheetFailure.failed("No view controller to present the Google sheet from")
        }
        let signIn = GIDSignIn.sharedInstance
        signIn.configuration = GIDConfiguration(clientID: clientID)
        // The SDK hands `nonce` to AppAuth unchanged, so the id token's nonce claim is this hash.
        return try await withCheckedThrowingContinuation { continuation in
            signIn.signIn(withPresenting: presenter, hint: nil, additionalScopes: nil, nonce: hashedNonce) { result, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: result?.user.idToken?.tokenString)
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
