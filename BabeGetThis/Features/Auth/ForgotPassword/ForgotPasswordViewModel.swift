import Foundation
import Observation

/// Two-step reset: enter email, then enter the code and a new password
/// (Android `ForgotPasswordViewModel`). `codeSent` flips the UI from step one to step two.
@MainActor
@Observable
final class ForgotPasswordViewModel {
    nonisolated static let codeLength = 8
    nonisolated static let minPasswordLength = 6
    nonisolated static let invalidEmailMessage = "Enter a valid email address"
    nonisolated static let passwordTooShortMessage = "Password must be at least \(minPasswordLength) characters"

    private(set) var email = ""
    private(set) var code = ""
    private(set) var newPassword = ""
    private(set) var emailError: String?
    private(set) var passwordError: String?
    private(set) var codeSent = false
    private(set) var isLoading = false
    private(set) var errorMessage: String?

    var isEmailValid: Bool { LoginEmailValidator.isValid(email) }

    var isResetFormValid: Bool {
        code.count == Self.codeLength && newPassword.count >= Self.minPasswordLength
    }

    /// Fires once per successful reset (Android `resetSuccess`); the user is then signed in.
    @ObservationIgnored var onResetSuccess: (@MainActor () -> Void)?

    @ObservationIgnored private let authRepository: any AuthRepository

    /// The in-flight request, so callers (and tests) can wait for it.
    @ObservationIgnored private(set) var inFlight: Task<Void, Never>?

    init(authRepository: any AuthRepository) {
        self.authRepository = authRepository
    }

    func onEmailChange(_ value: String) {
        email = value
        emailError = !value.isEmpty && !LoginEmailValidator.isValid(value) ? Self.invalidEmailMessage : nil
    }

    /// The code is digits only (AUTH-04): drop anything else the keyboard lets through.
    func onCodeChange(_ value: String) {
        code = String(value.filter { $0.isASCII && $0.isNumber }.prefix(Self.codeLength))
    }

    func onNewPasswordChange(_ value: String) {
        newPassword = value
        passwordError = !value.isEmpty && value.count < Self.minPasswordLength ? Self.passwordTooShortMessage : nil
    }

    func clearError() {
        errorMessage = nil
    }

    func sendCode() {
        guard isEmailValid, !isLoading else { return }
        let email = email
        isLoading = true
        errorMessage = nil

        inFlight = Task { [weak self, authRepository] in
            let result: Result<Void, AppError>
            do {
                result = try await authRepository.requestPasswordReset(email: email)
            } catch {
                self?.isLoading = false
                return
            }
            guard let self else { return }
            isLoading = false
            switch result {
            case .success: codeSent = true
            case .failure(let error): errorMessage = error.message
            }
        }
    }

    func resetPassword() {
        guard isResetFormValid, !isLoading else { return }
        let email = email, code = code, newPassword = newPassword
        isLoading = true
        errorMessage = nil

        inFlight = Task { [weak self, authRepository] in
            let result: Result<AuthUser, AppError>
            do {
                result = try await authRepository.resetPassword(email: email, code: code, newPassword: newPassword)
            } catch {
                self?.isLoading = false
                return
            }
            guard let self else { return }
            isLoading = false
            switch result {
            case .success: onResetSuccess?()
            case .failure(let error): errorMessage = error.message
            }
        }
    }
}
