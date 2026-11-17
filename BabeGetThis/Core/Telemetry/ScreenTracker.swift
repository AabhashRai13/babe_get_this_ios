import SwiftUI

/// Works out which screen is on top from the screens' own appear and disappear calls, and
/// reports it each time a different one comes on top (TEL-03).
///
/// Android has one hook for this: an `OnDestinationChangedListener` that fires whenever the
/// current destination changes, so a screen is reported on the way in and again on the way back.
/// SwiftUI has no such listener over a `NavigationStack` plus sheets, so each screen calls
/// `.reportsScreen(_:)` instead, and the one that appeared most recently and is still showing is
/// on top. A sheet leaves the screen below it showing, so when the sheet goes that screen is on
/// top again and is reported again, as Android reports the lists again when auth closes.
///
/// One SwiftUI update can remove a screen and insert another (Login and Register swap). The
/// report waits for the main actor's next turn, so the screen below never shows up in between.
@MainActor
final class ScreenTracker {
    private struct Showing {
        let id: UUID
        let screen: Screen
    }

    private let report: @MainActor (Screen) -> Void
    private let schedule: @MainActor (@escaping @MainActor () -> Void) -> Void
    /// The screens on display, oldest first: the last one is on top.
    private var showing: [Showing] = []
    /// The visit last reported, so each time a screen comes on top it is reported once.
    private var reportedId: UUID?
    private var isSettlePending = false

    /// `schedule` runs the report after the current update; tests run it by hand.
    init(report: @escaping @MainActor (Screen) -> Void,
         schedule: @escaping @MainActor (@escaping @MainActor () -> Void) -> Void = { work in
             Task { @MainActor in work() }
         }) {
        self.report = report
        self.schedule = schedule
    }

    /// `id` is the visit: one per screen view, kept for as long as that view lives.
    func appeared(_ screen: Screen, id: UUID) {
        showing.removeAll { $0.id == id }
        showing.append(Showing(id: id, screen: screen))
        settleLater()
    }

    func disappeared(id: UUID) {
        showing.removeAll { $0.id == id }
        settleLater()
    }

    private func settleLater() {
        guard !isSettlePending else { return }
        isSettlePending = true
        schedule { [weak self] in self?.settle() }
    }

    private func settle() {
        isSettlePending = false
        guard let top = showing.last, top.id != reportedId else { return }
        reportedId = top.id
        report(top.screen)
    }
}

private struct ScreenTrackerKey: EnvironmentKey {
    static let defaultValue: ScreenTracker? = nil
}

extension EnvironmentValues {
    /// The app's `ScreenTracker`, set by `RootView`. Nil in previews, where nothing is reported.
    var screenTracker: ScreenTracker? {
        get { self[ScreenTrackerKey.self] }
        set { self[ScreenTrackerKey.self] = newValue }
    }
}

extension View {
    /// Reports this screen to telemetry each time it comes on top (TEL-03): `screen_view` and
    /// the per-screen crash keys, through `TelemetryContext.onScreen(_:)`.
    func reportsScreen(_ screen: Screen) -> some View {
        modifier(ReportsScreen(screen: screen))
    }
}

private struct ReportsScreen: ViewModifier {
    let screen: Screen
    @Environment(\.screenTracker) private var tracker
    @State private var id = UUID()

    func body(content: Content) -> some View {
        content
            .onAppear { tracker?.appeared(screen, id: id) }
            .onDisappear { tracker?.disappeared(id: id) }
    }
}
