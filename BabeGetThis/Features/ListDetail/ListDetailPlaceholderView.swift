import SwiftUI

/// List detail screen: progress, active items grouped by shop then category, completed items.
/// An empty list shows the first-item prompt instead (Android `ShoppingItemsScreen`).
/// Keeps the placeholder's type name and initialiser so `ListsView` is unchanged.
struct ListDetailPlaceholderView: View {
    let list: ShoppingListSummary
    @State private var model: ListDetailViewModel
    @State private var showingAdd = false
    @State private var undoTask: Task<Void, Never>?

    init(list: ShoppingListSummary) {
        self.list = list
        _model = State(initialValue: ListDetailViewModel(listId: list.id))
    }

    var body: some View {
        Group {
            if model.isEmpty {
                FirstItemPromptView { showingAdd = true }
            } else {
                itemList
            }
        }
        .background(AppColors.background)
        .overlay(alignment: .bottomTrailing) {
            // The empty state has its own "Add first item" button (Android hides the FAB too).
            if !model.isEmpty {
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
            if let message = model.undoMessage {
                UndoSnackbar(message: message) {
                    undoTask?.cancel()
                    withAnimation { model.undoDelete() }
                }
                .padding(.bottom, AppMetrics.buttonHeight + AppMetrics.screenPadding * 2)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.easeOut(duration: 0.25), value: model.items)
        .animation(.easeOut(duration: 0.25), value: model.pendingUndo?.item.id)
        .navigationTitle(list.name)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showingAdd) {
            AddItemSheet { model.add($0) }
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
        ItemCardView(item: item) { model.toggle(item.id) }
            .plainRow(bottom: 8)
            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                Button(role: .destructive) {
                    model.delete(item.id)
                    scheduleUndoDismissal()
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
