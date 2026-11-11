import SwiftUI

/// Switches between the signed-out flow and the app proper.
struct RootView: View {
    @Environment(AppContainer.self) private var container
    @State private var listsPath: [ShoppingListSummary] = []
    @State private var appliedInitialPath = false

    var body: some View {
        Group {
            switch container.session.state {
            case .signedOut:
                NavigationStack { WelcomeView() }
            case .guest:
                NavigationStack(path: $listsPath) { ListsView(viewModel: container.lists) }
                    .onAppear {
                        guard !appliedInitialPath else { return }
                        appliedInitialPath = true
                        listsPath = container.initialPath
                    }
            }
        }
        .animation(.default, value: container.session.state)
    }
}

#Preview {
    RootView().environment(AppContainer.preview)
}
