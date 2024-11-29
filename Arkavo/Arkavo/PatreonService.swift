import Foundation
import ArkavoSocial

class PatreonService {
    let client: PatreonClient
    let config: PatreonConfig

    init() {
        config = PatreonConfig(
            clientId: Secrets.patreonClientId,
            clientSecret: Secrets.patreonClientSecret,
            creatorAccessToken: "",
            creatorRefreshToken: "",
            campaignId: KeychainManager.getCampaignId() ?? ""
        )
        client = PatreonClient(config: config)
    }
}
