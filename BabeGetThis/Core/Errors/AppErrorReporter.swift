import Foundation

/// Receives every error `safeCall` maps, for crash reporting. What actually gets sent is the
/// implementation's decision; most of these are ordinary offline-first outcomes and are dropped.
/// Must not throw: a failure inside reporting must never turn a handled error into an unhandled one.
protocol AppErrorReporter: Sendable {
    func report(_ error: any Error, mapped: AppError)
}

/// Reports nothing. Used until crash reporting is wired in, and by tests that only check mapping.
struct SilentAppErrorReporter: AppErrorReporter {
    func report(_ error: any Error, mapped: AppError) {}
}
