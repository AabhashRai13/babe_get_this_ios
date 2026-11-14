import SwiftUI

/// The account's profile, opened from the top bar's avatar (HOME-13). A placeholder with the
/// name and email only: F37 builds the real sheet (edit name, sign out, delete account).
struct ProfileSheet: View {
    let name: String?
    let email: String?

    static let noEmail = "No email"                     // profile_no_email

    var body: some View {
        VStack(spacing: 8) {
            Circle()
                .fill(AppColors.primaryContainer)
                .frame(width: 64, height: 64)
                .overlay {
                    if let initial = ListsViewModel.initial(name: name, email: email) {
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
            if let name, !name.isEmpty {
                Text(name)
                    .font(.title3.bold())
                    .foregroundStyle(AppColors.textPrimary)
            }
            Text(email ?? Self.noEmail)
                .font(.subheadline)
                .foregroundStyle(AppColors.textSecondary)
        }
        .padding(AppMetrics.screenPadding)
        .frame(maxWidth: .infinity)
        .presentationDetents([.height(220)])
        .presentationDragIndicator(.visible)
    }
}

#Preview {
    Text("").sheet(isPresented: .constant(true)) {
        ProfileSheet(name: "Aabhash", email: "a@b.com")
    }
}
