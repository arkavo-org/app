import ArkavoSocial
import OSLog
import SwiftUI

@main
struct ArkavoApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @State private var navigationPath = NavigationPath()
    @State private var selectedView: AppView = .registration // Default to registration view
    @State private var isCheckingAccountStatus = false
    @State private var tokenCheckTimer: Timer?
    @State private var connectionError: ConnectionError?
    @StateObject private var sharedState = SharedState()
    @StateObject private var messageRouter: ArkavoMessageRouter
    @StateObject private var agentService = AgentService()
    // BEGIN screenshots
//    @StateObject private var windowAccessor = WindowAccessor.shared
//    @State private var screenshotGenerator: AppStoreScreenshotGenerator?
    // END screenshots

    let persistenceController = PersistenceController.shared
    private let regLogger = Logger(subsystem: "com.arkavo.Arkavo", category: "Registration")
    let client: ArkavoClient

    // Connection retry configuration
    private enum ConnectionRetry {
        static let backoffInterval: TimeInterval = 10
    }

    init() {
        client = ArkavoClient(
            authURL: URL(string: "https://webauthn.arkavo.net")!,
            websocketURL: URL(string: "wss://100.arkavo.net")!,
            relyingPartyID: "webauthn.arkavo.net",
            curve: .p256,
            // Note: Modified for compatibility with latest OpenTDFKit
            // Capacity of 8192 keys is set in GroupViewModel.swift
        )
        ViewModelFactory.shared.serviceLocator.register(client)
        // Initialize router
        let router = ArkavoMessageRouter(
            client: client,
            persistenceController: PersistenceController.shared,
        )
        _messageRouter = StateObject(wrappedValue: router)
        ViewModelFactory.shared.serviceLocator.register(router)
        // Create a separate instance of SharedState for initialization
        // This avoids accessing the @StateObject property before it's installed
        let initialSharedState = SharedState()
        ViewModelFactory.shared.setSharedState(initialSharedState)
        do {
            let queueManager = try MessageQueueManager()
            ViewModelFactory.shared.serviceLocator.register(queueManager)
        } catch {
            print("Failed to initialize message cache: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            Group {
                switch selectedView {
                case .registration:
                    RegistrationView(onComplete: { profile in
                        Task {
                            let success = await saveProfile(profile: profile)
                            if success {
                                selectedView = .main
                            }
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
            .environmentObject(agentService)
            .modelContainer(persistenceController.container)
            .onAppear {
                // Update the shared state reference now that the StateObject is properly installed
                ViewModelFactory.shared.setSharedState(sharedState)
                // Register agent service in service locator
                ViewModelFactory.shared.serviceLocator.register(agentService)
            }
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
                            // Enter offline mode to avoid constructing view models that require an account
                            sharedState.isOfflineMode = true
                            selectedView = .main
                        }
                    },
                )
            }
        }
        .onChange(of: scenePhase) { _, newPhase in
            switch newPhase {
            case .active:
                switch client.currentState {
                case .disconnected:
                    Task {
                        await checkAccountStatus()
                    }
                case let .error(error):
                    print("error: \(error)")
                    Task {
                        await checkAccountStatus()
                    }
                case .authenticating, .connected, .connecting:
                    break
                }

                // Set up timer for handling retry connections
                tokenCheckTimer?.invalidate()
                tokenCheckTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
                    if Data.didPostRetryConnection {
                        Data.didPostRetryConnection = false
                        Task { @MainActor [self] in
                            // Reset offline mode flag
                            sharedState.isOfflineMode = false
                            // Attempt to reconnect
                            await checkAccountStatus()
                        }
                    }
                }

                // Start agent discovery when app becomes active
                agentService.onAppearActive()

            case .background:
                Task {
                    await saveChanges()
                }
                NotificationCenter.default.post(name: .closeWebSockets, object: nil)
                // No need to remove observer for retry connection
                tokenCheckTimer?.invalidate()
                tokenCheckTimer = nil

                // Stop agent discovery and cleanup when going to background
                agentService.onDisappear()

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
    private func saveProfile(profile: Profile) async -> Bool {
        do {
            // Generate default handle from name
            let handle = profile.name.lowercased().replacingOccurrences(of: " ", with: "-")

            regLogger.log("[Registration] Starting profile save for handle generation")
            // Generate DID key and get the DID string
            let did: String
            do {
                did = try client.generateDID()
                print("Generated DID: \(did)")
            } catch {
                print("Failed to generate DID: \(error)")
                regLogger.error("[Registration] DID generation failed: \(String(describing: error))")
                connectionError = ConnectionError(
                    title: "Registration Error",
                    message: "Failed to generate security credentials. Please try again.",
                    action: "Retry",
                    isBlocking: true,
                )
                return false
            }

            // Finalize the profile with DID and handle
            profile.finalizeRegistration(did: did, handle: handle)

            // Complete WebAuthn registration
            do {
                regLogger.log("[Registration] Calling registerUser for handle=\(handle, privacy: .private)")
                let token = try await client.registerUser(handle: handle, did: did)
                try KeychainManager.saveAuthenticationToken(token)
                regLogger.log("[Registration] registerUser succeeded, token saved")
            } catch let error as ArkavoError {
                regLogger.error("[Registration] ArkavoError during registerUser: \(String(describing: error))")
                let details: String
                switch error {
                case let .authenticationFailed(message):
                    details = message
                    connectionError = ConnectionError(
                        title: "Registration Failed",
                        message: "The server rejected the registration request. Details: \(message)",
                        action: "Try Again",
                        isBlocking: true,
                    )
                case let .connectionFailed(message):
                    details = message
                    connectionError = ConnectionError(
                        title: "Connection Failed",
                        message: "We couldn't reach the server. \(message)",
                        action: "Retry",
                        isBlocking: true,
                    )
                case .invalidResponse:
                    details = "Invalid response from server"
                    connectionError = ConnectionError(
                        title: "Server Error",
                        message: "Received an invalid response from the server. Please try again.",
                        action: "Retry",
                        isBlocking: true,
                    )
                default:
                    details = error.localizedDescription
                    connectionError = ConnectionError(
                        title: "Registration Error",
                        message: "An unexpected error occurred during registration. Details: \(error.localizedDescription)",
                        action: "Retry",
                        isBlocking: true,
                    )
                }
                sharedState.lastRegistrationErrorDetails = details
                return false
            } catch {
                print("Failed to register user: \(error)")
                regLogger.error("[Registration] Unknown error during registerUser: \(String(describing: error))")
                let ns = error as NSError
                print("[Registration] Error domain: \(ns.domain), code: \(ns.code)")
                var msg = error.localizedDescription
                var title = "Registration Error"
                var action = "Retry"

                // Handle duplicate passkey error specifically - check multiple conditions
                let isDuplicatePasskey = ns.code == -25300 ||
                                        ns.domain == "ArkavoRegistration" ||
                                        msg.lowercased().contains("duplicate") ||
                                        msg.lowercased().contains("already exists")

                if isDuplicatePasskey {
                    print("[Registration] Detected duplicate passkey error")
                    title = "Passkey Already Exists"
                    msg = ns.localizedDescription
                    if let recoverySuggestion = ns.localizedRecoverySuggestion {
                        msg += "\n\n\(recoverySuggestion)"
                    }
                    // If no recovery suggestion was provided, add default guidance
                    if ns.localizedRecoverySuggestion == nil {
                        msg += "\n\nTo register:\n1. Go to Settings → Passwords\n2. Search for 'webauthn.arkavo.net'\n3. Delete all existing passkeys\n4. Return and try again"
                    }
                    action = "Got It"
                } else if ns.domain == "HTTPError" {
                    msg = "HTTP \(ns.code): \(msg)"
                }

                connectionError = ConnectionError(
                    title: title,
                    message: msg,
                    action: action,
                    isBlocking: true,
                )
                sharedState.lastRegistrationErrorDetails = msg
                return false
            }

            // Create and set up account
            let account = try await persistenceController.getOrCreateAccount()
            account.profile = profile

            // Create streams
            do {
                let videoStream = try await createVideoStream(account: account, profile: profile)
                let postStream = try await createPostStream(account: account, profile: profile)

                // Create InnerCircle stream for P2P communication
                let innerCircleStream = try await createInnerCircleStream(account: account, profile: profile)

                print("Created streams - video: \(videoStream.id), post: \(postStream.id), innerCircle: \(innerCircleStream.id)")
            } catch {
                print("Failed to create streams: \(error)")
                regLogger.error("[Registration] Stream setup failed: \(String(describing: error))")
                connectionError = ConnectionError(
                    title: "Setup Error",
                    message: "Failed to set up your account streams. Details: \(error.localizedDescription)",
                    action: "Retry",
                    isBlocking: true,
                )
                sharedState.lastRegistrationErrorDetails = error.localizedDescription
                return false
            }

            ViewModelFactory.shared.setAccount(account)

            // Connect with WebAuthn
            do {
                regLogger.log("[Registration] Connecting with WebAuthn for account=\(profile.name, privacy: .private)")
                try await client.connect(accountName: profile.name)
                // If connection is successful, save token and changes
                if let token = client.currentToken {
                    try KeychainManager.saveAuthenticationToken(token)
                    try await persistenceController.saveChanges()
                    selectedView = .main // Only change view on complete success
                    regLogger.log("[Registration] Connected and saved; switching to main view")
                    return true
                }
            } catch {
                print("Failed to connect: \(error)")
                regLogger.error("[Registration] Connect failed: \(String(describing: error))")
                connectionError = ConnectionError(
                    title: "Connection Error",
                    message: "Failed to establish connection. Details: \(error.localizedDescription)",
                    action: "Retry",
                    isBlocking: true,
                )
                sharedState.lastRegistrationErrorDetails = error.localizedDescription
                return false
            }

        } catch {
            print("Failed to save profile: \(error)")
            connectionError = ConnectionError(
                title: "Profile Error",
                message: "Failed to save your profile. Please try again.",
                action: "Retry",
                isBlocking: true,
            )
            return false
        }
        return true
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
                age: .onlyKids,
            ),
        )

        // Create initial thought that marks this as a video stream
        let initialMetadata = Thought.Metadata(
            creatorPublicID: profile.publicID,
            streamPublicID: stream.publicID,
            mediaType: .video,
            createdAt: Date(),
            contributors: [],
        )

        let initialThought = Thought(
            nano: Data(),
            metadata: initialMetadata,
        )

        // Save the initial thought
        let saved = try await PersistenceController.shared.saveThought(initialThought)
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
                age: .onlyKids,
            ),
        )

        // Create initial thought that marks this as a post stream
        let initialMetadata = Thought.Metadata(
            creatorPublicID: profile.publicID,
            streamPublicID: stream.publicID,
            mediaType: .post, // Posts are primarily text-based
            createdAt: Date(),
            contributors: [],
        )

        let initialThought = Thought(
            nano: Data(), // Empty initial data
            metadata: initialMetadata,
        )

        print("Created initial post stream thought with ID: \(initialThought.id)")

        // Save the initial thought
        let saved = try await PersistenceController.shared.saveThought(initialThought)
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

    func createInnerCircleStream(account: Account, profile: Profile) async throws -> Stream {
        print("Creating InnerCircle stream for profile: \(profile.name)")

        // Check if InnerCircle already exists
        if let existingInnerCircle = account.streams.first(where: { $0.isInnerCircleStream }) {
            print("InnerCircle stream already exists with ID: \(existingInnerCircle.id)")
            return existingInnerCircle
        }

        // Create a special profile for InnerCircle
        let innerCircleProfile = Profile(
            name: "InnerCircle",
            blurb: "Local peer-to-peer communication",
            interests: "local",
            location: "",
        )

        // Create the stream with appropriate policies
        let stream = Stream(
            creatorPublicID: profile.publicID,
            profile: innerCircleProfile,
            policies: Policies(
                admission: .openInvitation,
                interaction: .open,
                age: .forAll,
            ),
        )

        // Unlike other streams, InnerCircle has no source thought (it's a group chat stream)

        // Add to account
        try account.addStream(stream)
        print("Added InnerCircle stream to account. Stream ID: \(stream.id)")

        // Save changes
        try await persistenceController.saveChanges()
        print("InnerCircle stream creation completed")

        return stream
    }

    @MainActor
    private func validateStreams() async {
        do {
            let account = try await persistenceController.getOrCreateAccount()

            // Check video stream
            let videoStream = account.streams.first(where: { stream in
                stream.source?.metadata.mediaType == .video
            })

            if videoStream == nil {
                print("⚠️ Video stream missing - attempting to create")
                guard let profile = account.profile else {
                    print("❌ Cannot create video stream: Profile not found")
                    return
                }

                let newVideoStream = try await createVideoStream(account: account, profile: profile)
                print("✅ Created new video stream: \(newVideoStream.id)")
            } else {
                print("✅ Video stream found: \(videoStream!.id)")
            }

            // Check post stream
            let postStream = account.streams.first(where: { stream in
                stream.source?.metadata.mediaType == .post
            })

            if postStream == nil {
                print("⚠️ Post stream missing - attempting to create")
                guard let profile = account.profile else {
                    print("❌ Cannot create post stream: Profile not found")
                    return
                }

                let newPostStream = try await createPostStream(account: account, profile: profile)
                print("✅ Created new post stream: \(newPostStream.id)")
            } else {
                print("✅ Post stream found: \(postStream!.id)")
            }

            // Check InnerCircle stream
            let innerCircleStream = account.streams.first(where: { stream in
                stream.isInnerCircleStream
            })

            if innerCircleStream == nil {
                print("⚠️ InnerCircle stream missing - attempting to create")
                guard let profile = account.profile else {
                    print("❌ Cannot create InnerCircle stream: Profile not found")
                    return
                }

                let newInnerCircleStream = try await createInnerCircleStream(account: account, profile: profile)
                print("✅ Created new InnerCircle stream: \(newInnerCircleStream.id)")
            } else {
                print("✅ InnerCircle stream found: \(innerCircleStream!.id)")
            }

            // Save any changes
            try await persistenceController.saveChanges()

        } catch {
            print("❌ Error validating streams: \(error)")
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

        if let next = sharedState.nextAllowedAccountCheck, Date() < next {
            print("checkAccountStatus: respecting backoff until \(next)")
            return
        }

        isCheckingAccountStatus = true
        defer { isCheckingAccountStatus = false }

        if case .connected = client.currentState {
            // Already connected, no need to re-authenticate
            selectedView = .main
            return
        }

        do {
            let account = try await persistenceController.getOrCreateAccount()
            print("Account retrieved: \(account.id), profile: \(String(describing: account.profile))")

            // If profile is nil, go to registration immediately
            if account.profile == nil {
                print("No profile found - routing to registration")
                selectedView = .registration
                return
            }

            // Set the account only after confirming it has a profile
            ViewModelFactory.shared.setAccount(account)

            guard let profile = account.profile else {
                print("Profile is nil after check - this shouldn't happen")
                connectionError = ConnectionError(
                    title: "Profile Error",
                    message: "There was an error loading your profile. Please try signing up again.",
                    action: "Sign Up",
                    isBlocking: true,
                )
                selectedView = .registration
                return
            }

            // First, try to validate streams safely without accessing Thoughts
            do {
                let (existingVideoStream, existingPostStream, existingInnerCircleStream) =
                    try await persistenceController.validateStreamsWithoutAccessingThoughts()

                // If we can't identify stream types safely, remove potentially corrupted streams
                if existingVideoStream == nil, existingPostStream == nil, !account.streams.isEmpty {
                    print("⚠️ Cannot safely identify stream types - removing potentially corrupted streams")
                    try await persistenceController.removeStreamsWithPotentiallyInvalidThoughts()
                }

                // Now recreate any missing streams
                if existingVideoStream == nil {
                    print("⚠️ Video stream missing - creating new one")
                    let newVideoStream = try await createVideoStream(account: account, profile: profile)
                    print("✅ Created new video stream: \(newVideoStream.id)")
                }

                if existingPostStream == nil {
                    print("⚠️ Post stream missing - creating new one")
                    let newPostStream = try await createPostStream(account: account, profile: profile)
                    print("✅ Created new post stream: \(newPostStream.id)")
                }

                if existingInnerCircleStream == nil {
                    print("⚠️ InnerCircle stream missing - creating new one")
                    let newInnerCircleStream = try await createInnerCircleStream(account: account, profile: profile)
                    print("✅ Created new InnerCircle stream: \(newInnerCircleStream.id)")
                }
            } catch {
                print("❌ Error validating streams: \(error.localizedDescription)")
                // If validation fails completely, remove all streams and recreate
                try await persistenceController.removeStreamsWithPotentiallyInvalidThoughts()

                // Create fresh streams
                let newVideoStream = try await createVideoStream(account: account, profile: profile)
                print("✅ Created new video stream after error: \(newVideoStream.id)")

                let newPostStream = try await createPostStream(account: account, profile: profile)
                print("✅ Created new post stream after error: \(newPostStream.id)")

                let newInnerCircleStream = try await createInnerCircleStream(account: account, profile: profile)
                print("✅ Created new InnerCircle stream after error: \(newInnerCircleStream.id)")
            }

            try await persistenceController.saveChanges()

            // Try to connect, but proceed to main view even if connection fails
            if KeychainManager.getAuthenticationToken() != nil {
                do {
                    print("Attempting connection with existing token")
                    try await client.connect(accountName: profile.name)
                    print("checkAccountStatus: Connected with existing token")
                    sharedState.nextAllowedAccountCheck = nil  // Reset backoff on success
                } catch {
                    print("Connection failed, but continuing in offline mode: \(error.localizedDescription)")
                    // Allow the app to function without network features
                    sharedState.isOfflineMode = true
                    sharedState.nextAllowedAccountCheck = Date().addingTimeInterval(ConnectionRetry.backoffInterval)
                }
            } else {
                do {
                    print("Attempting fresh connection")
                    try await client.connect(accountName: profile.name)
                    print("checkAccountStatus: Connected with fresh connection")
                    sharedState.nextAllowedAccountCheck = nil  // Reset backoff on success
                } catch let error as ArkavoError {
                    if case let .authenticationFailed(message) = error, message.contains("User Not Found") {
                        // User exists locally but not on server, go to registration
                        print("User exists locally but not on server - routing to registration")

                        // Clear the invalid account data
                        KeychainManager.deleteAuthenticationToken()

                        // Reset account state so registration can create a new one
                        account.profile = nil
                        try? await persistenceController.saveChanges()

                        // Route to registration
                        selectedView = .registration
                        ViewModelFactory.shared.clearAccount()
                        return
                    } else {
                        print("Connection failed, but continuing in offline mode: \(error.localizedDescription)")
                        // Allow the app to function without network features
                        sharedState.isOfflineMode = true
                        sharedState.nextAllowedAccountCheck = Date().addingTimeInterval(ConnectionRetry.backoffInterval)
                    }
                } catch {
                    print("Connection failed, but continuing in offline mode: \(error.localizedDescription)")
                    // Allow the app to function without network features
                    sharedState.isOfflineMode = true
                    sharedState.nextAllowedAccountCheck = Date().addingTimeInterval(ConnectionRetry.backoffInterval)
                }
            }

            // Proceed to main view regardless of connection status
            selectedView = .main

            // No need to show offline mode alert - OfflineHomeView provides sufficient information
            // User can tap "Try to Reconnect" button in OfflineHomeView if needed

        } catch {
            print("Error checking account status: \(error.localizedDescription)")
            sharedState.nextAllowedAccountCheck = Date().addingTimeInterval(ConnectionRetry.backoffInterval)

            // Even if there's an error, we'll still try to load the account
            do {
                let account = try? await persistenceController.getOrCreateAccount()
                if let account, let _ = account.profile {
                    // We have a profile, so we can proceed in offline mode
                    ViewModelFactory.shared.setAccount(account)
                    selectedView = .main
                    sharedState.isOfflineMode = true

                    connectionError = ConnectionError(
                        title: "Offline Mode",
                        message: "You're currently using Arkavo in offline mode. Some features like video and social feeds are unavailable. Secure P2P messaging still works.",
                        action: "Try to Connect",
                        isBlocking: false,
                    )
                } else {
                    // No profile, route to registration
                    selectedView = .registration
                }
            }
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
    static let retryConnection = Notification.Name("RetryConnection")
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
    case invalidEvent(String)
    case profileError(String)
    case profileNotFound(String)
    case streamError(String)
    case keyStoreError(String)
    case decryptionError(String)
    var errorDescription: String? {
        switch self {
        case let .profileError(message):
            "Profile Error: \(message)"
        case let .streamError(message):
            "Stream Error: \(message)"
        case let .keyStoreError(message):
            "KeyStore Error: \(message)"
        default:
            nil
        }
    }
}

class SharedState: ObservableObject {
    @Published var selectedCreatorPublicID: Data?
    @Published var selectedStreamPublicID: Data?
    @Published var selectedVideo: Video?
    @Published var selectedThought: Thought?
    @Published var selectedTab: Tab = .home
    @Published var showCreateView: Bool = false
    @Published var showChatOverlay: Bool = false
    @Published var isAwaiting: Bool = false
    @Published var isOfflineMode: Bool = false
    @Published var lastRegistrationErrorDetails: String?
    @Published var nextAllowedAccountCheck: Date? = nil

    // Store additional state values that don't need @Published
    private var stateStorage: [String: Any] = [:]

    func getState(forKey key: String) -> Any? {
        stateStorage[key]
    }

    func setState(_ value: Any, forKey key: String) {
        stateStorage[key] = value
        // Trigger objectWillChange if needed for UI updates
        objectWillChange.send()
    }

    func getCenterPrompt() -> String {
        switch selectedTab {
        case .home: "Capture" // create a video
        case .communities: "Converse" // start chatting
        case .contacts: "Connect" // invite someone new
        case .agents: "Discover" // find local agents
        case .social: "Publish" // post to the feed
        case .profile: "Express" // personalize your profile
        }
    }

    func getTooltipText() -> String {
        switch selectedTab {
        case .home: "Capture video"
        case .communities: "Converse in chat"
        case .contacts: "Connect with someone"
        case .agents: "Discover agents"
        case .social: "Publish post"
        case .profile: "Express yourself"
        }
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

    func resolve<T>(type: T.Type) -> T? {
        let key = String(describing: type)
        return services[key] as? T
    }
}

@MainActor
protocol ViewModel: ObservableObject {
    var client: ArkavoClient { get }
    var account: Account { get }
    var profile: Profile { get }

    init(client: ArkavoClient, account: Account, profile: Profile)
}

@MainActor
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
        // Only set the account if it has a valid profile
        guard let profile = account.profile else {
            print("Warning: Attempted to set account without profile")
            return
        }
        currentAccount = account
        currentProfile = profile
        print("Set account with profile: \(profile.name)")
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

    func makeViewModel<T: ViewModel>() -> T {
        guard let account = currentAccount, let profile = currentProfile else {
            fatalError("Attempting to create ViewModel without account/profile")
        }
        let client = serviceLocator.resolve() as ArkavoClient
        return T(client: client, account: account, profile: profile)
    }

    @MainActor
    func makeChatViewModel(streamPublicID: Data) -> ChatViewModel {
        guard let account = currentAccount, let profile = currentProfile else {
            fatalError("Attempting to create ChatViewModel without account/profile")
        }
        let client = serviceLocator.resolve() as ArkavoClient
        return ChatViewModel(
            client: client,
            account: account,
            profile: profile,
            streamPublicID: streamPublicID,
        )
    }

    func getChatViewModel(for streamPublicID: Data) -> ChatViewModel? {
        guard currentAccount != nil, currentProfile != nil else {
            return nil
        }
        return makeChatViewModel(streamPublicID: streamPublicID)
    }

    // Access the MultipeerConnectivity view model for peer discovery
    private var peerDiscoveryManager: PeerDiscoveryManager?
    private var globalSharedState: SharedState?

    @MainActor
    func getPeerDiscoveryManager() -> PeerDiscoveryManager {
        if peerDiscoveryManager == nil {
            let client = serviceLocator.resolve() as ArkavoClient
            peerDiscoveryManager = PeerDiscoveryManager(arkavoClient: client)
        }
        return peerDiscoveryManager!
    }

    @MainActor
    func setSharedState(_ state: SharedState) {
        globalSharedState = state
    }

    @MainActor
    func getSharedState() -> SharedState {
        if globalSharedState == nil {
            globalSharedState = SharedState()
        }
        return globalSharedState!
    }
}

