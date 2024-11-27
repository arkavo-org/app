import Foundation

class PatreonService {
    let client: PatreonClient
    let config: PatreonConfig

    init() {
        config = PatreonConfig(
            clientId: Secrets.patreonClientId,
            clientSecret: Secrets.patreonClientSecret,
            creatorAccessToken: "",
            creatorRefreshToken: "",
            campaignId: ""
        )
        client = PatreonClient(config: config)
    }
}
