import ArkavoSocial
import SwiftUI

@main
struct ArkavoApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @State private var navigationPath = NavigationPath()
    @State private var selectedView: AppView = .registration
    @State private var isCheckingAccountStatus = false
    @State private var tokenCheckTimer: Timer?
    let persistenceController = PersistenceController.shared
    let client: ArkavoClient

    init() {
        client = ArkavoClient(
            baseURL: URL(string: "https://webauthn.arkavo.net")!,
            relyingPartyID: "webauthn.arkavo.net"
        )
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
//                        ArkavoView(service: service)
//                        #if os(iOS)
//                            .navigationBarTitleDisplayMode(.inline)
//                            .navigationBarHidden(true)
//                        #endif
//                            .modelContainer(persistenceController.container)
//                            .navigationDestination(for: DeepLinkDestination.self) { destination in
//                                switch destination {
//                                case let .stream(publicID):
//                                    if service.streamService == nil {
//                                        Text("No Stream Service for \(publicID)")
//                                    } else {
//                                        StreamLoadingView(service: service.streamService!, publicID: publicID)
//                                    }
//                                case let .profile(publicID):
//                                    Text("Profile View for \(publicID)")
//                                }
//                            }
                    }
                }
            }
            .task {
                await checkAccountStatus()
            }
            .onOpenURL { url in
                handleIncomingURL(url)
            }
            .onReceive(NotificationCenter.default.publisher(for: .handleIncomingURL)) { notification in
                if let url = notification.object as? URL {
                    handleIncomingURL(url)
                }
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
    private func checkAccountStatus() async {
        guard !isCheckingAccountStatus else { return }
        isCheckingAccountStatus = true
        defer { isCheckingAccountStatus = false }
        do {
            let account = try await persistenceController.getOrCreateAccount()
            if account.profile == nil {
                selectedView = .registration
            } else {
                #if !targetEnvironment(macCatalyst)
                    selectedView = .main
                #endif
            }
        } catch {
            print("ArkavoApp: Error checking account status: \(error.localizedDescription)")
            selectedView = .registration
        }
    }

    @MainActor
    private func saveProfile(profile: Profile) async {
        do {
            let account = try await persistenceController.getOrCreateAccount()
            account.profile = profile

            // Connect with WebAuthn
            do {
                try await client.connect(accountName: profile.name)
                // If connection is successful, we should have a token from the server
                // Store it in the account
                if let token = client.currentToken {
                    account.authenticationToken = token
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
