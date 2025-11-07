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
    @StateObject private var webAuthnManager: WebAuthnManager
    @StateObject private var messagingViewModel: MessagingViewModel

    let arkavoClient: ArkavoClient

    init() {
        // Initialize Arkavo client with WebAuthn support
        let client = ArkavoClient(
            authURL: URL(string: "https://webauthn.arkavo.net")!,
            websocketURL: URL(string: "wss://100.arkavo.net")!,
            relyingPartyID: "webauthn.arkavo.net",
            curve: .p256
        )
        arkavoClient = client
        ViewModelFactory.shared.serviceLocator.register(client)

        // Initialize WebAuthn manager
        _webAuthnManager = StateObject(wrappedValue: WebAuthnManager(arkavoClient: client))

        // Initialize messaging view model
        _messagingViewModel = StateObject(wrappedValue: MessagingViewModel(arkavoClient: client))
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appState)
                .environmentObject(webAuthnManager)
                .environmentObject(messagingViewModel)
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
                .onChange(of: appState.currentUser) { _, newUser in
                    // Update messaging view model with current user
                    if let user = newUser {
                        messagingViewModel.setCurrentUser(userId: user, userName: user)
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

// MARK: - WebAuthn Manager

@MainActor
class WebAuthnManager: ObservableObject {
    @Published var isAuthenticating = false
    @Published var authError: String?

    private let arkavoClient: ArkavoClient

    init(arkavoClient: ArkavoClient) {
        self.arkavoClient = arkavoClient
    }

    /// Register a new user with passkey
    func register(handle: String) async throws {
        isAuthenticating = true
        authError = nil

        defer {
            isAuthenticating = false
        }

        do {
            // Generate DID for the user
            let did = try arkavoClient.generateDID()

            // Register with WebAuthn
            let token = try await arkavoClient.registerUser(handle: handle, did: did)

            // Token is returned, registration successful
            print("Registration successful, token received")
        } catch {
            authError = handleAuthError(error)
            throw error
        }
    }

    /// Authenticate existing user with passkey
    func authenticate(accountName: String) async throws {
        isAuthenticating = true
        authError = nil

        defer {
            isAuthenticating = false
        }

        do {
            // Connect will authenticate and establish WebSocket connection
            try await arkavoClient.connect(accountName: accountName)
            print("Authentication and connection successful")
        } catch {
            authError = handleAuthError(error)
            throw error
        }
    }

    /// Sign out the current user
    func signOut() async {
        await arkavoClient.disconnect()
    }

    /// Check if user is currently connected
    var isConnected: Bool {
        arkavoClient.currentState == .connected
    }

    /// Handle authentication errors and provide user-friendly messages
    private func handleAuthError(_ error: Error) -> String {
        if let arkavoError = error as? ArkavoError {
            switch arkavoError {
            case .authenticationFailed(let message):
                if message.contains("User Not Found") {
                    return "Account not found. Please register first."
                }
                return message
            case .connectionFailed(let message):
                return "Connection failed: \(message)"
            case .invalidResponse:
                return "Invalid response from server"
            default:
                return error.localizedDescription
            }
        }

        // Handle NSError codes
        let nsError = error as NSError
        if nsError.code == -25300 {
            // Duplicate passkey error
            return "A passkey already exists. Please delete existing passkeys from Settings → Passwords."
        } else if nsError.code == 1001 { // ASAuthorizationError.canceled
            return "Authentication cancelled"
        }

        return error.localizedDescription
    }
}
