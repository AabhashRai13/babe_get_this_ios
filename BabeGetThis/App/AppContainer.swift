import Foundation
import Observation

/// Composition root. Builds every long-lived dependency once and hands it to
/// the views. No DI framework: add properties here as features land.
@Observable
@MainActor
final class AppContainer {
    let config: AppConfig
    let authState: AuthStateManager
    let welcome: WelcomeRepository
    let session: StartSession
    let welcomeViewModel: WelcomeViewModel
    let lists: ListsViewModel
    /// Lists pushed on launch (from `-openList <id>`), for deterministic screenshots.
    let initialPath: [ShoppingListSummary]

    init(config: AppConfig, authState: AuthStateManager = AuthStateManager(tokenStore: KeychainTokenStore()),
         welcome: WelcomeRepository = WelcomeRepository(), forcedScreen: StartScreen? = nil,
         lists: ListsViewModel = ListsViewModel(), initialPath: [ShoppingListSummary] = []) {
        self.config = config
        self.authState = authState
        self.welcome = welcome
        let session = StartSession(authState: authState, welcome: welcome, forcedScreen: forcedScreen)
        self.session = session
        self.welcomeViewModel = WelcomeViewModel(welcome: welcome, onGuestChosen: { session.refresh() })
        self.lists = lists
        self.initialPath = initialPath
    }

    static func live(bundle: Bundle = .main, arguments: [String] = ProcessInfo.processInfo.arguments) -> AppContainer {
        let config: AppConfig
        do {
            config = try AppConfig(infoDictionary: bundle.infoDictionary ?? [:])
        } catch {
            fatalError("Invalid app configuration: \(error)")
        }
        // Launch arguments for screenshots and UI tests (non-prod only):
        //   -sampleData            skip Welcome and show the fixed sample lists
        //   -openList <listId>     also open that sample list's detail screen
        if config.environment != .prod, arguments.contains("-sampleData") {
            return AppContainer(config: config, forcedScreen: .lists,
                                lists: ListsViewModel(lists: ShoppingListSummary.samples),
                                initialPath: LaunchRoute.initialPath(arguments: arguments))
        }
        let container = AppContainer(config: config)
        container.authState.initialize()
        return container
    }

    static var preview: AppContainer {
        AppContainer(config: .preview, forcedScreen: .welcome, lists: ListsViewModel(lists: ShoppingListSummary.samples))
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

/// Parses launch-argument routes. Pure, so it is unit tested.
enum LaunchRoute {
    static func initialPath(arguments: [String], lists: [ShoppingListSummary] = ShoppingListSummary.samples) -> [ShoppingListSummary] {
        guard let flag = arguments.firstIndex(of: "-openList"), arguments.indices.contains(flag + 1) else { return [] }
        let id = arguments[flag + 1]
        return lists.first { $0.id == id }.map { [$0] } ?? []
    }
}
