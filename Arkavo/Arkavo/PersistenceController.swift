import Foundation
import OpenTDFKit // Needed for KeyStoreData parameters
import SwiftData

@MainActor
class PersistenceController {
    static let shared = PersistenceController()

    let container: ModelContainer

    // Convenience accessor for the main context
    var mainContext: ModelContext {
        container.mainContext
    }

    private init() {
        do {
            // Define the schema (no separate KeyStoreData model)
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
        // Use the mainContext property
        let descriptor = FetchDescriptor<Account>(predicate: #Predicate { $0.id == 0 })

        if let existingAccount = try mainContext.fetch(descriptor).first {
            print("PersistenceController: Fetched existing account.")
            // Ensure the profile relationship is loaded if needed later
            // (SwiftData often lazy loads, but explicit fetch can be useful)
            // _ = existingAccount.profile
            return existingAccount
        } else {
            print("PersistenceController: Creating new account.")
            let newAccount = Account()
            // Create the initial user profile associated with the account
            let userProfile = Profile(name: "Me") // Default name, user can change later
            newAccount.profile = userProfile // Associate profile with account
            mainContext.insert(newAccount) // Insert account (will also insert profile due to relationship)
            try mainContext.save()
            print("PersistenceController: New account and initial profile created and saved.")
            return newAccount
        }
    }

    // MARK: - Utility Methods

    func saveChanges() async throws {
        // Use the mainContext property
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
        // Use the mainContext property
        // Check if it's already inserted before inserting again
        if profile.modelContext == nil {
            mainContext.insert(profile)
        } else {
            print("PersistenceController: User profile is already in context, changes will be saved on `saveChanges`.")
        }
        try mainContext.save() // Consider if saveChanges() should be used instead for consistency
        print("PersistenceController: User Profile saved/updated successfully")
    }

    /// Fetches any profile (user's or peer's) based on its publicID.
    func fetchProfile(withPublicID publicID: Data) async throws -> Profile? {
        var fetchDescriptor = FetchDescriptor<Profile>(predicate: #Predicate { $0.publicID == publicID })
        fetchDescriptor.fetchLimit = 1 // Optimization: we only expect one
        // Use the mainContext property
        let profiles = try mainContext.fetch(fetchDescriptor)
        return profiles.first
    }

    /// Saves or updates a profile received from a peer.
    /// Updates `lastSeen` timestamp. Does not overwrite the main user's profile.
    func savePeerProfile(_ peerProfile: Profile) async throws {
        // Use the mainContext property
        let userAccount = try await getOrCreateAccount()

        // Ensure we don't accidentally try to save the user's own profile via this method
        guard peerProfile.publicID != userAccount.profile?.publicID else {
            print("PersistenceController: Attempted to save own profile using savePeerProfile. Skipping.")
            // Optionally update fields if needed, but generally avoid replacing the main profile object here.
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
            // Note: We don't overwrite keyStoreData here. It's managed separately.
        } else {
            // Insert new peer profile
            print("PersistenceController: Saving new peer profile: \(peerProfile.publicID.base58EncodedString)")
            peerProfile.lastSeen = Date() // Set last seen time
            mainContext.insert(peerProfile)
        }

        try await saveChanges() // Save the insert or update
    }

    /// Fetches all profiles stored, excluding the main user's profile associated with the Account.
    func fetchAllPeerProfiles() async throws -> [Profile] {
        // Use the mainContext property
        let userAccount = try await getOrCreateAccount()
        guard let userProfilePublicID = userAccount.profile?.publicID else {
            // If user profile doesn't exist yet, return all profiles (shouldn't happen ideally)
            print("PersistenceController Warning: User profile not found while fetching peers.")
            return try mainContext.fetch(FetchDescriptor<Profile>())
        }

        // Fetch all profiles *except* the one matching the user's publicID
        let predicate = #Predicate<Profile> { $0.publicID != userProfilePublicID }
        let descriptor = FetchDescriptor<Profile>(predicate: predicate, sortBy: [SortDescriptor(\.name)]) // Sort alphabetically
        return try mainContext.fetch(descriptor)
    }

    /// Fetches all profiles stored, including the main user's profile.
    func fetchAllProfiles() async throws -> [Profile] {
        // Use the mainContext property
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
        // Use the mainContext property
        try mainContext.fetch(FetchDescriptor<Stream>(predicate: #Predicate { $0.id == id })).first
    }

    func fetchStream(withPublicID publicID: Data) async throws -> Stream? {
        let fetchDescriptor = FetchDescriptor<Stream>(predicate: #Predicate { $0.publicID == publicID })
        // Use the mainContext property
        return try mainContext.fetch(fetchDescriptor).first
    }

    func saveStream(_ stream: Stream) throws {
        // Use the mainContext property
        // Check if it's already inserted before inserting again
        if stream.modelContext == nil {
            mainContext.insert(stream)
        } else {
            print("PersistenceController: Stream is already in context, changes will be saved on `saveChanges`.")
        }
        try mainContext.save() // Consider using saveChanges()
        print("PersistenceController: Stream saved successfully")
    }

    func deleteStreams(at offsets: IndexSet, from account: Account) async throws {
        // Ensure account is managed in the current context if necessary
        // let context = container.mainContext
        // guard let accountInContext = context.registeredModel(for: account.persistentModelID) else { ... }
        // Operate on accountInContext.streams

        // Assuming 'account' is already the managed instance from the context:
        // Create a copy of IDs to delete to avoid mutation issues while iterating
        let streamsToDelete = offsets.map { account.streams[$0] }
        for stream in streamsToDelete {
            mainContext.delete(stream) // Delete the stream object itself
        }
        // The relationship on Account should update automatically.
        // account.streams.remove(atOffsets: offsets) // This might also work depending on cascade rules and context management

        try await saveChanges()
        print("PersistenceController: Deleted streams at specified offsets.")
    }

    // MARK: - Thought Operations

    func fetchThought(withPublicID publicID: Data) async throws -> [Thought]? {
        let fetchDescriptor = FetchDescriptor<Thought>(predicate: #Predicate { $0.publicID == publicID })
        // Use the mainContext property
        return try mainContext.fetch(fetchDescriptor)
    }

    func saveThought(_ thought: Thought) async throws -> Bool {
        // Use the mainContext property
        do {
            // Check if a thought with the same publicID already exists
            let existing = try await fetchThought(withPublicID: thought.publicID)
            guard existing?.isEmpty ?? true else {
                print("PersistenceController: Thought with publicID \(thought.publicID.base58EncodedString) already exists. Skipping save.")
                // Optionally, update the existing thought if needed, but current logic prevents duplicates.
                return false // Indicate that no new thought was saved
            }

            // Insert the new thought if none exist with the same publicID
            mainContext.insert(thought)
            try mainContext.save() // Consider using saveChanges()
            print("PersistenceController: Thought saved successfully \(thought.publicID.base58EncodedString)")
            return true // Indicate successful save
        } catch {
            print("PersistenceController: Failed to fetch or save Thought: \(error.localizedDescription)")
            // Rethrow or handle more gracefully depending on requirements
            throw error // Rethrowing might be better to signal failure upstream
            // return false
        }
    }

    func fetchThoughtsForStream(withPublicID streamPublicID: Data) async throws -> [Thought] {
        let descriptor = FetchDescriptor<Thought>(
            predicate: #Predicate<Thought> { thought in
                thought.metadata.streamPublicID == streamPublicID
            },
            sortBy: [SortDescriptor(\.metadata.createdAt)] // Assuming createdAt is comparable
        )
        // Use the mainContext property
        return try mainContext.fetch(descriptor)
    }

    /// **FIX:** Added function to associate a Thought with a Stream safely within the main context.
    func associateThoughtWithStream(thought: Thought, stream: Stream) async {
        print("PersistenceController: Associating thought \(thought.publicID.base58EncodedString) with stream \(stream.publicID.base58EncodedString)")

        // Ensure both models are managed by the main context.
        // If they were fetched/created using this PersistenceController instance, they should be.
        guard thought.modelContext == mainContext, stream.modelContext == mainContext else {
            print("PersistenceController Error: Thought or Stream is not managed by the main context. Cannot associate.")
            // Attempt to re-fetch within the context if necessary, though this indicates a potential logic issue elsewhere.
            // For now, we'll just log the error and return.
            return
        }

        // Check if the thought is already associated to prevent duplicates in the array
        // Note: SwiftData might handle this automatically, but explicit check is safer.
        if !(stream.thoughts.contains { $0.persistentModelID == thought.persistentModelID }) {
            stream.thoughts.append(thought)
            do {
                try await saveChanges()
                print("PersistenceController: Successfully associated thought with stream.")
            } catch {
                print("PersistenceController Error: Failed to save changes after associating thought: \(error)")
                // Consider removing the thought if save fails to maintain consistency,
                // though this depends on desired error handling.
                // stream.thoughts.removeAll { $0.persistentModelID == thought.persistentModelID }
            }
        } else {
            print("PersistenceController: Thought \(thought.publicID.base58EncodedString) already associated with stream \(stream.publicID.base58EncodedString).")
        }
    }


    // MARK: - BlockedProfile Operations

    func saveBlockedProfile(_ blockedProfile: BlockedProfile) async throws {
        // Use the mainContext property

        // Get current user's profile public ID
        let userAccount = try await getOrCreateAccount()
        guard let userProfilePublicID = userAccount.profile?.publicID else {
            print("PersistenceController Error: Current user profile not found. Cannot block profile.")
            throw ArkavoError.profileError("Current profile not found")
        }

        // Prevent blocking self
        if blockedProfile.blockedPublicID == userProfilePublicID {
            print("PersistenceController Error: Attempted to block own profile.")
            throw ArkavoError.profileError("Cannot block own profile")
        }

        // Check if already blocked
        let alreadyBlocked = try await isBlockedProfile(blockedProfile.blockedPublicID)
        if alreadyBlocked {
            print("PersistenceController: Profile \(blockedProfile.blockedPublicID.base58EncodedString) is already blocked.")
            return // Or throw an error if desired
        }

        mainContext.insert(blockedProfile)
        try await saveChanges()
        print("PersistenceController: Blocked profile \(blockedProfile.blockedPublicID.base58EncodedString) saved.")
    }

    func fetchBlockedProfiles() async throws -> [BlockedProfile] {
        let descriptor = FetchDescriptor<BlockedProfile>()
        // Use the mainContext property
        return try mainContext.fetch(descriptor)
    }

    func isBlockedProfile(_ publicID: Data) async throws -> Bool {
        // Define a predicate to filter blocked profiles by the given publicID
        let predicate = #Predicate<BlockedProfile> { $0.blockedPublicID == publicID }
        // Create a FetchDescriptor with the predicate
        var descriptor = FetchDescriptor<BlockedProfile>(predicate: predicate)
        descriptor.fetchLimit = 1 // Optimization
        // Fetch the blocked profiles that match the predicate
        // Use the mainContext property
        let blockedProfiles = try mainContext.fetch(descriptor)
        // Return true if any matching profile is found
        return !blockedProfiles.isEmpty
    }

    // Add a method to unblock a profile
    func unblockProfile(withPublicID publicID: Data) async throws {
        // Use the mainContext property
        let predicate = #Predicate<BlockedProfile> { $0.blockedPublicID == publicID }
        let descriptor = FetchDescriptor<BlockedProfile>(predicate: predicate)

        let blockedEntries = try mainContext.fetch(descriptor)
        if blockedEntries.isEmpty {
            print("PersistenceController: Profile \(publicID.base58EncodedString) was not blocked.")
            return // Nothing to unblock
        }

        for entry in blockedEntries {
            mainContext.delete(entry)
        }

        try await saveChanges()
        print("PersistenceController: Unblocked profile \(publicID.base58EncodedString).")
    }
}

// No extension needed, use the existing ArkavoError directly
// The enum already has a profileError case available
