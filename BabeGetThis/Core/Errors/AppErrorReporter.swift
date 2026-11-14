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

/// A reporter built from a closure (Android `ErrorReporter`). The app wires it to
/// `CrashReporter.recordNonFatal`, which applies `ErrorReportingPolicy` (ERR-03). A closure
/// that throws is contained here: telemetry that can break the app it watches is worse than
/// telemetry that misses a report.
struct ErrorReporter: AppErrorReporter {
    private let body: @Sendable (any Error, AppError) throws -> Void

    init(_ body: @escaping @Sendable (any Error, AppError) throws -> Void) {
        self.body = body
    }

    /// Hands every mapped error to `crashReporter`, which filters it.
    init(crashReporter: any CrashReporter) {
        self.init { error, mapped in crashReporter.recordNonFatal(error, appError: mapped) }
    }

    func report(_ error: any Error, mapped: AppError) {
        try? body(error, mapped)
    }
}
