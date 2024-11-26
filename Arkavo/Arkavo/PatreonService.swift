import Foundation

class PatreonService {
    let client: PatreonClient
    let config: PatreonConfig

    init() {
        let secrets = ArkavoSecrets.shared
        config = PatreonConfig(
            clientId: secrets.patreonClientId,
            clientSecret: secrets.patreonClientSecret,
            creatorAccessToken: secrets.patreonCreatorAccessToken,
            creatorRefreshToken: secrets.patreonCreatorRefreshToken,
            campaignId: secrets.patreonCampaignId
        )
        client = PatreonClient(config: config)
    }
}
