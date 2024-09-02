import SwiftData
import SwiftUI

@main
struct ArkavoApp: App {
    @Environment(\.scenePhase) private var scenePhase
    var sharedModelContainer: ModelContainer = {
        let schema = Schema([Account.self, Profile.self, Stream.self])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        print(modelConfiguration.url)
        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            ArkavoView()
                .onAppear {
                    Task {
                        createAccountIfNeeded()
                    }
                }
            #if os(macOS)
                .frame(minWidth: 800, idealWidth: 1200, maxWidth: .infinity,
                       minHeight: 600, idealHeight: 800, maxHeight: .infinity)
            #endif
        }
        .modelContainer(sharedModelContainer)
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .background {
                NotificationCenter.default.post(name: .closeWebSockets, object: nil)
            }
        }
        #if os(macOS)
        .windowStyle(HiddenTitleBarWindowStyle())
        .defaultSize(width: 1200, height: 800)
        #endif
    }

    @MainActor
    private func createAccountIfNeeded() {
        do {
            let context = sharedModelContainer.mainContext
            let fetchDescriptor = FetchDescriptor<Account>(predicate: nil, sortBy: [])
            let existingAccounts = try context.fetch(fetchDescriptor)

            if existingAccounts.isEmpty {
                let newAccount = Account()
                context.insert(newAccount)
                try context.save()
                print("New Account created with ID: \(newAccount.id)")
            } else {
                print("Existing Account found with ID: \(existingAccounts[0].id)")
            }
        } catch {
            print("Error checking/creating Account: \(error)")
        }
    }
}

extension Notification.Name {
    static let closeWebSockets = Notification.Name("CloseWebSockets")
}
