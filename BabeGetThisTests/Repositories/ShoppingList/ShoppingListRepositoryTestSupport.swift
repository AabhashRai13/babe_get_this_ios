import Foundation
@testable import BabeGetThis

/// Counts `pushSoon()` calls (Android's `{ kicks++ }` lambda).
final class CountingSyncKicker: SyncKicking, @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0

    var kicks: Int {
        get { lock.withLock { count } }
        set { lock.withLock { count = newValue } }
    }

    func pushSoon() {
        lock.withLock { count += 1 }
    }
}

/// Android's `authStateFor(userId, expired)`: an initialised AuthStateManager for a
/// guest (nil), a signed-in user, or a user whose session was lost.
func authStateFor(_ userId: String?, expired: Bool = false) -> AuthStateManager {
    let tokens = InMemoryTokenStore()
    if let userId {
        tokens.saveUserId(userId)
        if !expired { tokens.saveToken("token-\(userId)") }
    }
    let auth = AuthStateManager(tokenStore: tokens)
    auth.initialize()
    return auth
}

extension TestData {
    /// A voice draft (Android `TestData.draft`). nil quantity/shop/note arrive as "" on iOS drafts.
    static func draft(
        name: String = "Milk",
        quantity: String? = "1",
        category: String? = nil,
        note: String? = nil,
        shop: String? = nil
    ) -> ItemDraft {
        var draft = ItemDraft()
        draft.name = name
        draft.quantity = quantity ?? ""
        draft.categoryId = category
        draft.note = note ?? ""
        draft.shop = shop ?? ""
        return draft
    }
}

struct StreamEndedEarly: Error {}

/// Flow.first(): the stream's first value.
func firstValue<T: Sendable>(_ stream: AsyncThrowingStream<T, any Error>) async throws -> T {
    var iterator = stream.makeAsyncIterator()
    guard let value = try await iterator.next() else { throw StreamEndedEarly() }
    return value
}
