import SwiftUI

/// Copy for the profile sheet (STR-10), Android's exact wording.
enum ProfileCopy {
    static let name = "Name"                            // profile_name
    static let noEmail = "No email"                     // profile_no_email
    static let logout = "Log out"                       // profile_logout
    static let save = "Save"
    static let deleteAccount = "Delete account"
    static let deleteTitle = "Delete account?"
    static let deleteBody = "This permanently deletes your account and can't be undone. Your lists are removed from this phone and our server; lists you shared stay with the people you shared them with." // delete_account_body
    static let delete = "Delete"
    static let cancel = "Cancel"
    static let unsyncedTitle = "Sign out?"              // sign_out_unsynced_title
    static let unsyncedBody = "Some changes haven't been saved to your account yet. If you sign out now, they'll be lost." // sign_out_unsynced_body
    static let unsyncedConfirm = "Sign out anyway"      // sign_out_unsynced_confirm
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
            .onSubmit { if viewModel.hasNameChanged { viewModel.saveName() } }
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
        .disabled(viewModel.isLoggingOut)
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
        .disabled(viewModel.isDeletingAccount)
        .accessibilityIdentifier("profile.deleteAccount")
    }

    /// Two layered circles with the name's initial, or a person glyph.
    struct Avatar: View {
        let name: String?

        var body: some View {
            ZStack {
                Circle()
                    .fill(AppColors.primaryContainer.opacity(0.3))
                    .frame(width: 88, height: 88)
                Circle()
                    .fill(AppColors.primaryContainer)
                    .frame(width: 64, height: 64)
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
