import Foundation
import Supabase

/// Port of Android `SupabaseSharedListRemote.kt`.
final class SupabaseSharedListRemote: SharedListRemote {
    /// Ends `changes(listId:)` when its channel stays unsubscribed after it joined.
    struct ChannelClosed: Error {}

    private let client: SupabaseClient

    init(client: SupabaseClient) {
        self.client = client
    }

    func insertList(_ row: ListRow) async throws -> Bool {
        do {
            try await client.from("lists").insert(row, returning: .minimal).execute()
            return true
        } catch let error as PostgrestError {
            // 23505 = unique violation: the list row (or, astronomically, the share code) already exists
            // server-side.
            if Self.isDuplicate(error) { return false }
            throw error
        }
    }

    func setShareCode(listId: String, code: String) async throws -> String? {
        let rows: [ListRow] = try await client.from("lists")
            .update(["share_code": code], returning: .representation)
            .eq("id", value: listId)
            .execute()
            .value
        return rows.first?.shareCode
    }

    func upsertLists(_ rows: [ListRow]) async throws {
        try await client.from("lists").upsert(rows, returning: .minimal).execute()
    }

    func upsertItems(_ rows: [ItemRow]) async throws {
        try await client.from("items").upsert(rows, returning: .minimal).execute()
    }

    /// One row by primary key: never more than a page.
    func fetchList(listId: String, sinceIso: String?) async throws -> [ListRow] {
        var query = client.from("lists").select().eq("id", value: listId)
        if let sinceIso { query = query.gte("updated_at", value: sinceIso) }
        return try await query.execute().value
    }

    func fetchItems(listId: String, sinceIso: String?) async throws -> [ItemRow] {
        try await fetchAllPaged("items", cursorOf: Self.cursor) { query in
            let query = query.eq("list_id", value: listId)
            guard let sinceIso else { return query }
            return query.gte("updated_at", value: sinceIso)
        }
    }

    func fetchAccountItems(sinceIso: String?) async throws -> [ItemRow] {
        try await fetchAllPaged("items", cursorOf: Self.cursor) { query in
            guard let sinceIso else { return query }
            return query.gte("updated_at", value: sinceIso)
        }
    }

    func fetchAllLists() async throws -> [ListRow] {
        try await fetchAllPaged("lists", cursorOf: Self.cursor) { $0 }
    }

    func joinListByCode(_ code: String) async throws -> String? {
        do {
            let listId: String = try await client.rpc("join_list_by_code", params: ["p_code": code])
                .execute()
                .value
            return listId
        } catch let error as PostgrestError {
            // The RPC raises 'invalid_code' for a code that matches nothing — that's a user-facing outcome,
            // not an infrastructure failure.
            if error.message.contains("invalid_code") { return nil }
            throw error
        }
    }

    func changes(listId: String) -> AsyncThrowingStream<Void, any Error> {
        let client = self.client
        return AsyncThrowingStream { continuation in
            let task = Task {
                let channel = client.channel(Self.channelTopic(listId: listId))
                let lists = channel.postgresChange(
                    AnyAction.self, schema: "public", table: "lists", filter: .eq("id", value: listId)
                )
                let items = channel.postgresChange(
                    AnyAction.self, schema: "public", table: "items", filter: .eq("list_id", value: listId)
                )
                do {
                    try await Self.forwardSignals(
                        lists: lists, items: items,
                        statuses: channel.statusChange, currentStatus: { channel.status },
                        system: channel.system(),
                        subscribe: { try await channel.subscribeWithError() },
                        to: continuation
                    )
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
                await client.removeChannel(channel)
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// How long a joined channel may sit unsubscribed before `forwardSignals` treats it as closed.
    static let closeGrace: Duration = .seconds(1)

    /// Yields one element into `continuation` per "worth catching up" signal of one list channel, until the
    /// feeds end, `subscribe` throws, the channel closes (below), or the task is cancelled:
    /// - every Postgres change on the list row or its items;
    /// - every SUBSCRIBED status: joins (initial AND automatic re-joins after a socket drop) also yield, so a
    ///   consumer doing catch-up-per-element is complete without any special reconnect handling;
    /// - every `system` message with `status: ok`, which Realtime sends ("Subscribed to PostgreSQL") once it
    ///   delivers this channel's Postgres changes. supabase-swift (2.55.6) reports SUBSCRIBED on the join reply,
    ///   which can come seconds earlier on a cold server. A write in between raises no event, and the SUBSCRIBED
    ///   catch-up has already run, so the write would wait for some later event. supabase-kt sets SUBSCRIBED on
    ///   the join reply too, so Android has the same gap.
    ///
    /// A joined channel that is still unsubscribed `closeGrace` later throws `ChannelClosed`, so the lifecycle
    /// subscribes a fresh channel after its backoff. supabase-swift (2.55.6) leaves a channel unsubscribed for good
    /// when the server closes it (`phx_close`, e.g. after an expired token), on `phx_error` while the socket stays
    /// up, and when a rejoin gives up; none of these end the feeds. A socket reconnect also resets the channel to
    /// unsubscribed, but starts its rejoin in the same step, so its status has moved on by the time the grace ends.
    ///
    /// Split out of `changes(listId:)` so tests can feed it a fake channel: supabase-swift's socket can't be
    /// replaced from outside the package.
    static func forwardSignals<Change: Sendable>(
        lists: AsyncStream<Change>,
        items: AsyncStream<Change>,
        statuses: AsyncStream<RealtimeChannelStatus>,
        currentStatus: @escaping @Sendable () -> RealtimeChannelStatus,
        system: AsyncStream<RealtimeMessageV2>,
        subscribe: @escaping @Sendable () async throws -> Void,
        sleep: @escaping @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) },
        to continuation: AsyncThrowingStream<Void, any Error>.Continuation
    ) async throws {
        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask { for await _ in lists { continuation.yield(()) } }
            group.addTask { for await _ in items { continuation.yield(()) } }
            group.addTask {
                var joined = false
                for await status in statuses {
                    switch status {
                    case .subscribed:
                        joined = true
                        continuation.yield(())
                    case .unsubscribed where joined:
                        try await sleep(closeGrace)
                        if currentStatus() == .unsubscribed { throw ChannelClosed() }
                    default:
                        break
                    }
                }
            }
            group.addTask {
                // A failed Postgres subscribe says `status: error`; Realtime retries it and sends `ok` later.
                for await message in system where message.status == .ok { continuation.yield(()) }
            }
            group.addTask { try await subscribe() }
            try await group.waitForAll()
        }
    }

    // MARK: - Helpers

    /// A fresh topic per subscription: `list-<id>-<uuid>`. supabase-swift's `channel(_:)` returns
    /// the registered channel for a topic, and `removeChannel` unmaps the topic only after the
    /// leave round trip. With a fixed `list-<id>`, reopening a list inside that window got the
    /// channel being removed (no listeners registered, subscribe throws CancellationError), and the
    /// old removal could unmap the new one. Android's supabase-kt `channel("list-$id")` builds a
    /// new channel each time. The topic name doesn't affect `postgres_changes` filtering.
    static func channelTopic(listId: String) -> String {
        "list-\(listId)-\(UUID().uuidString.lowercased())"
    }

    static func isDuplicate(_ error: PostgrestError) -> Bool {
        error.code == "23505"
            || error.message.contains("23505")
            || error.message.contains("duplicate key")
    }

    private static func cursor(_ row: ListRow) -> SharedListPageCursor {
        SharedListPageCursor(updatedAt: row.updatedAt, id: row.id)
    }

    private static func cursor(_ row: ItemRow) -> SharedListPageCursor {
        SharedListPageCursor(updatedAt: row.updatedAt, id: row.id)
    }

    private func fetchAllPaged<Row: Decodable & Sendable>(
        _ table: String,
        cursorOf: (Row) -> SharedListPageCursor,
        where filter: (PostgrestFilterBuilder) -> PostgrestFilterBuilder
    ) async throws -> [Row] {
        try await SharedListPaging.fetchAll(cursorOf: cursorOf) { cursor in
            var query = filter(client.from(table).select())
            if let cursor { query = query.or(SharedListPaging.afterFilter(cursor)) }
            return try await query
                .order("updated_at", ascending: true)
                .order("id", ascending: true)
                .limit(SharedListPaging.pageSize)
                .execute()
                .value
        }
    }
}
