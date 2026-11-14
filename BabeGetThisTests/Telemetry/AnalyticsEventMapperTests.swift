import XCTest
@testable import BabeGetThis

/// Port of Android's AnalyticsEventMapperTest, minus the 2 reminder and 4 Got This cases
/// (both features are out of iOS v1, and so are their events). Mostly whole-catalog checks:
/// a wrong mapping uploads fine and is only noticed weeks later.
final class AnalyticsEventMapperTests: XCTestCase {

    /// One instance of every event. The coverage test makes forgetting to extend it a failure.
    private let everyEvent: [AnalyticsEvent] = [
        .screenViewed(.shoppingList),
        .voiceSheetOpened,
        .voiceRecordingStarted,
        .voiceRecordingFailed,
        .voiceRecordingCancelled(elapsedMillis: 2_000),
        .voiceTranscriptionCompleted(latencyMillis: 1_500, itemCount: 4),
        .voiceTranscriptionFailed(reason: .network, latencyMillis: 900),
        .voiceItemsSaved(itemCount: 4),
        .shareCodeCreated,
        .shareCodeShared,
        .shareJoinAttempted,
        .shareJoinSucceeded,
        .shareJoinFailed(.invalidCode),
        .welcomeChoiceMade(.guest),
        .sharedListFirstEditByJoiner,
        .accountRegistered,
        .accountLoggedIn,
        .firstItemAdded(.voice),
        .firstListCompleted(itemCount: 12),
        .itemAdded(inputMethod: .manual, categorySource: .auto),
        .itemCheckedOff,
        .listCompleted(itemCount: 7),
        .categoryAutoAssigned(categoryId: "cat-dairy-eggs"),
        .categoryCorrected(fromCategoryId: "cat-dairy-eggs", toCategoryId: "cat-frozen-foods"),
    ]

    func testTheSampleCoversEveryEventInTheCatalog() {
        XCTAssertEqual(
            AnalyticsEvent.Kind.allCases.count,
            Set(everyEvent.map(\.kind)).count,
            "AnalyticsEvent gained or lost a case: update everyEvent")
    }

    func testEveryEventNameIsOneGA4WillAccept() {
        for event in everyEvent {
            let name = AnalyticsEventMapper.map(event).name
            XCTAssertTrue(AnalyticsEventMapper.isValidEventName(name), "invalid GA4 event name: '\(name)' from \(event)")
        }
    }

    func testEventNamesAreUniqueAcrossTheCatalog() {
        let names = everyEvent.map { AnalyticsEventMapper.map($0).name }
        XCTAssertEqual(names.count, Set(names).count)
    }

    func testNoEventExceedsGA4sParameterLimit() {
        for event in everyEvent {
            let mapped = AnalyticsEventMapper.map(event)
            XCTAssertLessThanOrEqual(mapped.text.count + mapped.numbers.count, 25, "too many params on \(mapped.name)")
        }
    }

    func testNoParameterValueExceedsGA4sStringLengthLimit() {
        for event in everyEvent {
            for (key, value) in AnalyticsEventMapper.map(event).text {
                XCTAssertLessThanOrEqual(value.count, 100, "\(key) too long on \(event)")
            }
        }
    }

    func testKnownTaxonomyCategoriesPassThroughAsThemselves() {
        let known = DefaultCategories.all[0].id
        let mapped = AnalyticsEventMapper.map(.categoryAutoAssigned(categoryId: known))
        XCTAssertEqual(known, mapped.text["category"])
    }

    func testUserCreatedCategoriesCollapseToASingleLabel() {
        let mapped = AnalyticsEventMapper.map(.categoryAutoAssigned(categoryId: "8f14e45f-ceea-467a-9f3e-2a1b7c9d4e50"))
        XCTAssertEqual("custom", mapped.text["category"])
    }

    func testAnAbsentCategoryIsDistinguishableFromACustomOne() {
        let mapped = AnalyticsEventMapper.map(.categoryAutoAssigned(categoryId: nil))
        XCTAssertEqual("none", mapped.text["category"])
    }

    func testCategoryCorrectionsLabelBothSides() {
        let mapped = AnalyticsEventMapper.map(
            .categoryCorrected(fromCategoryId: "cat-dairy-eggs", toCategoryId: "not-a-real-id"))
        XCTAssertEqual("cat-dairy-eggs", mapped.text["from_category"])
        XCTAssertEqual("custom", mapped.text["to_category"])
    }

    func testCountsAreSentBucketedAsWellAsRaw() {
        let mapped = AnalyticsEventMapper.map(.voiceTranscriptionCompleted(latencyMillis: 1_200, itemCount: 14))
        XCTAssertEqual("11-20", mapped.text["item_count_bucket"])
        XCTAssertEqual(14, mapped.numbers["item_count"])
    }

    func testLatencyIsOnlyEverSentBucketed() {
        let mapped = AnalyticsEventMapper.map(.voiceTranscriptionFailed(reason: .timeout, latencyMillis: 8_432))
        XCTAssertEqual("5-10s", mapped.text["latency_bucket"])
        XCTAssertTrue(mapped.numbers.isEmpty)
    }

    func testFailureReasonsAreSentAsBoundedLabels() {
        for reason in VoiceFailureReason.allCases {
            let mapped = AnalyticsEventMapper.map(.voiceTranscriptionFailed(reason: reason, latencyMillis: 100))
            XCTAssertEqual(reason.rawValue, mapped.text["reason"])
        }
        for reason in JoinFailureReason.allCases {
            let mapped = AnalyticsEventMapper.map(.shareJoinFailed(reason))
            XCTAssertEqual(reason.rawValue, mapped.text["reason"])
        }
    }

    func testWelcomeChoiceMapsToWelcomeChoiceWithABoundedChoiceParam() {
        XCTAssertEqual(
            MappedEvent(name: "welcome_choice", text: ["choice": "guest"]),
            AnalyticsEventMapper.map(.welcomeChoiceMade(.guest)))
        XCTAssertEqual(
            MappedEvent(name: "welcome_choice", text: ["choice": "sign_in"]),
            AnalyticsEventMapper.map(.welcomeChoiceMade(.signIn)))
    }

    func testScreenViewsMapThroughTheEnumNeverARawRoute() {
        for screen in Screen.allCases {
            let mapped = AnalyticsEventMapper.map(.screenViewed(screen))
            XCTAssertEqual("screen_view", mapped.name)
            XCTAssertEqual(screen.screenName, mapped.text["screen_name"])
        }
    }

    func testRoutePatternsResolveToScreensWithoutTouchingArguments() {
        XCTAssertEqual(.shoppingItems, Screen.fromRoute("shopping_items/{listId}/{listName}"))
        XCTAssertEqual(.shoppingList, Screen.fromRoute("shopping_list"))
        XCTAssertEqual(.settings, Screen.fromRoute("settings"))
        XCTAssertEqual(.login, Screen.fromRoute("login"))
        XCTAssertEqual(.register, Screen.fromRoute("register"))
        XCTAssertEqual(.forgotPassword, Screen.fromRoute("forgot_password"))
    }

    func testAnUnrecognisedRouteReportsUnknownRatherThanLeakingItself() {
        XCTAssertEqual(.unknown, Screen.fromRoute("some_new_screen/secret-list-name"))
        XCTAssertEqual(.unknown, Screen.fromRoute(nil))
    }

    func testNoMappedParameterValueContainsFreeText() {
        // Every value is an enum label, a bucket or a taxonomy id, so none should contain a space.
        for event in everyEvent {
            let mapped = AnalyticsEventMapper.map(event)
            for (key, value) in mapped.text {
                XCTAssertFalse(value.contains(" "), "'\(value)' under '\(key)' on \(mapped.name) looks like free text")
            }
        }
    }

    func testMappingIsTotal() {
        for event in everyEvent {
            XCTAssertFalse(AnalyticsEventMapper.map(event).name.isEmpty, "\(event) mapped to no name")
        }
    }
}
