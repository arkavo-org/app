import ArkavoKit
import SwiftUI

// MARK: - Creator Profile View

struct CreatorProfileView: View {
    @StateObject private var viewModel = CreatorProfileViewModel()
    @State private var showingAvatarPicker = false
    @State private var showingBannerPicker = false

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Header Section
                ProfileHeaderSection(
                    profile: $viewModel.profile,
                    onAvatarTap: { showingAvatarPicker = true },
                    onBannerTap: { showingBannerPicker = true }
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
                PatronTiersSection(tiers: $viewModel.profile.patronTiers)

                // Sync Status and Actions
                ProfileActionsSection(viewModel: viewModel)
            }
            .padding()
        }
        .alert("Error", isPresented: $viewModel.showError) {
            Button("OK") {}
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

    private func handleImageSelection(_ result: Result<[URL], Error>, for type: ImageType) {
        switch result {
        case let .success(urls):
            if let url = urls.first {
                switch type {
                case .avatar:
                    viewModel.profile.avatarURL = url
                case .banner:
                    viewModel.profile.bannerURL = url
                }
            }
        case let .failure(error):
            viewModel.errorMessage = error.localizedDescription
            viewModel.showError = true
        }
    }

    private enum ImageType {
        case avatar, banner
    }
}

// MARK: - Profile Header Section

private struct ProfileHeaderSection: View {
    @Binding var profile: CreatorProfile
    let onAvatarTap: () -> Void
    let onBannerTap: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            // Banner
            ZStack {
                if let bannerURL = profile.bannerURL {
                    AsyncImage(url: bannerURL) { image in
                        image.resizable().aspectRatio(contentMode: .fill)
                    } placeholder: {
                        Color.gray.opacity(0.3)
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
                        Button(action: onBannerTap) {
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

            // Avatar (overlapping banner)
            ZStack {
                if let avatarURL = profile.avatarURL {
                    AsyncImage(url: avatarURL) { image in
                        image.resizable().aspectRatio(contentMode: .fill)
                    } placeholder: {
                        Color.blue.opacity(0.3)
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
                Button(action: onAvatarTap) {
                    Image(systemName: "camera.fill")
                        .font(.caption2)
                        .padding(6)
                        .background(.ultraThinMaterial)
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
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
        VStack(alignment: .leading, spacing: 16) {
            Text("Basic Information")
                .font(.headline)

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
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 12))
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
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Social Links")
                    .font(.headline)
                Spacer()
                Button(action: { showingAddLink = true }) {
                    Image(systemName: "plus.circle")
                }
                .buttonStyle(.borderless)
            }

            if socialLinks.isEmpty {
                Text("No social links added yet")
                    .foregroundColor(.secondary)
                    .italic()
                    .padding(.vertical, 8)
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
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 12))
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
        VStack(alignment: .leading, spacing: 16) {
            Text("Content Categories")
                .font(.headline)

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
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

private struct CategoryChip: View {
    let category: ContentCategory
    let isSelected: Bool
    let onTap: () -> Void

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
            .background(isSelected ? Color.accentColor : Color.gray.opacity(0.2))
            .foregroundColor(isSelected ? .white : .primary)
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Streaming Schedule Section

private struct StreamingScheduleSection: View {
    @Binding var schedule: StreamingSchedule?
    @State private var showingAddSlot = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Streaming Schedule")
                    .font(.headline)
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
                Text("No streaming schedule set")
                    .foregroundColor(.secondary)
                    .italic()
                    .padding(.vertical, 8)
            }
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 12))
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
    @Binding var tiers: [PatronTier]
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

    let onAdd: (PatronTier) -> Void
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

                    let tier = PatronTier(
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
                    Text("Synced")
                        .foregroundColor(.green)
                case .error:
                    Image(systemName: "exclamationmark.cloud.fill")
                        .foregroundColor(.red)
                    Text("Sync failed")
                        .foregroundColor(.red)
                }

                Spacer()

                Text("v\(viewModel.profile.version)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .font(.subheadline)

            // Action Buttons
            HStack(spacing: 16) {
                Button("Save Draft") {
                    Task { await viewModel.saveDraft() }
                }
                .buttonStyle(.bordered)
                .disabled(viewModel.isSaving)

                Button("Publish Profile") {
                    Task { await viewModel.publishProfile() }
                }
                .buttonStyle(.borderedProminent)
                .disabled(!viewModel.canPublish || viewModel.isSaving)
            }
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
