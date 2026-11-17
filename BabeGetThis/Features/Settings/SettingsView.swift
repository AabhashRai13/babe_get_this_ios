import SwiftUI

/// Settings, pushed from the lists in every auth state (NAV-05). SET-01: Privacy, then About, then the version footer.
struct SettingsView: View {
    static let title = SettingsStrings.title            // settings

    @Environment(\.openURL) private var openURL
    @State private var viewModel: SettingsViewModel

    /// `consent` is the container's `TelemetryConsent` in the app, so a toggle reaches Analytics
    /// and Crashlytics at once, not at the next launch (TEL-02).
    init(consent: any TelemetryConsentStore) {
        _viewModel = State(initialValue: SettingsViewModel(consent: consent))
    }

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
        .reportsScreen(.settings)
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

    private var analyticsBinding: Binding<Bool> {
        Binding(get: { viewModel.analyticsEnabled }, set: { viewModel.setAnalyticsEnabled($0) })
    }

    private var crashReportingBinding: Binding<Bool> {
        Binding(get: { viewModel.crashReportingEnabled }, set: { viewModel.setCrashReportingEnabled($0) })
    }

    @ViewBuilder private var privacyRows: some View {
        toggleRow(title: SettingsStrings.analyticsTitle, subtitle: SettingsStrings.analyticsSubtitle,
                  icon: "chart.bar", isOn: analyticsBinding)
        toggleRow(title: SettingsStrings.crashTitle, subtitle: SettingsStrings.crashSubtitle,
                  icon: "ant", isOn: crashReportingBinding)
    }

    /// A row with a switch. Tapping the label flips it too. VoiceOver reads the row as one switch
    /// with the title as its label, the subtitle, and the on/off value, instead of a silent label
    /// button next to a switch that has no subtitle.
    private func toggleRow(title: String, subtitle: String, icon: String, isOn: Binding<Bool>) -> some View {
        SettingsRow(title: title, subtitle: subtitle, icon: icon, onTap: { isOn.wrappedValue.toggle() }) {
            Toggle(title, isOn: isOn)
                .labelsHidden()
                // Android's M3 Switch tracks in colorScheme.primary; iOS would show system green.
                .tint(AppColors.primary)
        }
        .accessibilityRepresentation {
            Toggle(isOn: isOn) {
                Text(title)
                Text(subtitle)
            }
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
    NavigationStack { SettingsView(consent: UserDefaultsTelemetryConsentStore()) }
}
