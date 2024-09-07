import Foundation
import SwiftData

@MainActor
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
            print(modelConfiguration.url)

            container = try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Failed to create ModelContainer: \(error.localizedDescription)")
        }
    }

    // MARK: - Account Operations

    func getOrCreateAccount() throws -> Account {
        let context = container.mainContext
        let descriptor = FetchDescriptor<Account>(predicate: #Predicate { $0.id == 0 })

        if let existingAccount = try context.fetch(descriptor).first {
            return existingAccount
        } else {
            let newAccount = Account()
            context.insert(newAccount)
            try context.save()
            return newAccount
        }
    }

    // MARK: - Utility Methods

    func saveChanges() throws {
        let context = container.mainContext
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
        container.mainContext.insert(profile)
        return profile
    }

    func fetchProfile(withID id: UUID) throws -> Profile? {
        try container.mainContext.fetch(FetchDescriptor<Profile>(predicate: #Predicate { $0.id == id })).first
    }
}
