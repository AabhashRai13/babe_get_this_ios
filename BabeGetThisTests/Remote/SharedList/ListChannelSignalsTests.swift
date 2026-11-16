import Supabase
import XCTest
@testable import BabeGetThis

/// A fake `list-<id>` channel for `SupabaseSharedListRemote.forwardSignals`: the test pushes what the
/// server would send, then `signalCount()` closes every feed, runs the forwarding to the end and counts
/// the "catch up now" elements. Closing the feeds first makes the count exact, with no waiting.
private struct FakeListChannel {
    struct SubscribeFailed: Error {}

    let lists = AsyncStream<Void>.makeStream()
    let items = AsyncStream<Void>.makeStream()
    let statuses = AsyncStream<RealtimeChannelStatus>.makeStream()
    let system = AsyncStream<RealtimeMessageV2>.makeStream()

    func listRowChanged() { lists.continuation.yield(()) }
    func itemChanged() { items.continuation.yield(()) }
    func status(_ status: RealtimeChannelStatus) { statuses.continuation.yield(status) }

    /// A Realtime `system` message, shaped like the server's `push_system_message` for postgres_changes.
    func system(status: String, message: String) {
        system.continuation.yield(RealtimeMessageV2(
            joinRef: "1", ref: nil, topic: "realtime:list-L1-fake", event: "system",
            payload: [
                "extension": "postgres_changes",
                "status": .string(status),
                "message": .string(message),
                "channel": "list-L1-fake",
            ]
        ))
    }

    func signalCount(subscribeFails: Bool = false) async throws -> Int {
        lists.continuation.finish()
        items.continuation.finish()
        statuses.continuation.finish()
        system.continuation.finish()
        let output = AsyncThrowingStream<Void, any Error>.makeStream()
        try await SupabaseSharedListRemote.forwardSignals(
            lists: lists.stream, items: items.stream,
            statuses: statuses.stream, system: system.stream,
            subscribe: { if subscribeFails { throw SubscribeFailed() } },
            to: output.continuation
        )
        output.continuation.finish()
        var count = 0
        for try await _ in output.stream { count += 1 }
        return count
    }
}

/// RT-01: every element of `changes(listId:)` is one `catchUp(listId)` (RT-02).
final class ListChannelSignalsTests: XCTestCase {
    func testEachRowChangeSignals() async throws {
        let channel = FakeListChannel()
        channel.listRowChanged()
        channel.itemChanged()
        channel.itemChanged()

        let count = try await channel.signalCount()

        XCTAssertEqual(count, 3)
    }

    func testOnlyTheSubscribedStatusSignals() async throws {
        let channel = FakeListChannel()
        for status in [RealtimeChannelStatus.unsubscribed, .subscribing, .subscribed, .unsubscribing] {
            channel.status(status)
        }

        let count = try await channel.signalCount()

        XCTAssertEqual(count, 1)
    }

    /// supabase-swift 2.55.6 reports SUBSCRIBED on the join reply, but Realtime starts listening for Postgres
    /// changes only later and says so with a `system` "Subscribed to PostgreSQL" message (seconds later on a
    /// cold server). A write in between raises no event, and the SUBSCRIBED catch-up ran before it, so the
    /// "now live" message has to catch up again.
    func testPostgresChangesGoingLiveSignalsAgainAfterTheJoin() async throws {
        let channel = FakeListChannel()
        channel.status(.subscribing)
        channel.status(.subscribed)
        channel.system(status: "ok", message: "Subscribed to PostgreSQL")

        let count = try await channel.signalCount()

        XCTAssertEqual(count, 2, "one catch-up for the join reply, one once Postgres changes are live")
    }

    /// Realtime reports a failed Postgres subscribe as `status: error` and retries it; only the later `ok` means
    /// changes are being delivered.
    func testFailedPostgresSubscribeDoesNotSignal() async throws {
        let channel = FakeListChannel()
        channel.system(status: "error", message: "Subscribing to PostgreSQL failed: timeout")

        let count = try await channel.signalCount()

        XCTAssertEqual(count, 0)
    }

    func testSubscribeFailureEndsTheSignalsWithItsError() async throws {
        let channel = FakeListChannel()

        do {
            _ = try await channel.signalCount(subscribeFails: true)
            XCTFail("expected the subscribe error")
        } catch is FakeListChannel.SubscribeFailed {
            // The lifecycle subscribes again after its backoff.
        }
    }
}
