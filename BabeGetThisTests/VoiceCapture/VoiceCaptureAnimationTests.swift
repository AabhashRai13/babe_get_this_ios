import XCTest
@testable import BabeGetThis

// Timing of the decorative voice animations, checked against the Android transition specs.
final class VoiceCaptureAnimationTests: XCTestCase {
    func testEasingsStartAndEndOnTheirEndpointsAndOnlyRise() {
        for easing in [CubicBezierEasing.fastOutSlowIn, .linearOutSlowIn] {
            XCTAssertEqual(easing(0), 0)
            XCTAssertEqual(easing(1), 1)
            var previous = 0.0
            for step in 1...20 {
                let value = easing(Double(step) / 20)
                XCTAssertGreaterThanOrEqual(value, previous - 1e-6)
                previous = value
            }
        }
        // Slow-in: well past halfway at the halfway point.
        XCTAssertGreaterThan(CubicBezierEasing.linearOutSlowIn(0.5), 0.7)
    }

    // The still pose shown under Reduce Motion (and the first frame): no rings or hearts yet,
    // eyes open, circle at rest.
    func testTheFirstPebbleFrameIsTheRestingPose() {
        let frame = PebbleFrame(elapsed: 0)
        XCTAssertEqual(frame.rings, [0, 0, 0])
        XCTAssertEqual(frame.hearts, [0, 0])
        XCTAssertEqual(frame.breathe, 1)
        XCTAssertEqual(frame.bob, 2)
        XCTAssertEqual(frame.blink, 1)
    }

    func testPebbleRingsAreStaggeredAndTheEyesBlinkNearTheEndOfEachCycle() {
        let frame = PebbleFrame(elapsed: 1.2)
        XCTAssertGreaterThan(frame.rings[0], frame.rings[1])
        XCTAssertGreaterThan(frame.rings[1], 0)
        XCTAssertEqual(frame.rings[2], 0)
        XCTAssertEqual(PebbleFrame(elapsed: 3.196).blink, 0.12, accuracy: 0.01)
        XCTAssertEqual(PebbleFrame(elapsed: 3.4 + 1).blink, 1)
    }

    func testWaveformBarsStayBetween30And100PercentAndRipple() {
        for step in 0..<60 {
            for bar in 0..<TranscribingWaveform.barCount {
                let value = TranscribingWaveform.fraction(bar: bar, elapsed: Double(step) * 0.05)
                XCTAssertGreaterThanOrEqual(value, 0.3 - 1e-9)
                XCTAssertLessThanOrEqual(value, 1 + 1e-9)
            }
        }
        XCTAssertNotEqual(TranscribingWaveform.fraction(bar: 0, elapsed: 0), TranscribingWaveform.fraction(bar: 2, elapsed: 0))
        XCTAssertEqual(TranscribingWaveform.restingFractions.count, TranscribingWaveform.barCount)
    }
}
