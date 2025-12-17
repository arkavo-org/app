import ArkavoKit
import CryptoKit
import Foundation
import SwiftUI

// MARK: - Sync State

enum ProfileSyncState: Equatable {
    case idle
    case syncing
    case synced
    case error(String)

    static func == (lhs: ProfileSyncState, rhs: ProfileSyncState) -> Bool {
        switch (lhs, rhs) {
        case (.idle, .idle), (.syncing, .syncing), (.synced, .synced):
            true
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

    private let irohClient = IrohProfileClient()
    private let authState = ArkavoAuthState.shared
    private let draftKey = "CreatorProfileDraft"

    var canPublish: Bool {
        !profile.displayName.isEmpty && authState.isAuthenticated
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
            errorMessage = "Cannot publish: display name is required and you must be logged in"
            showError = true
            return
        }

        isSaving = true
        syncState = .syncing

        defer { isSaving = false }

        do {
            // Update metadata
            profile.updatedAt = Date()
            profile.version += 1

            // Save draft first
            await saveDraft()

            // Get authentication token
            guard let token = KeychainManager.getAuthenticationToken() else {
                throw IrohProfileError.notAuthenticated
            }

            // Check if profile exists
            let existingProfile = try? await irohClient.fetchProfile(publicID: profile.publicID)

            let response: PublishProfileResponse
            if existingProfile != nil {
                // Update existing profile
                response = try await irohClient.updateProfile(profile, token: token)
            } else {
                // Publish new profile
                response = try await irohClient.publishProfile(profile, token: token)
            }

            print("Profile published with ticket: \(response.ticket)")
            syncState = .synced
        } catch {
            syncState = .error(error.localizedDescription)
            showError = true
            errorMessage = "Failed to publish: \(error.localizedDescription)"
        }
    }

    // MARK: - Refresh from Network

    func refreshFromNetwork() async {
        guard authState.isAuthenticated else { return }

        syncState = .syncing

        do {
            let fetchedProfile = try await irohClient.fetchProfile(publicID: profile.publicID)

            // Update local profile with fetched data
            profile = fetchedProfile

            // Save as draft
            await saveDraft()

            syncState = .synced
        } catch IrohProfileError.profileNotFound {
            // Profile doesn't exist on server yet, that's okay
            syncState = .idle
        } catch {
            syncState = .error(error.localizedDescription)
        }
    }
}
