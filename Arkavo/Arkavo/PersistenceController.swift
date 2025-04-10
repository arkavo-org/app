import Foundation
import SwiftData

@MainActor
class PersistenceController {
    static let shared = PersistenceController()

    let container: ModelContainer

    // Main context for database operations
    var mainContext: ModelContext {
        container.mainContext
    }

    private init() {
        do {
            // Define schema for the database models
            let schema = Schema([
                Account.self,
                Profile.self,
                Stream.self,
                Thought.self,
                BlockedProfile.self,
            ])
            let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
            print("PersistenceController: Model Store URL: \(modelConfiguration.url)")

            container = try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Failed to create ModelContainer: \(error.localizedDescription)")
        }
    }

    // MARK: - Account Operations

    func getOrCreateAccount() async throws -> Account {
        let descriptor = FetchDescriptor<Account>(predicate: #Predicate { $0.id == 0 })

        if let existingAccount = try mainContext.fetch(descriptor).first {
            print("PersistenceController: Fetched existing account.")
            return existingAccount
        } else {
            print("PersistenceController: Creating new account.")
            let newAccount = Account()
            // Create the initial user profile with placeholder name
            let userProfile = Profile(name: "Me")
            newAccount.profile = userProfile // Associate profile with account
            mainContext.insert(newAccount) // Insert account (will also insert profile due to relationship)
            try mainContext.save()
            print("PersistenceController: New account and initial profile created and saved.")
            return newAccount
        }
    }

    // MARK: - Utility Methods

    func saveChanges() async throws {
        if mainContext.hasChanges {
            try mainContext.save()
            print("PersistenceController: Changes saved successfully")
        } else {
            print("PersistenceController: No changes to save")
        }
    }

    // MARK: - Profile Operations

    /// Saves the primary user profile, typically during initial setup or significant updates.
    /// For peer profiles, use `savePeerProfile`.
    func saveUserProfile(_ profile: Profile) throws {
        // Only insert profile if it's not already in a context
        if profile.modelContext == nil {
            mainContext.insert(profile)
        } else {
            print("PersistenceController: User profile is already in context, changes will be saved on `saveChanges`.")
        }
        try mainContext.save()
        print("PersistenceController: User Profile saved/updated successfully")
    }

    /// Fetches any profile (user's or peer's) based on its publicID.
    func fetchProfile(withPublicID publicID: Data) async throws -> Profile? {
        var fetchDescriptor = FetchDescriptor<Profile>(predicate: #Predicate { $0.publicID == publicID })
        fetchDescriptor.fetchLimit = 1 // Limiting results for efficiency
        let profiles = try mainContext.fetch(fetchDescriptor)
        return profiles.first
    }

    /// Saves or updates a profile received from a peer.
    /// Updates `lastSeen` timestamp. Does not overwrite the main user's profile.
    func savePeerProfile(_ peerProfile: Profile) async throws {
        let userAccount = try await getOrCreateAccount()

        // Prevent overwriting the user's own profile through this method
        guard peerProfile.publicID != userAccount.profile?.publicID else {
            print("PersistenceController: Attempted to save own profile using savePeerProfile. Skipping.")
            return
        }

        // Check if a profile with this publicID already exists
        if let existingProfile = try await fetchProfile(withPublicID: peerProfile.publicID) {
            // Update existing peer profile
            print("PersistenceController: Updating existing peer profile: \(peerProfile.publicID.base58EncodedString)")
            existingProfile.name = peerProfile.name
            existingProfile.blurb = peerProfile.blurb
            existingProfile.interests = peerProfile.interests
            existingProfile.location = peerProfile.location
            existingProfile.hasHighEncryption = peerProfile.hasHighEncryption
            existingProfile.hasHighIdentityAssurance = peerProfile.hasHighIdentityAssurance
            existingProfile.did = peerProfile.did // Update DID/Handle if provided
            existingProfile.handle = peerProfile.handle
            existingProfile.lastSeen = Date() // Update last seen time
            // KeyStoreData is managed separately through dedicated methods
        } else {
            // Insert new peer profile
            print("PersistenceController: Saving new peer profile: \(peerProfile.publicID.base58EncodedString)")
            peerProfile.lastSeen = Date() // Set last seen time
            mainContext.insert(peerProfile)
        }

        try await saveChanges() // Save the insert or update
    }

    /// Deletes a profile and its associated KeyStore data.
    /// If this is the user's profile, it will reset the account to have no profile.
    func deleteProfile(_ profile: Profile) async throws {
        print("PersistenceController: Deleting profile: \(profile.publicID.base58EncodedString)")

        // Clear KeyStore data first
        profile.keyStoreData = nil
        profile.keyStoreCurve = nil
        profile.keyStoreCapacity = nil
        profile.keyStoreUpdatedAt = nil

        // Check if this is the user's profile
        let userAccount = try await getOrCreateAccount()
        let isUserProfile = userAccount.profile?.publicID == profile.publicID

        // For user's profile, we detach it from the account but don't delete it yet
        if isUserProfile {
            print("PersistenceController: Detaching user profile from account")
            userAccount.profile = nil
            try await saveChanges()
        }

        // Delete the profile from the context
        mainContext.delete(profile)
        try await saveChanges()

        print("PersistenceController: Profile successfully deleted")

        // If it was the user's profile, create a new empty one
        if isUserProfile {
            print("PersistenceController: Creating new empty profile for user account")
            let newProfile = Profile(name: "Me (New)")
            userAccount.profile = newProfile
            try await saveChanges()
        }
    }
    
    /// Deletes only the KeyStore data for a profile, keeping the profile itself.
    /// This is useful for removing a peer from the InnerCircle without deleting their profile.
    func deleteKeyStoreDataFor(profile: Profile) async throws {
        print("PersistenceController: Deleting KeyStore data for profile: \(profile.publicID.base58EncodedString)")
        
        // Ensure we are using the profile instance from the context if possible
        guard let profileInContext = try await fetchProfile(withPublicID: profile.publicID) else {
            print("PersistenceController: Profile not found. Cannot delete KeyStore data.")
            throw ArkavoError.profileError("Profile not found in the database")
        }
        
        // Clear all KeyStore-related data
        profileInContext.keyStoreData = nil
        profileInContext.keyStoreCurve = nil
        profileInContext.keyStoreCapacity = nil
        profileInContext.keyStoreUpdatedAt = nil
        
        // Save changes
        try await saveChanges()
        print("PersistenceController: KeyStore data successfully removed for profile \(profileInContext.publicID.base58EncodedString)")
    }

    /// Fetches all profiles stored, excluding the main user's profile associated with the Account.
    func fetchAllPeerProfiles() async throws -> [Profile] {
        let userAccount = try await getOrCreateAccount()
        guard let userProfilePublicID = userAccount.profile?.publicID else {
            // If user profile doesn't exist, return all profiles as a fallback
            print("PersistenceController Warning: User profile missing when fetching peers - returning all profiles.")
            return try mainContext.fetch(FetchDescriptor<Profile>())
        }

        // Fetch all profiles *except* the one matching the user's publicID
        let predicate = #Predicate<Profile> { $0.publicID != userProfilePublicID }
        let descriptor = FetchDescriptor<Profile>(predicate: predicate, sortBy: [SortDescriptor(\.name)]) // Sort alphabetically
        return try mainContext.fetch(descriptor)
    }

    /// Fetches all profiles stored, including the main user's profile.
    func fetchAllProfiles() async throws -> [Profile] {
        // Create a fetch descriptor for all profiles, sorted by name
        let descriptor = FetchDescriptor<Profile>(sortBy: [SortDescriptor(\.name)])
        return try mainContext.fetch(descriptor)
    }

    // MARK: - KeyStore Operations

    /// Saves or updates the KeyStore data associated with a given Profile.
    func saveKeyStoreData(for profile: Profile, serializedData: Data, keyCurve: Curve, capacity: Int) async throws {
        // Ensure the profile is associated with the context
        guard let profileInContext = try await fetchProfile(withPublicID: profile.publicID) else {
            print("PersistenceController Error: Profile \(profile.publicID.base58EncodedString) not found in context. Cannot save KeyStore data.")
            throw ArkavoError.profileError("Profile not managed by context.")
        }

        // Update the profile with KeyStore data
        print("PersistenceController: Updating KeyStore data for profile \(profileInContext.publicID.base58EncodedString)")
        profileInContext.keyStoreData = serializedData
        profileInContext.keyStoreCurve = keyCurve.rawValue.description
        profileInContext.keyStoreCapacity = capacity
        profileInContext.keyStoreUpdatedAt = Date()

        try await saveChanges()
        print("PersistenceController: KeyStore data saved successfully for profile \(profileInContext.publicID.base58EncodedString)")
    }

    /// Gets KeyStore details for a specific Profile.
    /// Returns serialized data, curve, and capacity if available
    func getKeyStoreDetails(for profile: Profile) async throws -> (data: Data, curve: String, capacity: Int)? {
        // Ensure we are using the profile instance from the context if possible
        guard let profileInContext = try await fetchProfile(withPublicID: profile.publicID) else {
            print("PersistenceController: Profile \(profile.publicID.base58EncodedString) not found. Cannot fetch KeyStore data.")
            return nil
        }

        // Check if KeyStore data is available
        if let keyStoreData = profileInContext.keyStoreData,
           let keyStoreCurve = profileInContext.keyStoreCurve,
           let keyStoreCapacity = profileInContext.keyStoreCapacity
        {
            return (keyStoreData, keyStoreCurve, keyStoreCapacity)
        }

        return nil
    }

    // MARK: - Stream Operations

    func fetchStream(withID id: UUID) async throws -> Stream? {
        try mainContext.fetch(FetchDescriptor<Stream>(predicate: #Predicate { $0.id == id })).first
    }

    func fetchStream(withPublicID publicID: Data) async throws -> Stream? {
        let fetchDescriptor = FetchDescriptor<Stream>(predicate: #Predicate { $0.publicID == publicID })
        return try mainContext.fetch(fetchDescriptor).first
    }

    func saveStream(_ stream: Stream) throws {
        // Only insert stream if it's not already in a context
        if stream.modelContext == nil {
            mainContext.insert(stream)
        } else {
            print("PersistenceController: Stream is already in context, changes will be saved on `saveChanges`.")
        }
        try mainContext.save()
        print("PersistenceController: Stream saved successfully")
    }

    func deleteStreams(at offsets: IndexSet, from account: Account) async throws {
        // Create a copy of IDs to delete to avoid mutation issues while iterating
        let streamsToDelete = offsets.map { account.streams[$0] }
        for stream in streamsToDelete {
            mainContext.delete(stream) // Delete the stream object itself
        }
        // The relationship on Account updates automatically due to SwiftData's relationship management

        try await saveChanges()
        print("PersistenceController: Deleted streams at specified offsets.")
    }

    // MARK: - Thought Operations

    func fetchThought(withPublicID publicID: Data) async throws -> [Thought]? {
        let fetchDescriptor = FetchDescriptor<Thought>(predicate: #Predicate { $0.publicID == publicID })
        return try mainContext.fetch(fetchDescriptor)
    }

    func saveThought(_ thought: Thought) async throws -> Bool {
        do {
            // Check if a thought with the same publicID already exists
            let existing = try await fetchThought(withPublicID: thought.publicID)
            guard existing?.isEmpty ?? true else {
                print("PersistenceController: Thought with publicID \(thought.publicID.base58EncodedString) already exists. Skipping save.")
                return false // Indicate that no new thought was saved
            }

            // Insert the new thought if none exist with the same publicID
            mainContext.insert(thought)
            try mainContext.save()
            print("PersistenceController: Thought saved successfully \(thought.publicID.base58EncodedString)")
            return true // Indicate successful save
        } catch {
            print("PersistenceController: Failed to fetch or save Thought: \(error.localizedDescription)")
            throw error
        }
    }

    func fetchThoughtsForStream(withPublicID streamPublicID: Data) async throws -> [Thought] {
        let descriptor = FetchDescriptor<Thought>(
            predicate: #Predicate<Thought> { thought in
                thought.metadata.streamPublicID == streamPublicID
            },
            sortBy: [SortDescriptor(\.metadata.createdAt)]
        )
        return try mainContext.fetch(descriptor)
    }

    /// Associates a Thought with a Stream safely within the main context to prevent orphaned relationships.
    func associateThoughtWithStream(thought: Thought, stream: Stream) async {
        print("PersistenceController: Associating thought \(thought.publicID.base58EncodedString) with stream \(stream.publicID.base58EncodedString)")

        // Ensure both models are managed by the main context to maintain data integrity
        guard thought.modelContext == mainContext, stream.modelContext == mainContext else {
            print("PersistenceController Error: Thought or Stream is not managed by the main context. Cannot associate.")
            return
        }

        // Prevent duplicate associations in the relationship array
        if !(stream.thoughts.contains { $0.persistentModelID == thought.persistentModelID }) {
            stream.thoughts.append(thought)
            do {
                try await saveChanges()
                print("PersistenceController: Successfully associated thought with stream.")
            } catch {
                print("PersistenceController Error: Failed to save changes after associating thought: \(error)")
            }
        } else {
            print("PersistenceController: Thought \(thought.publicID.base58EncodedString) already associated with stream \(stream.publicID.base58EncodedString).")
        }
    }

    // MARK: - BlockedProfile Operations

    func saveBlockedProfile(_ blockedProfile: BlockedProfile) async throws {
        // Get current user's profile public ID
        let userAccount = try await getOrCreateAccount()
        guard let userProfilePublicID = userAccount.profile?.publicID else {
            print("PersistenceController Error: Current user profile not found. Cannot block profile.")
            throw ArkavoError.profileError("Current profile not found")
        }

        // Prevent blocking self as a data integrity measure
        if blockedProfile.blockedPublicID == userProfilePublicID {
            print("PersistenceController Error: Attempted to block own profile.")
            throw ArkavoError.profileError("Cannot block own profile")
        }

        // Check if already blocked to prevent duplicates
        let alreadyBlocked = try await isBlockedProfile(blockedProfile.blockedPublicID)
        if alreadyBlocked {
            print("PersistenceController: Profile \(blockedProfile.blockedPublicID.base58EncodedString) is already blocked.")
            return
        }

        mainContext.insert(blockedProfile)
        try await saveChanges()
        print("PersistenceController: Blocked profile \(blockedProfile.blockedPublicID.base58EncodedString) saved.")
    }

    func fetchBlockedProfiles() async throws -> [BlockedProfile] {
        let descriptor = FetchDescriptor<BlockedProfile>()
        return try mainContext.fetch(descriptor)
    }

    func isBlockedProfile(_ publicID: Data) async throws -> Bool {
        // Define a predicate to filter blocked profiles by the given publicID
        let predicate = #Predicate<BlockedProfile> { $0.blockedPublicID == publicID }
        // Create a FetchDescriptor with the predicate
        var descriptor = FetchDescriptor<BlockedProfile>(predicate: predicate)
        descriptor.fetchLimit = 1 // Optimization for faster queries
        // Fetch the blocked profiles that match the predicate
        let blockedProfiles = try mainContext.fetch(descriptor)
        // Return true if any matching profile is found
        return !blockedProfiles.isEmpty
    }

    /// Removes a profile from the blocked list
    func unblockProfile(withPublicID publicID: Data) async throws {
        let predicate = #Predicate<BlockedProfile> { $0.blockedPublicID == publicID }
        let descriptor = FetchDescriptor<BlockedProfile>(predicate: predicate)

        let blockedEntries = try mainContext.fetch(descriptor)
        if blockedEntries.isEmpty {
            print("PersistenceController: Profile \(publicID.base58EncodedString) was not blocked.")
            return // No action needed if not blocked
        }

        for entry in blockedEntries {
            mainContext.delete(entry)
        }

        try await saveChanges()
        print("PersistenceController: Unblocked profile \(publicID.base58EncodedString).")
    }
}
