import ArkavoKit
import SwiftUI

// MARK: - Creator Profile Display View

/// Read-only view for displaying creator profiles fetched from iroh.arkavo.net
struct CreatorProfileDisplayView: View {
    let publicID: Data
    @StateObject private var viewModel: CreatorProfileDisplayViewModel
    @Environment(\.dismiss) private var dismiss

    init(publicID: Data) {
        self.publicID = publicID
        _viewModel = StateObject(wrappedValue: CreatorProfileDisplayViewModel(publicID: publicID))
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                // Header with banner and avatar
                CreatorProfileHeaderDisplay(profile: viewModel.profile)

                // Profile content
                VStack(alignment: .leading, spacing: 20) {
                    // Name and handle
                    VStack(alignment: .leading, spacing: 4) {
                        Text(viewModel.profile?.displayName ?? "Creator")
                            .font(.title)
                            .bold()

                        if let handle = viewModel.profile?.handle {
                            Text("@\(handle)")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                    }

                    // Bio
                    if let bio = viewModel.profile?.bio, !bio.isEmpty {
                        Text(bio)
                            .font(.body)
                    }

                    // Content Categories
                    if let categories = viewModel.profile?.contentCategories, !categories.isEmpty {
                        CreatorCategoriesDisplay(categories: categories)
                    }

                    // Social Links
                    if let socialLinks = viewModel.profile?.socialLinks, !socialLinks.isEmpty {
                        CreatorSocialLinksDisplay(socialLinks: socialLinks)
                    }

                    // Streaming Schedule
                    if let schedule = viewModel.profile?.streamingSchedule {
                        CreatorScheduleDisplay(schedule: schedule)
                    }

                    // Patron Tiers
                    if let tiers = viewModel.profile?.patronTiers, !tiers.isEmpty {
                        CreatorPatronTiersDisplay(tiers: tiers)
                    }
                }
                .padding()
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .refreshable {
            await viewModel.refresh()
        }
        .overlay {
            if viewModel.isLoading {
                ProgressView()
                    .scaleEffect(1.5)
            }
        }
        .alert("Error", isPresented: .constant(viewModel.error != nil)) {
            Button("OK") {
                viewModel.clearError()
            }
        } message: {
            Text(viewModel.error?.localizedDescription ?? "Unknown error")
        }
    }
}

// MARK: - Profile Header Display

private struct CreatorProfileHeaderDisplay: View {
    let profile: CreatorProfile?

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            // Banner
            Group {
                if let bannerURL = profile?.bannerURL {
                    AsyncImage(url: bannerURL) { image in
                        image.resizable().aspectRatio(contentMode: .fill)
                    } placeholder: {
                        LinearGradient(
                            colors: [.blue.opacity(0.3), .purple.opacity(0.3)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    }
                } else {
                    LinearGradient(
                        colors: [.blue.opacity(0.3), .purple.opacity(0.3)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                }
            }
            .frame(height: 180)
            .clipped()
        }
        .overlay(alignment: .bottomLeading) {
            // Avatar
            Group {
                if let avatarURL = profile?.avatarURL {
                    AsyncImage(url: avatarURL) { image in
                        image.resizable().aspectRatio(contentMode: .fill)
                    } placeholder: {
                        Circle()
                            .fill(Color.blue.opacity(0.5))
                            .overlay {
                                Image(systemName: "person.fill")
                                    .font(.system(size: 30))
                                    .foregroundColor(.white)
                            }
                    }
                } else {
                    Circle()
                        .fill(Color.blue.opacity(0.5))
                        .overlay {
                            Image(systemName: "person.fill")
                                .font(.system(size: 30))
                                .foregroundColor(.white)
                        }
                }
            }
            .frame(width: 80, height: 80)
            .clipShape(Circle())
            .overlay(Circle().stroke(Color(.systemBackground), lineWidth: 3))
            .offset(x: 16, y: 40)
        }
        .padding(.bottom, 40)
    }
}

// MARK: - Categories Display

private struct CreatorCategoriesDisplay: View {
    let categories: [ContentCategory]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Content")
                .font(.headline)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(categories, id: \.self) { category in
                        HStack(spacing: 4) {
                            Image(systemName: category.iconName)
                                .font(.caption)
                            Text(category.rawValue)
                                .font(.caption)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color.accentColor.opacity(0.2))
                        .clipShape(Capsule())
                    }
                }
            }
        }
    }
}

// MARK: - Social Links Display

private struct CreatorSocialLinksDisplay: View {
    let socialLinks: [CreatorSocialLink]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Social Links")
                .font(.headline)

            ForEach(socialLinks) { link in
                Link(destination: link.url) {
                    HStack {
                        Image(systemName: link.platform.iconName)
                            .frame(width: 24)
                            .foregroundColor(.accentColor)

                        VStack(alignment: .leading) {
                            Text(link.platform.rawValue)
                                .font(.subheadline)
                            Text("@\(link.username)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }

                        Spacer()

                        if link.isVerified {
                            Image(systemName: "checkmark.seal.fill")
                                .foregroundColor(.blue)
                        }

                        Image(systemName: "arrow.up.right")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding()
                    .background(Color(.systemGray6))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .foregroundColor(.primary)
            }
        }
    }
}

// MARK: - Schedule Display

private struct CreatorScheduleDisplay: View {
    let schedule: StreamingSchedule

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Streaming Schedule")
                    .font(.headline)
                Spacer()
                Text(schedule.timezone)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            if schedule.slots.isEmpty {
                Text("No scheduled streams")
                    .foregroundColor(.secondary)
                    .italic()
            } else {
                ForEach(schedule.slots) { slot in
                    HStack {
                        VStack(alignment: .leading) {
                            Text(slot.dayName)
                                .font(.subheadline)
                                .fontWeight(.medium)
                            Text(slot.formattedTime)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }

                        Spacer()

                        if let title = slot.title {
                            Text(title)
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                        }

                        Text("\(slot.durationMinutes) min")
                            .font(.caption2)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.accentColor.opacity(0.2))
                            .clipShape(Capsule())
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - Patron Tiers Display

private struct CreatorPatronTiersDisplay: View {
    let tiers: [PatronTier]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Support Tiers")
                .font(.headline)

            ForEach(tiers.filter(\.isActive)) { tier in
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(tier.name)
                            .font(.subheadline)
                            .fontWeight(.semibold)
                        Spacer()
                        Text(tier.formattedPrice)
                            .font(.subheadline)
                            .foregroundColor(.accentColor)
                            .fontWeight(.semibold)
                    }

                    if !tier.description.isEmpty {
                        Text(tier.description)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    if !tier.benefits.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(tier.benefits, id: \.self) { benefit in
                                HStack(spacing: 6) {
                                    Image(systemName: "checkmark.circle.fill")
                                        .font(.caption)
                                        .foregroundColor(.green)
                                    Text(benefit)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                    }
                }
                .padding()
                .background(Color(.systemGray6))
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
        }
    }
}

// MARK: - View Model

@MainActor
class CreatorProfileDisplayViewModel: ObservableObject {
    @Published var profile: CreatorProfile?
    @Published var isLoading = true
    @Published var error: Error?

    private let publicID: Data
    private let irohClient = IrohProfileClient()
    private let cacheKey: String

    init(publicID: Data) {
        self.publicID = publicID
        cacheKey = "creatorProfile_\(publicID.base58EncodedString)"

        Task {
            await loadProfile()
        }
    }

    func loadProfile() async {
        isLoading = true
        error = nil

        // First try to load from cache
        if let cachedData = UserDefaults.standard.data(forKey: cacheKey),
           let cached = try? CreatorProfile.fromData(cachedData)
        {
            profile = cached
            isLoading = false
        }

        // Then fetch from network
        await refresh()
    }

    func refresh() async {
        do {
            let fetchedProfile = try await irohClient.fetchProfile(publicID: publicID)
            profile = fetchedProfile

            // Cache the profile locally
            if let data = try? fetchedProfile.toData() {
                UserDefaults.standard.set(data, forKey: cacheKey)
            }

            isLoading = false
        } catch IrohProfileError.profileNotFound {
            // Profile doesn't exist yet
            isLoading = false
        } catch {
            self.error = error
            isLoading = false
        }
    }

    func clearError() {
        error = nil
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        CreatorProfileDisplayView(publicID: Data(repeating: 0, count: 32))
    }
}
