import ArkavoKit
import AuthenticationServices
import LocalAuthentication
import SwiftData
import SwiftUI

@MainActor
class WindowAccessor: ObservableObject {
    @Published var window: NSWindow?
    static let shared = WindowAccessor()

    private init() { /* Singleton: prevents external instantiation */ }
}

@main
struct ArkavoCreatorApp: App {
    @StateObject private var windowAccessor = WindowAccessor.shared

    let patreonClient = PatreonClient(clientId: Secrets.patreonClientId, clientSecret: Secrets.patreonClientSecret)
    let redditClient = RedditClient(clientId: Secrets.redditClientId)
    let micropubClient = MicropubClient(clientId: Config.micropubClientID)
    let blueskyClient: BlueskyClient = .init()
    let youtubeClient = YouTubeClient(
        clientId: Secrets.youtubeClientId,
        clientSecret: Secrets.youtubeClientSecret
    )
    let arkavoClient: ArkavoClient

    init() {
        arkavoClient = ArkavoClient(
            authURL: Config.arkavoAuthURL,
            websocketURL: Config.arkavoWebSocketURL,
            relyingPartyID: Config.arkavoRelyingPartyID,
            curve: .p256,
        )
        ViewModelFactory.shared.serviceLocator.register(arkavoClient)
        // TODO: Initialize router
//        let router = ArkavoMessageRouter(
//            client: client,
//            persistenceController: PersistenceController.shared
//        )
//        _messageRouter = StateObject(wrappedValue: router)
//        ViewModelFactory.shared.serviceLocator.register(router)
    }

    var body: some Scene {
        WindowGroup {
            ContentView(
                patreonClient: patreonClient,
                redditClient: redditClient,
                micropubClient: micropubClient,
                blueskyClient: blueskyClient,
                youtubeClient: youtubeClient,
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

                // Validate URL scheme and host
                guard url.scheme == "arkavocreator",
                      url.host == "oauth"
                else {
                    return
                }

                // Route OAuth callback to appropriate handler based on path
                switch url.path {
                case "/patreon":
                    // Handle Patreon OAuth callback
                    if let components = URLComponents(url: url, resolvingAgainstBaseURL: true),
                       let code = components.queryItems?.first(where: { $0.name == "code" })?.value
                    {
                        Task {
                            do {
                                let _ = try await patreonClient.exchangeCode(code)
                            } catch {
                                print("Patreon OAuth error: \(error)")
                            }
                        }
                    }

                case "/reddit":
                    // Post notification for Reddit OAuth callback
                    NotificationCenter.default.post(
                        name: Notification.Name("RedditOAuthCallback"),
                        object: nil,
                        userInfo: ["url": url]
                    )

                case "/youtube":
                    // Post notification for YouTube OAuth callback
                    NotificationCenter.default.post(
                        name: Notification.Name("YouTubeOAuthCallback"),
                        object: nil,
                        userInfo: ["url": url]
                    )

                case "/twitch":
                    // Post notification for Twitch OAuth callback
                    NotificationCenter.default.post(
                        name: Notification.Name("TwitchOAuthCallback"),
                        object: nil,
                        userInfo: ["url": url]
                    )

                case "/bluesky":
                    // Post notification for Bluesky OAuth callback (if needed)
                    NotificationCenter.default.post(
                        name: Notification.Name("BlueskyOAuthCallback"),
                        object: nil,
                        userInfo: ["url": url]
                    )

                case "/micropub":
                    // Post notification for Micropub OAuth callback
                    NotificationCenter.default.post(
                        name: Notification.Name("MicropubOAuthCallback"),
                        object: nil,
                        userInfo: ["url": url]
                    )

                default:
                    print("Unknown OAuth callback path: \(url.path)")
                }
            }
        }
        .windowStyle(.hiddenTitleBar)
        .windowToolbarStyle(.unified)
        // uncomment Screenshots
//        .defaultSize(width: 1280, height: 800)
//        .windowResizability(.contentMinSize)
        .commands {
            CommandGroup(after: .windowArrangement) {
                Button("Stream Monitor") {
                    StreamMonitorWindow.shared.toggle()
                }
                .keyboardShortcut("m", modifiers: [.command, .shift])
            }
        }
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

final class ServiceLocator {
    private var services: [String: Any] = [:]

    func register<T>(_ service: T) {
        let key = String(describing: T.self)
        services[key] = service
    }

    func resolve<T>() -> T {
        let key = String(describing: T.self)
        guard let service = services[key] as? T else {
            fatalError("No registered service for type \(T.self)")
        }
        return service
    }
}

final class ViewModelFactory {
    @MainActor public static let shared = ViewModelFactory(serviceLocator: ServiceLocator())
    public let serviceLocator: ServiceLocator
    private var messageDelegate: ArkavoMessageChainDelegate?

    private init(serviceLocator: ServiceLocator) {
        self.serviceLocator = serviceLocator
    }

    @MainActor
    func makeWorkflowViewModel() -> WorkflowViewModel {
        let client = serviceLocator.resolve() as ArkavoClient
        // Create message delegate if it doesn't exist
        if messageDelegate == nil {
            messageDelegate = ArkavoMessageChainDelegate(client: client, existingDelegate: nil)
        }
        return WorkflowViewModel(client: client, messageDelegate: messageDelegate!)
    }
}

class WebAuthnAuthenticationDelegate: NSObject, ASAuthorizationControllerDelegate {
    private let continuation: CheckedContinuation<ASAuthorizationPlatformPublicKeyCredentialAssertion, Error>

    init(continuation: CheckedContinuation<ASAuthorizationPlatformPublicKeyCredentialAssertion, Error>) {
        self.continuation = continuation
        super.init()
    }

    func authorizationController(controller _: ASAuthorizationController, didCompleteWithAuthorization authorization: ASAuthorization) {
        print("\n=== WebAuthn Authorization Completed ===")
        guard let credential = authorization.credential as? ASAuthorizationPlatformPublicKeyCredentialAssertion else {
            print("Error: Invalid credential type received")
            continuation.resume(throwing: ArkavoError.authenticationFailed("Invalid credential type"))
            return
        }
        continuation.resume(returning: credential)
    }

    func authorizationController(controller _: ASAuthorizationController, didCompleteWithError error: Error) {
        print("\n=== WebAuthn Authorization Error ===")
        print("Error occurred: \(error.localizedDescription)")
        if let authError = error as? ASAuthorizationError {
            print("Authorization Error Code: \(authError.code.rawValue)")
        }
        continuation.resume(throwing: error)
    }
}

// Helper classes to maintain strong references
private class DelegateBox {
    let delegate: AnyObject
    init(delegate: AnyObject) {
        self.delegate = delegate
    }
}

private enum AssociatedKeys {
    @MainActor static var delegateKey = "delegateKey"
    @MainActor static var providerKey = "providerKey"
}

class DefaultMacPresentationProvider: NSObject, ASAuthorizationControllerPresentationContextProviding {
    func presentationAnchor(for _: ASAuthorizationController) -> ASPresentationAnchor {
        print("Providing presentation anchor...")
        guard let window = NSApplication.shared.windows.first else {
            print("Warning: No window found, creating new window")
            return NSWindow()
        }
        print("Using window: \(window)")
        return window
    }
}
