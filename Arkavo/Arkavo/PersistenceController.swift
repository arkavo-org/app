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
        // Use SwiftData's native predicate syntax
        let descriptor = FetchDescriptor<Account>(predicate: #Predicate { $0.id == 0 })

        if let existingAccount = try mainContext.fetch(descriptor).first {
            print("PersistenceController: Fetched existing account.")
            return existingAccount
        } else {
            print("PersistenceController: Creating new account.")
            let newAccount = Account()
            // Do not create a default profile - let registration flow handle profile creation
            mainContext.insert(newAccount)
            try mainContext.save()
            print("PersistenceController: New account created and saved (no profile).")
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

    // MARK: - Data Integrity Methods

    /// Validates streams by checking their type without accessing potentially invalid Thought references
    /// Returns streams grouped by type
    func validateStreamsWithoutAccessingThoughts() async throws -> (videoStream: Stream?, postStream: Stream?, innerCircleStream: Stream?) {
        print("PersistenceController: Validating streams...")

        // Fetch all streams
        let streams = try mainContext.fetch(FetchDescriptor<Stream>())

        var videoStream: Stream?
        var postStream: Stream?
        var innerCircleStream: Stream?

        for stream in streams {
            // Check for InnerCircle stream (doesn't depend on Thought)
            if stream.isInnerCircleStream {
                innerCircleStream = stream
                print("PersistenceController: Found InnerCircle stream: \(stream.id)")
                continue
            }

            // For other streams, we'll try to identify them by other characteristics
            // or handle them as unknown streams that may need recreation
            // We cannot safely access stream.source without risking a crash

            // If we have profile information, we might infer the stream type
            if stream.profile.name.lowercased().contains("video") {
                videoStream = stream
                print("PersistenceController: Found potential video stream by name: \(stream.id)")
            } else if stream.profile.name.lowercased().contains("post") {
                postStream = stream
                print("PersistenceController: Found potential post stream by name: \(stream.id)")
            }
        }

        return (videoStream, postStream, innerCircleStream)
    }

    /// Removes all streams that might have invalid Thought references
    /// This is a more aggressive approach but ensures app stability
    func removeStreamsWithPotentiallyInvalidThoughts() async throws {
        print("PersistenceController: Removing streams with potential invalid thoughts...")

        let account = try await getOrCreateAccount()
        let streams = account.streams

        // Keep only InnerCircle streams (which don't have source thoughts)
        let safeStreams = streams.filter(\.isInnerCircleStream)
        let removedCount = streams.count - safeStreams.count

        if removedCount > 0 {
            print("PersistenceController: Removing \(removedCount) streams that may have invalid thoughts")

            // Remove non-InnerCircle streams
            for stream in streams where !stream.isInnerCircleStream {
                mainContext.delete(stream)
            }

            try await saveChanges()
            print("PersistenceController: Successfully removed \(removedCount) streams")
        } else {
            print("PersistenceController: No streams need to be removed")
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
        // Use SwiftData's native predicate syntax
        var fetchDescriptor = FetchDescriptor<Profile>(predicate: #Predicate { $0.publicID == publicID })
        fetchDescriptor.fetchLimit = 1 // Limiting results for efficiency
        let profiles = try mainContext.fetch(fetchDescriptor)
        return profiles.first
    }

    /// Saves or updates a peer's profile record in the local database.
    /// Optionally updates the peer's public KeyStore data (`keyStorePublic`) and/or
    /// the local user's private KeyStore data generated for this peer relationship (`keyStorePrivate`).
    /// This method specifically handles *peer* profiles.
    /// - Parameters:
    ///   - peerProfile: The profile object representing the peer.
    ///   - keyStorePublicData: Optional: The peer's public KeyStore data to save/update in `peerProfile.keyStorePublic`.
    ///   - keyStorePrivateData: Optional: The local user's private KeyStore data for this relationship to save/update in `peerProfile.keyStorePrivate`.
    func savePeerProfile(_ peerProfile: Profile, keyStorePublicData: Data? = nil, keyStorePrivateData: Data? = nil) async throws {
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
            // Update public KeyStore data if provided
            if let publicData = keyStorePublicData {
                existingProfile.keyStorePublic = publicData
                print("PersistenceController: Updated peer's public KeyStore data for profile \(existingProfile.publicID.base58EncodedString)")
            }
            // Update local private KeyStore data for this relationship if provided
            if let privateData = keyStorePrivateData {
                existingProfile.keyStorePrivate = privateData
                print("PersistenceController: Updated local private KeyStore data for relationship with peer \(existingProfile.publicID.base58EncodedString)")
            }
        } else {
            // Insert new peer profile
            print("PersistenceController: Saving new peer profile: \(peerProfile.publicID.base58EncodedString)")
            // Set public KeyStore data if provided
            if let publicData = keyStorePublicData {
                peerProfile.keyStorePublic = publicData
                print("PersistenceController: Added peer's public KeyStore data for new profile \(peerProfile.publicID.base58EncodedString)")
            }
            // Set local private KeyStore data for this relationship if provided
            if let privateData = keyStorePrivateData {
                peerProfile.keyStorePrivate = privateData
                print("PersistenceController: Added local private KeyStore data for relationship with new peer \(peerProfile.publicID.base58EncodedString)")
            }
            mainContext.insert(peerProfile)
        }

        try await saveChanges() // Save the insert or update
    }

    /// Deletes a profile and its associated KeyStore data (public and private).
    /// If this is the user's profile, it will reset the account to have no profile and create a new empty one.
    func deleteProfile(_ profile: Profile) async throws {
        print("PersistenceController: Deleting profile: \(profile.publicID.base58EncodedString)")

        // Clear KeyStore data first
        profile.keyStorePublic = nil
        profile.keyStorePrivate = nil

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

    /// Deletes the stored P2P relationship KeyStore data (both the peer's public keys in `keyStorePublic`
    /// and the local user's private keys for this relationship in `keyStorePrivate`) for a given peer profile,
    /// keeping the profile record itself.
    /// This is used when trust is revoked or the P2P relationship ends.
    /// This does **not** affect the local user's permanent keys managed elsewhere (e.g., Keychain).
    func deleteKeyStoreDataFor(profile: Profile) async throws {
        print("PersistenceController: Deleting P2P relationship KeyStore data for peer profile: \(profile.publicID.base58EncodedString)")

        // Ensure we are using the profile instance from the context if possible
        guard let profileInContext = try await fetchProfile(withPublicID: profile.publicID) else {
            print("PersistenceController: Profile not found. Cannot delete KeyStore data.")
            throw ArkavoError.profileError("Profile not found in the database")
        }

        // Clear both the peer's public keys and the local private keys for this relationship
        profileInContext.keyStorePublic = nil
        profileInContext.keyStorePrivate = nil

        // Save changes
        try await saveChanges()
        print("PersistenceController: P2P relationship KeyStore data successfully removed for peer profile \(profileInContext.publicID.base58EncodedString)")
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
        // Use SwiftData's native predicate syntax
        let descriptor = FetchDescriptor<Profile>(
            predicate: #Predicate { $0.publicID != userProfilePublicID },
            sortBy: [SortDescriptor(\.name)] // Sort alphabetically
        )
        return try mainContext.fetch(descriptor)
    }

    /// Fetches all profiles stored, including the main user's profile.
    func fetchAllProfiles() async throws -> [Profile] {
        // Create a fetch descriptor for all profiles, sorted by name
        let descriptor = FetchDescriptor<Profile>(sortBy: [SortDescriptor(\.name)])
        return try mainContext.fetch(descriptor)
    }

    // MARK: - Stream Operations

    func fetchStream(withID id: UUID) async throws -> Stream? {
        // Use SwiftData's native predicate syntax
        try mainContext.fetch(FetchDescriptor<Stream>(predicate: #Predicate { $0.id == id })).first
    }

    func fetchStream(withPublicID publicID: Data) async throws -> Stream? {
        // Use SwiftData's native predicate syntax
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
        // Use SwiftData's native predicate syntax
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

    func deleteThought(_ thought: Thought) async throws {
        mainContext.delete(thought)
        try await saveChanges()
        print("PersistenceController: Thought deleted with publicID: \(thought.publicID.base58EncodedString)")
    }

    func fetchThoughtsForStream(withPublicID streamPublicID: Data) async throws -> [Thought] {
        // Use SwiftData's native predicate syntax for nested properties
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
        // Use SwiftData's native predicate syntax
        var descriptor = FetchDescriptor<BlockedProfile>(
            predicate: #Predicate { $0.blockedPublicID == publicID }
        )
        descriptor.fetchLimit = 1 // Optimization for faster queries
        // Fetch the blocked profiles that match the predicate
        let blockedProfiles = try mainContext.fetch(descriptor)
        // Return true if any matching profile is found
        return !blockedProfiles.isEmpty
    }

    /// Removes a profile from the blocked list
    func unblockProfile(withPublicID publicID: Data) async throws {
        // Use SwiftData's native predicate syntax
        let descriptor = FetchDescriptor<BlockedProfile>(
            predicate: #Predicate { $0.blockedPublicID == publicID }
        )

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
