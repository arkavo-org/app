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
    var base58EncodedString: String {
        Base58.encode([UInt8](self))
    }

    init?(base58Encoded string: String) {
        guard let bytes = Base58.decode(string) else { return nil }
        self = Data(bytes)
    }

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

enum Base58 {
    private static let alphabet = "123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz"
    private static let baseCount = UInt8(alphabet.count)

    static func encode(_ bytes: [UInt8]) -> String {
        var bytes = bytes
        var zerosCount = 0
        var length = 0

        for b in bytes {
            if b != 0 { break }
            zerosCount += 1
        }

        bytes.removeFirst(zerosCount)

        let size = bytes.count * 138 / 100 + 1

        var base58: [UInt8] = Array(repeating: 0, count: size)
        for b in bytes {
            var carry = Int(b)
            var i = 0

            for j in 0 ... base58.count - 1 where carry != 0 || i < length {
                carry += 256 * Int(base58[base58.count - 1 - j])
                base58[base58.count - 1 - j] = UInt8(carry % 58)
                carry /= 58
                i += 1
            }

            assert(carry == 0)

            length = i
        }

        var string = ""
        for _ in 0 ..< zerosCount {
            string += "1"
        }

        for b in base58[base58.count - length ..< base58.count].reversed() {
            string += String(alphabet[alphabet.index(alphabet.startIndex, offsetBy: Int(b))])
        }

        return string
    }

    static func decode(_ base58: String) -> [UInt8]? {
        var result = [UInt8]()
        var leadingZeros = 0
        var value: UInt = 0
        var base: UInt = 1

        for char in base58.reversed() {
            guard let digit = alphabet.firstIndex(of: char) else { return nil }
            let index = alphabet.distance(from: alphabet.startIndex, to: digit)
            value += UInt(index) * base
            base *= UInt(baseCount)

            if value > UInt(UInt8.max) {
                var mod = value
                while mod > 0 {
                    result.insert(UInt8(mod & 0xFF), at: 0)
                    mod >>= 8
                }
                value = 0
                base = 1
            }
        }

        if value > 0 {
            result.insert(UInt8(value), at: 0)
        }

        for char in base58 {
            guard char == "1" else { break }
            leadingZeros += 1
        }

        result.insert(contentsOf: repeatElement(0, count: leadingZeros), at: 0)
        return result
    }
}
