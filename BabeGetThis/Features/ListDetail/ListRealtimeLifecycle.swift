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
///
/// A channel that ends (supabase-swift's subscribe gives up after its own retries, or the server
/// closes the channel) is subscribed again after a backoff of 1, 2, 4, 8, 16, then 30 s, for as
/// long as the list stays shared and the screen open. Android's supabase-kt client keeps
/// rejoining on its own, so RT-01/RT-03 assume the channel lives as long as the screen.
@MainActor
final class ListRealtimeLifecycle {
    /// Waits before a re-subscribe; throws when the task is cancelled. Tests skip the wait.
    typealias Sleep = @Sendable (Duration) async throws -> Void

    let listId: String
    private let shareState: any ListShareStateSource
    private let resolveCatchUp: @MainActor () -> any ListCatchingUp
    private let resolveChanges: @MainActor () -> any ListChangesSource
    private let sleep: Sleep

    init(listId: String, shareState: any ListShareStateSource,
         catchUp: @escaping @MainActor () -> any ListCatchingUp,
         changes: @escaping @MainActor () -> any ListChangesSource,
         sleep: @escaping Sleep = { try await Task.sleep(for: $0) }) {
        self.listId = listId
        self.shareState = shareState
        self.resolveCatchUp = catchUp
        self.resolveChanges = changes
        self.sleep = sleep
    }

    /// The wait before re-subscribe number `attempt` (0-based): 1, 2, 4, 8, 16, then 30 s.
    nonisolated static func resubscribeDelay(attempt: Int) -> Duration {
        .seconds(min(1 << min(attempt, 5), 30))
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
            var attempt = 0
            while !Task.isCancelled {
                do {
                    // Every element, including the SUBSCRIBED of each (re)join, catches up, so a
                    // re-subscribe leaves no gap.
                    for try await _ in resolveChanges().changes(listId: listId) {
                        attempt = 0
                        await catchUp()
                    }
                } catch {
                    // The channel ended with an error; subscribe again below.
                }
                guard !Task.isCancelled else { return }
                do {
                    try await sleep(Self.resubscribeDelay(attempt: attempt))
                } catch {
                    return
                }
                attempt += 1
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
