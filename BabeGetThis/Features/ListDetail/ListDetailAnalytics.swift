import Foundation

/// What the list detail screen reports (TEL-04), in its own terms; the app's adapter
/// (`TrackingListAnalytics`) turns it into analytics events. Ids only: a list's or an item's
/// name and a share code never cross this line.
@MainActor
protocol ListDetailAnalytics {
    /// An item was added from the add sheet, with the category the user picked (nil: none).
    func itemAdded(toList listId: String, categoryId: String?)
    /// Spoken items were added to the list: one category id per item, assigned automatically
    /// (nil where none was).
    func voiceItemsAdded(toList listId: String, categoryIds: [String?])
    /// An item was ticked (`isPickedUp`) or unticked.
    func itemToggled(inList listId: String, isPickedUp: Bool)
    /// An item was edited; its category before and after.
    func itemEdited(inList listId: String, fromCategoryId: String?, toCategoryId: String?)
    /// The list went from not finished to finished.
    func listCompleted(itemCount: Int)
    /// The share dialog is showing the list's code, new or re-shown.
    func shareCodeShown(forList listId: String)
    /// The code was copied: the sharing act (there is no share sheet in this flow).
    func shareCodeCopied()
}

struct NoopListDetailAnalytics: ListDetailAnalytics {
    func itemAdded(toList listId: String, categoryId: String?) {}
    func voiceItemsAdded(toList listId: String, categoryIds: [String?]) {}
    func itemToggled(inList listId: String, isPickedUp: Bool) {}
    func itemEdited(inList listId: String, fromCategoryId: String?, toCategoryId: String?) {}
    func listCompleted(itemCount: Int) {}
    func shareCodeShown(forList listId: String) {}
    func shareCodeCopied() {}
}
