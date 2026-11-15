import Foundation

/// A vendor-shaped event: a name plus parameters, split by type because GA4 treats strings as
/// dimensions and numbers as metrics. Plain Swift, so the mapper tests need no Firebase.
struct MappedEvent: Equatable, Sendable {
    let name: String
    var text: [String: String] = [:]
    var numbers: [String: Int64] = [:]
}

/// Translates the catalog into GA4's shape (port of Android `AnalyticsEventMapper`). The only
/// place that knows what an event is called on the wire.
enum AnalyticsEventMapper {
    // GA4's documented limits. Exceeding one is silent data loss at the backend, so they are
    // enforced here.
    private static let maxNameLength = 40
    private static let maxParamNameLength = 40
    private static let maxTextValueLength = 100
    private static let maxParams = 25

    /// Reserved by Google; an event using one of these prefixes is rejected.
    private static let reservedPrefixes = ["firebase_", "google_", "ga_"]

    private static let knownCategoryIds = Set(DefaultCategories.all.map(\.id))

    /// A user-created category has a generated id and a user-authored name; neither is sent.
    private static let customCategory = "custom"
    private static let noCategory = "none"

    static func map(_ event: AnalyticsEvent) -> MappedEvent {
        switch event {
        case .screenViewed(let screen):
            // GA4's own screen_view event and parameter name, so it feeds the built-in reports.
            ev("screen_view", text: ["screen_name": screen.screenName])

        // Voice
        case .voiceSheetOpened:
            ev("voice_sheet_opened")
        case .voiceRecordingStarted:
            ev("voice_recording_started")
        case .voiceRecordingFailed:
            ev("voice_recording_failed")
        case .voiceRecordingCancelled(let elapsedMillis):
            ev("voice_recording_cancelled", text: ["duration_bucket": Buckets.millis(elapsedMillis)])
        case .voiceTranscriptionCompleted(let latencyMillis, let itemCount):
            ev("voice_transcription_completed",
               text: ["latency_bucket": Buckets.millis(latencyMillis), "item_count_bucket": Buckets.count(itemCount)],
               numbers: ["item_count": Int64(itemCount)])
        case .voiceTranscriptionFailed(let reason, let latencyMillis):
            ev("voice_transcription_failed",
               text: ["reason": reason.rawValue, "latency_bucket": Buckets.millis(latencyMillis)])
        case .voiceItemsSaved(let itemCount):
            ev("voice_items_saved",
               text: ["item_count_bucket": Buckets.count(itemCount)],
               numbers: ["item_count": Int64(itemCount)])

        // Sharing
        case .shareCodeCreated:
            ev("share_code_created")
        case .shareCodeShared:
            ev("share_code_shared")
        case .shareJoinAttempted:
            ev("share_join_attempted")
        case .shareJoinSucceeded:
            ev("share_join_succeeded")
        case .shareJoinFailed(let reason):
            ev("share_join_failed", text: ["reason": reason.rawValue])
        case .sharedListFirstEditByJoiner:
            ev("shared_list_first_edit")

        // Activation
        case .welcomeChoiceMade(let choice):
            ev("welcome_choice", text: ["choice": choice.rawValue])
        case .accountRegistered:
            ev("account_registered")
        case .accountLoggedIn:
            ev("account_logged_in")
        case .firstItemAdded(let inputMethod):
            ev("first_item_added", text: ["input_method": inputMethod.rawValue])
        case .firstListCompleted(let itemCount):
            ev("first_list_completed", text: ["item_count_bucket": Buckets.count(itemCount)])

        // Habit and taxonomy
        case .itemAdded(let inputMethod, let categorySource):
            ev("item_added", text: ["input_method": inputMethod.rawValue, "category_source": categorySource.rawValue])
        case .itemCheckedOff:
            ev("item_checked_off")
        case .listCompleted(let itemCount):
            ev("list_completed",
               text: ["item_count_bucket": Buckets.count(itemCount)],
               numbers: ["item_count": Int64(itemCount)])
        case .categoryAutoAssigned(let categoryId):
            ev("category_auto_assigned", text: ["category": categoryLabel(categoryId)])
        case .categoryCorrected(let fromCategoryId, let toCategoryId):
            ev("category_corrected",
               text: ["from_category": categoryLabel(fromCategoryId), "to_category": categoryLabel(toCategoryId)])
        }
    }

    /// Only ids from our shipped taxonomy pass through; anything else is user-created.
    private static func categoryLabel(_ categoryId: String?) -> String {
        guard let categoryId else { return noCategory }
        return knownCategoryIds.contains(categoryId) ? categoryId : customCategory
    }

    /// Every event is built here, so the limits apply to all of them. Values are truncated
    /// rather than rejected: a clipped value beats a hole in a funnel. Keys are taken in
    /// sorted order so a clipped event is always clipped the same way.
    private static func ev(
        _ name: String,
        text: [String: String] = [:],
        numbers: [String: Int64] = [:]
    ) -> MappedEvent {
        let keptText = text.sorted { $0.key < $1.key }.prefix(maxParams)
        let keptNumbers = numbers.sorted { $0.key < $1.key }.prefix(maxParams - min(text.count, maxParams))
        return MappedEvent(
            name: String(name.prefix(maxNameLength)),
            text: Dictionary(
                keptText.map { (String($0.key.prefix(maxParamNameLength)), String($0.value.prefix(maxTextValueLength))) },
                uniquingKeysWith: { first, _ in first }),
            numbers: Dictionary(
                keptNumbers.map { (String($0.key.prefix(maxParamNameLength)), $0.value) },
                uniquingKeysWith: { first, _ in first }))
    }

    /// For the tests, which check every event in the catalog produces a name GA4 accepts.
    static func isValidEventName(_ name: String) -> Bool {
        guard let first = name.first, name.count <= maxNameLength, first.isLetter else { return false }
        return name.allSatisfy { $0.isLetter || $0.isNumber || $0 == "_" }
            && !reservedPrefixes.contains { name.hasPrefix($0) }
    }
}
