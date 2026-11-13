import SwiftUI

/// Entry point for the list detail screen. Keeps the placeholder's type name and initialiser
/// so `ListsView` is unchanged; the item repository comes from the `AppContainer` in the environment.
struct ListDetailPlaceholderView: View {
    let list: ShoppingListSummary
    @Environment(AppContainer.self) private var container

    var body: some View {
        ListDetailScreen(list: list, source: container.itemRepository,
                         authState: { [authState = container.authState] in authState.authState },
                         makeVoiceViewModel: { container.makeVoiceCaptureViewModel() },
                         leaveCleaner: container.listRepository)
    }
}

/// UIKit share sheet for "Share as text".
private struct ActivityShareSheet: UIViewControllerRepresentable {
    let text: String

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [text], applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}

/// List detail screen: progress, active items grouped by shop then category, completed items,
/// all live from the database. An empty list shows the first-item prompt instead
/// (Android `ShoppingItemsScreen`).
private struct ListDetailScreen: View {
    let list: ShoppingListSummary
    @State private var model: ListDetailViewModel
    @State private var showingAdd = false
    @State private var editingItem: ShoppingItem?
    @State private var undoTask: Task<Void, Never>?
    @State private var errorTask: Task<Void, Never>?
    @State private var chrome: ListDetailChromeModel
    @State private var leaveGuard: ListLeaveGuard
    private let makeVoiceViewModel: () -> VoiceCaptureViewModel

    init(list: ShoppingListSummary, source: any ListDetailItemsSource,
         authState: @escaping () -> AuthState,
         makeVoiceViewModel: @escaping () -> VoiceCaptureViewModel,
         leaveCleaner: any ListLeaveCleaning) {
        self.list = list
        self.makeVoiceViewModel = makeVoiceViewModel
        _model = State(initialValue: ListDetailViewModel(listId: list.id, source: source))
        _chrome = State(initialValue: ListDetailChromeModel(listName: list.name, authState: authState))
        _leaveGuard = State(initialValue: ListLeaveGuard(listId: list.id, cleaner: leaveCleaner))
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
            VStack(alignment: .trailing, spacing: 12) {
                Button {
                    chrome.voiceFabTapped()
                } label: {
                    Image(systemName: "mic.fill")
                        .font(.title3)
                        .foregroundStyle(AppColors.primary)
                        .frame(width: 48, height: 48)
                        .background(AppColors.surface, in: Circle())
                        .shadow(radius: 2, y: 1)
                }
                .accessibilityLabel("Add by voice")
                .accessibilityIdentifier("voice-fab")
                // The empty state has its own "Add first item" button (Android hides the FAB too).
                if model.hasLoaded && !model.isEmpty {
                    Button {
                        showingAdd = true
                    } label: {
                        Label("Add", systemImage: "plus")
                    }
                    .buttonStyle(TonalFABStyle())
                    .accessibilityIdentifier("add-item-button")
                }
            }
            .padding(AppMetrics.screenPadding)
        }
        .overlay {
            if let prompt = chrome.authPrompt {
                AuthPromptDialog(content: prompt,
                                 onLogin: { chrome.promptSignIn() },
                                 onRegister: { chrome.promptCreateAccount() },
                                 onDismiss: { chrome.dismissAuthPrompt() })
            }
        }
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                ForEach(ListDetailChromeModel.topBarActions) { action in
                    Button(action.title, systemImage: action.systemImage) { chrome.perform(action) }
                        .labelStyle(.iconOnly)
                        .accessibilityIdentifier("detail.\(action.rawValue)")
                }
            }
        }
        .sheet(item: $chrome.authRoute) { route in
            AuthSheet(initialRoute: route, onDone: { chrome.authRoute = nil })
        }
        .sheet(isPresented: $chrome.isVoicePresented) {
            VoiceCaptureSheet(
                viewModel: makeVoiceViewModel(),
                // TODO(F41): add the transcribed items to this list.
                persist: { _ in .failure(.unknown("Adding items from voice isn't available yet.")) },
                onDismiss: { chrome.isVoicePresented = false },
                onSwitchToType: {
                    chrome.isVoicePresented = false
                    showingAdd = true
                })
        }
        .sheet(isPresented: $chrome.isShareLivePresented) {
            // Placeholder: the share dialog is F34.
            Text("Share list live")
                .font(.title3.bold())
                .padding()
                .presentationDetents([.medium])
        }
        .sheet(isPresented: Binding(
            get: { chrome.sharedText != nil },
            set: { if !$0 { chrome.sharedText = nil } }
        )) {
            ActivityShareSheet(text: chrome.sharedText ?? "")
                .presentationDetents([.medium, .large])
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
                        // Not tied to the screen: an undo tapped just before leaving still runs,
                        // and the leave teardown waits for it.
                        leaveGuard.trackUndo { await model.undoDelete() }
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
        .sheet(item: $editingItem) { item in
            AddItemSheet(editing: item) { await model.edit(item.id, with: $0) }
        }
        .task { await model.observeItems() }
        .leaveEmptyListGuard(leaveGuard, model: model)
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
        let actions = ItemCardActions.forItem(
            item, in: model,
            onEdit: { editingItem = item },
            onDelete: {
                Task {
                    await model.delete(item.id)
                    if model.undoMessage != nil { scheduleUndoDismissal() }
                }
            })
        return actions.card(for: item) {
            ItemCardView(item: item, onToggle: {
                SystemHapticPlayer().play(.light)
                actions.onToggle()
            }, onEdit: actions.onEdit)
        }
        .plainRow(bottom: 8)
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
