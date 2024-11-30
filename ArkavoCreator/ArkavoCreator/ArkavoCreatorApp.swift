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
                .onOpenURL { url in
                    print("ac url: \(url.absoluteString)")
                    guard url.scheme == "arkavocreator",
                          url.host == "oauth",
                          url.path == "/patreon"
                    else {
                        return
                    }

                    if let components = URLComponents(url: url, resolvingAgainstBaseURL: true),
                       let code = components.queryItems?.first(where: { $0.name == "code" })?.value
                    {
                        Task {
                            do {
                                let token = try await patreonClient.exchangeCode(code)
                                // Handle successful token here
                                print("Received token: \(token.accessToken)")
                            } catch {
                                print("OAuth error: \(error)")
                            }
                        }
                    }
                }
        }
        .windowStyle(.hiddenTitleBar)
        .windowToolbarStyle(.unified)
    }
}
