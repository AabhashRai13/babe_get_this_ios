import Foundation

/// The slice of `ShoppingListRepository` the in-list mic uses.
protocol ListItemsAdding: Sendable {
    func addItemsToList(listId: String, drafts: [ItemDraft]) async throws -> Result<String, AppError>
}

extension ShoppingListRepository: ListItemsAdding {}

/// The voice sheet's persist step inside an open list (Android `addItemsWithVoice`): the spoken
/// drafts go straight into this list with no review step. Every draft is saved, an empty
/// quantity included, so this never goes through the manual add rule. Failure is returned for
/// the sheet to show inline; the error keeps the repository's message.
func saveVoiceDrafts(_ drafts: [ItemDraft], intoList listId: String,
                     using repository: any ListItemsAdding) async -> Result<String, VoiceError> {
    do {
        switch try await repository.addItemsToList(listId: listId, drafts: drafts) {
        case .success(let id): return .success(id)
        case .failure(let error): return .failure(.unknown(error.message))
        }
    } catch {
        return .failure(.unknown())
    }
}
