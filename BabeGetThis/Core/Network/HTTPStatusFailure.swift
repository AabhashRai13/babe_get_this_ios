import Foundation

/// A non-2xx HTTP response from one of our own URLSession clients, the iOS stand-in for
/// Retrofit's `HttpException`. `safeCall` maps it by status code.
struct HTTPStatusFailure: Error, Equatable, Sendable {
    let statusCode: Int

    init(statusCode: Int) {
        self.statusCode = statusCode
    }

    /// Like Retrofit's message: a status line, never a body or headers.
    var statusLine: String { "HTTP \(statusCode)" }
}
