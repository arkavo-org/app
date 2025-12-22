import ArkavoKit
import CryptoKit
import Foundation
import SwiftUI

// MARK: - Sync State

enum ProfileSyncState: Equatable {
    case idle
    case syncing
    case synced(ticket: String)
    case error(String)

    static func == (lhs: ProfileSyncState, rhs: ProfileSyncState) -> Bool {
        switch (lhs, rhs) {
        case (.idle, .idle), (.syncing, .syncing):
            true
        case let (.synced(l), .synced(r)):
            l == r
        case let (.error(l), .error(r)):
            l == r
        default:
            false
        }
    }
}

// MARK: - Creator Profile View Model

@MainActor
class CreatorProfileViewModel: ObservableObject {
    @Published var profile: CreatorProfile
    @Published var syncState: ProfileSyncState = .idle
    @Published var showError = false
    @Published var errorMessage: String?
    @Published var isSaving = false
    @Published var lastTicket: ProfileTicket?

    private let authState = ArkavoAuthState.shared
    private let draftKey = "CreatorProfileDraft"

    var canPublish: Bool {
        !profile.displayName.isEmpty && ArkavoIrohManager.shared.isReady
    }

    /// The profile service (from ArkavoIrohManager)
    private var profileService: IrohProfileService? {
        ArkavoIrohManager.shared.profileService
    }

    init() {
        // Load existing profile or create new one
        if let credentials = KeychainManager.getArkavoCredentials() {
            let publicID = Self.generatePublicID(from: credentials.handle)
            profile = CreatorProfile(
                publicID: publicID,
                did: credentials.did,
                handle: credentials.handle,
                displayName: credentials.handle
            )
            loadDraft()
        } else {
            // Create placeholder profile
            profile = CreatorProfile(
                displayName: ""
            )
        }
    }

    // MARK: - Public ID Generation

    private static func generatePublicID(from handle: String) -> Data {
        let data = handle.data(using: .utf8) ?? Data()
        return Data(SHA256.hash(data: data))
    }

    // MARK: - Draft Management

    func loadDraft() {
        if let data = UserDefaults.standard.data(forKey: draftKey),
           let savedProfile = try? CreatorProfile.fromData(data)
        {
            // Merge draft with current identity
            profile.displayName = savedProfile.displayName
            profile.bio = savedProfile.bio
            profile.avatarURL = savedProfile.avatarURL
            profile.bannerURL = savedProfile.bannerURL
            profile.socialLinks = savedProfile.socialLinks
            profile.contentCategories = savedProfile.contentCategories
            profile.streamingSchedule = savedProfile.streamingSchedule
            profile.patronTiers = savedProfile.patronTiers
            profile.featuredContentIDs = savedProfile.featuredContentIDs
        }
    }

    func saveDraft() async {
        isSaving = true
        defer { isSaving = false }

        do {
            profile.updatedAt = Date()
            let data = try profile.toData()
            UserDefaults.standard.set(data, forKey: draftKey)
            syncState = .idle
        } catch {
            showError = true
            errorMessage = "Failed to save draft: \(error.localizedDescription)"
        }
    }

    // MARK: - Publishing

    func publishProfile() async {
        guard canPublish else {
            errorMessage = "Cannot publish: display name is required and iroh must be initialized"
            showError = true
            return
        }

        guard let service = profileService else {
            errorMessage = "Iroh node not initialized. Please wait and try again."
            showError = true
            return
        }

        isSaving = true
        syncState = .syncing

        defer { isSaving = false }

        do {
            // Update metadata
            profile.updatedAt = Date()

            // Save draft first
            await saveDraft()

            // Publish via native iroh P2P
            let ticket = try await service.updateProfile(profile)

            // Cache the ticket for future lookups
            await ProfileTicketCache.shared.cache(ticket, for: profile.publicID)

            lastTicket = ticket
            print("Profile published with ticket: \(ticket.ticket)")
            syncState = .synced(ticket: ticket.ticket)
        } catch {
            syncState = .error(error.localizedDescription)
            showError = true
            errorMessage = "Failed to publish: \(error.localizedDescription)"
        }
    }

    // MARK: - Refresh from Network

    func refreshFromNetwork() async {
        guard let service = profileService else { return }

        // Check if we have a cached ticket for this profile
        guard let ticketString = await ProfileTicketCache.shared.ticketString(for: profile.publicID) else {
            // No cached ticket - can't refresh without one
            syncState = .idle
            return
        }

        syncState = .syncing

        do {
            let fetchedProfile = try await service.fetchProfile(ticket: ticketString)

            // Update local profile with fetched data
            profile = fetchedProfile

            // Save as draft
            await saveDraft()

            syncState = .synced(ticket: ticketString)
        } catch {
            syncState = .error(error.localizedDescription)
        }
    }
}
