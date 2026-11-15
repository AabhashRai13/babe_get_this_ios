import XCTest
@testable import BabeGetThis

/// Port of Android's FailureReasonsTest. Labels come from the error's case, never its message,
/// because server and unknown errors can carry text off the wire.
final class FailureReasonsTests: XCTestCase {

    func testVoiceFailuresMapByType() {
        XCTAssertEqual(.network, VoiceFailureReason.from(.network()))
        XCTAssertEqual(.timeout, VoiceFailureReason.from(.timeout()))
        XCTAssertEqual(.server, VoiceFailureReason.from(.server(code: 503)))
        // A 4xx from transcribe is "bad audio": validation, read here as nothing heard.
        XCTAssertEqual(.nothingHeard, VoiceFailureReason.from(.validation("x")))
        XCTAssertEqual(.unknown, VoiceFailureReason.from(.unknown()))
        XCTAssertEqual(.unknown, VoiceFailureReason.from(.database()))
    }

    func testJoinFailuresMapByType() {
        XCTAssertEqual(.invalidCode, JoinFailureReason.from(.notFound()))
        XCTAssertEqual(.notSignedIn, JoinFailureReason.from(.auth()))
        XCTAssertEqual(.notSignedIn, JoinFailureReason.from(.unauthorized()))
        XCTAssertEqual(.network, JoinFailureReason.from(.network()))
        XCTAssertEqual(.network, JoinFailureReason.from(.timeout()))
        // Membership without data: the worst outcome of this flow, so it has its own label.
        XCTAssertEqual(.catchUpFailed, JoinFailureReason.from(.server(code: 500)))
        XCTAssertEqual(.catchUpFailed, JoinFailureReason.from(.database()))
        XCTAssertEqual(.unknown, JoinFailureReason.from(.unknown()))
        XCTAssertEqual(.unknown, JoinFailureReason.from(.validation("x")))
    }
}
