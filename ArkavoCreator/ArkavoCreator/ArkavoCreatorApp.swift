import ArkavoSocial
import SwiftData
import SwiftUI

@MainActor
class WindowAccessor: ObservableObject {
    @Published var window: NSWindow?
    static let shared = WindowAccessor()

    private init() {}
}

@main
struct ArkavoCreatorApp: App {
    @StateObject private var windowAccessor = WindowAccessor.shared

    let patreonClient = PatreonClient(config: PatreonConfig(
        clientId: Secrets.patreonClientId,
        clientSecret: Secrets.patreonClientSecret
    ))

    var body: some Scene {
        WindowGroup {
            ContentView(patreonClient: patreonClient)
                .onAppear {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        windowAccessor.window = NSApplication.shared.windows.first { $0.isVisible }
                    }
                }
                .onChange(of: NSApplication.shared.windows) { _, newValue in
                    if windowAccessor.window == nil {
                        windowAccessor.window = newValue.first { $0.isVisible }
                    }
                }
        }
        .windowStyle(.hiddenTitleBar)
        .windowToolbarStyle(.unified)
    }
}
