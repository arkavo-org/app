import Foundation

class PatreonService {
    let client: PatreonClient
    
    init() {
        let secrets = AppSecrets.shared
        let config = PatreonConfig(
            clientId: secrets.patreonClientId,
            clientSecret: secrets.patreonClientSecret,
            creatorAccessToken: secrets.patreonCreatorAccessToken,
            creatorRefreshToken: secrets.patreonCreatorRefreshToken,
            redirectURI: secrets.patreonRedirectURI,
            campaignId: secrets.patreonCampaignId
        )
        self.client = PatreonClient(config: config)
    }
}

struct AppSecrets {
    static let shared = AppSecrets()
    
    let patreonClientId: String
    let patreonClientSecret: String
    let patreonCreatorAccessToken: String
    let patreonCreatorRefreshToken: String
    let patreonCampaignId: String
    let patreonRedirectURI: String
    
    private init() {
        // Read from Secrets.xcconfig bundle
        guard let path = Bundle.main.path(forResource: "Secrets", ofType: "xcconfig"),
              let config = try? String(contentsOfFile: path, encoding: .utf8) else {
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
        patreonRedirectURI = secrets["PATREON_REDIRECT_URI"] ?? ""
    }
}
