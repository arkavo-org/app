import ArkavoSocial
import Foundation

/// Application configuration delegating to ArkavoConfiguration for identity settings
enum Config {
    // MARK: - Arkavo Service URLs

    static var arkavoAuthURL: URL { ArkavoConfiguration.shared.identityURL }
    static var arkavoWebSocketURL: URL { ArkavoConfiguration.shared.websocketURL }
    static var arkavoRelyingPartyID: String { ArkavoConfiguration.shared.relyingPartyID }

    // MARK: - Micropub Configuration

    static var micropubClientID: String { "https://app.arkavo.com/microblog-creator.json" }

    // MARK: - Debug Helpers

    /// Print current configuration (useful for debugging)
    static func printCurrentConfig() {
        print("""
        === Arkavo Configuration ===
        Auth URL: \(arkavoAuthURL.absoluteString)
        WebSocket URL: \(arkavoWebSocketURL.absoluteString)
        Relying Party ID: \(arkavoRelyingPartyID)
        Micropub Client ID: \(micropubClientID)
        ===========================
        """)
    }
}
