import SwiftUI

@main
struct BabeGetThisApp: App {
    @State private var container = AppContainer.live()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(container)
        }
        // Coming back to the foreground kicks a push + catch-up (TRIG-02).
        .onChange(of: scenePhase, initial: true) { _, phase in
            container.syncTrigger.scenePhaseChanged(phase)
        }
    }
}
