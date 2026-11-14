import SwiftUI

/// Settings, pushed from the lists in every auth state (NAV-05). SET-01: Privacy, then About, then the version footer.
struct SettingsView: View {
    static let title = SettingsStrings.title            // settings

    @Environment(\.openURL) private var openURL
    @State private var viewModel = SettingsViewModel()

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                ForEach(viewModel.sections, id: \.title) { section in
                    header(section.title)
                    switch section {
                    case .privacy: privacyRows
                    case .about: aboutRows
                    }
                }
                Text(viewModel.versionFooter)
                    .font(.footnote)
                    .foregroundStyle(AppColors.textSecondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 16)
            }
        }
        .background(AppColors.background)
        .navigationTitle(Self.title)
        .navigationBarTitleDisplayMode(.inline)
    }

    private func header(_ title: String) -> some View {
        Text(title)
            .font(.subheadline.bold())
            .foregroundStyle(AppColors.primary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.leading, 20)
            .padding(.top, 16)
            .padding(.bottom, 4)
            .accessibilityAddTraits(.isHeader)
    }

    @ViewBuilder private var privacyRows: some View {
        SettingsRow(
            title: SettingsStrings.analyticsTitle,
            subtitle: SettingsStrings.analyticsSubtitle,
            icon: "chart.bar",
            onTap: { viewModel.setAnalyticsEnabled(!viewModel.analyticsEnabled) }
        ) {
            Toggle(SettingsStrings.analyticsTitle, isOn: Binding(
                get: { viewModel.analyticsEnabled },
                set: { viewModel.setAnalyticsEnabled($0) }
            ))
            .labelsHidden()
        }
        SettingsRow(
            title: SettingsStrings.crashTitle,
            subtitle: SettingsStrings.crashSubtitle,
            icon: "ant",
            onTap: { viewModel.setCrashReportingEnabled(!viewModel.crashReportingEnabled) }
        ) {
            Toggle(SettingsStrings.crashTitle, isOn: Binding(
                get: { viewModel.crashReportingEnabled },
                set: { viewModel.setCrashReportingEnabled($0) }
            ))
            .labelsHidden()
        }
    }

    @ViewBuilder private var aboutRows: some View {
        if let rateURL = viewModel.rateURL {
            SettingsRow(
                title: SettingsStrings.rateTitle,
                subtitle: SettingsStrings.rateSubtitle,
                icon: "star",
                onTap: { openURL(rateURL) }
            )
        }
        SettingsRow(
            title: SettingsStrings.privacyPolicyTitle,
            subtitle: SettingsStrings.privacyPolicySubtitle,
            icon: "hand.raised",
            onTap: { openURL(viewModel.privacyPolicyURL) }
        )
    }
}

#Preview {
    NavigationStack { SettingsView() }
}
