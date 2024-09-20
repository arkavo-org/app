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
                        case let .stream(publicId):
                            StreamLoadingView(publicId: publicId)
                        case let .profile(publicId):
                            // TODO: account profile
                            Text("Profile View for \(publicId)")
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
        let publicId = pathComponents[1]

        switch type {
        case "stream":
            navigationPath.append(DeepLinkDestination.stream(publicId: publicId))
        case "profile":
            navigationPath.append(DeepLinkDestination.profile(publicId: publicId))
        default:
            print("Unknown URL type")
        }
    }
}

struct StreamLoadingView: View {
    let publicId: String
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
            await loadStream(withPublicId: publicId)
        }
    }

    @MainActor
    private func loadStream(withPublicId publicId: String) async {
        isLoading = true
        // Decode the hex-encoded publicId to Data
        guard let publicIdData = Data(hexString: publicId) else {
            print("Invalid publicId format")
            stream = nil
            isLoading = false
            return
        }

        do {
            let account = try await PersistenceController.shared.getOrCreateAccount()
            accountProfile = account.profile
            let streams = try await PersistenceController.shared.fetchStream(withPublicId: publicIdData)

            if let stream = streams?.first {
                print("Stream found with publicId: \(publicId)")
                self.stream = stream
                isLoading = false
            } else {
                print("No stream found with publicId: \(publicId)")
                // Here you would typically implement logic to fetch the stream from a network source
                // For now, we'll just return nil
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
    case stream(publicId: String)
    case profile(publicId: String)
}

extension Notification.Name {
    static let closeWebSockets = Notification.Name("CloseWebSockets")
    static let handleIncomingURL = Notification.Name("HandleIncomingURL")
}

extension Data {
    init?(hexString: String) {
        let len = hexString.count / 2
        var data = Data(capacity: len)
        for i in 0 ..< len {
            let j = hexString.index(hexString.startIndex, offsetBy: i * 2)
            let k = hexString.index(j, offsetBy: 2)
            let bytes = hexString[j ..< k]
            if var num = UInt8(bytes, radix: 16) {
                data.append(&num, count: 1)
            } else {
                return nil
            }
        }
        self = data
    }
}
