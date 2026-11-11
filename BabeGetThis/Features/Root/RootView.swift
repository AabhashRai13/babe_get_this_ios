import SwiftUI

/// Placeholder entry screen. Replaced by Welcome / Lists once those land.
struct RootView: View {
    @Environment(AppContainer.self) private var container

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "cart")
                .font(.system(size: 56))
                .foregroundStyle(.tint)
            Text("Babe, Get This")
                .font(.largeTitle.bold())
            if container.config.environment != .prod {
                Text(container.config.environment.rawValue.uppercased())
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color("Background"))
    }
}

#Preview {
    RootView()
        .environment(AppContainer(config: AppConfig(
            environment: .dev,
            supabaseURL: URL(string: "http://127.0.0.1:54321")!,
            supabaseAnonKey: "",
            apiBaseURL: URL(string: "http://127.0.0.1:8080/")!
        )))
}
