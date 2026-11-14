import Foundation

/// THE EVENT CATALOG (port of Android `AnalyticsEvent`). Everything this app can report is here.
///
/// An enum rather than `track(name:params:)`: a typo'd name or a wrong-typed parameter is a
/// compile error, the mapper's `switch` is exhaustive, and this file answers "what does the app
/// track?". GA4's name-and-params shape lives only in `AnalyticsEventMapper`.
///
/// iOS v1 leaves out Android's reminder and Got This events (both features are out of v1).
///
/// PRIVACY: parameters are bounded enums, bucketed numbers and ids from our own fixed taxonomy.
/// There is no untyped map, so free text has no way in.
enum AnalyticsEvent: Equatable, Sendable {
    // MARK: Screen views
    case screenViewed(Screen)

    // MARK: Voice-to-list funnel (sheet opened, recording, transcription, items saved)
    case voiceSheetOpened
    case voiceRecordingStarted
    /// The mic could not be opened.
    case voiceRecordingFailed
    /// Sheet dismissed mid-recording; the duration separates a mis-tap from a change of mind.
    case voiceRecordingCancelled(elapsedMillis: Int64)
    /// `itemCount` is also sent raw: items per utterance is small and the number we average.
    case voiceTranscriptionCompleted(latencyMillis: Int64, itemCount: Int)
    case voiceTranscriptionFailed(reason: VoiceFailureReason, latencyMillis: Int64)
    case voiceItemsSaved(itemCount: Int)

    // MARK: Sharing loop
    /// Owner side, first share of a list only.
    case shareCodeCreated
    /// The share sheet was shown; which app was picked is not known.
    case shareCodeShared
    case shareJoinAttempted
    case shareJoinSucceeded
    case shareJoinFailed(JoinFailureReason)
    /// A joiner's first edit to a list, once per list.
    case sharedListFirstEditByJoiner

    // MARK: Activation
    case welcomeChoiceMade(WelcomeChoice)
    case accountRegistered
    case accountLoggedIn
    case firstItemAdded(InputMethod)
    case firstListCompleted(itemCount: Int)

    // MARK: Habit and taxonomy
    case itemAdded(inputMethod: InputMethod, categorySource: CategorySource)
    /// No input method: items record no provenance.
    case itemCheckedOff
    /// The last unchecked item on a list was checked.
    case listCompleted(itemCount: Int)
    case categoryAutoAssigned(categoryId: String?)
    case categoryCorrected(fromCategoryId: String?, toCategoryId: String?)

    /// One value per case, so tests can check that a sample covers the whole catalog
    /// (Android uses `sealedSubclasses`). The switch is exhaustive, so a new case won't build
    /// until it is added here.
    enum Kind: CaseIterable {
        case screenViewed, voiceSheetOpened, voiceRecordingStarted, voiceRecordingFailed,
             voiceRecordingCancelled, voiceTranscriptionCompleted, voiceTranscriptionFailed,
             voiceItemsSaved, shareCodeCreated, shareCodeShared, shareJoinAttempted,
             shareJoinSucceeded, shareJoinFailed, sharedListFirstEditByJoiner, welcomeChoiceMade,
             accountRegistered, accountLoggedIn, firstItemAdded, firstListCompleted, itemAdded,
             itemCheckedOff, listCompleted, categoryAutoAssigned, categoryCorrected
    }

    var kind: Kind {
        switch self {
        case .screenViewed: .screenViewed
        case .voiceSheetOpened: .voiceSheetOpened
        case .voiceRecordingStarted: .voiceRecordingStarted
        case .voiceRecordingFailed: .voiceRecordingFailed
        case .voiceRecordingCancelled: .voiceRecordingCancelled
        case .voiceTranscriptionCompleted: .voiceTranscriptionCompleted
        case .voiceTranscriptionFailed: .voiceTranscriptionFailed
        case .voiceItemsSaved: .voiceItemsSaved
        case .shareCodeCreated: .shareCodeCreated
        case .shareCodeShared: .shareCodeShared
        case .shareJoinAttempted: .shareJoinAttempted
        case .shareJoinSucceeded: .shareJoinSucceeded
        case .shareJoinFailed: .shareJoinFailed
        case .sharedListFirstEditByJoiner: .sharedListFirstEditByJoiner
        case .welcomeChoiceMade: .welcomeChoiceMade
        case .accountRegistered: .accountRegistered
        case .accountLoggedIn: .accountLoggedIn
        case .firstItemAdded: .firstItemAdded
        case .firstListCompleted: .firstListCompleted
        case .itemAdded: .itemAdded
        case .itemCheckedOff: .itemCheckedOff
        case .listCompleted: .listCompleted
        case .categoryAutoAssigned: .categoryAutoAssigned
        case .categoryCorrected: .categoryCorrected
        }
    }
}

/// How an item got into the list. The voice bet is measured by the ratio between these two.
enum InputMethod: String, CaseIterable, Sendable {
    case voice
    case manual
}

/// Where an item's category came from. `user` covers picking one and correcting one;
/// `none` means uncategorised.
enum CategorySource: String, CaseIterable, Sendable {
    case auto
    case user
    case none
}

/// Why voice failed. Bounded on purpose: the raw error message could leak a server response.
enum VoiceFailureReason: String, CaseIterable, Sendable {
    /// Transcription worked but understood nothing.
    case nothingHeard = "nothing_heard"
    case network
    case timeout
    case server
    case unknown

    /// Maps from the error's TYPE, never its message, which can carry text off the wire.
    static func from(_ error: AppError) -> VoiceFailureReason {
        switch error {
        case .network: .network
        case .timeout: .timeout
        case .server: .server
        // A 4xx from the transcribe endpoint means bad audio; the voice client maps it to validation.
        case .validation: .nothingHeard
        default: .unknown
        }
    }
}

// `WelcomeChoice` (guest / sign_in) is declared with the Welcome feature and reused here.

/// Why joining a shared list failed. Mirrors what `ShareRepository.join` can produce.
enum JoinFailureReason: String, CaseIterable, Sendable {
    /// The code matched no list (usually a typo).
    case invalidCode = "invalid_code"
    /// The code was good but the first full pull failed: membership without data.
    case catchUpFailed = "catch_up_failed"
    case notSignedIn = "not_signed_in"
    case network
    case unknown

    static func from(_ error: AppError) -> JoinFailureReason {
        switch error {
        case .notFound: .invalidCode
        case .auth, .unauthorized: .notSignedIn
        case .network, .timeout: .network
        // The code was good and the pull failed: the worst outcome this flow has.
        case .server, .database: .catchUpFailed
        default: .unknown
        }
    }
}
