import Foundation

/// Per-environment settings, injected by Config/*.xcconfig through Info.plist.
struct AppConfig: Equatable, Sendable {
    enum Environment: String, Sendable {
        case dev, staging, prod
    }

    enum ConfigError: Error, Equatable {
        case missing(String)
        case invalid(String)
    }

    let environment: Environment
    let supabaseURL: URL
    /// Empty until Config/Secrets.xcconfig is filled in.
    let supabaseAnonKey: String
    /// Base URL of the transcribe API. Always ends with "/".
    let apiBaseURL: URL

    init(environment: Environment, supabaseURL: URL, supabaseAnonKey: String, apiBaseURL: URL) {
        self.environment = environment
        self.supabaseURL = supabaseURL
        self.supabaseAnonKey = supabaseAnonKey
        self.apiBaseURL = apiBaseURL
    }

    init(infoDictionary info: [String: Any]) throws {
        func string(_ key: String) throws -> String {
            guard let value = info[key] as? String else { throw ConfigError.missing(key) }
            return value.trimmingCharacters(in: .whitespaces)
        }
        func url(_ key: String) throws -> URL {
            let raw = try string(key)
            guard let url = URL(string: raw), url.scheme != nil, url.host() != nil else {
                throw ConfigError.invalid(key)
            }
            return url
        }

        guard let environment = Environment(rawValue: try string("BGTEnvironment")) else {
            throw ConfigError.invalid("BGTEnvironment")
        }
        self.environment = environment
        self.supabaseURL = try url("BGTSupabaseURL")
        self.supabaseAnonKey = try string("BGTSupabaseAnonKey")
        self.apiBaseURL = try url("BGTApiBaseURL")
    }
}
