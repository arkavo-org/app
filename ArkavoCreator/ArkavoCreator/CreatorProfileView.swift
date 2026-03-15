import ArkavoKit
import ArkavoSocial
import SwiftUI

// MARK: - Creator Profile View

struct CreatorProfileView: View {
    @StateObject private var viewModel = CreatorProfileViewModel()
    @ObservedObject var twitchClient: TwitchAuthClient
    @State private var showingAvatarPicker = false
    @State private var showingBannerPicker = false

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Header Section
                ProfileHeaderSection(
                    profile: $viewModel.profile,
                    twitchProfileImageURL: twitchClient.profileImageURL,
                    onAvatarTap: { showingAvatarPicker = true },
                    onBannerTap: { showingBannerPicker = true },
                    onUseTwitchAvatar: {
                        if let urlString = twitchClient.profileImageURL,
                           let url = URL(string: urlString) {
                            viewModel.profile.avatarURL = url
                        }
                    }
                )

                // Basic Info Section
                BasicInfoSection(profile: $viewModel.profile)

                // Social Links Section
                SocialLinksSection(socialLinks: $viewModel.profile.socialLinks)

                // Content Categories Section
                ContentCategoriesSection(categories: $viewModel.profile.contentCategories)

                // Streaming Schedule Section
                StreamingScheduleSection(schedule: $viewModel.profile.streamingSchedule)

                // Patron Tiers Section
                if FeatureFlags.patreon {
                    PatronTiersSection(tiers: $viewModel.profile.patronTiers)
                }

                // Sync Status and Actions
                ProfileActionsSection(viewModel: viewModel)
            }
            .padding()
        }
        .onChange(of: twitchClient.username) { _, newUsername in
            guard let username = newUsername, viewModel.profile.displayName.isEmpty else { return }
            importTwitchToProfile(username: username)
        }
        .alert("Error", isPresented: $viewModel.showError) {
            Button("OK") { /* Dismisses alert */ }
        } message: {
            Text(viewModel.errorMessage ?? "An error occurred")
        }
        .fileImporter(
            isPresented: $showingAvatarPicker,
            allowedContentTypes: [.image],
            allowsMultipleSelection: false
        ) { result in
            handleImageSelection(result, for: .avatar)
        }
        .fileImporter(
            isPresented: $showingBannerPicker,
            allowedContentTypes: [.image],
            allowsMultipleSelection: false
        ) { result in
            handleImageSelection(result, for: .banner)
        }
    }

    private func importTwitchToProfile(username: String) {
        withAnimation(.easeInOut) {
            viewModel.profile.displayName = username

            if let description = twitchClient.channelDescription, !description.isEmpty, viewModel.profile.bio.isEmpty {
                viewModel.profile.bio = description
            }

            if let profileImageURL = twitchClient.profileImageURL,
               let url = URL(string: profileImageURL),
               viewModel.profile.avatarURL == nil {
                viewModel.profile.avatarURL = url
            }

            // Add Twitch social link if not already present
            if !viewModel.profile.socialLinks.contains(where: { $0.platform == .twitch }) {
                if let linkURL = URL(string: "https://twitch.tv/\(username.lowercased())") {
                    let link = CreatorSocialLink(
                        platform: .twitch,
                        username: username,
                        url: linkURL,
                        isVerified: true
                    )
                    viewModel.profile.socialLinks.append(link)
                }
            }

            // Map Twitch tags to content categories
            if viewModel.profile.contentCategories.isEmpty {
                let tagMapping: [String: ContentCategory] = [
                    "gaming": .gaming, "music": .music, "art": .art,
                    "technology": .technology, "education": .education,
                    "sports": .sports, "cooking": .cooking,
                    "fitness": .fitness, "science": .science,
                    "comedy": .comedy, "entertainment": .entertainment,
                ]
                for tag in twitchClient.channelTags {
                    let lowered = tag.lowercased()
                    if let category = tagMapping[lowered],
                       !viewModel.profile.contentCategories.contains(category) {
                        viewModel.profile.contentCategories.append(category)
                    }
                }
            }

            // Map Twitch schedule to streaming schedule
            if viewModel.profile.streamingSchedule == nil, !twitchClient.schedule.isEmpty {
                let formatter = ISO8601DateFormatter()
                let calendar = Calendar.current
                var slots: [ScheduleSlot] = []
                for segment in twitchClient.schedule {
                    guard let start = formatter.date(from: segment.start_time),
                          let end = formatter.date(from: segment.end_time) else { continue }
                    let components = calendar.dateComponents([.weekday, .hour, .minute], from: start)
                    let duration = Int(end.timeIntervalSince(start) / 60)
                    let slot = ScheduleSlot(
                        dayOfWeek: components.weekday ?? 1,
                        startHour: components.hour ?? 0,
                        startMinute: components.minute ?? 0,
                        durationMinutes: max(duration, 15),
                        title: segment.title
                    )
                    slots.append(slot)
                }
                if !slots.isEmpty {
                    viewModel.profile.streamingSchedule = StreamingSchedule(slots: slots)
                }
            }
        }
    }

    private func handleImageSelection(_ result: Result<[URL], Error>, for type: ImageType) {
        switch result {
        case let .success(urls):
            if let url = urls.first {
                // fileImporter returns security-scoped URLs that AsyncImage can't access.
                // Copy the file into the app's support directory for persistent access.
                do {
                    let persistedURL = try copyImageToAppSupport(url, type: type)
                    switch type {
                    case .avatar:
                        viewModel.profile.avatarURL = persistedURL
                    case .banner:
                        viewModel.profile.bannerURL = persistedURL
                    }
                } catch {
                    viewModel.errorMessage = "Failed to save image: \(error.localizedDescription)"
                    viewModel.showError = true
                }
            }
        case let .failure(error):
            viewModel.errorMessage = error.localizedDescription
            viewModel.showError = true
        }
    }

    private func copyImageToAppSupport(_ sourceURL: URL, type: ImageType) throws -> URL {
        guard sourceURL.startAccessingSecurityScopedResource() else {
            throw CocoaError(.fileReadNoPermission)
        }
        defer { sourceURL.stopAccessingSecurityScopedResource() }

        let appSupport = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let imagesDir = appSupport.appendingPathComponent("ProfileImages", isDirectory: true)
        try FileManager.default.createDirectory(at: imagesDir, withIntermediateDirectories: true)

        let filename = "\(type == .avatar ? "avatar" : "banner").\(sourceURL.pathExtension)"
        let destURL = imagesDir.appendingPathComponent(filename)

        // Replace existing file
        if FileManager.default.fileExists(atPath: destURL.path) {
            try FileManager.default.removeItem(at: destURL)
        }
        try FileManager.default.copyItem(at: sourceURL, to: destURL)

        return destURL
    }

    private enum ImageType {
        case avatar, banner
    }
}

// MARK: - Profile Header Section

private struct ProfileHeaderSection: View {
    @Binding var profile: CreatorProfile
    let twitchProfileImageURL: String?
    let onAvatarTap: () -> Void
    let onBannerTap: () -> Void
    let onUseTwitchAvatar: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            // Banner
            ZStack {
                if let bannerURL = profile.bannerURL {
                    if bannerURL.isFileURL, let nsImage = NSImage(contentsOf: bannerURL) {
                        Image(nsImage: nsImage)
                            .resizable().aspectRatio(contentMode: .fill)
                    } else {
                        AsyncImage(url: bannerURL) { image in
                            image.resizable().aspectRatio(contentMode: .fill)
                        } placeholder: {
                            Color.gray.opacity(0.3)
                        }
                    }
                } else {
                    LinearGradient(
                        colors: [.blue.opacity(0.3), .purple.opacity(0.3)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                }

                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        Menu {
                            Button("Choose Image...") { onBannerTap() }
                            Divider()
                            if profile.bannerURL != nil {
                                Button("Remove", role: .destructive) { profile.bannerURL = nil }
                            }
                        } label: {
                            Image(systemName: "camera.fill")
                                .font(.caption)
                                .padding(8)
                                .background(.ultraThinMaterial)
                                .clipShape(Circle())
                        }
                        .buttonStyle(.plain)
                        .padding(8)
                    }
                }
            }
            .frame(height: 180)
            .clipped()
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .contextMenu {
                Button("Choose Banner Image...") { onBannerTap() }
                Divider()
                if profile.bannerURL != nil {
                    Button("Remove Banner", role: .destructive) { profile.bannerURL = nil }
                }
            }

            // Avatar (overlapping banner)
            ZStack {
                if let avatarURL = profile.avatarURL {
                    if avatarURL.isFileURL, let nsImage = NSImage(contentsOf: avatarURL) {
                        Image(nsImage: nsImage)
                            .resizable().aspectRatio(contentMode: .fill)
                    } else {
                        AsyncImage(url: avatarURL) { image in
                            image.resizable().aspectRatio(contentMode: .fill)
                        } placeholder: {
                            Color.blue.opacity(0.3)
                        }
                    }
                } else {
                    Circle()
                        .fill(Color.blue.opacity(0.3))
                    Image(systemName: "person.fill")
                        .font(.system(size: 40))
                        .foregroundColor(.white)
                }
            }
            .frame(width: 100, height: 100)
            .clipShape(Circle())
            .overlay(Circle().stroke(Color(NSColor.windowBackgroundColor), lineWidth: 4))
            .overlay(alignment: .bottomTrailing) {
                Menu {
                    Button("Choose Image...") { onAvatarTap() }
                    if twitchProfileImageURL != nil {
                        Button("Use Twitch Avatar") { onUseTwitchAvatar() }
                    }
                    Divider()
                    if profile.avatarURL != nil {
                        Button("Remove", role: .destructive) { profile.avatarURL = nil }
                    }
                } label: {
                    Image(systemName: "camera.fill")
                        .font(.caption2)
                        .padding(6)
                        .background(.ultraThinMaterial)
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
            }
            .contextMenu {
                Button("Choose Image...") { onAvatarTap() }
                if twitchProfileImageURL != nil {
                    Button("Use Twitch Avatar") { onUseTwitchAvatar() }
                }
                Divider()
                if profile.avatarURL != nil {
                    Button("Remove", role: .destructive) { profile.avatarURL = nil }
                }
            }
            .offset(y: -50)
        }
        .padding(.bottom, -40)
    }
}

// MARK: - Basic Info Section

private struct BasicInfoSection: View {
    @Binding var profile: CreatorProfile

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 16) {
                TextField("Display Name", text: $profile.displayName)
                    .textFieldStyle(.roundedBorder)

                VStack(alignment: .leading, spacing: 4) {
                    Text("Bio")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    TextEditor(text: $profile.bio)
                        .frame(minHeight: 100)
                        .font(.body)
                        .scrollContentBackground(.hidden)
                        .padding(8)
                        .background(Color(NSColor.textBackgroundColor))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }

                if let handle = profile.handle {
                    HStack {
                        Text("Handle:")
                            .foregroundColor(.secondary)
                        Text("@\(handle)")
                            .fontWeight(.medium)
                    }
                    .font(.subheadline)
                }
            }
        } label: {
            Label("Basic Information", systemImage: "person.text.rectangle")
        }
    }
}

// MARK: - Social Links Section

private struct SocialLinksSection: View {
    @Binding var socialLinks: [CreatorSocialLink]
    @State private var showingAddLink = false
    @State private var newPlatform: CreatorSocialPlatform = .twitter
    @State private var newUsername = ""
    @State private var newURL = ""

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Spacer()
                    Button(action: { showingAddLink = true }) {
                        Image(systemName: "plus.circle")
                    }
                    .buttonStyle(.borderless)
                }

                if socialLinks.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "link.badge.plus")
                            .font(.title2)
                            .foregroundColor(.secondary)
                        Text("Connect your community")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        Button("Add Social Link") { showingAddLink = true }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                } else {
                    ForEach(socialLinks) { link in
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

                            Button(action: { socialLinks.removeAll { $0.id == link.id } }) {
                                Image(systemName: "trash")
                                    .foregroundColor(.red)
                            }
                            .buttonStyle(.borderless)
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
        } label: {
            Label("Social Links", systemImage: "link")
        }
        .sheet(isPresented: $showingAddLink) {
            AddSocialLinkSheet(
                platform: $newPlatform,
                username: $newUsername,
                url: $newURL,
                onAdd: {
                    if let linkURL = URL(string: newURL.isEmpty ? (newPlatform.baseURL ?? "") + newUsername : newURL) {
                        let link = CreatorSocialLink(
                            platform: newPlatform,
                            username: newUsername,
                            url: linkURL
                        )
                        socialLinks.append(link)
                    }
                    newUsername = ""
                    newURL = ""
                    showingAddLink = false
                },
                onCancel: {
                    newUsername = ""
                    newURL = ""
                    showingAddLink = false
                }
            )
        }
    }
}

private struct AddSocialLinkSheet: View {
    @Binding var platform: CreatorSocialPlatform
    @Binding var username: String
    @Binding var url: String

    let onAdd: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            Text("Add Social Link")
                .font(.headline)

            Picker("Platform", selection: $platform) {
                ForEach(CreatorSocialPlatform.allCases, id: \.self) { p in
                    Label(p.rawValue, systemImage: p.iconName)
                        .tag(p)
                }
            }
            .pickerStyle(.menu)

            TextField("Username", text: $username)
                .textFieldStyle(.roundedBorder)

            if platform == .custom || platform == .discord {
                TextField("URL", text: $url)
                    .textFieldStyle(.roundedBorder)
            }

            HStack {
                Button("Cancel", action: onCancel)
                    .buttonStyle(.bordered)

                Button("Add", action: onAdd)
                    .buttonStyle(.borderedProminent)
                    .disabled(username.isEmpty)
            }
        }
        .padding()
        .frame(width: 300)
    }
}

// MARK: - Content Categories Section

private struct ContentCategoriesSection: View {
    @Binding var categories: [ContentCategory]

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 16) {
                Text("Select categories that describe your content")
                    .font(.caption)
                    .foregroundColor(.secondary)

                FlowLayout(spacing: 8) {
                    ForEach(ContentCategory.allCases, id: \.self) { category in
                        CategoryChip(
                            category: category,
                            isSelected: categories.contains(category)
                        ) {
                            if categories.contains(category) {
                                categories.removeAll { $0 == category }
                            } else {
                                categories.append(category)
                            }
                        }
                    }
                }
            }
        } label: {
            Label("Content Categories", systemImage: "tag")
        }
    }
}

private struct CategoryChip: View {
    let category: ContentCategory
    let isSelected: Bool
    let onTap: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 4) {
                Image(systemName: category.iconName)
                    .font(.caption)
                Text(category.rawValue)
                    .font(.subheadline)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(isSelected ? Color.accentColor : Color.gray.opacity(isHovered ? 0.3 : 0.2))
            .foregroundColor(isSelected ? .white : .primary)
            .clipShape(Capsule())
            .scaleEffect(isHovered && !isSelected ? 1.05 : 1.0)
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .animation(.easeInOut(duration: 0.15), value: isHovered)
    }
}

// MARK: - Streaming Schedule Section

private struct StreamingScheduleSection: View {
    @Binding var schedule: StreamingSchedule?
    @State private var showingAddSlot = false

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Spacer()
                    Button(action: { showingAddSlot = true }) {
                        Image(systemName: "plus.circle")
                    }
                    .buttonStyle(.borderless)
                }

                if let schedule, !schedule.slots.isEmpty {
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
                            }

                            Text("\(slot.durationMinutes) min")
                                .font(.caption)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color.accentColor.opacity(0.2))
                                .clipShape(Capsule())
                        }
                        .padding(.vertical, 4)
                    }
                } else {
                    VStack(spacing: 8) {
                        Image(systemName: "calendar.badge.plus")
                            .font(.title2)
                            .foregroundColor(.secondary)
                        Text("Let viewers know when you're live")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        Button("Add Time Slot") { showingAddSlot = true }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                }
            }
        } label: {
            Label("Streaming Schedule", systemImage: "calendar")
        }
        .sheet(isPresented: $showingAddSlot) {
            AddScheduleSlotSheet { slot in
                if schedule == nil {
                    schedule = StreamingSchedule()
                }
                schedule?.slots.append(slot)
                showingAddSlot = false
            } onCancel: {
                showingAddSlot = false
            }
        }
    }
}

private struct AddScheduleSlotSheet: View {
    @State private var dayOfWeek = 2 // Monday
    @State private var startHour = 19 // 7 PM
    @State private var durationMinutes = 120
    @State private var title = ""

    let onAdd: (ScheduleSlot) -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            Text("Add Schedule Slot")
                .font(.headline)

            Picker("Day", selection: $dayOfWeek) {
                Text("Sunday").tag(1)
                Text("Monday").tag(2)
                Text("Tuesday").tag(3)
                Text("Wednesday").tag(4)
                Text("Thursday").tag(5)
                Text("Friday").tag(6)
                Text("Saturday").tag(7)
            }

            Picker("Start Time", selection: $startHour) {
                ForEach(0 ..< 24, id: \.self) { hour in
                    Text(formatHour(hour)).tag(hour)
                }
            }

            Stepper("Duration: \(durationMinutes) minutes", value: $durationMinutes, in: 15 ... 480, step: 15)

            TextField("Title (optional)", text: $title)
                .textFieldStyle(.roundedBorder)

            HStack {
                Button("Cancel", action: onCancel)
                    .buttonStyle(.bordered)

                Button("Add") {
                    let slot = ScheduleSlot(
                        dayOfWeek: dayOfWeek,
                        startHour: startHour,
                        durationMinutes: durationMinutes,
                        title: title.isEmpty ? nil : title
                    )
                    onAdd(slot)
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding()
        .frame(width: 300)
    }

    private func formatHour(_ hour: Int) -> String {
        let h = hour % 12 == 0 ? 12 : hour % 12
        let period = hour < 12 ? "AM" : "PM"
        return "\(h):00 \(period)"
    }
}

// MARK: - Patron Tiers Section

private struct PatronTiersSection: View {
    @Binding var tiers: [ArkavoSocial.PatronTier]
    @State private var showingAddTier = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Patron Tiers")
                    .font(.headline)
                Spacer()
                Button(action: { showingAddTier = true }) {
                    Image(systemName: "plus.circle")
                }
                .buttonStyle(.borderless)
            }

            if tiers.isEmpty {
                Text("No patron tiers configured")
                    .foregroundColor(.secondary)
                    .italic()
                    .padding(.vertical, 8)
            } else {
                ForEach(tiers) { tier in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text(tier.name)
                                .font(.subheadline)
                                .fontWeight(.semibold)
                            Spacer()
                            Text(tier.formattedPrice)
                                .font(.subheadline)
                                .foregroundColor(.accentColor)
                        }

                        if !tier.description.isEmpty {
                            Text(tier.description)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }

                        if !tier.benefits.isEmpty {
                            HStack(spacing: 4) {
                                ForEach(tier.benefits.prefix(3), id: \.self) { benefit in
                                    Text("• \(benefit)")
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                    }
                    .padding()
                    .background(Color(NSColor.textBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
            }
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .sheet(isPresented: $showingAddTier) {
            AddPatronTierSheet { tier in
                tiers.append(tier)
                showingAddTier = false
            } onCancel: {
                showingAddTier = false
            }
        }
    }
}

private struct AddPatronTierSheet: View {
    @State private var name = ""
    @State private var description = ""
    @State private var priceDollars = 5.0
    @State private var benefitsText = ""

    let onAdd: (ArkavoSocial.PatronTier) -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            Text("Add Patron Tier")
                .font(.headline)

            TextField("Tier Name", text: $name)
                .textFieldStyle(.roundedBorder)

            TextField("Description", text: $description)
                .textFieldStyle(.roundedBorder)

            HStack {
                Text("Price: $\(String(format: "%.2f", priceDollars))/mo")
                Slider(value: $priceDollars, in: 1 ... 100, step: 1)
            }

            VStack(alignment: .leading) {
                Text("Benefits (one per line)")
                    .font(.caption)
                TextEditor(text: $benefitsText)
                    .frame(height: 80)
                    .font(.caption)
            }

            HStack {
                Button("Cancel", action: onCancel)
                    .buttonStyle(.bordered)

                Button("Add") {
                    let benefits = benefitsText
                        .components(separatedBy: .newlines)
                        .map { $0.trimmingCharacters(in: .whitespaces) }
                        .filter { !$0.isEmpty }

                    let tier = ArkavoSocial.PatronTier(
                        name: name,
                        description: description,
                        priceCents: Int(priceDollars * 100),
                        benefits: benefits
                    )
                    onAdd(tier)
                }
                .buttonStyle(.borderedProminent)
                .disabled(name.isEmpty)
            }
        }
        .padding()
        .frame(width: 350)
    }
}

// MARK: - Profile Actions Section

private struct ProfileActionsSection: View {
    @ObservedObject var viewModel: CreatorProfileViewModel

    var body: some View {
        VStack(spacing: 16) {
            // Sync Status
            HStack {
                switch viewModel.syncState {
                case .idle:
                    Image(systemName: "cloud")
                        .foregroundColor(.secondary)
                        .help("Profile sync status — publish to share via the Arkavo network")
                    Text("Not synced")
                        .foregroundColor(.secondary)
                case .syncing:
                    ProgressView()
                        .controlSize(.small)
                    Text("Syncing...")
                        .foregroundColor(.secondary)
                case .synced:
                    Image(systemName: "checkmark.cloud.fill")
                        .foregroundColor(.green)
                        .help("Profile sync status — publish to share via the Arkavo network")
                    Text("Synced")
                        .foregroundColor(.green)
                case .error:
                    Image(systemName: "exclamationmark.cloud.fill")
                        .foregroundColor(.red)
                        .help("Profile sync status — publish to share via the Arkavo network")
                    Text("Sync failed")
                        .foregroundColor(.red)
                }

                Spacer()

                Text("v\(viewModel.profile.version)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .font(.subheadline)

            // Single Save Profile button
            Button {
                Task {
                    await viewModel.saveDraft()
                    if FeatureFlags.contentProtection, ArkavoIrohManager.shared.isReady {
                        await viewModel.publishProfile()
                    }
                }
            } label: {
                HStack(spacing: 8) {
                    if viewModel.isSaving {
                        ProgressView()
                            .controlSize(.small)
                    } else if viewModel.showSavedConfirmation {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                        Text("Saved!")
                    } else {
                        Text("Save Profile")
                    }
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.defaultAction)
            .disabled(viewModel.isSaving)
            .help("Save your profile locally")
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - Flow Layout

struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache _: inout ()) -> CGSize {
        let result = FlowResult(in: proposal.width ?? 0, subviews: subviews, spacing: spacing)
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache _: inout ()) {
        let result = FlowResult(in: proposal.width ?? 0, subviews: subviews, spacing: spacing)
        for (index, subview) in subviews.enumerated() {
            subview.place(at: CGPoint(x: bounds.minX + result.positions[index].x,
                                      y: bounds.minY + result.positions[index].y),
                          proposal: .unspecified)
        }
    }

    struct FlowResult {
        var size: CGSize = .zero
        var positions: [CGPoint] = []

        init(in maxWidth: CGFloat, subviews: Subviews, spacing: CGFloat) {
            var x: CGFloat = 0
            var y: CGFloat = 0
            var lineHeight: CGFloat = 0

            for subview in subviews {
                let size = subview.sizeThatFits(.unspecified)
                if x + size.width > maxWidth, x > 0 {
                    x = 0
                    y += lineHeight + spacing
                    lineHeight = 0
                }
                positions.append(CGPoint(x: x, y: y))
                lineHeight = max(lineHeight, size.height)
                x += size.width + spacing
                self.size.width = max(self.size.width, x - spacing)
            }
            size.height = y + lineHeight
        }
    }
}
