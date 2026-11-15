import Foundation

/// Lets an action run at most once per window (port of Android `Throttle`). The caller asks
/// before acting; this only answers whether enough time has passed since the last yes.
///
/// `now` is injected so tests can move time by hand; the app passes a monotonic clock, because
/// wall time can jump backwards. A refused attempt does not restart the window.
final class Throttle: @unchecked Sendable {
    private let windowMillis: Int64
    private let now: @Sendable () -> Int64
    private let lock = NSLock()
    private var lastAcquiredAt: Int64?

    init(windowMillis: Int64, now: @escaping @Sendable () -> Int64 = Throttle.monotonicMillis) {
        self.windowMillis = windowMillis
        self.now = now
    }

    func tryAcquire() -> Bool {
        lock.withLock {
            let at = now()
            if let last = lastAcquiredAt, at - last < windowMillis { return false }
            lastAcquiredAt = at
            return true
        }
    }

    /// Milliseconds on a clock that never goes backwards and keeps counting while asleep
    /// (Android's `elapsedRealtime`).
    static let monotonicMillis: @Sendable () -> Int64 = {
        Int64(clock_gettime_nsec_np(CLOCK_MONOTONIC) / 1_000_000)
    }
}
