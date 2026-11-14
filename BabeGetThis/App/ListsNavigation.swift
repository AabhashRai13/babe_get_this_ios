import Foundation

/// The lists' navigation stack (`RootView`): the list screens pushed over the lists (NAV-01).
/// A value type, so the routing rules are unit tested without a view.
struct ListsNavigation: Equatable {
    /// List screens over the lists, bottom first. Each carries the id and the name; the detail
    /// screen's title is that name.
    var path: [ShoppingListSummary] = []

    /// A tapped card, or a list just created from the name dialog.
    mutating func open(_ list: ShoppingListSummary) {
        path.append(list)
    }

    /// Leaving auth opened from a list's screen (NAV-03). Android `closeAuth` and `leaveAuth` both
    /// run `popBackStack(Routes.SHOPPING_LIST, inclusive = false)`, so Close and a successful
    /// sign-in land on the lists, not back on the list.
    mutating func leaveAuth(_ exit: AuthFlow.Exit) {
        if exit == .lists { path.removeAll() }
    }

    /// Signing out clears the stack to Welcome (NAV-04), so the next sign-in starts on the lists.
    mutating func signedOut() {
        path.removeAll()
    }
}
