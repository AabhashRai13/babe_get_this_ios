import SwiftUI

/// Settings, pushed from the lists in every auth state (NAV-05). A placeholder: F42 builds it.
struct SettingsView: View {
    static let title = "Settings"                       // settings

    var body: some View {
        List {}
            .scrollContentBackground(.hidden)
            .background(AppColors.background)
            .navigationTitle(Self.title)
            .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview {
    NavigationStack { SettingsView() }
}
