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

/// Where the monitor reads the current path from. `nil` means no path is known yet.
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

    init(source: any NetworkPathSource = SystemNetworkPathSource()) {
        self.source = source
    }

    /// Reads the current path every time; connectivity changes under the app.
    func isOnline() -> Bool {
        guard let path = source.currentPath else { return false }
        return path.status == .satisfied
    }
}

/// `NWPathMonitor` behind `NetworkPathSource`. Starts monitoring on creation and keeps the
/// latest path, so reads are a lock and a copy.
final class SystemNetworkPathSource: NetworkPathSource, @unchecked Sendable {
    private let monitor = NWPathMonitor()
    private let lock = NSLock()
    private var latest: NetworkPathSnapshot?

    init() {
        monitor.pathUpdateHandler = { [weak self] path in
            self?.store(Self.snapshot(of: path))
        }
        monitor.start(queue: DispatchQueue(label: "com.babegetthis.ios.network-monitor"))
        // Seed from the monitor unless the handler already delivered a newer path.
        let initial = Self.snapshot(of: monitor.currentPath)
        lock.lock()
        if latest == nil { latest = initial }
        lock.unlock()
    }

    deinit {
        monitor.cancel()
    }

    var currentPath: NetworkPathSnapshot? {
        lock.lock()
        defer { lock.unlock() }
        return latest
    }

    private func store(_ snapshot: NetworkPathSnapshot) {
        lock.lock()
        latest = snapshot
        lock.unlock()
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
