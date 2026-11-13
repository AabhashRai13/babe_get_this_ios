import Foundation
import Observation

/// Login form state and the email / Google sign-in flows (Android `LoginViewModel`).
@MainActor
@Observable
final class LoginViewModel {
    nonisolated static let invalidEmailMessage = "Enter a valid email address"
    nonisolated static let noGoogleAccountMessage = "Add a Google account to this device, then try again."

    private(set) var email = ""
    private(set) var password = ""
    private(set) var emailError: String?
    private(set) var isLoading = false
    private(set) var errorMessage: String?

    var isFormValid: Bool {
        LoginEmailValidator.isValid(email) && !password.allSatisfy(\.isWhitespace)
    }

    /// Fires once per successful sign-in (Android `loginSuccess`).
    @ObservationIgnored var onLoginSuccess: (@MainActor () -> Void)?

    @ObservationIgnored private let authRepository: any AuthRepository
    @ObservationIgnored private let googleAuth: any LoginGoogleAuthenticating
    @ObservationIgnored private let googleTokens: any LoginGoogleTokenRequester
    @ObservationIgnored private let analytics: any LoginAnalytics
    @ObservationIgnored private let reporter: any AppErrorReporter

    /// The in-flight sign-in, so callers (and tests) can wait for it.
    @ObservationIgnored private(set) var inFlight: Task<Void, Never>?

    init(authRepository: any AuthRepository,
         googleAuth: any LoginGoogleAuthenticating,
         googleTokens: any LoginGoogleTokenRequester,
         analytics: any LoginAnalytics = NoopLoginAnalytics(),
         reporter: any AppErrorReporter = SilentAppErrorReporter()) {
        self.authRepository = authRepository
        self.googleAuth = googleAuth
        self.googleTokens = googleTokens
        self.analytics = analytics
        self.reporter = reporter
    }

    func onEmailChange(_ value: String) {
        email = value
        emailError = !value.isEmpty && !LoginEmailValidator.isValid(value) ? Self.invalidEmailMessage : nil
    }

    func onPasswordChange(_ value: String) {
        password = value
    }

    func clearError() {
        errorMessage = nil
    }

    func login() {
        guard isFormValid else { return }
        let email = email, password = password
        signIn { [authRepository] in
            do {
                return try await authRepository.login(email: email, password: password)
            } catch {
                return nil
            }
        }
    }

    /// The whole Google flow, run in the view model's task rather than the view's so a
    /// re-render mid-sheet doesn't drop the chosen account.
    func signInWithGoogle() {
        signIn { [googleTokens, googleAuth, reporter] in
            let token: GoogleSignInToken?
            do {
                token = try await googleTokens.request()
            } catch is CancellationError {
                return nil
            } catch GoogleSheetFailure.offline {
                return .failure(.network())
            } catch GoogleSheetFailure.noAccount {
                return .failure(.auth(Self.noGoogleAccountMessage))
            } catch {
                // Reported as `.unknown` because the reporting policy drops `.auth`, and a
                // misconfigured OAuth client would otherwise surface nowhere but the banner.
                let mapped = AppError.unknown(AuthErrorMapper.googleSignInFailed)
                reporter.report(error, mapped: mapped)
                return .failure(mapped)
            }
            // nil: the user closed the sheet, which is not an error.
            guard let token else { return nil }
            return await googleAuth.signInWithGoogle(idToken: token.idToken, rawNonce: token.rawNonce)
        }
    }

    /// Shared by both paths; a nil result means the user backed out. `isLoading` flips
    /// before launching, so a double tap can't open two sheets or race an email login.
    private func signIn(_ call: @escaping @Sendable () async -> Result<AuthUser, AppError>?) {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil

        inFlight = Task { [weak self] in
            let result = await call()
            guard let self else { return }
            switch result {
            case nil:
                isLoading = false
            case .success?:
                isLoading = false
                analytics.trackAccountLoggedIn()
                onLoginSuccess?()
            case .failure(let error)?:
                isLoading = false
                errorMessage = error.message
            }
        }
    }
}
