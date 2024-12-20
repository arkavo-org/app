import ArkavoSocial
import SwiftUI

@main
struct ArkavoApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @State private var navigationPath = NavigationPath()
    @State private var selectedView: AppView = .registration
    @State private var isCheckingAccountStatus = false
    @State private var tokenCheckTimer: Timer?
    @State private var connectionError: ConnectionError?
    let persistenceController = PersistenceController.shared
    let client: ArkavoClient

    init() {
        client = ArkavoClient(
            authURL: URL(string: "https://webauthn.arkavo.net")!,
            websocketURL: URL(string: "wss://kas.arkavo.net")!,
            relyingPartyID: "webauthn.arkavo.net",
            curve: .p256
        )
        ViewModelFactory.shared.serviceLocator.register(client)
    }

    var body: some Scene {
        WindowGroup {
            Group {
                switch selectedView {
                case .registration:
                    RegistrationView(onComplete: { profile in
                        Task {
                            await saveProfile(profile: profile)
                            selectedView = .main
                        }
                    })
                case .main:
                    NavigationStack(path: $navigationPath) {
                        ContentView()
                    }
                }
            }
            .task {
                await checkAccountStatus()
            }
            .environmentObject(SharedState())
            .onOpenURL { url in
                handleIncomingURL(url)
            }
            .onReceive(NotificationCenter.default.publisher(for: .handleIncomingURL)) { notification in
                if let url = notification.object as? URL {
                    handleIncomingURL(url)
                }
            }
            .alert(item: $connectionError) { error in
                Alert(
                    title: Text(error.title),
                    message: Text(error.message),
                    primaryButton: .default(Text(error.action)) {
                        if error.action == "Update App" {
                            // Open App Store
                            if let url = URL(string: "itms-apps://apple.com/app/id<your-app-id>") { // FIXME:
                                UIApplication.shared.open(url)
                            }
                        } else {
                            // Retry connection
                            Task {
                                await checkAccountStatus()
                            }
                        }
                    },
                    secondaryButton: .cancel(Text("Later")) {
                        // Only allow dismissal if error is not blocking
                        if error.isBlocking {
                            selectedView = .main
                        }
                    }
                )
            }
            #if targetEnvironment(macCatalyst)
            .frame(minWidth: 800, idealWidth: 1200, maxWidth: .infinity,
                   minHeight: 600, idealHeight: 800, maxHeight: .infinity)
            #endif
        }
        .onChange(of: scenePhase) { _, newPhase in
            switch newPhase {
            case .active:
                Task {
                    await checkAccountStatus()
                }
            case .background:
                Task {
                    await saveChanges()
                }
                NotificationCenter.default.post(name: .closeWebSockets, object: nil)
                tokenCheckTimer?.invalidate()
                tokenCheckTimer = nil
            case .inactive:
                break
            @unknown default:
                break
            }
        }
    }

    @MainActor
    private func saveProfile(profile: Profile) async {
        do {
            let account = try await persistenceController.getOrCreateAccount()
            account.profile = profile
            ViewModelFactory.shared.setAccount(account)
            // Connect with WebAuthn
            do {
                try await client.connect(accountName: profile.name)
                // If connection is successful, we should have a token from the server
                // Store it in the keychain
                if let token = client.currentToken {
                    try KeychainManager.saveAuthenticationToken(token)
                    try await persistenceController.saveChanges()
                }
            } catch {
                print("Failed to connect: \(error)")
            }
        } catch {
            print("Failed to save profile: \(error)")
        }
    }

    @MainActor
    private func saveChanges() async {
        do {
            try await persistenceController.saveChanges()
            print("ArkavoApp: Changes saved successfully")
        } catch {
            print("ArkavoApp: Error saving changes: \(error.localizedDescription)")
        }
    }

    @MainActor
    private func checkAccountStatus() async {
        guard !isCheckingAccountStatus else { return }
        isCheckingAccountStatus = true
        defer { isCheckingAccountStatus = false }

        do {
            let account = try await persistenceController.getOrCreateAccount()
            ViewModelFactory.shared.setAccount(account)
            if account.profile == nil {
                selectedView = .registration
                return
            }

            guard let profile = account.profile else {
                connectionError = ConnectionError(
                    title: "Profile Error",
                    message: "There was an error loading your profile. Please try signing up again.",
                    action: "Sign Up",
                    isBlocking: true
                )
                selectedView = .registration
                return
            }

            // If we're already connected, nothing to do
            if case .connected = client.currentState {
                print("Client already connected, no action needed")
                selectedView = .main
                return
            }

            // If we're in the process of connecting, wait for that to complete
            if case .connecting = client.currentState {
                print("Connection already in progress, waiting...")
                return
            }

            // Try to connect with existing token if available
            if KeychainManager.getAuthenticationToken() != nil {
                do {
                    print("Attempting connection with existing token")
                    try await client.connect(accountName: profile.name)
                    selectedView = .main
                    print("checkAccountStatus: Connected with existing token")
                    return
                } catch {
                    print("Connection with existing token failed: \(error.localizedDescription)")
                    KeychainManager.deleteAuthenticationToken()
                    // Fall through to fresh connection attempt
                }
            }

            // Only reach here if no token, token connection failed, or we're disconnected
            print("Attempting fresh connection")
            try await client.connect(accountName: profile.name)
            selectedView = .main
            print("checkAccountStatus: Connected with fresh connection")

        } catch let error as ArkavoError {
            switch error {
            case .authenticationFailed:
                connectionError = ConnectionError(
                    title: "Authentication Failed",
                    message: "We couldn't verify your identity. This can happen if you've signed in on another device. Please sign in again to continue.",
                    action: "Sign In",
                    isBlocking: true
                )
                selectedView = .main

            case .connectionFailed:
                connectionError = ConnectionError(
                    title: "Connection Failed",
                    message: "We're having trouble reaching Arkavo servers. Please check your internet connection and try again.",
                    action: "Retry",
                    isBlocking: false
                )
                if selectedView != .main {
                    selectedView = .main
                }

            case .invalidResponse:
                connectionError = ConnectionError(
                    title: "Update Required",
                    message: "This version of Arkavo is no longer supported. Please update to the latest version from the App Store to continue.",
                    action: "Update App",
                    isBlocking: true
                )
                selectedView = .main

            default:
                connectionError = ConnectionError(
                    title: "Connection Error",
                    message: "Something went wrong while connecting to Arkavo. Please try again.",
                    action: "Retry",
                    isBlocking: false
                )
                selectedView = .main
            }
        } catch let error as URLError {
            switch error.code {
            case .notConnectedToInternet:
                connectionError = ConnectionError(
                    title: "No Internet Connection",
                    message: "Please check your internet connection and try again.",
                    action: "Retry",
                    isBlocking: false
                )

            case .timedOut:
                connectionError = ConnectionError(
                    title: "Connection Timeout",
                    message: "The connection to Arkavo is taking longer than expected. This might be due to a slow internet connection.",
                    action: "Try Again",
                    isBlocking: false
                )

            default:
                connectionError = ConnectionError(
                    title: "Network Error",
                    message: "There was a problem connecting to Arkavo. Please check your internet connection and try again.",
                    action: "Retry",
                    isBlocking: false
                )
            }
            if selectedView != .main {
                selectedView = .main
            }
        } catch {
            connectionError = ConnectionError(
                title: "Unexpected Error",
                message: "Something unexpected happened. Please try again or contact support if the problem persists.",
                action: "Retry",
                isBlocking: false
            )
            selectedView = .main
        }
    }

    // applinks
    private func handleIncomingURL(_ url: URL) {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: true),
              components.host == "app.arkavo.com"
        else {
            print("Invalid URL format")
            return
        }

        let pathComponents = components.path.split(separator: "/").map(String.init)

        guard pathComponents.count == 2 else {
            print("Invalid path format")
            return
        }

        let type = pathComponents[0]
        let publicIDString = pathComponents[1]
        // convert publicIDString using base58 decode to publicID
        guard let publicID = publicIDString.base58Decoded else {
            print("Invalid publicID format")
            return
        }
        switch type {
        case "stream":
            navigationPath.append(DeepLinkDestination.stream(publicID: publicID))
        case "profile":
            navigationPath.append(DeepLinkDestination.profile(publicID: publicID))
        default:
            print("Unknown URL type")
        }
    }
}

enum AppView {
    case registration
    case main
}

enum DeepLinkDestination: Hashable {
    case stream(publicID: Data)
    case profile(publicID: Data)
}

extension Notification.Name {
    static let closeWebSockets = Notification.Name("CloseWebSockets")
    static let handleIncomingURL = Notification.Name("HandleIncomingURL")
}

@MainActor
struct ConnectionError: Identifiable {
    let id = UUID()
    let title: String
    let message: String
    let action: String
    let isBlocking: Bool // If true, user must resolve before continuing
}

enum ArkavoError: Error {
    case invalidURL
    case authenticationFailed(String)
    case connectionFailed(String)
    case invalidResponse
    case messageError(String)
    case notConnected
    case invalidState
}

class SharedState: ObservableObject {
    @Published var selectedCreator: Creator?
    @Published var servers: [Server] = []
    @Published var selectedServer: Server?
    @Published var selectedVideo: Video?
    @Published var selectedTab: Tab?
    @Published var showCreateView: Bool = false
    @Published var selectedChannel: Channel?
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
    public static var shared = ViewModelFactory(serviceLocator: ServiceLocator())

    public let serviceLocator: ServiceLocator

    // Store current account and profile
    private var currentAccount: Account?
    private var currentProfile: Profile?

    private init(serviceLocator: ServiceLocator) {
        self.serviceLocator = serviceLocator
    }

    // Set current account and profile
    @MainActor
    func setAccount(_ account: Account) {
        currentAccount = account
        currentProfile = account.profile
    }

    // Clear current account and profile
    @MainActor
    func clearAccount() {
        currentAccount = nil
        currentProfile = nil
    }

    // Accessor methods for current account and profile
    @MainActor
    func getCurrentAccount() -> Account? {
        currentAccount
    }

    @MainActor
    func getCurrentProfile() -> Profile? {
        currentProfile
    }

    @MainActor
    func makeDiscordViewModel() -> DiscordViewModel {
        let client = serviceLocator.resolve() as ArkavoClient
        return DiscordViewModel(
            client: client,
            account: currentAccount!,
            profile: currentProfile!
        )
    }

    @MainActor
    func makeChatViewModel(channel _: Channel) -> ChatViewModel {
        let client = serviceLocator.resolve() as ArkavoClient
        return ChatViewModel(
            client: client,
            account: currentAccount!,
            profile: currentProfile!
        )
    }

    @MainActor
    func makeTikTokFeedViewModel() -> TikTokFeedViewModel {
        let client = serviceLocator.resolve() as ArkavoClient
        return TikTokFeedViewModel(
            client: client,
            account: currentAccount!,
            profile: currentProfile!
        )
    }
}
