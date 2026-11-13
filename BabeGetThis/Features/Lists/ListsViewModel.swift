import Foundation
import Observation

/// Lists overview state (Android `ShoppingListViewModel` + `ShoppingListUiState`).
/// The lists come live from the `ShoppingListRepository`: one owner's lists, newest
/// created first. `init(lists:)` is a fixed snapshot for previews.
@Observable
@MainActor
final class ListsViewModel {
    enum Tab: Int, CaseIterable, Identifiable, Comparable {
        case active
        case completed

        var id: Self { self }
        var title: String { self == .active ? "Active" : "Completed" }

        /// Outlined when inactive, filled when active (Android TabPill).
        func systemImage(selected: Bool) -> String {
            switch self {
            case .active: selected ? "cart.fill" : "cart"
            case .completed: selected ? "checkmark.circle.fill" : "checkmark.circle"
            }
        }

        static func < (lhs: Tab, rhs: Tab) -> Bool { lhs.rawValue < rhs.rawValue }
    }

    /// One date bucket of lists inside a tab.
    struct Section: Identifiable, Equatable {
        let period: TimePeriod
        let lists: [ShoppingListSummary]
        var id: TimePeriod { period }
    }

    /// Everything one tab's pane renders. Both tabs can be built at once, so the
    /// outgoing pane keeps its own data while it slides away.
    struct Pane: Equatable {
        let tab: Tab
        /// Greeting card only on the Active tab, as its first row.
        let showsGreeting: Bool
        let sections: [Section]
        var isEmpty: Bool { sections.isEmpty }

        var emptyMessage: String {
            tab == .active ? "All done! All your lists are completed." : "No completed lists yet"
        }
    }

    /// Repository order: `createdAt` newest first.
    private(set) var lists: [ShoppingListSummary]
    var selectedTab: Tab = .active
    /// A failed write's message, for the screen to show once.
    var errorMessage: String?

    /// "<name> deleted", while the Undo snackbar is up.
    private(set) var undoMessage: String?
    /// The list whose rename dialog is open (Android `editingList`).
    private(set) var renamingList: ShoppingListSummary?

    /// The repository's own models, kept so a delete can be undone with every field.
    @ObservationIgnored private var domainLists: [ShoppingList] = []
    /// Cached because the CASCADE wipes a guest list's items with the list row.
    @ObservationIgnored private var pendingDelete: (list: ShoppingList, items: [ShoppingItemRecord])?
    @ObservationIgnored private let repository: (any ListsRepositoryProviding)?
    @ObservationIgnored private let authState: AuthStateManager?
    @ObservationIgnored private let shareJoiner: (any ListJoining)?
    @ObservationIgnored private let ownership: (any ListOwnershipStore)?

    /// How many guest lists just moved into the account; the screen says so once, then
    /// `dismissAdoptionNotice()` (Android `adoptionNotice`).
    private(set) var adoptionNotice = 0

    init(lists: [ShoppingListSummary] = []) {
        self.lists = lists
        self.repository = nil
        self.authState = nil
        self.shareJoiner = nil
        self.ownership = nil
    }

    init(
        repository: any ListsRepositoryProviding,
        authState: AuthStateManager,
        shareJoiner: (any ListJoining)? = nil,
        ownership: (any ListOwnershipStore)? = nil
    ) {
        self.lists = []
        self.repository = repository
        self.authState = authState
        self.shareJoiner = shareJoiner
        self.ownership = ownership
        self.adoptionNotice = ownership?.adoptionNotice ?? 0
    }

    /// A lost session keeps the account's lists on screen (Android decision 008); the screen
    /// asks the user to sign in again so they sync.
    var isSessionExpired: Bool {
        if case .sessionExpired = authState?.authState { true } else { false }
    }

    func dismissAdoptionNotice() {
        ownership?.setAdoptionNotice(0)
        adoptionNotice = 0
    }

    /// Follows the ownership store's notice until cancelled.
    func observeAdoptionNotice() async {
        guard let ownership else { return }
        for await count in ownership.adoptionNoticeUpdates() { adoptionNotice = count }
    }

    /// Shows a message through the same one-shot channel as failures (Android `showSnackBar`).
    func showSnackBar(_ message: String) { errorMessage = message }

    var activeLists: [ShoppingListSummary] { lists.filter { !$0.isCompleted } }
    var completedLists: [ShoppingListSummary] { lists.filter(\.isCompleted) }
    var hasNoLists: Bool { lists.isEmpty }
    var isActiveTab: Bool { selectedTab == .active }
    var activeItemsToGet: Int { activeLists.reduce(0) { $0 + $1.itemsToGet } }

    func lists(for tab: Tab) -> [ShoppingListSummary] {
        tab == .active ? activeLists : completedLists
    }

    func pane(for tab: Tab, now: Date = .now, calendar: Calendar = .current) -> Pane {
        var sections: [Section] = []
        for list in lists(for: tab) {
            let period = TimePeriod.of(list.createdAt, now: now, calendar: calendar)
            // Insertion order, like Android's linkedMapOf: lists arrive newest first.
            if let index = sections.firstIndex(where: { $0.period == period }) {
                sections[index] = Section(period: period, lists: sections[index].lists + [list])
            } else {
                sections.append(Section(period: period, lists: [list]))
            }
        }
        return Pane(tab: tab, showsGreeting: tab == .active, sections: sections)
    }

    var greetingSummary: String {
        Greeting.summary(listCount: activeLists.count, itemsToGet: activeItemsToGet)
    }

    /// "Good afternoon, Aabhash" while an account's name is known, else just the prefix.
    func greetingTitle(hour: Int) -> String {
        Greeting.title(hour: hour, userName: authState?.userName)
    }

    /// Follows the repository until cancelled (the screen's `.task`). Signing in or
    /// out swaps the lists, because the repository re-queries for the new owner.
    func observeLists() async {
        guard let repository else { return }
        do {
            for try await fresh in repository.allLists() {
                domainLists = fresh
                lists = fresh.map(ShoppingListSummary.init)
            }
        } catch is CancellationError {
        } catch {
            errorMessage = AppError.database().message
        }
    }

    /// Creates the list through the repository (which trims and validates the name)
    /// and returns its id, or nil after reporting a failure.
    @discardableResult
    func createList(named name: String) async -> String? {
        guard let repository else { return nil }
        let result: Result<String, AppError>
        do {
            result = try await repository.createList(name: name)
        } catch {
            return nil // Cancelled.
        }
        switch result {
        case .success(let id):
            selectedTab = .active
            return id
        case .failure(let error):
            errorMessage = error.message
            return nil
        }
    }

    /// A create from the name dialog is being written; Create is disabled meanwhile, so a
    /// double tap can't insert the list twice.
    private(set) var isCreatingList = false
    /// The list the screen should open next (Android `navigateToList`). The screen pushes it
    /// and calls `didOpenRequestedList()`.
    private(set) var openListRequest: ShoppingListSummary?

    /// The name dialog's Create (HOME-11): on success the dialog closes and the new list
    /// opens; on failure the error shows and the dialog stays open with the typed name.
    func confirmCreate(named name: String) async {
        guard !isCreatingList else { return }
        isCreatingList = true
        defer { isCreatingList = false }
        guard let id = await createList(named: name) else { return }
        isNamingList = false
        openListRequest = ShoppingListSummary(
            id: id, name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            totalItems: 0, pickedUpItems: 0, createdAt: .now)
    }

    func didOpenRequestedList() { openListRequest = nil }

    // MARK: - Create chooser and voice gate

    /// The Type / Voice chooser sheet is up.
    private(set) var isChooserPresented = false
    /// The name-the-list dialog is up (the Type path).
    var isNamingList = false
    /// The voice capture sheet is up (signed-in accounts only).
    var isVoicePresented = false
    /// The sign-in prompt for a gated feature, nil when none is showing.
    private(set) var authPrompt: AuthPromptContent?

    /// Create button: opens the chooser.
    func startCreating() { isChooserPresented = true }

    func dismissChooser() { isChooserPresented = false }

    func pickType() {
        isChooserPresented = false
        isNamingList = true
    }

    /// Voice needs a live account session (Android: guests get the auth prompt instead).
    func pickVoice() {
        isChooserPresented = false
        if authState?.liveSessionUserId != nil {
            isVoicePresented = true
        } else {
            authPrompt = .voice
        }
    }

    func dismissAuthPrompt() { authPrompt = nil }

    /// Where the auth prompt sends a guest (AUTH-10).
    enum AuthRoute: String, Identifiable {
        case login, register
        var id: String { rawValue }
    }

    /// The sign-in or create-account screen presented over the lists, nil when none is.
    var authRoute: AuthRoute?

    /// The prompt's "Sign in": closes the prompt and opens Login.
    func promptSignIn() {
        authPrompt = nil
        authRoute = .login
    }

    /// The prompt's "Create account": closes the prompt and opens Register.
    func promptCreateAccount() {
        authPrompt = nil
        authRoute = .register
    }

    // MARK: - Delete, undo, rename

    /// Deletes a list (swipe) and offers Undo. Only offers it when the list was captured,
    /// so the snackbar never advertises an action that can't be honoured.
    func deleteList(id: String) async {
        guard let repository else { return }
        let captured = domainLists.first { $0.id == id }
        let result: Result<[ShoppingItemRecord], AppError>
        do {
            result = try await repository.deleteListAndCaptureItems(listId: id)
        } catch {
            return // Cancelled.
        }
        switch result {
        case .success(let items):
            if let captured {
                pendingDelete = (captured, items)
                undoMessage = "\(captured.name) deleted"
            }
        case .failure(let error):
            errorMessage = error.message
        }
    }

    /// Restores the last deleted list with its items. The pending copy is cleared only once
    /// the restore succeeded, so a failed attempt can be retried.
    func undoDelete() async {
        undoMessage = nil
        guard let repository, let pending = pendingDelete else { return }
        let result: Result<Void, AppError>
        do {
            // An unstructured Task, so cancelling the caller (tapping Undo, then leaving the
            // screen) can't abort the restore half way: Android runs it on applicationScope.
            result = try await Task {
                try await repository.restoreListWithItems(list: pending.list, items: pending.items)
            }.value
        } catch {
            return // Cancelled.
        }
        switch result {
        case .success: pendingDelete = nil
        case .failure(let error): errorMessage = error.message
        }
    }

    /// The snackbar timed out: Undo is no longer on offer.
    func dismissUndo() { undoMessage = nil }

    func startRenaming(id: String) {
        renamingList = lists.first { $0.id == id }
    }

    func cancelRenaming() { renamingList = nil }

    // MARK: - Voice

    /// The voice flow's persist step: names the list from the spoken items, creates it with
    /// them and opens it. Failure is returned, not shown: the voice sheet renders it inline,
    /// so a second error surface would double up.
    func createListWithVoice(_ drafts: [ItemDraft]) async throws -> Result<String, AppError> {
        guard let repository else { return .failure(.unknown()) }
        let name = autoNameVoiceList(drafts)
        let result = try await repository.createListWithItems(name: name, drafts: drafts)
        if case .success(let id) = result {
            openListRequest = ShoppingListSummary(id: id, name: name, totalItems: 0, pickedUpItems: 0, createdAt: .now)
        }
        return result
    }

    // MARK: - Join a shared list by code

    private(set) var isJoinDialogPresented = false
    private(set) var isJoinAuthPromptPresented = false
    private(set) var isJoining = false
    /// Why the last join failed, shown inline in the dialog.
    private(set) var joinError: String?

    /// Joining needs a live session; a guest or a lost session gets the sign-in prompt.
    func startJoining() {
        if authState?.liveSessionUserId != nil {
            joinError = nil
            isJoinDialogPresented = true
        } else {
            isJoinAuthPromptPresented = true
        }
    }

    func dismissJoinDialog() { isJoinDialogPresented = false }

    func dismissJoinAuthPrompt() { isJoinAuthPromptPresented = false }

    /// On success the replica lands in the database and the list appears through the live
    /// query, so nothing else happens here. On failure the dialog stays open with the error.
    func joinList(code: String) async {
        guard let shareJoiner else { return }
        isJoining = true
        joinError = nil
        defer { isJoining = false }
        let result: Result<String, AppError>
        do {
            result = try await shareJoiner.join(code: code)
        } catch {
            return // Cancelled.
        }
        switch result {
        case .success: isJoinDialogPresented = false
        case .failure(let error): joinError = error.message
        }
    }

    /// Renames through the repository (which trims and validates). The dialog closes on
    /// success and stays open, with the error shown, on failure.
    func renameList(id: String, to newName: String) async {
        guard let repository else { return }
        let result: Result<Void, AppError>
        do {
            result = try await repository.updateListName(listId: id, newName: newName)
        } catch {
            return // Cancelled.
        }
        switch result {
        case .success: renamingList = nil
        case .failure(let error): errorMessage = error.message
        }
    }
}

/// Copy for the lists overview (Android GreetingSection and ShoppingListCard strings).
enum Greeting {
    static func prefix(hour: Int) -> String {
        switch hour {
        case ..<12: "Good morning"
        case ..<17: "Good afternoon"
        default: "Good evening"
        }
    }

    /// "Good afternoon, Aabhash" when a name is known, else just the prefix.
    static func title(hour: Int, userName: String?) -> String {
        let firstName = userName?
            .trimmingCharacters(in: .whitespaces)
            .split(separator: " ").first.map(String.init)
        guard let firstName, !firstName.isEmpty else { return prefix(hour: hour) }
        return "\(prefix(hour: hour)), \(firstName)"
    }

    static func summary(listCount: Int, itemsToGet: Int) -> String {
        let lists = listCount == 1 ? "1 list" : "\(listCount) lists"
        let items: String = switch itemsToGet {
        case 0: "nothing to pick up yet"
        case 1: "1 item to get"
        default: "\(itemsToGet) items to get"
        }
        return "\(lists) · \(items)"
    }

    /// "3/7 items" (pluralised on the total, like Android).
    static func progress(picked: Int, total: Int) -> String {
        "\(picked)/\(total) \(total == 1 ? "item" : "items")"
    }

    /// "5 items": the Completed tab's plain count.
    static func count(_ total: Int) -> String {
        "\(total) \(total == 1 ? "item" : "items")"
    }
}

/// What a list card shows (Android ShoppingListCard). Pure, so it is unit tested.
struct ListCardContent: Equatable {
    let name: String
    let subtitle: String
    /// A check on the Completed tab, a cart on Active.
    let systemImage: String
    /// The name is muted (regular weight, secondary colour) on the Completed tab.
    let isNameMuted: Bool

    init(list: ShoppingListSummary, isCompletedTab: Bool) {
        name = list.name
        subtitle = if list.totalItems == 0 {
            "No items yet"
        } else if isCompletedTab {
            Greeting.count(list.totalItems)
        } else {
            Greeting.progress(picked: list.pickedUpItems, total: list.totalItems)
        }
        systemImage = isCompletedTab ? "checkmark" : "cart"
        isNameMuted = isCompletedTab
    }
}
