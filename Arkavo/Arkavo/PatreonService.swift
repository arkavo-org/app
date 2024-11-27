import Foundation

class PatreonService {
    let client: PatreonClient
    let config: PatreonConfig

    init() {
        config = PatreonConfig(
            clientId: ArkavoConfiguration.patreonClientId,
            clientSecret: ArkavoConfiguration.patreonClientSecret,
            creatorAccessToken: "", // These values should be handled separately
            creatorRefreshToken: "", // perhaps through secure storage or auth flow
            campaignId: ""
        )
        client = PatreonClient(config: config)
    }
}
