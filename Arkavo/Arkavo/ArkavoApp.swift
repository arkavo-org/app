import SwiftUI
import SwiftData

@main
struct ArkavoApp: App {
    @Environment(\.scenePhase) private var scenePhase
    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            SecureStreamModel.self,
        ])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(sharedModelContainer)
        .onChange(of: scenePhase) { oldPhase, newPhase in
            if newPhase == .background {
                // Close any open WebSockets
                NotificationCenter.default.post(name: .closeWebSockets, object: nil)
            }
        }
    }
}

extension Notification.Name {
    static let closeWebSockets = Notification.Name("CloseWebSockets")
}
