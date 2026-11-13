import XCTest
@testable import BabeGetThis

@MainActor
final class FakeMicrophonePermission: MicrophonePermissionProviding {
    var granted: Bool
    var grantOnRequest: Bool
    private(set) var requestCalls = 0

    init(granted: Bool = false, grantOnRequest: Bool = false) {
        self.granted = granted
        self.grantOnRequest = grantOnRequest
    }

    var isGranted: Bool { granted }

    func request() async -> Bool {
        requestCalls += 1
        granted = grantOnRequest
        return grantOnRequest
    }
}

@MainActor
final class VoiceCaptureSheetTests: XCTestCase {
    private var recorder = FakeVoiceRecorder()
    private var transcriber = FakeVoiceTranscriber()
    private var dismissed = 0
    private var switchedToType = 0

    private func makeModel(permission: FakeMicrophonePermission) -> (VoiceCaptureSheetModel, VoiceCaptureViewModel) {
        let vm = VoiceCaptureViewModel(recorder: recorder, transcriber: transcriber)
        let model = VoiceCaptureSheetModel(
            viewModel: vm,
            permission: permission,
            onDismiss: { [unowned self] in dismissed += 1 },
            onSwitchToType: { [unowned self] in switchedToType += 1 }
        )
        return (model, vm)
    }

    private let persist: VoiceCaptureViewModel.Persist = { _ in .success("list-1") }

    func testIdleRendersSpinnerBeforeAnyAction() {
        let (model, vm) = makeModel(permission: FakeMicrophonePermission())
        XCTAssertEqual(vm.state, .idle)
        XCTAssertEqual(model.content, .idle)
    }

    func testNeedsPermissionOffersAllowMicrophone() async {
        let permission = FakeMicrophonePermission(granted: false, grantOnRequest: false)
        let (model, _) = makeModel(permission: permission)

        // First open asks the system; a denial lands on the explanation.
        await model.onAppear(persist: persist)

        XCTAssertEqual(
            model.content,
            .needsPermission(message: "Microphone access is needed to capture your list.", buttonTitle: "Allow microphone")
        )
        XCTAssertEqual(permission.requestCalls, 1)
        XCTAssertEqual(recorder.startCalls, 0)
    }

    func testAllowMicrophoneGrantStartsRecording() async {
        let permission = FakeMicrophonePermission(granted: false, grantOnRequest: false)
        let (model, vm) = makeModel(permission: permission)
        await model.onAppear(persist: persist)

        permission.grantOnRequest = true
        await model.allowMicrophoneTapped()
        await voiceTestEventually { vm.state == .recording }

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

    func testDismissingTheSheetCancelsTheRecorder() async {
        let (model, vm) = makeModel(permission: FakeMicrophonePermission(granted: true))
        await model.onAppear(persist: persist)
        await voiceTestEventually { vm.state == .recording }

        model.sheetDismissed()

        XCTAssertEqual(vm.state, .idle)
        XCTAssertGreaterThan(recorder.cancelCalls, 0)
        XCTAssertEqual(dismissed, 1)
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
