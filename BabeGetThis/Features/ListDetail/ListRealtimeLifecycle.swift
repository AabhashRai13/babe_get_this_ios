import Foundation

/// Where the realtime lifecycle reads a list's share state and owner. The app passes
/// `ShoppingListRepository`.
protocol ListShareStateSource: Sendable {
    func shareCode(listId: String) -> AsyncThrowingStream<String?, any Error>
    func isAccountList(_ listId: String) async throws -> Bool
}

extension ShoppingListRepository: ListShareStateSource {}

/// "Catch up this list" (Android `syncEngine.catchUp`). The app passes `SyncEngine`.
protocol ListCatchingUp: Sendable {
    func catchUp(listId: String) async throws -> Result<Void, AppError>
}

extension SyncEngine: ListCatchingUp {}

/// "Changes for this list": one element per realtime signal, carrying no data (RT-01, RT-02).
protocol ListChangesSource: Sendable {
    func changes(listId: String) -> AsyncThrowingStream<Void, any Error>
}

/// The app's `ListChangesSource`: the realtime channel of `SharedListRemote`.
struct SharedListRemoteChanges: ListChangesSource {
    let remote: any SharedListRemote

    func changes(listId: String) -> AsyncThrowingStream<Void, any Error> {
        remote.changes(listId: listId)
    }
}

/// Live sync while the list detail screen is open (RT-03, Android `ShoppingItemsViewModel.init`),
/// keyed on whether the list is shared:
/// - shared: catch up once, then subscribe and catch up again on every signal, including
///   each (re)subscribe, since realtime never carries data (RT-02);
/// - unshared account list: the account's other phones may have changed it, so catch up once,
///   with no socket for a list nobody else edits live;
/// - guest list: nothing, so it never reaches the network.
///
/// A change of share state replaces the previous follow (Android `collectLatest`), so a list
/// unshared while open closes its channel. Cancelling `run()` (SwiftUI does, when the screen
/// closes) tears everything down.
///
/// The engine and remote are resolved only when needed: a guest list never builds the sync stack.
@MainActor
final class ListRealtimeLifecycle {
    let listId: String
    private let shareState: any ListShareStateSource
    private let resolveCatchUp: @MainActor () -> any ListCatchingUp
    private let resolveChanges: @MainActor () -> any ListChangesSource

    init(listId: String, shareState: any ListShareStateSource,
         catchUp: @escaping @MainActor () -> any ListCatchingUp,
         changes: @escaping @MainActor () -> any ListChangesSource) {
        self.listId = listId
        self.shareState = shareState
        self.resolveCatchUp = catchUp
        self.resolveChanges = changes
    }

    /// Follows the list's share state until the calling task is cancelled.
    func run() async {
        var current: Task<Void, Never>?
        var lastShared: Bool?
        do {
            for try await code in shareState.shareCode(listId: listId) {
                let shared = code != nil
                // distinctUntilChanged: an unrelated edit to the list row must not re-subscribe.
                guard shared != lastShared else { continue }
                lastShared = shared
                current?.cancel()
                current = Task { await self.follow(shared: shared) }
            }
        } catch {
            // The share state is unreadable: stop following rather than guess.
        }
        current?.cancel()
    }

    private func follow(shared: Bool) async {
        if shared {
            await catchUp()
            guard !Task.isCancelled else { return }
            do {
                for try await _ in resolveChanges().changes(listId: listId) {
                    await catchUp()
                }
            } catch {
                // The channel failed; the next screen open (or share-state change) subscribes again.
            }
        } else if (try? await shareState.isAccountList(listId)) == true, !Task.isCancelled {
            await catchUp()
        }
    }

    private func catchUp() async {
        // A failed catch-up is retried by the next signal; there is nothing to show.
        _ = try? await resolveCatchUp().catchUp(listId: listId)
    }
}
