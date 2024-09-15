import SwiftData
import SwiftUI

@main
struct ArkavoApp: App {
    @Environment(\.scenePhase) private var scenePhase
    let persistenceController = PersistenceController.shared

    var body: some Scene {
        WindowGroup {
            ArkavoView()
                .modelContainer(persistenceController.container)
                .task {
                    await ensureAccountExists()
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
}

extension Notification.Name {
    static let closeWebSockets = Notification.Name("CloseWebSockets")
}
