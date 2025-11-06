import ArkavoAgent
import ArkavoSocial
import AuthenticationServices
import SwiftData
import SwiftUI

@MainActor
class WindowAccessor: ObservableObject {
    @Published var window: NSWindow?
    static let shared = WindowAccessor()

    private init() {}
}

@main
struct HYPERforumApp: App {
    @StateObject private var windowAccessor = WindowAccessor.shared
    @StateObject private var appState = AppState()

    let arkavoClient: ArkavoClient

    init() {
        // Initialize Arkavo client with WebAuthn support
        arkavoClient = ArkavoClient(
            authURL: URL(string: "https://webauthn.arkavo.net")!,
            websocketURL: URL(string: "wss://100.arkavo.net")!,
            relyingPartyID: "webauthn.arkavo.net",
            curve: .p256
        )
        ViewModelFactory.shared.serviceLocator.register(arkavoClient)
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appState)
                .onAppear {
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
        }
        .windowStyle(.hiddenTitleBar)
        .windowToolbarStyle(.unified)
        .defaultSize(width: 1200, height: 800)
        .commands {
            // Custom menu commands can be added here
        }
    }
}

// MARK: - App State

class AppState: ObservableObject {
    @Published var isAuthenticated: Bool = false
    @Published var currentUser: String?
    @Published var selectedGroup: String?
    @Published var showCouncil: Bool = false

    init() {
        // Load saved state if needed
        isAuthenticated = UserDefaults.standard.bool(forKey: "isAuthenticated")
        currentUser = UserDefaults.standard.string(forKey: "currentUser")
    }

    func signIn(user: String) {
        isAuthenticated = true
        currentUser = user
        UserDefaults.standard.set(true, forKey: "isAuthenticated")
        UserDefaults.standard.set(user, forKey: "currentUser")
    }

    func signOut() {
        isAuthenticated = false
        currentUser = nil
        selectedGroup = nil
        UserDefaults.standard.removeObject(forKey: "isAuthenticated")
        UserDefaults.standard.removeObject(forKey: "currentUser")
    }
}

// MARK: - Service Locator

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

// MARK: - View Model Factory

final class ViewModelFactory {
    @MainActor public static let shared = ViewModelFactory(serviceLocator: ServiceLocator())
    public let serviceLocator: ServiceLocator

    private init(serviceLocator: ServiceLocator) {
        self.serviceLocator = serviceLocator
    }

    @MainActor
    func makeForumViewModel() -> ForumViewModel {
        let client = serviceLocator.resolve() as ArkavoClient
        return ForumViewModel(client: client)
    }
}

// MARK: - WebAuthn Support

class DefaultMacPresentationProvider: NSObject, ASAuthorizationControllerPresentationContextProviding {
    func presentationAnchor(for _: ASAuthorizationController) -> ASPresentationAnchor {
        guard let window = NSApplication.shared.windows.first else {
            return NSWindow()
        }
        return window
    }
}
