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

    let patreonClient = PatreonClient(clientId: Secrets.patreonClientId, clientSecret: Secrets.patreonClientSecret)
    let redditClient = RedditClient(clientId: Secrets.redditClientId)
    let micropubClient = MicropubClient(clientId: "https://app.arkavo.com/microblog-creator.json")
    let blueskyClient: BlueskyClient = .init()
    let youtubeClient = YouTubeClient(
        clientId: Secrets.youtubeClientId,
        clientSecret: Secrets.youtubeClientSecret,
        redirectUri: "urn:ietf:wg:oauth:2.0:oob"
    )

    var body: some Scene {
        WindowGroup {
            ContentView(
                patreonClient: patreonClient,
                redditClient: redditClient,
                micropubClient: micropubClient,
                blueskyClient: blueskyClient,
                youtubeClient: youtubeClient
            )
            .onAppear {
                // Load stored tokens
                redditClient.loadStoredTokens()
                micropubClient.loadStoredTokens()
                // uncomment for Screenshots
//                if let window = NSApplication.shared.windows.first {
//                    window.setContentSize(NSSize(width: 1280, height: 800))
//                    window.styleMask.remove(.resizable)
//                }
//                // Create a timer to take screenshots
//                if let window = NSApplication.shared.windows.first {
//                    window.setContentSize(NSSize(width: 1280, height: 800))
//                    window.styleMask.remove(.resizable)
//
//                    // Create a timer to take screenshots
//                    Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { timer in
//                        Task { @MainActor in
//                            if let view = window.contentView {
//                                let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds)!
//                                view.cacheDisplay(in: view.bounds, to: rep)
//
//                                // Create NSImage with no alpha
//                                let image = NSImage(size: view.bounds.size)
//                                image.addRepresentation(rep)
//
//                                // Convert to PNG data without alpha
//                                if let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil),
//                                   let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
//                                   let bitmapContext = CGContext(
//                                       data: nil,
//                                       width: Int(view.bounds.width),
//                                       height: Int(view.bounds.height),
//                                       bitsPerComponent: 8,
//                                       bytesPerRow: 0,
//                                       space: colorSpace,
//                                       bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
//                                   ) {
//                                    bitmapContext.draw(cgImage, in: CGRect(origin: .zero, size: view.bounds.size))
//                                    if let finalImage = bitmapContext.makeImage(),
//                                       let data = NSBitmapImageRep(cgImage: finalImage).representation(using: .png, properties: [:]) {
//                                        // Save to desktop with timestamp
//                                        let timestamp = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .medium)
//                                            .replacingOccurrences(of: ":", with: "-")
//                                        let desktopURL = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask)[0]
//                                        let fileURL = desktopURL.appendingPathComponent("app_screenshot_\(timestamp).png")
//                                        try? data.write(to: fileURL)
//                                    }
//                                }
//                            }
//                        }
//                    }
//                }
                // Set up window accessor
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

                if url.path == "/patreon" {
                    if let components = URLComponents(url: url, resolvingAgainstBaseURL: true),
                       let code = components.queryItems?.first(where: { $0.name == "code" })?.value
                    {
                        Task {
                            do {
                                let _ = try await patreonClient.exchangeCode(code)
                            } catch {
                                print("OAuth error: \(error)")
                            }
                        }
                    }
                } else if url.path == "/reddit" {
                    // Create a NotificationCenter name for Reddit OAuth callback
                    let notificationName = Notification.Name("RedditOAuthCallback")
                    // Post the URL to any listeners
                    NotificationCenter.default.post(
                        name: notificationName,
                        object: nil,
                        userInfo: ["url": url]
                    )
                }
            }
        }
        .windowStyle(.hiddenTitleBar)
        .windowToolbarStyle(.unified)
        // uncomment Screenshots
//        .defaultSize(width: 1280, height: 800)
//        .windowResizability(.contentMinSize)
    }
}

// MARK: - App State for Feedback

class AppState: ObservableObject {
    @Published var isFeedbackEnabled: Bool {
        didSet {
            UserDefaults.standard.set(isFeedbackEnabled, forKey: "isFeedbackEnabled")
        }
    }

    init() {
        // Default to enabled if no value is set
        isFeedbackEnabled = UserDefaults.standard.object(forKey: "isFeedbackEnabled") as? Bool ?? true
    }
}
