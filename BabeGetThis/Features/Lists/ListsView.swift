import SwiftUI

/// Lists overview (Android ShoppingListScreen): tab pills, then per tab the greeting
/// (Active only) and the lists grouped into date buckets.
struct ListsView: View {
    @Bindable var viewModel: ListsViewModel
    @State private var isCreating = false
    @State private var newListName = ""

    /// Android AnimatedContent: tab content slides in the direction of travel, 280 ms.
    private static let tabMotion = Animation.easeInOut(duration: 0.28)

    var body: some View {
        VStack(spacing: 0) {
            if viewModel.hasNoLists {
                ScrollView {
                    EmptyListsView { isCreating = true }
                        .padding(.top, 48)
                        .padding(.horizontal, AppMetrics.screenPadding)
                }
            } else {
                TabPillRow(selected: viewModel.selectedTab) { tab in
                    SystemHapticPlayer().play(.medium)
                    withAnimation(Self.tabMotion) { viewModel.selectedTab = tab }
                }
                ZStack {
                    ListsPaneView(pane: viewModel.pane(for: viewModel.selectedTab),
                                  greetingTitle: viewModel.greetingTitle(hour: Calendar.current.component(.hour, from: .now)),
                                  greetingSummary: viewModel.greetingSummary)
                        .id(viewModel.selectedTab)
                        // Active sits left of Completed, so each pane enters and leaves on its own side.
                        .transition(.move(edge: viewModel.selectedTab == .active ? .leading : .trailing)
                            .combined(with: .opacity))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipped()
            }
        }
        .background(AppColors.background)
        .navigationTitle("Babe, Get This")
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button("Join a list", systemImage: "person.badge.plus") {}
                    .disabled(true) // Sharing lands with sync.
                Button("Settings", systemImage: "gearshape") {}
                    .disabled(true)
            }
        }
        .overlay(alignment: .bottomTrailing) {
            // Android: the FAB shows on the Active tab only, and not over the empty state.
            if viewModel.isActiveTab && !viewModel.hasNoLists {
                Button { isCreating = true } label: {
                    Label("Create list", systemImage: "plus")
                }
                .buttonStyle(TonalFABStyle())
                .padding(AppMetrics.screenPadding)
                .accessibilityIdentifier("lists.create")
            }
        }
        .task { await viewModel.observeLists() }
        .alert("New List", isPresented: $isCreating) {
            TextField("List name", text: $newListName)
                .accessibilityIdentifier("lists.newName")
            Button("Cancel", role: .cancel) { newListName = "" }
            Button("Create") {
                let name = newListName
                newListName = ""
                Task { await viewModel.createList(named: name) }
            }
            .disabled(newListName.trimmingCharacters(in: .whitespaces).isEmpty)
        }
        .alert("Something went wrong", isPresented: Binding(
            get: { viewModel.errorMessage != nil },
            set: { if !$0 { viewModel.errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
        .navigationDestination(for: ShoppingListSummary.self) { list in
            ListDetailPlaceholderView(list: list)
        }
    }
}

/// One tab's content. Built from its own `Pane`, so the outgoing pane keeps its data mid-slide.
private struct ListsPaneView: View {
    let pane: ListsViewModel.Pane
    let greetingTitle: String
    let greetingSummary: String

    var body: some View {
        if pane.isEmpty {
            Text(pane.emptyMessage)
                .font(.subheadline)
                .foregroundStyle(AppColors.textSecondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.horizontal, AppMetrics.screenPadding)
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    if pane.showsGreeting {
                        GreetingCard(title: greetingTitle, summary: greetingSummary)
                            .padding(.top, 8)
                    }
                    ForEach(pane.sections) { section in
                        TimePeriodHeader(period: section.period)
                        ForEach(section.lists) { list in
                            NavigationLink(value: list) {
                                ListCard(list: list, isCompletedTab: pane.tab == .completed)
                            }
                            .buttonStyle(.plain)
                            .padding(.bottom, 8)
                        }
                        Spacer().frame(height: 4)
                    }
                }
                .padding(.horizontal, AppMetrics.screenPadding)
                .padding(.bottom, 96)
            }
        }
    }
}

/// Pill-style tab row (Android TabPillRow): the selected pill is filled with the primary
/// colour and its icon filled; colour changes animate over 200 ms.
private struct TabPillRow: View {
    let selected: ListsViewModel.Tab
    let onSelect: (ListsViewModel.Tab) -> Void

    var body: some View {
        HStack(spacing: 4) {
            ForEach(ListsViewModel.Tab.allCases) { tab in
                let isSelected = tab == selected
                Button { onSelect(tab) } label: {
                    HStack(spacing: 8) {
                        Image(systemName: tab.systemImage(selected: isSelected))
                            .font(.subheadline)
                        Text(tab.title)
                            .font(.subheadline.weight(isSelected ? .semibold : .medium))
                    }
                    .foregroundStyle(isSelected ? AppColors.onPrimary : AppColors.textSecondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(isSelected ? AppColors.primary : Color.clear, in: Capsule())
                    .shadow(color: AppColors.shadow.opacity(isSelected ? 0.12 : 0), radius: 2, y: 1)
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("lists.tab.\(tab.rawValue)")
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
        .padding(4)
        .background(AppColors.surfaceContainer, in: Capsule())
        .padding(.horizontal, AppMetrics.screenPadding)
        .padding(.vertical, 8)
        .animation(.easeInOut(duration: 0.2), value: selected)
    }
}

/// Date bucket header: a 6 pt primary dot and a bold label (Android TimePeriodHeader).
private struct TimePeriodHeader: View {
    let period: TimePeriod

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(AppColors.primary)
                .frame(width: 6, height: 6)
            Text(period.displayName)
                .font(.subheadline.bold())
                .tracking(0.5)
                .foregroundStyle(AppColors.primary)
        }
        .padding(.top, 16)
        .padding(.bottom, 8)
        .padding(.leading, 4)
        .accessibilityAddTraits(.isHeader)
    }
}

private struct GreetingCard: View {
    let title: String
    let summary: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.title2.bold())
                .foregroundStyle(AppColors.onPrimaryContainer)
            Text(summary)
                .font(.subheadline)
                .foregroundStyle(AppColors.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .background(AppColors.primaryContainer.opacity(0.4),
                    in: RoundedRectangle(cornerRadius: AppMetrics.cardRadius, style: .continuous))
    }
}

struct ListCard: View {
    let list: ShoppingListSummary
    var isCompletedTab = false

    var body: some View {
        let accent = ListAccent(listId: list.id)
        let content = ListCardContent(list: list, isCompletedTab: isCompletedTab)
        HStack(spacing: 16) {
            Image(systemName: content.systemImage)
                .font(.title3)
                .foregroundStyle(accent.onContainer)
                .frame(width: AppMetrics.listTileSize, height: AppMetrics.listTileSize)
                .background(accent.container, in: RoundedRectangle(cornerRadius: AppMetrics.tileRadius, style: .continuous))
            VStack(alignment: .leading, spacing: 4) {
                Text(content.name)
                    .font(.headline.weight(content.isNameMuted ? .regular : .semibold))
                    .foregroundStyle(content.isNameMuted ? AppColors.textSecondary : AppColors.textPrimary)
                    .lineLimit(1)
                Text(content.subtitle)
                    .font(.subheadline)
                    .foregroundStyle(AppColors.textSecondary)
            }
            Spacer(minLength: 8)
            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(AppColors.textSecondary)
        }
        .padding(16)
        .background(AppColors.surfaceContainerLow,
                    in: RoundedRectangle(cornerRadius: AppMetrics.cardRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: AppMetrics.cardRadius, style: .continuous)
                .strokeBorder(AppColors.outline.opacity(0.6), lineWidth: 0.5)
        }
        .shadow(color: AppColors.shadow.opacity(0.04), radius: 4, y: 2)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("lists.card.\(list.id)")
    }
}

private struct EmptyListsView: View {
    let onCreate: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            BrandMark()
            Text("No lists yet")
                .font(.title2.bold())
                .foregroundStyle(AppColors.textPrimary)
                .padding(.top, 8)
            Text("Create a list and share it so you can shop together.")
                .font(.subheadline)
                .foregroundStyle(AppColors.textSecondary)
                .multilineTextAlignment(.center)
            Button("Create your first list", action: onCreate)
                .buttonStyle(PrimaryButtonStyle())
                .padding(.top, 16)
                .accessibilityIdentifier("lists.createFirst")
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 8)
    }
}

#Preview("Lists") {
    NavigationStack { ListsView(viewModel: ListsViewModel(lists: ShoppingListSummary.samples)) }
}

#Preview("Empty") {
    NavigationStack { ListsView(viewModel: ListsViewModel()) }
}
