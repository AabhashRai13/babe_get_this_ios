import Foundation
import Supabase

/// What Supabase says about the session (supabase-kt `SessionStatus`).
enum SupabaseSessionStatus: Equatable, Sendable {
    /// Nothing is known yet.
    case initializing
    /// A live session; `userId` is the Supabase UUID, never the email.
    case authenticated(accessToken: String, userId: String?)
    /// Supabase has definitively lost the session (refresh token expired or revoked, or a sign-out).
    case notAuthenticated
    /// A refresh failed (offline, flaky network); Supabase keeps retrying.
    case refreshFailure

    /// Maps a supabase-swift auth event. A failed background refresh emits no event, so
    /// `.refreshFailure` never comes from here.
    ///
    /// Only `.signedOut` means the session is gone. An `.initialSession` without a session is
    /// not proof of that: supabase-swift refreshes an expired stored session before emitting
    /// it and sends nil when that refresh fails, which offline it does even though the refresh
    /// token is still valid (supabase-kt reports `RefreshFailure` there). A session that is
    /// really dead (refresh token revoked or expired) is cleared by supabase-swift, which then
    /// emits `.signedOut`.
    static func from(event: AuthChangeEvent, session: Session?) -> SupabaseSessionStatus {
        if event == .signedOut { return .notAuthenticated }
        if let session {
            return .authenticated(accessToken: session.accessToken, userId: session.user.id.uuidString.lowercased())
        }
        return .initializing
    }
}

/// The two `AuthStateManager` transitions the observer drives.
protocol SessionAuthStateSink: AnyObject, Sendable {
    func refreshToken(_ token: String)
    func expireSession()
}

extension AuthStateManager: SessionAuthStateSink {}

/// Telemetry identity: the Supabase user UUID, or nil when nobody is signed in.
protocol SessionTelemetryIdentity: Sendable {
    func onUserChanged(_ userId: String?)
}

/// Until telemetry is wired, identity changes go nowhere.
struct NoopSessionTelemetryIdentity: SessionTelemetryIdentity {
    func onUserChanged(_ userId: String?) {}
}

/// Where the observer does its work (Android's IO dispatcher).
protocol SessionObserverScheduler: Sendable {
    func schedule(_ work: @escaping @Sendable () -> Void)
}

/// A serial background queue: off the caller's thread, and changes apply in order.
struct SerialQueueSessionObserverScheduler: SessionObserverScheduler {
    private let queue: DispatchQueue

    init(queue: DispatchQueue = DispatchQueue(label: "com.babegetthis.ios.session-observer", qos: .utility)) {
        self.queue = queue
    }

    func schedule(_ work: @escaping @Sendable () -> Void) {
        queue.async(execute: work)
    }
}

/// Mirrors the Supabase session into the app's own state (Android `SessionObserver`).
///
/// Supabase auto-refreshes the session in the background and rotates the access token.
/// Each rotated token is persisted so the transcribe API stops sending the stale one cached
/// at login, and telemetry identity rides the same signal as auth identity so the two
/// cannot drift apart. The token store writes the Keychain, so the work runs on the
/// scheduler, not on whatever thread delivered the event.
final class SessionObserver: Sendable {
    private let authState: any SessionAuthStateSink
    private let telemetry: any SessionTelemetryIdentity
    private let scheduler: any SessionObserverScheduler

    init(
        authState: any SessionAuthStateSink,
        telemetry: any SessionTelemetryIdentity = NoopSessionTelemetryIdentity(),
        scheduler: any SessionObserverScheduler = SerialQueueSessionObserverScheduler()
    ) {
        self.authState = authState
        self.telemetry = telemetry
        self.scheduler = scheduler
    }

    /// Call once at launch. The observation lives until the stream ends or the task is cancelled.
    @discardableResult
    func observe(_ statuses: AsyncStream<SupabaseSessionStatus>) -> Task<Void, Never> {
        Task { [self] in
            for await status in statuses {
                scheduler.schedule { [self] in onStatus(status) }
            }
        }
    }

    /// Observes supabase-swift's auth events.
    @discardableResult
    func observe(auth: AuthClient) -> Task<Void, Never> {
        let events = auth.authStateChanges
        let statuses = AsyncStream<SupabaseSessionStatus> { continuation in
            let task = Task {
                for await change in events {
                    continuation.yield(.from(event: change.event, session: change.session))
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
        return observe(statuses)
    }

    private func onStatus(_ status: SupabaseSessionStatus) {
        switch status {
        case .authenticated(let accessToken, let userId):
            authState.refreshToken(accessToken)
            telemetry.onUserChanged(userId)
        // Mirror a lost session locally, otherwise the token store keeps serving a dead
        // token and the user finds out mid-action via a 401. expireSession, not logout:
        // the account's lists stay on screen and editable until the user signs in again
        // (Android decision 008). A no-op for signed-out users and for the explicit
        // sign-out that also lands here, which clears our own state first.
        case .notAuthenticated:
            authState.expireSession()
            telemetry.onUserChanged(nil)
        // A refresh failure is deliberately not a lost session: we're offline-first and
        // Supabase keeps retrying.
        case .refreshFailure, .initializing:
            break
        }
    }
}
