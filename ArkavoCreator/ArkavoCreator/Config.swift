import Foundation

/// Environment configuration for the Arkavo Creator app
enum AppEnvironment {
    case development
    case staging
    case production

    /// Current environment based on build configuration
    static var current: AppEnvironment {
        #if DEBUG
        return .development
        #else
        return .production
        #endif
    }

    /// Override environment via environment variable for testing
    /// Set ARKAVO_ENV to "development", "staging", or "production"
    static var override: AppEnvironment? {
        guard let envString = ProcessInfo.processInfo.environment["ARKAVO_ENV"] else {
            return nil
        }
        switch envString.lowercased() {
        case "development", "dev":
            return .development
        case "staging", "stage":
            return .staging
        case "production", "prod":
            return .production
        default:
            return nil
        }
    }

    /// Active environment (override takes precedence)
    static var active: AppEnvironment {
        return override ?? current
    }
}

/// Application configuration based on environment
enum Config {

    // MARK: - Arkavo Service URLs

    static var arkavoAuthURL: URL {
        switch AppEnvironment.active {
        case .development:
            return URL(string: "https://webauthn.dev.arkavo.net")!
        case .staging:
            return URL(string: "https://webauthn.staging.arkavo.net")!
        case .production:
            return URL(string: "https://webauthn.arkavo.net")!
        }
    }

    static var arkavoWebSocketURL: URL {
        switch AppEnvironment.active {
        case .development:
            return URL(string: "wss://100.dev.arkavo.net")!
        case .staging:
            return URL(string: "wss://100.staging.arkavo.net")!
        case .production:
            return URL(string: "wss://100.arkavo.net")!
        }
    }

    static var arkavoRelyingPartyID: String {
        switch AppEnvironment.active {
        case .development:
            return "webauthn.dev.arkavo.net"
        case .staging:
            return "webauthn.staging.arkavo.net"
        case .production:
            return "webauthn.arkavo.net"
        }
    }

    // MARK: - Micropub Configuration

    static var micropubClientID: String {
        switch AppEnvironment.active {
        case .development:
            return "https://app.dev.arkavo.com/microblog-creator.json"
        case .staging:
            return "https://app.staging.arkavo.com/microblog-creator.json"
        case .production:
            return "https://app.arkavo.com/microblog-creator.json"
        }
    }

    // MARK: - Debug Helpers

    /// Print current configuration (useful for debugging)
    static func printCurrentConfig() {
        print("""
        === Arkavo Configuration ===
        Environment: \(AppEnvironment.active)
        Auth URL: \(arkavoAuthURL.absoluteString)
        WebSocket URL: \(arkavoWebSocketURL.absoluteString)
        Relying Party ID: \(arkavoRelyingPartyID)
        Micropub Client ID: \(micropubClientID)
        ===========================
        """)
    }
}
