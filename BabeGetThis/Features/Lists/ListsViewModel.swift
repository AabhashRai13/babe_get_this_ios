import Foundation
import Observation

@Observable
@MainActor
final class ListsViewModel {
    enum Tab: String, CaseIterable, Identifiable {
        case active = "Active"
        case completed = "Completed"
        var id: Self { self }
        var systemImage: String { self == .active ? "cart" : "checkmark.circle" }
    }

    private(set) var lists: [ShoppingListSummary]
    var selectedTab: Tab = .active

    init(lists: [ShoppingListSummary] = []) {
        self.lists = lists
    }

    var activeLists: [ShoppingListSummary] { sorted(lists.filter { !$0.isCompleted }) }
    var completedLists: [ShoppingListSummary] { sorted(lists.filter(\.isCompleted)) }
    var visibleLists: [ShoppingListSummary] { selectedTab == .active ? activeLists : completedLists }

    var greetingSummary: String {
        Greeting.summary(listCount: activeLists.count, itemsToGet: activeLists.reduce(0) { $0 + $1.itemsToGet })
    }

    /// Returns the new list, or nil when the name is blank.
    @discardableResult
    func createList(named rawName: String, id: String = UUID().uuidString.lowercased(), now: Date = .now) -> ShoppingListSummary? {
        let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return nil }
        let list = ShoppingListSummary(id: id, name: name, totalItems: 0, pickedUpItems: 0, updatedAt: now)
        lists.append(list)
        selectedTab = .active
        return list
    }

    private func sorted(_ lists: [ShoppingListSummary]) -> [ShoppingListSummary] {
        lists.sorted { $0.updatedAt > $1.updatedAt }
    }
}

/// Time-aware greeting on the lists overview (Android GreetingSection).
enum Greeting {
    static func prefix(hour: Int) -> String {
        switch hour {
        case ..<12: "Good morning"
        case ..<17: "Good afternoon"
        default: "Good evening"
        }
    }

    /// "Good afternoon, Aabhash" when a name is known, else just the prefix.
    static func title(hour: Int, userName: String?) -> String {
        let firstName = userName?
            .trimmingCharacters(in: .whitespaces)
            .split(separator: " ").first.map(String.init)
        guard let firstName, !firstName.isEmpty else { return prefix(hour: hour) }
        return "\(prefix(hour: hour)), \(firstName)"
    }

    static func summary(listCount: Int, itemsToGet: Int) -> String {
        let lists = listCount == 1 ? "1 list" : "\(listCount) lists"
        let items: String = switch itemsToGet {
        case 0: "nothing to pick up yet"
        case 1: "1 item to get"
        default: "\(itemsToGet) items to get"
        }
        return "\(lists) · \(items)"
    }

    /// "3/7 items" (pluralised on the total, like Android).
    static func progress(picked: Int, total: Int) -> String {
        "\(picked)/\(total) \(total == 1 ? "item" : "items")"
    }
}
