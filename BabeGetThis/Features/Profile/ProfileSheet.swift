import SwiftUI

/// Copy for the profile sheet (STR-10): Android's keys and wording, in Localizable.xcstrings.
enum ProfileCopy {
    static var name: String { String(localized: .profileName) }
    static var noEmail: String { String(localized: .profileNoEmail) }
    static var logout: String { String(localized: .profileLogout) }
    static var save: String { String(localized: .save) }
    static var deleteAccount: String { String(localized: .profileDeleteAccount) }
    static var deleteTitle: String { String(localized: .profileDeleteTitle) }
    static var deleteBody: String { String(localized: .deleteAccountBody) }
    static var delete: String { String(localized: .profileDelete) }
    static var cancel: String { String(localized: .cancel) }
    static var unsyncedTitle: String { String(localized: .signOutUnsyncedTitle) }
    static var unsyncedBody: String { String(localized: .signOutUnsyncedBody) }
    static var unsyncedConfirm: String { String(localized: .signOutUnsyncedConfirm) }
}

extension EnvironmentValues {
    /// The container's profile view model; nil in previews, where the sheet shows name and email only.
    @Entry var profileViewModel: ProfileViewModel?
}

/// The account's profile (PROF-01), opened from the top bar's avatar while an account exists:
/// a large avatar, the editable name, the read-only email, Log out and Delete account.
struct ProfileSheet: View {
    let name: String?
    let email: String?
    @Environment(\.profileViewModel) private var viewModel

    static let noEmail = ProfileCopy.noEmail

    var body: some View {
        Group {
            if let viewModel {
                ProfileSheetContent(viewModel: viewModel)
            } else {
                ProfileSheetContent.Avatar(name: name)
                    .padding(AppMetrics.screenPadding)
            }
        }
        .frame(maxWidth: .infinity)
        .background(AppColors.surface)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
}

private struct ProfileSheetContent: View {
    @Bindable var viewModel: ProfileViewModel
    @State private var isDeleteConfirmationPresented = false

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                Avatar(name: viewModel.userName)
                    .padding(.top, 24)
                    .padding(.bottom, 20)
                nameField
                    .padding(.bottom, 12)
                HStack(spacing: 12) {
                    Image(systemName: "envelope")
                        .font(.subheadline)
                        .accessibilityHidden(true)
                    Text(viewModel.userEmail.allSatisfy(\.isWhitespace) ? ProfileCopy.noEmail : viewModel.userEmail)
                        .font(.subheadline)
                    Spacer(minLength: 0)
                }
                .foregroundStyle(AppColors.textSecondary)
                .padding(.horizontal, 4)
                .padding(.vertical, 8)
                .accessibilityIdentifier("profile.email")
                Divider()
                    .overlay(AppColors.outline)
                    .padding(.vertical, 16)
                logoutButton
                deleteButton
                    .padding(.top, 8)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 32)
        }
        .overlay(alignment: .bottom) { ProfileToastView(viewModel: viewModel) }
        .alert(ProfileCopy.deleteTitle, isPresented: $isDeleteConfirmationPresented) {
            Button(ProfileCopy.delete, role: .destructive) { viewModel.deleteAccount() }
            Button(ProfileCopy.cancel, role: .cancel) {}
        } message: {
            Text(ProfileCopy.deleteBody)
        }
        .alert(ProfileCopy.unsyncedTitle, isPresented: Binding(
            get: { viewModel.showUnsyncedSignOutWarning },
            set: { if !$0 { viewModel.dismissUnsyncedSignOutWarning() } }
        )) {
            Button(ProfileCopy.unsyncedConfirm, role: .destructive) { viewModel.confirmSignOutAnyway() }
            Button(ProfileCopy.cancel, role: .cancel) { viewModel.dismissUnsyncedSignOutWarning() }
        } message: {
            Text(ProfileCopy.unsyncedBody)
        }
    }

    private var nameField: some View {
        HStack(spacing: 12) {
            Image(systemName: "person")
                .foregroundStyle(AppColors.primary)
                .accessibilityHidden(true)
            TextField(ProfileCopy.name, text: Binding(
                get: { viewModel.editedName },
                set: { viewModel.onNameChanged($0) }
            ))
            .textContentType(.name)
            .submitLabel(.done)
            // The view model also ignores a save while anything is running (Return during a save).
            .onSubmit { if viewModel.hasNameChanged && !viewModel.isBusy { viewModel.saveName() } }
            .accessibilityIdentifier("profile.name")
            // Save shows only while there is a different, non-blank name to save.
            if viewModel.hasNameChanged {
                if viewModel.isSaving {
                    ProgressView()
                        .tint(AppColors.primary)
                } else {
                    Button(ProfileCopy.save) { viewModel.saveName() }
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(AppColors.primary)
                        .disabled(viewModel.isBusy)
                        .accessibilityIdentifier("profile.save")
                }
            }
        }
        .padding(.horizontal, 16)
        .frame(minHeight: AppMetrics.buttonHeight)
        .background {
            RoundedRectangle(cornerRadius: AppMetrics.tileRadius, style: .continuous)
                .strokeBorder(AppColors.outline, lineWidth: 1)
        }
    }

    private var logoutButton: some View {
        Button { viewModel.logout() } label: {
            if viewModel.isLoggingOut {
                ProgressView()
                    .tint(AppColors.error)
            } else {
                // The error colour marks it destructive; set on the label, inside the button style.
                Label(ProfileCopy.logout, systemImage: "rectangle.portrait.and.arrow.right")
                    .foregroundStyle(AppColors.error)
            }
        }
        .buttonStyle(OutlinedButtonStyle())
        // Log out and Delete account never run together.
        .disabled(viewModel.isBusy)
        .accessibilityIdentifier("profile.logout")
    }

    /// Deliberately quieter than Log out: required, but not something to encourage.
    private var deleteButton: some View {
        Button { isDeleteConfirmationPresented = true } label: {
            if viewModel.isDeletingAccount {
                ProgressView()
                    .tint(AppColors.error)
            } else {
                Text(ProfileCopy.deleteAccount)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(AppColors.error)
            }
        }
        .frame(minHeight: 44)
        .disabled(viewModel.isBusy)
        .accessibilityIdentifier("profile.deleteAccount")
    }

    /// Two layered circles with the name's initial, or a person glyph.
    struct Avatar: View {
        let name: String?
        /// 88 pt (outer) at the default text size; grows with the initial inside it.
        @ScaledMetric(relativeTo: .title) private var size: CGFloat = 88

        var body: some View {
            ZStack {
                Circle()
                    .fill(AppColors.primaryContainer.opacity(0.3))
                    .frame(width: size, height: size)
                Circle()
                    .fill(AppColors.primaryContainer)
                    .frame(width: size * 64 / 88, height: size * 64 / 88)
                if let initial = ListsViewModel.initial(name: name) {
                    Text(initial)
                        .font(.title.bold())
                        .foregroundStyle(AppColors.onPrimaryContainer)
                } else {
                    Image(systemName: "person")
                        .font(.title2)
                        .foregroundStyle(AppColors.onPrimaryContainer)
                }
            }
            .accessibilityHidden(true)
        }
    }
}

/// The profile's messages ("Name updated", errors, "Your account has been deleted") as a
/// snackbar that clears itself after the short duration.
struct ProfileToastView: View {
    let viewModel: ProfileViewModel

    var body: some View {
        if let toast = viewModel.toast {
            Snackbar(message: toast.message)
                .padding(.bottom, 8)
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .task(id: toast.id) {
                    try? await Task.sleep(for: SnackbarDuration.short)
                    if !Task.isCancelled { viewModel.dismissToast(id: toast.id) }
                }
                .accessibilityIdentifier("profile.toast")
        }
    }
}

#Preview {
    Text("").sheet(isPresented: .constant(true)) {
        ProfileSheet(name: "Aabhash", email: "a@b.com")
    }
}
