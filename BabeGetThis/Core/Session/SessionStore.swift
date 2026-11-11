import Observation

/// Who is using the app. In-memory for now; the auth milestone backs this with
/// Supabase Auth and persists the guest choice (Android decision 008).
@Observable
@MainActor
final class SessionStore {
    enum State: Equatable {
        case signedOut
        case guest
    }

    private(set) var state: State

    init(state: State = .signedOut) {
        self.state = state
    }

    func continueAsGuest() { state = .guest }
    func signOut() { state = .signedOut }
}
