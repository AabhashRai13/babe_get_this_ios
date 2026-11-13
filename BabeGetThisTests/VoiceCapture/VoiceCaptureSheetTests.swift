import XCTest
@testable import BabeGetThis

/// Models iOS: `request()` prompts only while undetermined, and the answer sticks. After a
/// denial it returns false at once without changing anything; only Settings (`status = ...`
/// from the test) can turn it back on.
@MainActor
final class FakeMicrophonePermission: MicrophonePermissionProviding {
    var status: MicrophonePermissionStatus
    var grantOnRequest: Bool
    private(set) var requestCalls = 0

    init(granted: Bool = false, grantOnRequest: Bool = false) {
        self.status = granted ? .granted : .undetermined
        self.grantOnRequest = grantOnRequest
    }

    init(status: MicrophonePermissionStatus) {
        self.status = status
        self.grantOnRequest = false
    }

    func request() async -> Bool {
        requestCalls += 1
        if status == .undetermined {
            status = grantOnRequest ? .granted : .denied
        }
        return status == .granted
    }
}

@MainActor
final class VoiceCaptureSheetTests: XCTestCase {
    private var recorder = FakeVoiceRecorder()
    private var transcriber = FakeVoiceTranscriber()
    private var dismissed = 0
    private var switchedToType = 0
    private var settingsOpened = 0

    private func makeModel(permission: FakeMicrophonePermission) -> (VoiceCaptureSheetModel, VoiceCaptureViewModel) {
        let vm = VoiceCaptureViewModel(recorder: recorder, transcriber: transcriber)
        let model = VoiceCaptureSheetModel(
            viewModel: vm,
            permission: permission,
            onDismiss: { [unowned self] in dismissed += 1 },
            onSwitchToType: { [unowned self] in switchedToType += 1 },
            openSettings: { [unowned self] in settingsOpened += 1 }
        )
        return (model, vm)
    }

    private let persist: VoiceCaptureViewModel.Persist = { _ in .success("list-1") }

    func testIdleRendersSpinnerBeforeAnyAction() {
        let (model, vm) = makeModel(permission: FakeMicrophonePermission())
        XCTAssertEqual(vm.state, .idle)
        XCTAssertEqual(model.content, .idle)
    }

    func testNeedsPermissionOffersAllowMicrophone() {
        XCTAssertEqual(
            VoiceCaptureSheetModel.content(for: .needsPermission, permission: .undetermined),
            .needsPermission(message: "Microphone access is needed to capture your list.", buttonTitle: "Allow microphone")
        )
    }

    // iOS prompts once. After a denial the request returns false without any UI, so the
    // sheet must send the user to Settings instead of offering a button that does nothing.
    func testDeniedPermissionOffersSettings() async {
        let permission = FakeMicrophonePermission(status: .denied)
        let (model, vm) = makeModel(permission: permission)

        await model.onAppear(persist: persist)

        XCTAssertEqual(vm.state, .needsPermission)
        XCTAssertEqual(
            model.content,
            .needsPermission(message: "Microphone access is needed to capture your list.", buttonTitle: "Open Settings")
        )

        await model.allowMicrophoneTapped()

        XCTAssertEqual(settingsOpened, 1)
        XCTAssertEqual(permission.requestCalls, 1)
        XCTAssertEqual(recorder.startCalls, 0)
    }

    // The first open asks the system; refusing the prompt also lands on Settings.
    func testRefusingTheFirstPromptOffersSettings() async {
        let permission = FakeMicrophonePermission(granted: false, grantOnRequest: false)
        let (model, _) = makeModel(permission: permission)

        await model.onAppear(persist: persist)

        XCTAssertEqual(permission.requestCalls, 1)
        XCTAssertEqual(
            model.content,
            .needsPermission(message: "Microphone access is needed to capture your list.", buttonTitle: "Open Settings")
        )
        XCTAssertEqual(recorder.startCalls, 0)
    }

    func testComingBackFromSettingsWithTheMicAllowedStartsRecording() async {
        let permission = FakeMicrophonePermission(status: .denied)
        let (model, vm) = makeModel(permission: permission)
        await model.onAppear(persist: persist)
        await model.allowMicrophoneTapped()

        permission.status = .granted
        model.sceneBecameActive()
        await voiceTestEventually { vm.state == .recording }

        XCTAssertEqual(vm.state, .recording)
        XCTAssertEqual(model.content, .recording)
    }

    func testComingBackStillDeniedChangesNothing() async {
        let (model, vm) = makeModel(permission: FakeMicrophonePermission(status: .denied))
        await model.onAppear(persist: persist)

        model.sceneBecameActive()

        XCTAssertEqual(vm.state, .needsPermission)
        XCTAssertEqual(recorder.startCalls, 0)
    }

    func testAllowMicrophoneGrantStartsRecording() async {
        let permission = FakeMicrophonePermission(granted: false, grantOnRequest: true)
        let (model, vm) = makeModel(permission: permission)
        // The sheet was left on the explanation (e.g. reopened before the prompt was answered).
        vm.onPermissionResult(granted: false)

        await model.allowMicrophoneTapped()
        await voiceTestEventually { vm.state == .recording }

        XCTAssertEqual(permission.requestCalls, 1)
        XCTAssertEqual(vm.state, .recording)
        XCTAssertEqual(model.content, .recording)
    }

    func testAlreadyGrantedStartsRecordingWithoutPrompt() async {
        let permission = FakeMicrophonePermission(granted: true)
        let (model, vm) = makeModel(permission: permission)

        await model.onAppear(persist: persist)
        await voiceTestEventually { vm.state == .recording }

        XCTAssertEqual(permission.requestCalls, 0)
        XCTAssertEqual(vm.state, .recording)
    }

    func testTranscribingCopyAdvancesEvery2_5Seconds() async {
        var sleeps: [Duration] = []
        let copy = VoiceTranscribingCopy(sleep: { sleeps.append($0) })

        XCTAssertEqual(copy.line, "Listening to your list…")
        await copy.run()

        // Two advances, each after 2.5 s, then it holds on the last line.
        XCTAssertEqual(sleeps, [.milliseconds(2500), .milliseconds(2500)])
        XCTAssertEqual(copy.line, "Almost there…")
        XCTAssertEqual(
            VoiceTranscribingCopy.lines,
            ["Listening to your list…", "Sorting your items…", "Almost there…"]
        )
    }

    func testTranscribingCopyShowsEachLineInOrder() async {
        var seen: [String] = []
        var copyRef: VoiceTranscribingCopy?
        let copy = VoiceTranscribingCopy(sleep: { _ in
            if let copyRef { seen.append(copyRef.line) }
        })
        copyRef = copy
        await copy.run()
        XCTAssertEqual(seen, ["Listening to your list…", "Sorting your items…"])
        XCTAssertEqual(copy.line, "Almost there…")
    }

    func testFailedOffersRetryAndTypeInstead() async {
        let permission = FakeMicrophonePermission(granted: true)
        let (model, vm) = makeModel(permission: permission)
        await model.onAppear(persist: persist)
        await voiceTestEventually { vm.state == .recording }

        model.stopTapped()
        await voiceTestEventually { if case .failed = vm.state { true } else { false } }

        XCTAssertEqual(
            model.content,
            .failed(message: "Didn't catch any items. Try again?", retryTitle: "Try again", typeInsteadTitle: "Type instead")
        )
    }

    func testTypeInsteadCancelsAndSwitches() async {
        let (model, vm) = makeModel(permission: FakeMicrophonePermission(granted: true))
        await model.onAppear(persist: persist)
        await voiceTestEventually { vm.state == .recording }

        model.typeInsteadTapped()

        XCTAssertEqual(switchedToType, 1)
        XCTAssertEqual(vm.state, .idle)
        XCTAssertGreaterThan(recorder.cancelCalls, 0)
    }

    // Swipe-down: the view's onDisappear path. Cancels and tells the host, like Android's
    // onDismissRequest.
    func testSwipingTheSheetAwayCancelsTheRecorderAndTellsTheHost() async {
        let (model, vm) = makeModel(permission: FakeMicrophonePermission(granted: true))
        await model.onAppear(persist: persist)
        await voiceTestEventually { vm.state == .recording }

        model.sheetDisappeared()

        XCTAssertEqual(vm.state, .idle)
        XCTAssertGreaterThan(recorder.cancelCalls, 0)
        XCTAssertEqual(dismissed, 1)
    }

    // On success the host was told when Done arrived; the sheet then disappearing must not
    // tell it a second time.
    func testDisappearingAfterSuccessDoesNotDismissTwice() async {
        transcriber.result = .success([TranscribedItem(name: "Milk")])
        let (model, vm) = makeModel(permission: FakeMicrophonePermission(granted: true))
        await model.onAppear(persist: persist)
        await voiceTestEventually { vm.state == .recording }
        model.stopTapped()
        await voiceTestEventually { vm.state == .done }
        model.stateChanged()

        model.sheetDisappeared()

        XCTAssertEqual(dismissed, 1)
    }

    // "Type instead" hands over to the typing flow; closing the sheet for it is not a dismissal.
    func testDisappearingAfterTypeInsteadDoesNotDismiss() async {
        let (model, vm) = makeModel(permission: FakeMicrophonePermission(granted: true))
        await model.onAppear(persist: persist)
        await voiceTestEventually { vm.state == .recording }
        model.typeInsteadTapped()

        model.sheetDisappeared()

        XCTAssertEqual(switchedToType, 1)
        XCTAssertEqual(dismissed, 0)
    }

    func testStateChangesAreAnnouncedWithTheTextThatAppeared() {
        XCTAssertEqual(
            VoiceCaptureSheetModel.content(for: .failed("Didn't catch any items. Try again?")).announcement,
            "Didn't catch any items. Try again?"
        )
        XCTAssertEqual(
            VoiceCaptureSheetModel.content(for: .needsPermission).announcement,
            "Microphone access is needed to capture your list."
        )
        XCTAssertEqual(VoiceCaptureSheetModel.content(for: .recording).announcement, "Listening…")
        XCTAssertEqual(VoiceCaptureSheetModel.content(for: .transcribing).announcement, "Listening to your list…")
        XCTAssertEqual(VoiceCaptureSheetModel.content(for: .saving).announcement, "Saving your list…")
        XCTAssertNil(VoiceCaptureSheetModel.content(for: .idle).announcement)
    }

    func testDoneDismissesAndResetsToIdle() async {
        transcriber.result = .success([TranscribedItem(name: "Milk")])
        let (model, vm) = makeModel(permission: FakeMicrophonePermission(granted: true))
        await model.onAppear(persist: persist)
        await voiceTestEventually { vm.state == .recording }

        model.stopTapped()
        await voiceTestEventually { vm.state == .done }
        XCTAssertEqual(model.content, .loading(label: "Done!"))

        model.stateChanged()

        XCTAssertEqual(dismissed, 1)
        XCTAssertEqual(vm.state, .idle)
    }

    func testSavingShowsSavingLabel() {
        XCTAssertEqual(VoiceCaptureSheetModel.content(for: .saving), .loading(label: "Saving your list…"))
    }
}
