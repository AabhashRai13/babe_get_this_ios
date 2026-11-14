import Foundation
import Observation
import Supabase

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
    /// Device-local ownership facts (adoption notice, locks, unverified claims).
    let ownership: any ListOwnershipStore
    let lists: ListsViewModel
    /// Lists pushed on launch (from `-openList <id>`), for deterministic screenshots.
    let initialPath: [ShoppingListSummary]

    init(config: AppConfig, authState: AuthStateManager = AuthStateManager(tokenStore: KeychainTokenStore()),
         database: AppDatabase, welcome: WelcomeRepository = WelcomeRepository(), forcedScreen: StartScreen? = nil,
         initialPath: [ShoppingListSummary] = [],
         ownership: any ListOwnershipStore = PrefsListOwnershipStore()) {
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
        self.ownership = ownership
        // No share joiner yet: ShareRepository needs the SyncEngine, which F30 wires (Join is F34).
        self.lists = ListsViewModel(repository: listRepository, authState: authState, ownership: ownership)
        self.initialPath = initialPath
    }

    /// A fresh voice capture view model per sheet: real microphone, real transcribe API.
    func makeVoiceCaptureViewModel() -> VoiceCaptureViewModel {
        let auth = TranscribeBearerAuth(tokenStore: KeychainTokenStore(), authStateManager: authState)
        return VoiceCaptureViewModel(
            recorder: AVVoiceRecorder(),
            transcriber: TranscribeClient(baseURL: config.apiBaseURL, auth: auth))
    }

    // MARK: - Auth screens

    /// Built on first use, so launching the app (and every test container) opens no Supabase
    /// client until someone actually reaches a sign-in screen.
    @ObservationIgnored private var cachedAuthRepository: (any AuthRepository)?

    private var authRepository: any AuthRepository {
        if let cachedAuthRepository { return cachedAuthRepository }
        let client = SupabaseClient(supabaseURL: config.supabaseURL, supabaseKey: config.supabaseAnonKey)
        let repository = SupabaseAuthRepository(
            remote: SupabaseAuthRemote(client: client), authStateManager: authState, networkMonitor: NetworkMonitor())
        cachedAuthRepository = repository
        return repository
    }

    func makeLoginViewModel() -> LoginViewModel {
        // Google sign-in is F23; until then its button reports that it failed.
        LoginViewModel(authRepository: authRepository,
                       googleAuth: GoogleSignInNotWired(), googleTokens: GoogleSignInNotWired())
    }

    func makeRegisterViewModel() -> RegisterViewModel {
        RegisterViewModel(authRepository: authRepository)
    }

    func makeForgotPasswordViewModel() -> ForgotPasswordViewModel {
        ForgotPasswordViewModel(authRepository: authRepository)
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
