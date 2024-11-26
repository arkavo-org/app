import Foundation

enum ArkavoConfiguration {
    private enum Keys {
        #if DEBUG
            static let patreonClientId = ArkavoSecrets.shared.patreonClientId
            static let patreonClientSecret = ArkavoSecrets.shared.patreonClientSecret
        #else
            // Values injected at build time via -D compiler flags
            static let patreonClientId = PATREON_CLIENT_ID // Will be replaced by actual value
            static let patreonClientSecret = PATREON_CLIENT_SECRET // Will be replaced by actual value
        #endif
    }

    static let patreonClientId: String = Keys.patreonClientId
    static let patreonClientSecret: String = Keys.patreonClientSecret
}

struct ArkavoSecrets {
    static let shared = ArkavoSecrets()

    let patreonClientId: String
    let patreonClientSecret: String
    let patreonCreatorAccessToken: String
    let patreonCreatorRefreshToken: String
    let patreonCampaignId: String

    private init() {
        // Read from Secrets.xcconfig bundle
        guard let path = Bundle.main.path(forResource: "Secrets", ofType: "xcconfig"),
              let config = try? String(contentsOfFile: path, encoding: .utf8)
        else {
            fatalError("Secrets.xcconfig not found")
        }

        let lines = config.components(separatedBy: .newlines)
        var secrets: [String: String] = [:]

        for line in lines {
            let parts = line.components(separatedBy: "=").map { $0.trimmingCharacters(in: .whitespaces) }
            if parts.count == 2 {
                secrets[parts[0]] = parts[1]
            }
        }

        // Extract values with default empty strings
        patreonClientId = secrets["PATREON_CLIENT_ID"] ?? ""
        patreonClientSecret = secrets["PATREON_CLIENT_SECRET"] ?? ""
        patreonCreatorAccessToken = secrets["PATREON_CREATOR_ACCESS_TOKEN"] ?? ""
        patreonCreatorRefreshToken = secrets["PATREON_CREATOR_REFRESH_TOKEN"] ?? ""
        patreonCampaignId = secrets["PATREON_CAMPAIGN_ID"] ?? ""
    }
}
