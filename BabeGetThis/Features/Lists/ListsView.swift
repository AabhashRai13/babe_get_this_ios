import SwiftUI

/// Lists overview (Android ShoppingListScreen): greeting, Active/Completed tabs, list cards.
struct ListsView: View {
    @Bindable var viewModel: ListsViewModel
    @State private var isCreating = false
    @State private var newListName = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Picker("Lists", selection: $viewModel.selectedTab) {
                    ForEach(ListsViewModel.Tab.allCases) { tab in
                        Label(tab.rawValue, systemImage: tab.systemImage).tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("lists.tabs")

                if viewModel.lists.isEmpty {
                    EmptyListsView { isCreating = true }
                        .padding(.top, 48)
                } else {
                    GreetingCard(
                        title: Greeting.title(hour: Calendar.current.component(.hour, from: .now), userName: nil),
                        summary: viewModel.greetingSummary
                    )
                    listsSection
                }
            }
            .padding(.horizontal, AppMetrics.screenPadding)
            .padding(.bottom, 96)
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
            if !viewModel.lists.isEmpty {
                Button { isCreating = true } label: {
                    Label("Create list", systemImage: "plus")
                }
                .buttonStyle(TonalFABStyle())
                .padding(AppMetrics.screenPadding)
                .accessibilityIdentifier("lists.create")
            }
        }
        .alert("New List", isPresented: $isCreating) {
            TextField("List name", text: $newListName)
                .accessibilityIdentifier("lists.newName")
            Button("Cancel", role: .cancel) { newListName = "" }
            Button("Create") {
                viewModel.createList(named: newListName)
                newListName = ""
            }
            .disabled(newListName.trimmingCharacters(in: .whitespaces).isEmpty)
        }
        .navigationDestination(for: ShoppingListSummary.self) { list in
            ListDetailPlaceholderView(list: list)
        }
    }

    @ViewBuilder private var listsSection: some View {
        let lists = viewModel.visibleLists
        if lists.isEmpty {
            Text(viewModel.selectedTab == .active
                 ? "All done! All your lists are completed."
                 : "No completed lists yet")
                .font(.subheadline)
                .foregroundStyle(AppColors.textSecondary)
                .frame(maxWidth: .infinity)
                .padding(.top, 32)
        } else {
            LazyVStack(spacing: 10) {
                ForEach(lists) { list in
                    NavigationLink(value: list) { ListCard(list: list) }
                        .buttonStyle(.plain)
                }
            }
            .padding(.top, 8)
        }
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

    var body: some View {
        let accent = ListAccent(listId: list.id)
        HStack(spacing: 16) {
            Image(systemName: "cart")
                .font(.title3)
                .foregroundStyle(accent.onContainer)
                .frame(width: AppMetrics.listTileSize, height: AppMetrics.listTileSize)
                .background(accent.container, in: RoundedRectangle(cornerRadius: AppMetrics.tileRadius, style: .continuous))
            VStack(alignment: .leading, spacing: 4) {
                Text(list.name)
                    .font(.headline)
                    .foregroundStyle(AppColors.textPrimary)
                    .lineLimit(1)
                Text(Greeting.progress(picked: list.pickedUpItems, total: list.totalItems))
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
