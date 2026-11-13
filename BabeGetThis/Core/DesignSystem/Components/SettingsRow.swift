import SwiftUI

/// What a settings row shows and does, separate from layout so it can be tested.
struct SettingsRowModel {
    let title: String
    var subtitle: String?
    let onTap: () -> Void

    /// Every text the row renders, top to bottom.
    var visibleTexts: [String] { [title] + (subtitle.map { [$0] } ?? []) }

    func tap() { onTap() }
}

/// Shared settings-screen row: optional 24pt icon, tinted title, optional subtitle,
/// optional trailing control (e.g. a Toggle). The whole row outside the control is tappable.
struct SettingsRow<Trailing: View>: View {
    private let model: SettingsRowModel
    private let icon: String?
    private let tint: Color
    private let trailing: Trailing

    init(
        title: String,
        subtitle: String? = nil,
        icon: String? = nil,
        tint: Color = AppColors.textPrimary,
        onTap: @escaping () -> Void,
        @ViewBuilder trailing: () -> Trailing
    ) {
        model = SettingsRowModel(title: title, subtitle: subtitle, onTap: onTap)
        self.icon = icon
        self.tint = tint
        self.trailing = trailing()
    }

    var body: some View {
        if Trailing.self == EmptyView.self {
            // Navigation row: one button, read as "title, subtitle".
            Button(action: model.tap) {
                label
                    .padding(.horizontal, 20)
                    .padding(.vertical, 16)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        } else {
            // Toggle row: the label is its own button and the trailing control stays a separate
            // accessibility element, so VoiceOver can reach the toggle's value and action.
            HStack(spacing: 16) {
                Button(action: model.tap) {
                    label
                        .padding(.leading, 20)
                        .padding(.vertical, 16)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                trailing
                    .padding(.trailing, 20)
            }
            .accessibilityElement(children: .contain)
        }
    }

    /// Icon and the model's texts, rendered from `visibleTexts`: title, then subtitle.
    private var label: some View {
        HStack(spacing: 16) {
            if let icon {
                Image(systemName: icon)
                    .font(.system(size: 24))
                    .foregroundStyle(tint)
                    .frame(width: 24, height: 24)
                    .accessibilityHidden(true)
            }
            VStack(alignment: .leading) {
                ForEach(Array(model.visibleTexts.enumerated()), id: \.offset) { index, text in
                    if index == 0 {
                        Text(text).font(.body).foregroundStyle(tint)
                    } else {
                        Text(text).font(.footnote).foregroundStyle(AppColors.textSecondary)
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

extension SettingsRow where Trailing == EmptyView {
    init(title: String, subtitle: String? = nil, icon: String? = nil,
         tint: Color = AppColors.textPrimary, onTap: @escaping () -> Void) {
        self.init(title: title, subtitle: subtitle, icon: icon, tint: tint, onTap: onTap) { EmptyView() }
    }
}
