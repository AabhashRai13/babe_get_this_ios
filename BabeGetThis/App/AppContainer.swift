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
        self.safeCall = safeCall
        // No catchUp yet: `syncEngine` exists (built lazily below) but nothing triggers it. F30
        // passes `catchUp: { try await engine.catchUp(listId: $0) }` here, or leaving an empty
        // list that is on the server never deletes it (DATA-06), and replaces NoOpSyncKicker.
        let listRepository = ShoppingListRepository(
            listDao: database.lists, itemDao: database.items, categoryDao: database.categories,
            authStateManager: authState, syncKicker: NoOpSyncKicker(), safeCall: safeCall)
        self.listRepository = listRepository
        self.itemRepository = ShoppingItemRepository(
            itemDao: database.items, categoryDao: database.categories, listDao: database.lists,
            syncKicker: NoOpSyncKicker(), safeCall: safeCall)
        self.ownership = ownership
        // Join goes through `shareRepository`, resolved on the first join so building the lists
        // opens no Supabase client. Sync triggers and realtime are still F30's.
        let containerRef = WeakContainerRef()
        let joiner = DeferredListJoiner { [containerRef] in containerRef.container?.shareRepository }
        self.lists = ListsViewModel(repository: listRepository, authState: authState,
                                    shareJoiner: joiner, ownership: ownership)
        self.initialPath = initialPath
        containerRef.container = self
    }

    @ObservationIgnored private let safeCall: SafeCall

    /// A fresh voice capture view model per sheet: real microphone, real transcribe API.
    func makeVoiceCaptureViewModel() -> VoiceCaptureViewModel {
        let auth = TranscribeBearerAuth(tokenStore: KeychainTokenStore(), authStateManager: authState)
        return VoiceCaptureViewModel(
            recorder: AVVoiceRecorder(),
            transcriber: TranscribeClient(baseURL: config.apiBaseURL, auth: auth))
    }

    // MARK: - Supabase and sync

    /// One client for auth and PostgREST, so server calls carry the signed-in session. Built on
    /// first use, so launching the app (and every test container) opens no Supabase client until
    /// someone reaches a sign-in screen, a join or a share.
    @ObservationIgnored private var cachedSupabaseClient: SupabaseClient?

    private var supabaseClient: SupabaseClient {
        if let cachedSupabaseClient { return cachedSupabaseClient }
        let client = SupabaseClient(supabaseURL: config.supabaseURL, supabaseKey: config.supabaseAnonKey)
        cachedSupabaseClient = client
        return client
    }

    @ObservationIgnored private var cachedSharedListRemote: (any SharedListRemote)?
    @ObservationIgnored private var cachedSyncEngine: SyncEngine?
    @ObservationIgnored private var cachedShareRepository: ShareRepository?

    var sharedListRemote: any SharedListRemote {
        if let cachedSharedListRemote { return cachedSharedListRemote }
        let remote = SupabaseSharedListRemote(client: supabaseClient)
        cachedSharedListRemote = remote
        return remote
    }

    /// Built once. Only share and join call it so far; F30 adds the sync triggers, the list
    /// repository's catchUp and a real SyncKicking.
    var syncEngine: SyncEngine {
        if let cachedSyncEngine { return cachedSyncEngine }
        let engine = SyncEngine(
            listDao: database.lists, itemDao: database.items, remote: sharedListRemote,
            syncPoints: PrefsSyncPointStore(), ownership: ownership,
            currentUserId: { [authState] in authState.liveSessionUserId }, safeCall: safeCall)
        cachedSyncEngine = engine
        return engine
    }

    var shareRepository: ShareRepository {
        if let cachedShareRepository { return cachedShareRepository }
        let repository = ShareRepository(
            lists: database.lists, remote: sharedListRemote, syncEngine: syncEngine,
            currentUserId: { [authState] in authState.liveSessionUserId }, safeCall: safeCall)
        cachedShareRepository = repository
        return repository
    }

    // MARK: - Auth screens

    @ObservationIgnored private var cachedAuthRepository: (any AuthRepository)?

    private var authRepository: any AuthRepository {
        if let cachedAuthRepository { return cachedAuthRepository }
        let repository = SupabaseAuthRepository(
            remote: SupabaseAuthRemote(client: supabaseClient), authStateManager: authState,
            networkMonitor: NetworkMonitor())
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

/// A `ListJoining` that finds the real joiner on the main actor at join time, so the container
/// can hand the lists a joiner without building the sync stack up front.
private struct DeferredListJoiner: ListJoining {
    let resolve: @MainActor @Sendable () -> (any ListJoining)?

    func join(code: String) async throws -> Result<String, AppError> {
        guard let joiner = await resolve() else { return .failure(.unknown()) }
        return try await joiner.join(code: code)
    }
}

/// Lets the container's init hand out a closure that reaches the container once it exists,
/// without keeping it alive.
@MainActor
private final class WeakContainerRef {
    weak var container: AppContainer?
}

/// Parses launch-argument routes. Pure, so it is unit tested.
enum LaunchRoute {
    static func initialPath(arguments: [String], lists: [ShoppingListSummary] = ShoppingListSummary.samples) -> [ShoppingListSummary] {
        guard let flag = arguments.firstIndex(of: "-openList"), arguments.indices.contains(flag + 1) else { return [] }
        let id = arguments[flag + 1]
        return lists.first { $0.id == id }.map { [$0] } ?? []
    }
}
