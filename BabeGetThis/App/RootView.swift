import SwiftUI

/// Switches between the signed-out flow and the app proper.
struct RootView: View {
    @Environment(AppContainer.self) private var container
    @State private var listsPath: [ShoppingListSummary] = []
    @State private var appliedInitialPath = false

    var body: some View {
        Group {
            switch container.session.screen {
            case .launch:
                AppColors.background.ignoresSafeArea()
            case .welcome:
                NavigationStack { WelcomeView() }
            case .lists:
                NavigationStack(path: $listsPath) {
                    ListsView(viewModel: container.lists,
                              makeVoiceViewModel: { container.makeVoiceCaptureViewModel() },
                              onOpenList: { listsPath.append($0) })
                }
                    .onAppear {
                        guard !appliedInitialPath else { return }
                        appliedInitialPath = true
                        listsPath = container.initialPath
                    }
            }
        }
        .animation(.default, value: container.session.screen)
    }
}

#Preview {
    RootView().environment(AppContainer.preview)
}
