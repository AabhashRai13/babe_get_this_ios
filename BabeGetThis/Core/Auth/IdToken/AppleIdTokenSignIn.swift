import AuthenticationServices
import Foundation

/// What a successful Apple authorisation hands to the repository.
struct AppleSignInCredential: Equatable, Sendable {
    let idToken: String
    let rawNonce: String
    /// Only on the user's FIRST authorisation; Apple never sends it again.
    let fullName: String?
}

/// Why an Apple authorisation produced no credential. Its text is never shown.
enum AppleSignInFailure: Error, Equatable, Sendable {
    case failed(String)
}

/// The parts of an `ASAuthorization` result the app uses, so the mapping below is tested
/// without a real Apple sheet (Apple's credential types can't be built in a test).
enum AppleAuthorizationOutcome: Sendable {
    case authorized(identityToken: Data?, fullName: PersonNameComponents?)
    case failed(any Error)

    init(_ result: Result<ASAuthorization, any Error>) {
        switch result {
        case .success(let authorization):
            guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential else {
                self = .failed(AppleSignInFailure.failed("Unexpected credential type"))
                return
            }
            self = .authorized(identityToken: credential.identityToken, fullName: credential.fullName)
        case .failure(let error):
            self = .failed(error)
        }
    }
}

/// AUTH-06: Sign in with Apple, with the same nonce scheme as Google.
enum AppleIdTokenSignIn {
    static let scopes: [ASAuthorization.Scope] = [.fullName, .email]

    /// Fills in the Apple request: name and email scopes, and the HASHED nonce
    /// (`IdTokenNonce.sha256Hex` of the raw one, which only Supabase gets).
    @MainActor
    static func configure(_ request: ASAuthorizationAppleIDRequest, nonceHash: String) {
        request.requestedScopes = scopes
        request.nonce = nonceHash
    }

    /// The credential for Supabase, or nil when the user cancelled (not an error).
    static func credential(from outcome: AppleAuthorizationOutcome, rawNonce: String) throws(AppleSignInFailure) -> AppleSignInCredential? {
        switch outcome {
        case .failed(let error):
            if isCancel(error) { return nil }
            throw .failed(String(describing: error))
        case .authorized(let identityToken, let fullName):
            guard let identityToken, let idToken = String(data: identityToken, encoding: .utf8), !idToken.isEmpty else {
                throw .failed("Apple returned no identity token")
            }
            return AppleSignInCredential(idToken: idToken, rawNonce: rawNonce, fullName: displayName(fullName))
        }
    }

    static func isCancel(_ error: any Error) -> Bool {
        let error = error as NSError
        return error.domain == ASAuthorizationError.errorDomain && error.code == ASAuthorizationError.canceled.rawValue
    }

    /// "Ann Lee" from Apple's name parts; nil when there is no name (every later sign-in).
    static func displayName(_ components: PersonNameComponents?) -> String? {
        guard let components else { return nil }
        let name = PersonNameComponentsFormatter().string(from: components)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? nil : name
    }
}
