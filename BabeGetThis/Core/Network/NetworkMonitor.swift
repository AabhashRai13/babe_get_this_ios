import Foundation
import Network

/// The parts of an `NWPath` the monitor looks at, so tests can drive it without the system.
struct NetworkPathSnapshot: Equatable, Sendable {
    enum Status: Equatable, Sendable {
        /// The path is usable. iOS only reports this once it can actually route traffic,
        /// the equivalent of Android's INTERNET + VALIDATED.
        case satisfied
        case unsatisfied
        /// Usable only after a connection is established first (VPN on demand, a captive portal).
        case requiresConnection
    }

    var status: Status
    var isExpensive: Bool = false
    var isConstrained: Bool = false
}

/// Where the monitor reads the current path from. `nil` means the system has not reported a
/// path yet (unknown), not "no network": an evaluated offline path is `.unsatisfied`.
protocol NetworkPathSource: AnyObject, Sendable {
    var currentPath: NetworkPathSnapshot? { get }
}

/// Cheap, synchronous "is there usable internet right now?" check. Port of Android's NetworkMonitor.
///
/// Genuinely-network calls (auth, voice) are gated on this so an offline user gets a clean
/// "No internet connection." at once instead of a long timeout. Local database calls and sync
/// are NOT gated: the app is offline-first and must keep working with no internet.
final class NetworkMonitor: Sendable {
    private let source: any NetworkPathSource

    init(source: any NetworkPathSource = SystemNetworkPathSource.shared) {
        self.source = source
    }

    /// Reads the current path every time; connectivity changes under the app.
    /// An unknown path counts as online: the request then fails on its own if it must, instead
    /// of a false "No internet connection." before the system has reported (Android's
    /// ConnectivityManager answers synchronously, so it never has this state).
    func isOnline() -> Bool {
        guard let path = source.currentPath else { return true }
        return path.status == .satisfied
    }
}

/// `NWPathMonitor` behind `NetworkPathSource`. Starts monitoring on creation and keeps the
/// latest path, so reads are a lock and a copy. One instance for the app (`shared`).
final class SystemNetworkPathSource: NetworkPathSource, @unchecked Sendable {
    /// Created once, at first use, and kept for the app's lifetime.
    static let shared = SystemNetworkPathSource()

    private let monitor = NWPathMonitor()
    private let lock = NSLock()
    private var latest: NetworkPathSnapshot?

    /// Waits up to `firstPathTimeout` for the first real path. `monitor.currentPath` read right
    /// after `start` is an unevaluated `.unsatisfied` placeholder, so it is never used as a seed.
    init(firstPathTimeout: DispatchTimeInterval = .milliseconds(100)) {
        let firstPath = DispatchSemaphore(value: 0)
        monitor.pathUpdateHandler = { [weak self] path in
            guard let self else { return }
            if self.store(Self.snapshot(of: path)) { firstPath.signal() }
        }
        monitor.start(queue: DispatchQueue(label: "com.babegetthis.ios.network-monitor"))
        _ = firstPath.wait(timeout: .now() + firstPathTimeout)
    }

    deinit {
        monitor.cancel()
    }

    var currentPath: NetworkPathSnapshot? {
        lock.lock()
        defer { lock.unlock() }
        return latest
    }

    /// Returns whether this was the first path.
    private func store(_ snapshot: NetworkPathSnapshot) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        let isFirst = latest == nil
        latest = snapshot
        return isFirst
    }

    private static func snapshot(of path: NWPath) -> NetworkPathSnapshot {
        let status: NetworkPathSnapshot.Status = switch path.status {
        case .satisfied: .satisfied
        case .requiresConnection: .requiresConnection
        default: .unsatisfied
        }
        return NetworkPathSnapshot(status: status, isExpensive: path.isExpensive, isConstrained: path.isConstrained)
    }
}
