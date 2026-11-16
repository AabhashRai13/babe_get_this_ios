import Foundation

/// The slice of `ShoppingListRepository` the lists overview uses, so the view model can be
/// tested against a fake that fails on demand (Android mocks the repository with MockK).
protocol ListsRepositoryProviding: Sendable {
    func allLists() -> AsyncThrowingStream<[ShoppingList], any Error>
    func createList(name: String) async throws -> Result<String, AppError>
    func createListWithItems(name: String, drafts: [ItemDraft]) async throws -> Result<String, AppError>
    func updateListName(listId: String, newName: String) async throws -> Result<Void, AppError>
    func deleteListAndCaptureItems(listId: String) async throws -> Result<[ShoppingItemRecord], AppError>
    func restoreListWithItems(list: ShoppingList, items: [ShoppingItemRecord]) async throws -> Result<Void, AppError>
}

extension ShoppingListRepository: ListsRepositoryProviding {}

/// Joining a shared list by its code (Android `ShareRepository.join`). Succeeds with the
/// joined list's id.
protocol ListJoining: Sendable {
    func join(code: String) async throws -> Result<String, AppError>
}

extension ShareRepository: ListJoining {}

/// Names a voice-created list from its first item (Android `autoNameVoiceList`): nobody
/// wants to name a grocery list. "Milk" for one item, "Milk + 2 more" for several.
func autoNameVoiceList(_ drafts: [ItemDraft]) -> String {
    let trimmed = drafts.first?.name.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    // Capped so a mis-parsed, paragraph-long first item can't make an absurd title.
    let capped = String(trimmed.prefix(40))
    let first = capped.isEmpty ? "List" : capped
    let others = drafts.count - 1
    return others > 0 ? "\(first) + \(others) more" : first
}

/// What the lists overview reports (TEL-04), in its own terms; the app's adapter
/// (`TrackingListAnalytics`) turns it into analytics events. Ids only: a list's name, an item's
/// name and a join code never cross this line.
@MainActor
protocol ListsAnalytics {
    /// A list was created by voice: one category id per spoken item, nil where none was assigned.
    func voiceListCreated(categoryIds: [String?])
    /// A join is about to be sent, before its outcome is known.
    func joinAttempted()
    /// This device joined `listId`.
    func joinSucceeded(listId: String)
    func joinFailed(_ error: AppError)
}

struct NoopListsAnalytics: ListsAnalytics {
    func voiceListCreated(categoryIds: [String?]) {}
    func joinAttempted() {}
    func joinSucceeded(listId: String) {}
    func joinFailed(_ error: AppError) {}
}
