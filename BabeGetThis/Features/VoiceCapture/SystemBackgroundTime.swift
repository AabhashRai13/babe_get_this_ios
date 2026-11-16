import UIKit

/// iOS background time for work that has to finish after the app leaves the foreground.
enum SystemBackgroundTime {
    /// Asks iOS to keep the app running while `name` finishes, and returns the call that gives the
    /// time back (the first call counts; later ones do nothing). If iOS runs out of time first
    /// (about 30 s), the time is given back then and the app can be suspended with the work
    /// unfinished.
    @MainActor
    static func begin(_ name: String) -> @MainActor () -> Void {
        let grant = Grant()
        grant.id = UIApplication.shared.beginBackgroundTask(withName: name) { grant.end() }
        return { grant.end() }
    }

    @MainActor
    private final class Grant {
        var id = UIBackgroundTaskIdentifier.invalid

        func end() {
            guard id != .invalid else { return }
            UIApplication.shared.endBackgroundTask(id)
            id = .invalid
        }
    }
}
