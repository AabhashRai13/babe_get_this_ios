import CryptoKit
import Foundation

/// The nonce scheme shared by Google and Apple sign-in (Android `GoogleSignIn.kt`). The provider
/// gets the SHA-256 of a random raw nonce and signs it into the id token; Supabase gets the raw
/// nonce, hashes it and compares, so a token lifted from somewhere else can't be replayed.
enum IdTokenNonce {
    /// A fresh raw nonce per sign-in (Android uses a random UUID too).
    static func random() -> String {
        UUID().uuidString
    }

    /// Lowercase, zero-padded SHA-256 hex: exactly what Supabase computes. Any other encoding
    /// (uppercase, base64, unpadded bytes) fails every sign-in with a nonce mismatch.
    static func sha256Hex(_ value: String) -> String {
        SHA256.hash(data: Data(value.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}
