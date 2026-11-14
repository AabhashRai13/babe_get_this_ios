import Foundation

/// Remembers which once-only events have fired (port of Android `TelemetryMarkers`). "First item
/// added" sent on every item would corrupt the funnel it exists to measure. Plain UserDefaults,
/// like the sync point store: these are booleans, not secrets.
final class TelemetryMarkers: @unchecked Sendable {
    static let suiteName = "telemetry_markers"

    /// Signed-out users still add items; their activation just can't be tied to an account.
    private static let anonymous = "anon"

    private let defaults: UserDefaults
    private let lock = NSLock()

    init(defaults: UserDefaults = UserDefaults(suiteName: TelemetryMarkers.suiteName) ?? .standard) {
        self.defaults = defaults
    }

    /// True the first time for a marker and scope, false forever after. Write-then-report, so a
    /// crash between the two loses one event instead of repeating it every launch.
    ///
    /// `scope` is what "once" counts against: the user id for activation markers, the list id
    /// for sharing markers.
    func firstTime(_ marker: Marker, scope: String?) -> Bool {
        let key = Self.key(marker, scope)
        return lock.withLock {
            if defaults.bool(forKey: key) { return false }
            defaults.set(true, forKey: key)
            return true
        }
    }

    /// Reads without claiming (JoinedList is read on every later edit to that list).
    func has(_ marker: Marker, scope: String?) -> Bool {
        defaults.bool(forKey: Self.key(marker, scope))
    }

    /// Records without reporting (JoinedList marks a fact, not an event).
    func mark(_ marker: Marker, scope: String?) {
        defaults.set(true, forKey: Self.key(marker, scope))
    }

    private static func key(_ marker: Marker, _ scope: String?) -> String {
        "\(marker.rawValue):\(scope ?? anonymous)"
    }
}

/// Android's marker names, so the keys match.
enum Marker: String, CaseIterable, Sendable {
    // Activation, scoped to the user id.
    case firstItemAdded = "FirstItemAdded"
    case firstListCompleted = "FirstListCompleted"

    // Sharing, scoped to the list id. Which side of an invite this device was on is only
    // knowable when it happens, so it is written down then.
    case shareCodeCreated = "ShareCodeCreated"
    case joinedList = "JoinedList"
    case sharedListFirstEdit = "SharedListFirstEdit"
}
