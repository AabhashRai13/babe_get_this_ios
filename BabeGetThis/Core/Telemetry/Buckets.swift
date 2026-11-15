import Foundation

/// Unbounded numbers become bounded labels here, and only here (port of Android `Buckets.kt`).
/// A raw count would spread one question over hundreds of one-user dimension values, and at
/// the tail it identifies a person. Call sites pass real numbers; the edges live here.
enum Buckets {
    /// Counts: items in a list, items from one utterance, pending sync operations.
    static func count(_ count: Int) -> String {
        switch count {
        case ...0: "0"
        case 1: "1"
        case ...5: "2-5"
        case ...10: "6-10"
        case ...20: "11-20"
        case ...50: "21-50"
        default: "50+"
        }
    }

    /// Durations: recording length, transcription latency. Under 1s is a mis-tap; over 10s is
    /// where users assume the app has hung. A negative duration (a clock moved back) is unknown.
    static func millis(_ millis: Int64) -> String {
        switch millis {
        case ..<0: "unknown"
        case ..<1_000: "<1s"
        case ..<3_000: "1-3s"
        case ..<5_000: "3-5s"
        case ..<10_000: "5-10s"
        case ..<30_000: "10-30s"
        default: "30s+"
        }
    }

    /// How long ago an item was last bought. Edges follow the hint windows (3, 5, 14, 30 days).
    static func daysAgo(_ days: Int) -> String {
        switch days {
        case ...0: "0"
        case 1: "1"
        case ...3: "2-3"
        case ...7: "4-7"
        case ...14: "8-14"
        case ...30: "15-30"
        default: "30+"
        }
    }

    /// Bought day minus predicted day. "-2..2" is the band we call right.
    static func errorDays(_ days: Int) -> String {
        switch days {
        case ..<(-7): "<-7"
        case ..<(-2): "-7..-3"
        case ...2: "-2..2"
        case ...7: "3..7"
        default: ">7"
        }
    }
}
