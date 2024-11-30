import ArkavoSocial
import SwiftData
import SwiftUI

@main
struct ArkavoCreatorApp: App {
    let patreonClient = PatreonClient(config: PatreonConfig(
        clientId: Secrets.patreonClientId,
        clientSecret: Secrets.patreonClientSecret
    ))

    var body: some Scene {
        WindowGroup {
            ContentView(patreonClient: patreonClient)
        }
        .windowStyle(.hiddenTitleBar)
        .windowToolbarStyle(.unified)
    }
}
