import SwiftUI

// Decorative recording and transcribing animations (Android PebbleListeningIndicator.kt and
// TranscribingWaveform.kt). Both are pure drawing driven by elapsed time, hidden from
// VoiceOver, and hold still under Reduce Motion.

/// Compose's `CubicBezierEasing`: x(t) is solved for the fraction, y(t) is the eased value.
struct CubicBezierEasing: Sendable {
    let x1: Double, y1: Double, x2: Double, y2: Double

    /// `FastOutSlowInEasing`.
    static let fastOutSlowIn = CubicBezierEasing(x1: 0.4, y1: 0, x2: 0.2, y2: 1)
    /// `LinearOutSlowInEasing`.
    static let linearOutSlowIn = CubicBezierEasing(x1: 0, y1: 0, x2: 0.2, y2: 1)

    func callAsFunction(_ fraction: Double) -> Double {
        let x = min(max(fraction, 0), 1)
        if x == 0 || x == 1 { return x }
        // Bisection on x(t): monotonic for control points in [0, 1], and exact enough to draw.
        var low = 0.0, high = 1.0, t = x
        for _ in 0..<24 {
            let value = Self.bezier(t, x1, x2)
            if abs(value - x) < 1e-5 { break }
            if value < x { low = t } else { high = t }
            t = (low + high) / 2
        }
        return Self.bezier(t, y1, y2)
    }

    private static func bezier(_ t: Double, _ p1: Double, _ p2: Double) -> Double {
        let u = 1 - t
        return 3 * u * u * t * p1 + 3 * u * t * t * p2 + t * t * t
    }
}

/// Compose `infiniteRepeatable` timing, as a function of seconds since the animation started.
enum RepeatingTween {
    /// `RepeatMode.Restart` with a start delay: 0 until `delay`, then 0→1 every `duration`.
    static func restart(_ elapsed: Double, duration: Double, delay: Double = 0,
                        easing: (Double) -> Double = { $0 }) -> Double {
        guard elapsed >= delay else { return 0 }
        return easing((elapsed - delay).truncatingRemainder(dividingBy: duration) / duration)
    }

    /// `RepeatMode.Reverse`: 0→1 over `duration`, then back, forever. `offset` is a
    /// fast-forward start offset (`StartOffsetType.FastForward`).
    static func reverse(_ elapsed: Double, duration: Double, offset: Double = 0,
                        easing: (Double) -> Double = { $0 }) -> Double {
        let phase = (elapsed + offset).truncatingRemainder(dividingBy: 2 * duration) / duration
        return phase <= 1 ? easing(phase) : easing(2 - phase)
    }
}

// MARK: - Recording: the pebble mascot

/// Blinking mascot face inside the recorder circle, breathing scale, pulsing sound rings and
/// floating hearts. Drawn in a 240×240 design space scaled to fit; the circle is 107 wide and
/// the rest is headroom for the rings and hearts.
struct PebbleListeningIndicator: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var startedAt = Date()

    var body: some View {
        TimelineView(.animation(paused: reduceMotion)) { timeline in
            Canvas { context, size in
                // Reduce Motion: the first frame, which is the calm resting pose (no rings or
                // hearts yet, eyes open).
                let elapsed = reduceMotion ? 0 : max(0, timeline.date.timeIntervalSince(startedAt))
                PebbleDrawing(frame: .init(elapsed: elapsed)).draw(in: &context, size: size)
            }
        }
        .accessibilityHidden(true)
    }
}

/// Every animated value at one instant, matching the Android transition specs.
struct PebbleFrame: Equatable {
    var rings: [Double]
    var hearts: [Double]
    var breathe: Double
    var bob: Double
    var blink: Double

    init(elapsed t: Double) {
        let ease = CubicBezierEasing.linearOutSlowIn
        rings = [0, 0.8, 1.6].map { RepeatingTween.restart(t, duration: 2.4, delay: $0, easing: ease.callAsFunction) }
        hearts = [0, 1.6].map { RepeatingTween.restart(t, duration: 3.2, delay: $0) }
        breathe = 1 + 0.06 * RepeatingTween.reverse(t, duration: 1.2, easing: ease.callAsFunction)
        bob = 2 - 5 * RepeatingTween.reverse(t, duration: 1.1, easing: ease.callAsFunction)
        // Eyes open for most of a 3.4 s cycle, then a quick squash.
        let ms = t.truncatingRemainder(dividingBy: 3.4) * 1000
        blink = switch ms {
        case ..<3094: 1
        case ..<3196: 1 - 0.88 * (ms - 3094) / 102
        default: 0.12 + 0.88 * (ms - 3196) / 204
        }
    }
}

private struct PebbleDrawing {
    let frame: PebbleFrame

    private let center = CGPoint(x: 120, y: 120)
    private let radius: CGFloat = 107 / 2

    func draw(in context: inout GraphicsContext, size: CGSize) {
        let scale = min(size.width, size.height) / 240
        context.translateBy(x: (size.width - 240 * scale) / 2, y: (size.height - 240 * scale) / 2)
        context.scaleBy(x: scale, y: scale)

        // Pulsing rings, fading out as they expand.
        for ring in frame.rings where ring > 0 && ring < 1 {
            let r = radius * (1 + 1.05 * ring)
            context.stroke(circle(center, r), with: .color(AppColors.pebbleSlate.opacity(0.4 * (1 - ring))), lineWidth: 2)
        }

        heart(frame.hearts[0], x: 74, baseY: 44, width: 18, color: AppColors.pebbleSlate, in: context)
        heart(frame.hearts[1], x: 148, baseY: 52, width: 13, color: AppColors.pebbleBlush, in: context)

        // The circle breathes gently while listening, and the face bobs with it.
        var body = context
        scaleAround(&body, center, frame.breathe, frame.breathe)
        body.fill(circle(center, radius), with: .color(AppColors.pebbleSlate))
        body.translateBy(x: 0, y: frame.bob)
        face(in: body)
    }

    private func face(in context: GraphicsContext) {
        let faceTop = center.y - 23

        // Brows: "M4 14 Q 20 2 36 12" in a 40×18 box, scaled to 22 wide.
        let brow: CGFloat = 22 / 40
        for (left, flip) in [(center.x - 8 - 22, false), (center.x + 8, true)] {
            var path = Path()
            let startX: CGFloat = flip ? 36 : 4, endX: CGFloat = flip ? 4 : 36
            path.move(to: CGPoint(x: left + startX * brow, y: faceTop + 14 * brow))
            path.addQuadCurve(to: CGPoint(x: left + endX * brow, y: faceTop + 12 * brow),
                              control: CGPoint(x: left + 20 * brow, y: faceTop + 2 * brow))
            context.stroke(path, with: .color(AppColors.pebbleCream), style: StrokeStyle(lineWidth: 5 * brow, lineCap: .round))
        }

        // Eyes: 20 wide, 10 apart, just below the brows; they blink by squashing vertically.
        let eyeTop = faceTop + 12
        let eyeRadius: CGFloat = 10
        for side: CGFloat in [-1, 1] {
            let eye = CGPoint(x: center.x + side * (5 + eyeRadius), y: eyeTop + eyeRadius)
            var lid = context
            scaleAround(&lid, eye, 1, frame.blink)
            lid.fill(circle(eye, eyeRadius), with: .color(AppColors.pebbleEye))
            let pupilRadius = 0.48 * eyeRadius
            let pupil = CGPoint(x: eye.x, y: eye.y - 0.04 * eyeRadius)
            lid.fill(circle(pupil, pupilRadius), with: .color(AppColors.pebblePupil))
            let glint = CGPoint(x: pupil.x - 0.34 * pupilRadius, y: pupil.y - 0.42 * pupilRadius)
            lid.fill(circle(glint, 0.34 * pupilRadius), with: .color(AppColors.pebbleEye))
        }

        // Blush: soft 11×7 ovals overlapping the bottom of the eye row.
        let blushY = eyeTop + 2 * eyeRadius + 1
        for side: CGFloat in [-1, 1] {
            let blush = CGPoint(x: center.x + side * (17 + 5.5), y: blushY)
            var cheek = context
            scaleAround(&cheek, blush, 1, 7 / 11)
            let gradient = Gradient(stops: [
                .init(color: AppColors.pebbleBlush.opacity(0.9), location: 0.55),
                .init(color: AppColors.pebbleBlush.opacity(0), location: 1),
            ])
            cheek.fill(circle(blush, 5.5), with: .radialGradient(gradient, center: blush, startRadius: 0, endRadius: 5.5))
        }

        // Smile: "M5 5 Q 20 18 35 5" in a 40×20 box, scaled to 20 wide.
        let smile: CGFloat = 20 / 40
        let smileLeft = center.x - 10, smileTop = blushY + 5
        var path = Path()
        path.move(to: CGPoint(x: smileLeft + 5 * smile, y: smileTop + 5 * smile))
        path.addQuadCurve(to: CGPoint(x: smileLeft + 35 * smile, y: smileTop + 5 * smile),
                          control: CGPoint(x: smileLeft + 20 * smile, y: smileTop + 18 * smile))
        context.stroke(path, with: .color(AppColors.pebbleCream), style: StrokeStyle(lineWidth: 5 * smile, lineCap: .round))
    }

    /// A heart rising 78 points while it fades in then out, growing from 0.5× to 1.05×.
    private func heart(_ progress: Double, x: CGFloat, baseY: CGFloat, width: CGFloat, color: Color,
                       in context: GraphicsContext) {
        guard progress > 0, progress < 1 else { return }
        let alpha = progress < 0.18 ? progress / 0.18 * 0.95 : 0.95 * (1 - (progress - 0.18) / 0.82)
        let y = baseY - 78 * progress
        let unit = width / 40
        func p(_ px: CGFloat, _ py: CGFloat) -> CGPoint { CGPoint(x: x + px * unit, y: y + py * unit) }
        var path = Path()
        path.move(to: p(20, 34))
        path.addCurve(to: p(2, 10.5), control1: p(7, 24), control2: p(2, 17))
        path.addCurve(to: p(10.5, 2), control1: p(2, 5), control2: p(6, 2))
        path.addCurve(to: p(20, 8), control1: p(14.5, 2), control2: p(18, 4.5))
        path.addCurve(to: p(29.5, 2), control1: p(22, 4.5), control2: p(25.5, 2))
        path.addCurve(to: p(38, 10.5), control1: p(34, 2), control2: p(38, 5))
        path.addCurve(to: p(20, 34), control1: p(38, 17), control2: p(33, 24))
        path.closeSubpath()
        var layer = context
        let grow = 0.5 + 0.55 * progress
        scaleAround(&layer, CGPoint(x: x + width / 2, y: y + width * 0.45), grow, grow)
        layer.fill(path, with: .color(color.opacity(alpha)))
    }

    private func circle(_ center: CGPoint, _ radius: CGFloat) -> Path {
        Path(ellipseIn: CGRect(x: center.x - radius, y: center.y - radius, width: 2 * radius, height: 2 * radius))
    }

    private func scaleAround(_ context: inout GraphicsContext, _ pivot: CGPoint, _ sx: CGFloat, _ sy: CGFloat) {
        context.translateBy(x: pivot.x, y: pivot.y)
        context.scaleBy(x: sx, y: sy)
        context.translateBy(x: -pivot.x, y: -pivot.y)
    }
}

// MARK: - Transcribing: the 5-bar waveform

/// Looping equaliser bars while the audio is transcribed. Not a live level: recording has
/// stopped and the backend reports no progress, so this only says "working on it". Each bar
/// pulses on a reversing loop with a per-bar offset, so they ripple rather than move together.
struct TranscribingWaveform: View {
    static let barCount = 5
    /// Height fractions held under Reduce Motion: a still, recognisable waveform.
    static let restingFractions: [Double] = [0.5, 0.8, 1, 0.8, 0.5]

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var startedAt = Date()

    /// Bar `index`'s height fraction `elapsed` seconds in: 0.3→1 over 600 ms, reversing,
    /// each bar fast-forwarded 120 ms past the previous one.
    static func fraction(bar index: Int, elapsed: Double) -> Double {
        0.3 + 0.7 * RepeatingTween.reverse(elapsed, duration: 0.6, offset: Double(index) * 0.12,
                                           easing: CubicBezierEasing.fastOutSlowIn.callAsFunction)
    }

    var body: some View {
        TimelineView(.animation(paused: reduceMotion)) { timeline in
            let elapsed = timeline.date.timeIntervalSince(startedAt)
            HStack(alignment: .center, spacing: 6) {
                ForEach(0..<Self.barCount, id: \.self) { index in
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(AppColors.primary)
                        .frame(width: 6, height: 40 * (reduceMotion
                            ? Self.restingFractions[index]
                            : Self.fraction(bar: index, elapsed: elapsed)))
                }
            }
            .frame(height: 40)
        }
        .accessibilityHidden(true)
    }
}
