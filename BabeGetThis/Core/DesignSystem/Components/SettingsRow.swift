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

enum SettingsRowLayout {
    /// At the accessibility sizes an icon, the text and a toggle side by side leave the text a
    /// narrow column that breaks words ("analyt-ics"). Stacked, the icon sits above the text and
    /// the toggle below it, and the text gets the full width.
    static func stacksVertically(at size: DynamicTypeSize) -> Bool { size.isAccessibilitySize }
}

/// Shared settings-screen row: optional 24pt icon, tinted title, optional subtitle,
/// optional trailing control (e.g. a Toggle). The whole row outside the control is tappable.
struct SettingsRow<Trailing: View>: View {
    private let model: SettingsRowModel
    private let icon: String?
    private let tint: Color
    private let trailing: Trailing
    /// 24 pt at the default text size, growing with Dynamic Type like the title next to it.
    @ScaledMetric(relativeTo: .body) private var iconSize: CGFloat = 24
    @Environment(\.dynamicTypeSize) private var typeSize
    private var stacked: Bool { SettingsRowLayout.stacksVertically(at: typeSize) }

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
            let layout = stacked ? AnyLayout(VStackLayout(alignment: .leading, spacing: 0))
                                 : AnyLayout(HStackLayout(spacing: 16))
            layout {
                Button(action: model.tap) {
                    label
                        .padding(.leading, 20)
                        .padding(.trailing, stacked ? 20 : 0)
                        .padding(.vertical, 16)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                trailing
                    .padding(stacked ? .leading : .trailing, 20)
                    .padding(.bottom, stacked ? 16 : 0)
            }
            .accessibilityElement(children: .contain)
        }
    }

    /// Icon and the model's texts, rendered from `visibleTexts`: title, then subtitle.
    private var label: some View {
        let layout = stacked ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
                             : AnyLayout(HStackLayout(spacing: 16))
        return layout {
            if let icon {
                Image(systemName: icon)
                    .font(.system(size: iconSize))
                    .foregroundStyle(tint)
                    .frame(width: iconSize, height: iconSize)
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
            if !stacked { Spacer(minLength: 0) }
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
