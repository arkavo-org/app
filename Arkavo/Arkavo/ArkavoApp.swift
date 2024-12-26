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
    @StateObject private var sharedState = SharedState()
    @StateObject private var messageRouter: ArkavoMessageRouter
    // BEGIN screenshots
//    @StateObject private var windowAccessor = WindowAccessor.shared
//    @State private var screenshotGenerator: AppStoreScreenshotGenerator?
    // END screenshots
    
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
        // Initialize router
        let router = ArkavoMessageRouter(
            client: client,
            persistenceController: PersistenceController.shared
        )
        _messageRouter = StateObject(wrappedValue: router)
        ViewModelFactory.shared.serviceLocator.register(router)
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
            .environmentObject(sharedState)
            .environmentObject(messageRouter)
            // BEGIN screenshots
//            .onAppear {
//                // Set up window accessor for screenshots
//                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
//                    if let window = UIApplication.shared.windows.first(where: { $0.isKeyWindow }) {
//                        windowAccessor.window = window
//                        screenshotGenerator = AppStoreScreenshotGenerator(window: window)
//                        #if DEBUG
//                        screenshotGenerator?.startCapturing()  // No orientation parameter needed
//                        #endif
//                    }
//                }
//            }
            // END screenshots
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
                            if let url = URL(string: "itms-apps://apple.com/app/id6670504172") {
                                UIApplication.shared.open(url)
                            }
                        } else {
                            Task {
                                await checkAccountStatus()
                            }
                        }
                    },
                    secondaryButton: .cancel(Text("Later")) {
                        if error.isBlocking {
                            selectedView = .main
                        }
                    }
                )
            }
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
                // BEGIN screenshots
                // Stop screenshot capture when going to background
//                screenshotGenerator?.stopCapturing()
                // END screenshots
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
            let videoStream = try await createVideoStream(account: account, profile: profile)
            let postStream = try await createPostStream(account: account, profile: profile)
            print("Created streams - video: \(videoStream.id), post: \(postStream.id)")
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

    func createVideoStream(account: Account, profile: Profile) async throws -> Stream {
        print("Creating video stream for profile: \(profile.name)")

        // Create the stream with appropriate policies
        let stream = Stream(
            creatorPublicID: profile.publicID,
            profile: profile,
            policies: Policies(
                admission: .closed,
                interaction: .closed,
                age: .onlyKids
            )
        )

        // Create initial thought that marks this as a video stream
        let initialMetadata = Thought.Metadata(
            creator: profile.id,
            streamPublicID: stream.publicID,
            mediaType: .video,
            createdAt: Date(),
            summary: "Video Stream",
            contributors: []
        )

        let initialThought = Thought(
            nano: Data(),
            metadata: initialMetadata
        )

        // Save the initial thought
        let saved = try PersistenceController.shared.saveThought(initialThought)
        print("Saved initial thought \(saved)")

        // Set the source thought to mark this as a video stream
        stream.source = initialThought
        print("Set video stream source thought. Stream ID: \(stream.id)")

        // Add to account
        try account.addStream(stream)
        print("Added stream to account. Total streams: \(account.streams.count)")

        // Save changes
        try await persistenceController.saveChanges()
        print("Video stream creation completed")

        return stream
    }

    func createPostStream(account: Account, profile: Profile) async throws -> Stream {
        print("Creating post stream for profile: \(profile.name)")

        // Create the stream with appropriate policies
        let stream = Stream(
            creatorPublicID: profile.publicID,
            profile: profile,
            policies: Policies(
                admission: .closed,
                interaction: .closed,
                age: .onlyKids
            )
        )

        // Create initial thought that marks this as a post stream
        let initialMetadata = Thought.Metadata(
            creator: profile.id,
            streamPublicID: stream.publicID,
            mediaType: .text, // Posts are primarily text-based
            createdAt: Date(),
            summary: "Post Stream",
            contributors: []
        )

        let initialThought = Thought(
            nano: Data(), // Empty initial data
            metadata: initialMetadata
        )

        print("Created initial post stream thought with ID: \(initialThought.id)")

        // Save the initial thought
        let saved = try PersistenceController.shared.saveThought(initialThought)
        print("Saved initial thought \(saved)")

        // Set the source thought to mark this as a post stream
        stream.source = initialThought
        print("Set post stream source thought. Stream ID: \(stream.id)")

        // Add to account
        try account.addStream(stream)
        print("Added stream to account. Total streams: \(account.streams.count)")

        // Save changes
        try await persistenceController.saveChanges()
        print("Post stream creation completed")

        return stream
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
    func handleIncomingURL(_ url: URL) {
        print("Handling URL: \(url.absoluteString)") // Debug logging

        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: true),
              components.host == "app.arkavo.com"
        else {
            print("Invalid URL format")
            return
        }

        let pathComponents = components.path.split(separator: "/").map(String.init)
        print("Path components: \(pathComponents)") // Debug logging

        guard pathComponents.count == 2 else {
            print("Invalid path format")
            return
        }

        let type = pathComponents[0]
        let publicIDString = pathComponents[1]

        print("Type: \(type), PublicID: \(publicIDString)") // Debug logging

        // convert publicIDString using base58 decode to publicID
        guard let publicID = publicIDString.base58Decoded else {
            print("Failed to decode publicID: \(publicIDString)") // Debug logging
            return
        }

        print("Successfully decoded publicID") // Debug logging

        switch type {
        case "stream":
            print("Processing stream deep link") // Debug logging
            // First switch the tab
            sharedState.selectedTab = .communities
            // Then append to navigation path
            DispatchQueue.main.async {
                navigationPath.append(DeepLinkDestination.stream(publicID: publicID))
                if selectedView != .main {
                    selectedView = .main
                }
            }
            print("Navigation updated for stream") // Debug logging

        case "profile":
            // Similar handling for profile...
            break

        default:
            print("Unknown URL type: \(type)")
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
    @Published var selectedServer: Server?
    @Published var selectedVideo: Video?
    @Published var selectedThought: Thought?
    @Published var selectedTab: Tab = .home
    @Published var showCreateView: Bool = false
    @Published var selectedChannel: Channel?
    @Published var isAwaiting: Bool = false
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
    func makeDiscordViewModel() -> GroupChatViewModel {
        let client = serviceLocator.resolve() as ArkavoClient
        return GroupChatViewModel(
            client: client,
            account: currentAccount!,
            profile: currentProfile!
        )
    }

    @MainActor
    func makeChatViewModel(stream: Stream) -> ChatViewModel {
        let client = serviceLocator.resolve() as ArkavoClient
        return ChatViewModel(
            client: client,
            account: currentAccount!,
            profile: currentProfile!,
            stream: stream
        )
    }

    @MainActor
    func makeVideoFeedViewModel() -> VideoFeedViewModel {
        let client = serviceLocator.resolve() as ArkavoClient
        return VideoFeedViewModel(
            client: client,
            account: currentAccount!,
            profile: currentProfile!
        )
    }

    @MainActor
    func makeVideoRecordingViewModel() -> VideoRecordingViewModel {
        let client = serviceLocator.resolve() as ArkavoClient
        return VideoRecordingViewModel(
            client: client,
            account: currentAccount!,
            profile: currentProfile!
        )
    }

    @MainActor
    func makePostFeedViewModel() -> PostFeedViewModel {
        let client = serviceLocator.resolve() as ArkavoClient
        return PostFeedViewModel(
            client: client,
            account: currentAccount!,
            profile: currentProfile!
        )
    }

    @MainActor
    func makePatreonViewModel() -> CreatorViewModel {
        let client = serviceLocator.resolve() as ArkavoClient
        return CreatorViewModel(
            client: client,
            account: currentAccount!,
            profile: currentProfile!
        )
    }
}
