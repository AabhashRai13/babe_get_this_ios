import Foundation
import XCTest
@testable import BabeGetThis

/// Stands in for `ShoppingItemRepository` (Android's mocked repository plus the
/// `MutableStateFlow` of items): `send` emits a new item list, and each write returns
/// the result a test set, recording what it was called with.
final class FakeListDetailItemsSource: ListDetailItemsSource, @unchecked Sendable {
    private let lock = NSLock()
    private var current: [StoredShoppingItem]?
    private var continuations: [AsyncThrowingStream<[StoredShoppingItem], any Error>.Continuation] = []

    var addResult: Result<String, AppError> = .success("new-id")
    var toggleResult: Result<Void, AppError> = .success(())
    var deleteResult: Result<Void, AppError> = .success(())
    var restoreResult: Result<Void, AppError> = .success(())

    private(set) var added: [(name: String, quantity: String, categoryId: String?, shop: String?, note: String?)] = []
    private(set) var toggled: [(itemId: String, isPickedUp: Bool)] = []
    private(set) var deleted: [String] = []
    private(set) var restored: [StoredShoppingItem] = []

    /// Like `MutableStateFlow.value = items`: current and later subscribers see it.
    func send(_ items: [StoredShoppingItem]) {
        let targets = lock.withLock {
            current = items
            return continuations
        }
        for continuation in targets { continuation.yield(items) }
    }

    func itemsByListId(_ listId: String) -> AsyncThrowingStream<[StoredShoppingItem], any Error> {
        AsyncThrowingStream { continuation in
            let initial = lock.withLock {
                continuations.append(continuation)
                return current
            }
            if let initial { continuation.yield(initial) }
        }
    }

    func addItem(listId: String, name: String, quantity: String, categoryId: String?, shop: String?,
                 note: String?) async throws -> Result<String, AppError> {
        locked {
            added.append((name, quantity, categoryId, shop, note))
            return addResult
        }
    }

    func togglePickedUp(itemId: String, isPickedUp: Bool) async throws -> Result<Void, AppError> {
        locked {
            toggled.append((itemId, isPickedUp))
            return toggleResult
        }
    }

    func deleteItem(itemId: String) async throws -> Result<Void, AppError> {
        locked {
            deleted.append(itemId)
            return deleteResult
        }
    }

    func restoreItem(_ item: StoredShoppingItem) async throws -> Result<Void, AppError> {
        locked {
            restored.append(item)
            return restoreResult
        }
    }

    private func locked<T>(_ body: () -> T) -> T {
        lock.withLock(body)
    }
}

extension TestData {
    /// Android's `item(id, isPickedUp, name)` helper in ShoppingItemsViewModelTest.
    static func storedItem(_ id: String, isPickedUp: Bool = false, name: String? = nil) -> StoredShoppingItem {
        StoredShoppingItem(id: id, listId: "L1", name: name ?? "Item-\(id)", quantity: "1",
                           isPickedUp: isPickedUp, createdAt: 1_000, updatedAt: 1_000)
    }
}

/// Waits (polling) until `condition` holds; fails the test after `timeout`.
@MainActor
func listDetailEventually(
    timeout: Duration = .seconds(5),
    _ message: String = "condition never became true",
    file: StaticString = #filePath,
    line: UInt = #line,
    _ condition: () -> Bool
) async {
    let clock = ContinuousClock()
    let deadline = clock.now + timeout
    while !condition() {
        if clock.now >= deadline {
            XCTFail(message, file: file, line: line)
            return
        }
        try? await Task.sleep(for: .milliseconds(10))
    }
}
