import SwiftUI

/// Switches between the signed-out flow and the app proper.
struct RootView: View {
    @Environment(AppContainer.self) private var container

    var body: some View {
        Group {
            switch container.session.state {
            case .signedOut:
                NavigationStack { WelcomeView() }
            case .guest:
                NavigationStack { ListsView(viewModel: container.lists) }
            }
        }
        .animation(.default, value: container.session.state)
    }
}

#Preview {
    RootView().environment(AppContainer.preview)
}
