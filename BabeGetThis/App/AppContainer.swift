import Foundation
import Observation

/// Composition root. Builds every long-lived dependency once and hands it to
/// the views. No DI framework: add properties here as features land.
@Observable
@MainActor
final class AppContainer {
    let config: AppConfig
    let session: SessionStore
    let lists: ListsViewModel

    init(config: AppConfig, session: SessionStore = SessionStore(), lists: ListsViewModel = ListsViewModel()) {
        self.config = config
        self.session = session
        self.lists = lists
    }

    static func live(bundle: Bundle = .main, arguments: [String] = ProcessInfo.processInfo.arguments) -> AppContainer {
        let config: AppConfig
        do {
            config = try AppConfig(infoDictionary: bundle.infoDictionary ?? [:])
        } catch {
            fatalError("Invalid app configuration: \(error)")
        }
        // Launch argument for screenshots and UI tests: skip Welcome and show sample lists.
        if config.environment != .prod, arguments.contains("-sampleData") {
            return AppContainer(config: config, session: SessionStore(state: .guest),
                                lists: ListsViewModel(lists: ShoppingListSummary.samples))
        }
        return AppContainer(config: config)
    }

    static var preview: AppContainer {
        AppContainer(config: .preview, lists: ListsViewModel(lists: ShoppingListSummary.samples))
    }
}

extension AppConfig {
    static let preview = AppConfig(
        environment: .dev,
        supabaseURL: URL(string: "http://127.0.0.1:54321")!,
        supabaseAnonKey: "",
        apiBaseURL: URL(string: "http://127.0.0.1:8080/")!
    )
}
