import SwiftUI

/// Switches between the signed-out flow and the app proper.
struct RootView: View {
    @Environment(AppContainer.self) private var container
    @State private var navigation = ListsNavigation()
    @State private var appliedInitialPath = false

    var body: some View {
        Group {
            switch container.session.screen {
            case .launch:
                AppColors.background.ignoresSafeArea()
            case .welcome:
                NavigationStack { WelcomeView() }
            case .lists:
                NavigationStack(path: $navigation.path) {
                    ListsView(viewModel: container.lists,
                              makeVoiceViewModel: { container.makeVoiceCaptureViewModel() },
                              onOpenList: { navigation.open($0) })
                }
                    .environment(\.leaveAuthFromList) { exit in navigation.leaveAuth(exit) }
                    .onAppear {
                        guard !appliedInitialPath else { return }
                        appliedInitialPath = true
                        navigation.path = container.initialPath
                    }
            }
        }
        .animation(.default, value: container.session.screen)
        // Signing out shows Welcome; the list screens it left behind must not come back.
        .onChange(of: container.session.screen) { _, screen in
            if screen == .welcome { navigation.signedOut() }
        }
    }
}

#Preview {
    RootView().environment(AppContainer.preview)
}
