import GoogleSignIn
import SwiftUI

@main
struct BabeGetThisApp: App {
    @State private var container = AppContainer.live()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(container)
                // The Google sheet returns through the app's reversed-client-id URL (AUTH-05).
                .onOpenURL { _ = GIDSignIn.sharedInstance.handle($0) }
        }
        // Coming back to the foreground kicks a push + catch-up (TRIG-02).
        .onChange(of: scenePhase, initial: true) { _, phase in
            container.syncTrigger.scenePhaseChanged(phase)
        }
    }
}
