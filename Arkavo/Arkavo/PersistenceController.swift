import Foundation
import SwiftData

@globalActor actor PersistenceActor {
    static let shared = PersistenceActor()
}

@PersistenceActor
class PersistenceController {
    static let shared = PersistenceController()

    let container: ModelContainer

    private init() {
        do {
            let schema = Schema([
                Account.self,
                Profile.self,
            ])
            let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
            container = try ModelContainer(for: schema, configurations: [modelConfiguration])
//            print("PersistenceController: ModelContainer created successfully")
        } catch {
//            print("PersistenceController: Failed to create ModelContainer: \(error.localizedDescription)")
            fatalError("Failed to create ModelContainer: \(error.localizedDescription)")
        }
    }

    // MARK: - Account Operations

    func getOrCreateAccount() async throws -> Account {
        let context = await container.mainContext
        let descriptor = FetchDescriptor<Account>(predicate: #Predicate { $0.id == 0 })

        if let existingAccount = try context.fetch(descriptor).first {
//            print("PersistenceController: Fetched existing account")
            return existingAccount
        } else {
//            print("PersistenceController: Creating new account")
            let newAccount = Account()
            context.insert(newAccount)
            try context.save()
            return newAccount
        }
    }

    // MARK: - Utility Methods

    func saveChanges() async throws {
        let context = await container.mainContext
        if context.hasChanges {
            try context.save()
            print("PersistenceController: Changes saved successfully")
        } else {
            print("PersistenceController: No changes to save")
        }
    }

    // MARK: - Profile Operations

    func createProfile(name: String, blurb: String?) -> Profile {
        let profile = Profile(name: name, blurb: blurb)
        Task { @MainActor in
            container.mainContext.insert(profile)
        }
        return profile
    }

    func fetchProfile(withID id: UUID) async throws -> Profile? {
        try await withCheckedThrowingContinuation { continuation in
            Task { @MainActor in
                do {
                    let result = try container.mainContext.fetch(FetchDescriptor<Profile>(predicate: #Predicate { $0.id == id })).first
                    continuation.resume(returning: result)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
}
