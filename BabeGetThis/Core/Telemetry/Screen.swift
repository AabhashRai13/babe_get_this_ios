import Foundation

/// The screens we report, as a closed set (port of Android `Screen`). A list screen's title is
/// user-authored, so nothing route- or title-shaped is ever sent; only these names are.
enum Screen: String, CaseIterable, Sendable {
    case shoppingList = "shopping_list"
    case shoppingItems = "shopping_items"
    case login
    case register
    case forgotPassword = "forgot_password"
    case settings
    case welcome
    /// A route this enum does not know. Reported rather than dropped, so a forgotten screen shows up.
    case unknown

    var screenName: String { rawValue }

    /// Matches on the route PATTERN's prefix, so "shopping_items/{listId}/{listName}" resolves
    /// without reading its arguments. Anything unrecognised is `unknown`, never itself.
    static func fromRoute(_ route: String?) -> Screen {
        guard let route else { return .unknown }
        if route.hasPrefix("shopping_items") { return .shoppingItems }
        if route.hasPrefix("shopping_list") { return .shoppingList }
        if route.hasPrefix("forgot_password") { return .forgotPassword }
        if route.hasPrefix("register") { return .register }
        if route.hasPrefix("login") { return .login }
        if route.hasPrefix("settings") { return .settings }
        if route.hasPrefix("welcome") { return .welcome }
        return .unknown
    }
}
