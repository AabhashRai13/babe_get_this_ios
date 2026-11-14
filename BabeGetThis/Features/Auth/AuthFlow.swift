import Foundation

/// The auth back stack (NAV-03, Android `BgtNavGraph` login / register / forgot-password routes):
/// - Login and Register replace each other; Forgot stacks on Login.
/// - Close pops to the lists (or to Welcome if the lists aren't below).
/// - Success lands on the lists and drops Welcome.
/// - Opened from a list's screen, both pop that screen too (Android `closeAuth` / `leaveAuth`
///   run `popBackStack(SHOPPING_LIST, inclusive = false)`).
///
/// Pure value, so the rules are unit tested; `AuthSheet` renders it and reports the `Exit`.
struct AuthFlow: Equatable, Sendable {
    enum Screen: Equatable, Sendable {
        case login, register, forgotPassword
    }

    /// What auth was opened over: the lists, a list's screen (pushed on the lists), or Welcome
    /// (where the lists aren't on the stack).
    enum Below: Equatable, Sendable {
        case lists, list, welcome
    }

    /// Where leaving auth lands. `.lists` from a list's screen means that screen is popped too.
    enum Exit: Equatable, Sendable {
        case lists, welcome
    }

    let below: Below
    /// Bottom first. The root is Login or Register; Forgot password can only sit on Login.
    private(set) var stack: [Screen]

    init(start: Screen = .login, below: Below) {
        self.below = below
        // Forgot password is reached from Login only, so a flow never starts on it alone.
        stack = start == .forgotPassword ? [.login, .forgotPassword] : [start]
    }

    var root: Screen { stack[0] }
    var current: Screen { stack[stack.count - 1] }
    var isShowingForgotPassword: Bool { current == .forgotPassword }

    /// "Sign up" on Login: Register replaces Login, so the two never stack up.
    mutating func showRegister() {
        stack = [.register]
    }

    /// "Sign in" on Register: Login replaces Register.
    mutating func showLogin() {
        stack = [.login]
    }

    /// "Forgot password?" on Login: stacked on top of it, so back returns there.
    mutating func showForgotPassword() {
        guard current == .login else { return }
        stack.append(.forgotPassword)
    }

    /// Back: Forgot password pops to Login; on the root screen back closes auth.
    mutating func back() -> Exit? {
        guard stack.count > 1 else { return close() }
        stack.removeLast()
        return nil
    }

    /// Close: back to the lists if they're on the stack (popping a list's screen on the way),
    /// else to Welcome.
    func close() -> Exit {
        below == .welcome ? .welcome : .lists
    }

    /// Signed in (login, register or a password reset): always the lists. Started from Welcome,
    /// the caller drops Welcome (`StartSession.leaveAuth(_:)`); from a list's screen, it pops
    /// that screen (`ListsNavigation.leaveAuth(_:)`).
    func succeed() -> Exit {
        .lists
    }
}
