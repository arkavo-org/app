import FlatBuffers
import SwiftData
import SwiftUI

@main
struct ArkavoApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @State private var navigationPath = NavigationPath()
    let persistenceController = PersistenceController.shared
    #if os(macOS)
        @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    #endif
    var body: some Scene {
        WindowGroup {
            NavigationStack(path: $navigationPath) {
                ArkavoView()
                #if os(iOS)
                    .navigationBarTitleDisplayMode(.inline)
                    .navigationBarHidden(true)
                #endif
                    .modelContainer(persistenceController.container)
                    .task {
                        await ensureAccountExists()
                    }
                    .navigationDestination(for: DeepLinkDestination.self) { destination in
                        switch destination {
                        case let .stream(publicID):
                            StreamLoadingView(publicID: publicID)
                        case let .profile(publicID):
                            // TODO: account profile
                            Text("Profile View for \(publicID)")
                        }
                    }
            }
            .onOpenURL { url in
                handleIncomingURL(url)
            }
            .onReceive(NotificationCenter.default.publisher(for: .handleIncomingURL)) { notification in
                if let url = notification.object as? URL {
                    handleIncomingURL(url)
                }
            }
            #if os(macOS)
            .frame(minWidth: 800, idealWidth: 1200, maxWidth: .infinity,
                   minHeight: 600, idealHeight: 800, maxHeight: .infinity)
            #endif
        }
        .onChange(of: scenePhase) { _, newPhase in
            switch newPhase {
            case .active:
                Task {
                    await ensureAccountExists()
                }
            case .background:
                Task {
                    await saveChanges()
                }
                NotificationCenter.default.post(name: .closeWebSockets, object: nil)
            case .inactive:
                break
            @unknown default:
                break
            }
        }
        #if os(macOS)
        .windowStyle(HiddenTitleBarWindowStyle())
        .defaultSize(width: 1200, height: 800)
        #endif
    }

    @MainActor
    private func ensureAccountExists() async {
        do {
            let account = try await persistenceController.getOrCreateAccount()
            print("ArkavoApp: Account ensured with ID: \(account.id)")
        } catch {
            print("ArkavoApp: Error ensuring Account exists: \(error.localizedDescription)")
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

struct StreamLoadingView: View {
    let publicID: Data
    @State private var stream: Stream?
    @State private var accountProfile: Profile?
    @State private var isLoading = true

    var body: some View {
        Group {
            if isLoading {
                ProgressView("Loading stream...")
            } else if let stream {
                let thoughtService = ThoughtService(ArkavoService())
                let thoughtStreamViewModel = ThoughtStreamViewModel(service: thoughtService)
                ThoughtStreamView(viewModel: thoughtStreamViewModel)
                    .onAppear {
                        thoughtStreamViewModel.stream = stream
                        // FIXME: creatorProfile != accountProfile
                        thoughtStreamViewModel.creatorProfile = accountProfile
                        thoughtService.streamViewModel = StreamViewModel(thoughtStreamViewModel: thoughtStreamViewModel)
                    }
            } else {
                Text("Stream not found")
            }
        }
        .task {
            await loadStream(withPublicID: publicID)
        }
    }

    @MainActor
    private func loadStream(withPublicID publicID: Data) async {
        isLoading = true
        do {
            let account = try await PersistenceController.shared.getOrCreateAccount()
            accountProfile = account.profile
            let streams = try await PersistenceController.shared.fetchStream(withPublicID: publicID)

            if let stream = streams?.first {
                print("Stream found with publicID: \(publicID)")
                self.stream = stream
                isLoading = false
            } else {
                print("No stream found with publicID: \(publicID)")
                // get stream
                var builder = FlatBufferBuilder(initialSize: 1024)
                // Create string offsets
                let targetIdVector = builder.createVector(bytes: publicID)
                let sourcePublicID: [UInt8] = [1, 2, 3, 4, 5] // Example byte array for sourcePublicID
                let sourcePublicIDOffset = builder.createVector(sourcePublicID)
                // Create the Event object in the FlatBuffer
                let action = Arkavo_UserEvent.createUserEvent(
                    &builder,
                    sourceType: .accountProfile,
                    targetType: .streamProfile,
                    sourceIdVectorOffset: sourcePublicIDOffset,
                    targetIdVectorOffset: targetIdVector
                )
                // Create the Event object
                let eventOffset = Arkavo_Event.createEvent(
                    &builder,
                    action: .invite,
                    timestamp: UInt64(Date().timeIntervalSince1970),
                    status: .preparing,
                    dataType: .userevent,
                    dataOffset: action
                )
                builder.finish(offset: eventOffset)
                let data = builder.data
                let serializedEvent = data.base64EncodedString()
                print("streamInvite: \(serializedEvent)")
                // TODO: send NATSEvent
                isLoading = false
            }
        } catch {
            print("Error fetching stream: \(error.localizedDescription)")
            isLoading = false
            return
        }
        isLoading = false
    }
}

#if os(macOS)
    class AppDelegate: NSObject, NSApplicationDelegate {
        func application(_: NSApplication, open urls: [URL]) {
            if let url = urls.first {
                NotificationCenter.default.post(name: .handleIncomingURL, object: url)
            }
        }
    }
#endif

enum DeepLinkDestination: Hashable {
    case stream(publicID: Data)
    case profile(publicID: Data)
}

extension Notification.Name {
    static let closeWebSockets = Notification.Name("CloseWebSockets")
    static let handleIncomingURL = Notification.Name("HandleIncomingURL")
}
