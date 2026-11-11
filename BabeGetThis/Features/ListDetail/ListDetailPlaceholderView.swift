import SwiftUI

/// Stand-in for the list detail screen (items grouped by shop), which lands with the items milestone.
struct ListDetailPlaceholderView: View {
    let list: ShoppingListSummary

    var body: some View {
        ContentUnavailableView(
            "Items are coming soon",
            systemImage: "checklist",
            description: Text("Adding, ticking and grouping items by shop arrive in the next milestone.")
        )
        .background(AppColors.background)
        .navigationTitle(list.name)
        .navigationBarTitleDisplayMode(.inline)
    }
}
