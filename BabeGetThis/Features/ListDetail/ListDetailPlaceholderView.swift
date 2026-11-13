import SwiftUI

/// Entry point for the list detail screen. Keeps the placeholder's type name and initialiser
/// so `ListsView` is unchanged; the item repository comes from the `AppContainer` in the environment.
struct ListDetailPlaceholderView: View {
    let list: ShoppingListSummary
    @Environment(AppContainer.self) private var container

    var body: some View {
        ListDetailScreen(list: list, source: container.itemRepository)
    }
}

/// List detail screen: progress, active items grouped by shop then category, completed items,
/// all live from the database. An empty list shows the first-item prompt instead
/// (Android `ShoppingItemsScreen`).
private struct ListDetailScreen: View {
    let list: ShoppingListSummary
    @State private var model: ListDetailViewModel
    @State private var showingAdd = false
    @State private var undoTask: Task<Void, Never>?
    @State private var errorTask: Task<Void, Never>?

    init(list: ShoppingListSummary, source: any ListDetailItemsSource) {
        self.list = list
        _model = State(initialValue: ListDetailViewModel(listId: list.id, source: source))
    }

    var body: some View {
        Group {
            if !model.hasLoaded {
                Color.clear
            } else if model.isEmpty {
                FirstItemPromptView { showingAdd = true }
            } else {
                itemList
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppColors.background)
        .overlay(alignment: .bottomTrailing) {
            // The empty state has its own "Add first item" button (Android hides the FAB too).
            if model.hasLoaded && !model.isEmpty {
                Button {
                    showingAdd = true
                } label: {
                    Label("Add", systemImage: "plus")
                }
                .buttonStyle(TonalFABStyle())
                .padding(AppMetrics.screenPadding)
                .accessibilityIdentifier("add-item-button")
            }
        }
        .overlay(alignment: .bottom) {
            VStack(spacing: 8) {
                if let message = model.errorMessage {
                    Snackbar(message: message)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
                if let message = model.undoMessage {
                    UndoSnackbar(message: message) {
                        undoTask?.cancel()
                        SystemHapticPlayer().play(.light)
                        // Not tied to the screen: an undo tapped just before leaving still runs.
                        Task { await model.undoDelete() }
                    }
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .padding(.bottom, AppMetrics.buttonHeight + AppMetrics.screenPadding * 2)
        }
        .animation(.easeOut(duration: 0.25), value: model.items)
        .animation(.easeOut(duration: 0.25), value: model.undoMessage)
        .animation(.easeOut(duration: 0.25), value: model.errorMessage)
        .navigationTitle(list.name)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showingAdd) {
            AddItemSheet { await model.add($0) }
        }
        .task { await model.observeItems() }
        .onChange(of: model.errorMessage) { _, message in
            guard message != nil else { return }
            errorTask?.cancel()
            errorTask = Task {
                try? await Task.sleep(for: SnackbarDuration.short)
                if !Task.isCancelled { model.errorMessage = nil }
            }
        }
    }

    private var itemList: some View {
        List {
            ProgressCardView(total: model.totalCount, pickedUp: model.pickedUpCount)
                .plainRow(top: 8, bottom: 16)

            if !model.activeItems.isEmpty {
                SectionHeaderView(title: "ACTIVE ITEMS", count: model.activeItems.count)
                    .plainRow(bottom: 8)
                ForEach(model.activeGroups) { shopGroup in
                    if model.showsShopHeader(shopGroup) {
                        GroupHeaderView(title: shopGroup.title, systemImage: "mappin.and.ellipse")
                            .plainRow(top: 8, bottom: 4)
                    }
                    ForEach(shopGroup.categories) { category in
                        if !shopGroup.hidesCategoryHeaders {
                            GroupHeaderView(title: category.title)
                                .plainRow(bottom: 4)
                        }
                        ForEach(category.items) { itemRow($0) }
                    }
                }
            }

            if !model.completedItems.isEmpty {
                SectionHeaderView(title: "COMPLETED")
                    .plainRow(top: 16, bottom: 8)
                ForEach(model.completedItems) { itemRow($0) }
            }

            Color.clear.frame(height: 80).plainRow()
        }
        .listStyle(.plain)
        .environment(\.defaultMinListRowHeight, 1)
        .scrollContentBackground(.hidden)
    }

    private func itemRow(_ item: ShoppingItem) -> some View {
        ItemCardView(item: item) {
            SystemHapticPlayer().play(.light)
            Task { await model.toggle(item.id) }
        }
        .plainRow(bottom: 8)
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button(role: .destructive) {
                SystemHapticPlayer().play(.medium)
                Task {
                    await model.delete(item.id)
                    if model.undoMessage != nil { scheduleUndoDismissal() }
                }
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }

    private func scheduleUndoDismissal() {
        undoTask?.cancel()
        undoTask = Task {
            try? await Task.sleep(for: ListDetailViewModel.undoSnackbarDuration)
            if !Task.isCancelled { model.dismissUndo() }
        }
    }
}

private extension View {
    /// A borderless, transparent list row with the screen's horizontal padding.
    func plainRow(top: CGFloat = 0, bottom: CGFloat = 0) -> some View {
        listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
            .listRowInsets(EdgeInsets(top: top, leading: AppMetrics.screenPadding,
                                      bottom: bottom, trailing: AppMetrics.screenPadding))
    }
}
