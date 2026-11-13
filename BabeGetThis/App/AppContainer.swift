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
    let database: AppDatabase
    let listRepository: ShoppingListRepository
    let itemRepository: ShoppingItemRepository
    let lists: ListsViewModel
    /// Lists pushed on launch (from `-openList <id>`), for deterministic screenshots.
    let initialPath: [ShoppingListSummary]

    init(config: AppConfig, authState: AuthStateManager = AuthStateManager(tokenStore: KeychainTokenStore()),
         database: AppDatabase, welcome: WelcomeRepository = WelcomeRepository(), forcedScreen: StartScreen? = nil,
         initialPath: [ShoppingListSummary] = []) {
        self.config = config
        self.authState = authState
        self.welcome = welcome
        let session = StartSession(authState: authState, welcome: welcome, forcedScreen: forcedScreen)
        self.session = session
        self.welcomeViewModel = WelcomeViewModel(welcome: welcome, onGuestChosen: { session.refresh() })
        self.database = database
        let safeCall = SafeCall(reporter: SilentAppErrorReporter())
        let listRepository = ShoppingListRepository(
            listDao: database.lists, itemDao: database.items, categoryDao: database.categories,
            authStateManager: authState, syncKicker: NoOpSyncKicker(), safeCall: safeCall)
        self.listRepository = listRepository
        self.itemRepository = ShoppingItemRepository(
            itemDao: database.items, categoryDao: database.categories, listDao: database.lists,
            syncKicker: NoOpSyncKicker(), safeCall: safeCall)
        self.lists = ListsViewModel(repository: listRepository, authState: authState)
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
            return sampleContainer(config: config, forcedScreen: .lists,
                                   initialPath: LaunchRoute.initialPath(arguments: arguments))
        }
        let database: AppDatabase
        do {
            database = try AppDatabase.onDisk()
        } catch {
            fatalError("Could not open the local database: \(error)")
        }
        let container = AppContainer(config: config, database: database)
        container.authState.initialize()
        return container
    }

    static var preview: AppContainer {
        sampleContainer(config: .preview, forcedScreen: .welcome)
    }

    /// A signed-out guest on an in-memory database seeded with the sample lists.
    private static func sampleContainer(config: AppConfig, forcedScreen: StartScreen,
                                        initialPath: [ShoppingListSummary] = []) -> AppContainer {
        let database: AppDatabase
        do {
            database = try AppDatabase.inMemory()
            try SampleListSeeder.seed(database)
        } catch {
            fatalError("Could not seed the sample database: \(error)")
        }
        let authState = AuthStateManager(tokenStore: InMemoryTokenStore())
        authState.initialize()
        return AppContainer(config: config, authState: authState, database: database,
                            forcedScreen: forcedScreen, initialPath: initialPath)
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
