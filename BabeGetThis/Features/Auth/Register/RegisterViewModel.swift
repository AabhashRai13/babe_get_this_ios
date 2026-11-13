import Foundation
import Observation

/// Sign-up telemetry. The event carries nothing: never attach the email or name.
protocol RegisterAnalytics: Sendable {
    func trackAccountRegistered()
}

struct NoopRegisterAnalytics: RegisterAnalytics {
    func trackAccountRegistered() {}
}

/// Register form state and the sign-up flow (Android `RegisterViewModel`).
@MainActor
@Observable
final class RegisterViewModel {
    nonisolated static let minPasswordLength = 6
    nonisolated static let invalidEmailMessage = "Enter a valid email address"
    nonisolated static let passwordTooShortMessage = "Password must be at least \(minPasswordLength) characters"
    nonisolated static let passwordMismatchMessage = "Passwords do not match"
    nonisolated static let confirmEmailMessage = "Check your email to confirm your account, then sign in."

    private(set) var name = ""
    private(set) var email = ""
    private(set) var password = ""
    private(set) var confirmPassword = ""
    private(set) var emailError: String?
    private(set) var passwordError: String?
    private(set) var confirmPasswordError: String?
    private(set) var isLoading = false
    private(set) var errorMessage: String?

    var isFormValid: Bool {
        !name.allSatisfy(\.isWhitespace)
            && LoginEmailValidator.isValid(email)
            && password.count >= Self.minPasswordLength
            && confirmPassword == password
    }

    /// Fires once per sign-up that left the user signed in (Android `registerSuccess`).
    @ObservationIgnored var onRegisterSuccess: (@MainActor () -> Void)?

    @ObservationIgnored private let authRepository: any AuthRepository
    @ObservationIgnored private let analytics: any RegisterAnalytics

    /// The in-flight sign-up, so callers (and tests) can wait for it.
    @ObservationIgnored private(set) var inFlight: Task<Void, Never>?

    init(authRepository: any AuthRepository, analytics: any RegisterAnalytics = NoopRegisterAnalytics()) {
        self.authRepository = authRepository
        self.analytics = analytics
    }

    func onNameChange(_ value: String) {
        name = value
    }

    func onEmailChange(_ value: String) {
        email = value
        emailError = !value.isEmpty && !LoginEmailValidator.isValid(value) ? Self.invalidEmailMessage : nil
    }

    func onPasswordChange(_ value: String) {
        password = value
        passwordError = !value.isEmpty && value.count < Self.minPasswordLength ? Self.passwordTooShortMessage : nil
        confirmPasswordError = Self.confirmMismatchError(password: value, confirm: confirmPassword)
    }

    func onConfirmPasswordChange(_ value: String) {
        confirmPassword = value
        confirmPasswordError = Self.confirmMismatchError(password: password, confirm: value)
    }

    func clearError() {
        errorMessage = nil
    }

    func register() {
        guard isFormValid, !isLoading else { return }
        let email = email, password = password, name = name
        isLoading = true
        errorMessage = nil

        inFlight = Task { [weak self, authRepository] in
            let result: Result<AuthRegisterResult, AppError>
            do {
                result = try await authRepository.register(email: email, password: password, name: name)
            } catch {
                self?.isLoading = false
                return
            }
            guard let self else { return }
            isLoading = false
            switch result {
            case .success(.signedIn):
                // Only signedIn counts: confirmationRequired means the account exists but the
                // person is not through the door yet, so counting it would make the funnel's
                // first step optimistic.
                analytics.trackAccountRegistered()
                onRegisterSuccess?()
            case .success(.confirmationRequired):
                errorMessage = Self.confirmEmailMessage
            case .failure(let error):
                errorMessage = error.message
            }
        }
    }

    private static func confirmMismatchError(password: String, confirm: String) -> String? {
        !confirm.isEmpty && confirm != password ? passwordMismatchMessage : nil
    }
}
