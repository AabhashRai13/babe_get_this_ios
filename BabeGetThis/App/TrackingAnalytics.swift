import Foundation

// The bridges from each feature's own analytics protocol to the app's event catalog
// (`AnalyticsEvent`). The features stay ignorant of telemetry; `AppContainer` hands these out.

/// Sends the Welcome choice as `welcome_choice`.
struct TrackingWelcomeAnalytics: WelcomeAnalytics {
    let analytics: any AnalyticsRepository

    func track(choice: WelcomeChoice) {
        analytics.track(.welcomeChoiceMade(choice))
    }
}

/// Sends sign-in and sign-up as `account_logged_in` and `account_registered`.
struct TrackingAuthAnalytics: LoginAnalytics, RegisterAnalytics {
    let analytics: any AnalyticsRepository

    func trackAccountLoggedIn() {
        analytics.track(.accountLoggedIn)
    }

    func trackAccountRegistered() {
        analytics.track(.accountRegistered)
    }
}

/// Sends the voice funnel (`voice_*` events).
@MainActor
struct TrackingVoiceCaptureAnalytics: VoiceCaptureAnalytics {
    let analytics: any AnalyticsRepository

    func track(_ event: VoiceCaptureEvent) {
        analytics.track(Self.analyticsEvent(for: event))
    }

    private static func analyticsEvent(for event: VoiceCaptureEvent) -> AnalyticsEvent {
        switch event {
        case .sheetOpened: .voiceSheetOpened
        case .recordingStarted: .voiceRecordingStarted
        case .recordingFailed: .voiceRecordingFailed
        case .recordingCancelled(let elapsedMillis): .voiceRecordingCancelled(elapsedMillis: Int64(elapsedMillis))
        case .transcriptionCompleted(let latencyMillis, let itemCount):
            .voiceTranscriptionCompleted(latencyMillis: Int64(latencyMillis), itemCount: itemCount)
        case .transcriptionFailed(let reason, let latencyMillis):
            .voiceTranscriptionFailed(reason: analyticsReason(for: reason), latencyMillis: Int64(latencyMillis))
        case .itemsSaved(let itemCount): .voiceItemsSaved(itemCount: itemCount)
        }
    }

    private static func analyticsReason(for reason: VoiceCaptureFailureReason) -> VoiceFailureReason {
        switch reason {
        case .nothingHeard: .nothingHeard
        case .network: .network
        case .timeout: .timeout
        case .server: .server
        // The analytics taxonomy has no "unauthorized"; Android reports an auth failure as unknown.
        case .unauthorized, .unknown: .unknown
        }
    }
}

/// Sends the lists' and list detail's habit, activation and sharing events (TEL-04, Android
/// `ShoppingListViewModel` and `ShoppingItemsViewModel`). Owns the once-only rules, through
/// `TelemetryMarkers`: activation once per user, a share and a joiner's first edit once per list.
/// Only enums, counts and ids go out: the protocols carry nothing else.
@MainActor
struct TrackingListAnalytics: ListsAnalytics, ListDetailAnalytics {
    let analytics: any AnalyticsRepository
    let markers: TelemetryMarkers
    /// Activation is scoped to the signed-in user, so a second account on the phone still records
    /// its own; a guest's is scoped to "anon".
    let authState: AuthStateManager

    // MARK: Lists

    /// The other voice path (into an existing list) reports the same events, so the funnel does
    /// not care which route an item took.
    func voiceListCreated(categoryIds: [String?]) {
        trackVoiceItems(categoryIds)
    }

    /// Before the call, so attempts over successes is the real conversion rate: counting on
    /// completion would drop everyone whose join never returned.
    func joinAttempted() {
        analytics.track(.shareJoinAttempted)
    }

    /// Also writes down that THIS device joined the list. Once it syncs, owner and joiner look the
    /// same, so this is the only moment the difference can be captured (`listEdited` reads it).
    func joinSucceeded(listId: String) {
        analytics.track(.shareJoinSucceeded)
        markers.mark(.joinedList, scope: listId)
    }

    /// The reason only, never the code.
    func joinFailed(_ error: AppError) {
        analytics.track(.shareJoinFailed(JoinFailureReason.from(error)))
    }

    // MARK: List detail

    /// Whatever category a manual add has, the user picked it: nothing was auto-assigned.
    func itemAdded(toList listId: String, categoryId: String?) {
        analytics.track(.itemAdded(inputMethod: .manual, categorySource: categoryId == nil ? .none : .user))
        trackFirstItemAdded(.manual)
        listEdited(listId)
    }

    func voiceItemsAdded(toList listId: String, categoryIds: [String?]) {
        trackVoiceItems(categoryIds)
        listEdited(listId)
    }

    /// Only the tick: an untick is a correction, and counting it would inflate the shopping
    /// activity this measures. Both are edits to the list.
    func itemToggled(inList listId: String, isPickedUp: Bool) {
        if isPickedUp { analytics.track(.itemCheckedOff) }
        listEdited(listId)
    }

    /// A changed category is the taxonomy signal: direct evidence that the fixed category set put
    /// the item in the wrong place. A rename alone is not, and would make the taxonomy look worse.
    func itemEdited(inList listId: String, fromCategoryId: String?, toCategoryId: String?) {
        if fromCategoryId != toCategoryId {
            analytics.track(.categoryCorrected(fromCategoryId: fromCategoryId, toCategoryId: toCategoryId))
        }
        listEdited(listId)
    }

    func listCompleted(itemCount: Int) {
        analytics.track(.listCompleted(itemCount: itemCount))
        if markers.firstTime(.firstListCompleted, scope: authState.liveSessionUserId) {
            analytics.track(.firstListCompleted(itemCount: itemCount))
        }
    }

    /// Sharing hands back the EXISTING code after the first time, so only the marker can tell a
    /// new share from the dialog being opened again.
    func shareCodeShown(forList listId: String) {
        if markers.firstTime(.shareCodeCreated, scope: listId) {
            analytics.track(.shareCodeCreated)
        }
    }

    func shareCodeCopied() {
        analytics.track(.shareCodeShared)
    }

    // MARK: Helpers

    /// One add and one auto-category per item: the correction rate is per category, so it needs a
    /// per-category denominator. Activation once, after the loop: three spoken items are one.
    private func trackVoiceItems(_ categoryIds: [String?]) {
        guard !categoryIds.isEmpty else { return }
        for categoryId in categoryIds {
            analytics.track(.itemAdded(inputMethod: .voice, categorySource: categoryId == nil ? .none : .auto))
            analytics.track(.categoryAutoAssigned(categoryId: categoryId))
        }
        trackFirstItemAdded(.voice)
    }

    private func trackFirstItemAdded(_ inputMethod: InputMethod) {
        if markers.firstTime(.firstItemAdded, scope: authState.liveSessionUserId) {
            analytics.track(.firstItemAdded(inputMethod))
        }
    }

    /// A joiner's first edit to a shared list, once per list, and only on the device that joined.
    private func listEdited(_ listId: String) {
        guard markers.has(.joinedList, scope: listId) else { return }
        guard markers.firstTime(.sharedListFirstEdit, scope: listId) else { return }
        analytics.track(.sharedListFirstEditByJoiner)
    }
}
