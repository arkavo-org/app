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
                Stream.self,
                Thought.self,
            ])
            let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
            print(modelConfiguration.url)

            container = try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Failed to create ModelContainer: \(error.localizedDescription)")
        }
    }

    // MARK: - Account Operations

    func getOrCreateAccount() async throws -> Account {
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

    func saveChanges() async throws {
        let context = container.mainContext
        if context.hasChanges {
            try context.save()
            print("PersistenceController: Changes saved successfully")
        } else {
            print("PersistenceController: No changes to save")
        }
    }

    // MARK: - Profile Operations

    func fetchProfile(withID id: UUID) throws -> Profile? {
        try container.mainContext.fetch(FetchDescriptor<Profile>(predicate: #Predicate { $0.id == id })).first
    }

    // MARK: - Stream Operations

    func fetchStream(withID id: UUID) async throws -> Stream? {
        try container.mainContext.fetch(FetchDescriptor<Stream>(predicate: #Predicate { $0.id == id })).first
    }

    func fetchStream(withPublicID publicID: Data) async throws -> [Stream]? {
        let fetchDescriptor = FetchDescriptor<Stream>(predicate: #Predicate { $0.publicID == publicID })
        return try container.mainContext.fetch(fetchDescriptor)
    }
}
