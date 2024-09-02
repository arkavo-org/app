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
                .onAppear {
                    Task {
                        await ensureAccountExists()
                    }
                }
            #if os(macOS)
                .frame(minWidth: 800, idealWidth: 1200, maxWidth: .infinity,
                       minHeight: 600, idealHeight: 800, maxHeight: .infinity)
            #endif
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .background {
                Task {
                    await saveChanges()
                }
                NotificationCenter.default.post(name: .closeWebSockets, object: nil)
            }
            if newPhase == .active {
                Task {
                    await ensureAccountExists()
                }
            }
        }
        #if os(macOS)
        .windowStyle(HiddenTitleBarWindowStyle())
        .defaultSize(width: 1200, height: 800)
        #endif
    }

    private func ensureAccountExists() async {
        do {
            let account = try await Task { @PersistenceActor in
                try await persistenceController.getOrCreateAccount()
            }.value
            print("ArkavoApp: Account ensured with ID: \(account.id)")
        } catch {
            print("ArkavoApp: Error ensuring Account exists: \(error.localizedDescription)")
        }
    }

    private func saveChanges() async {
        do {
            try await Task { @PersistenceActor in
                try await persistenceController.saveChanges()
            }.value
            print("ArkavoApp: Changes saved successfully")
        } catch {
            print("ArkavoApp: Error saving changes: \(error.localizedDescription)")
        }
    }
}

extension Notification.Name {
    static let closeWebSockets = Notification.Name("CloseWebSockets")
}
