import SwiftUI
import ArkavoKit

/// Universal stream info editing form for Twitch & YouTube.
/// Embedded in the StreamDestinationPicker as step 2 of the go-live flow.
struct StreamInfoFormView: View {
    let platform: StreamViewModel.StreamPlatform

    // Platform clients (provide the one that matches `platform`)
    var twitchClient: TwitchAuthClient?
    @ObservedObject var youtubeClient: YouTubeClient

    // Stream info fields (shared)
    @State var streamTitle: String = ""
    @State var tags: [String] = []
    @State var language: String = "en"

    // Twitch-specific
    @State var goLiveNotification: String = ""
    @State var categoryName: String = ""
    @State var categoryId: String = ""
    @State var isRerun: Bool = false
    @State var isBrandedContent: Bool = false

    // YouTube-specific (privacy is bound to view model so it reaches createAndBindBroadcast)
    @Binding var privacyStatus: String
    @State var youtubeDescription: String = ""

    // UI state
    @State private var newTag: String = ""
    @State private var categorySearchResults: [TwitchCategory] = []
    @State private var isSearchingCategories: Bool = false
    @State private var categorySearchTask: Task<Void, Never>?
    @State private var isSaving: Bool = false
    @State private var saveError: String?
    @State private var showCategoryResults: Bool = false
    @State private var needsReauth: Bool = false

    var onBack: () -> Void
    var onStartStream: () async -> Void

    private static let titleLimit = 140
    private static let tagCharLimit = 25
    private static let maxTags = 10
    private static let descriptionLimit = 5000

    private static let languages: [(code: String, name: String)] = [
        ("en", "English"), ("es", "Spanish"), ("fr", "French"), ("de", "German"),
        ("it", "Italian"), ("pt", "Portuguese"), ("ja", "Japanese"), ("ko", "Korean"),
        ("zh", "Chinese"), ("ru", "Russian"), ("ar", "Arabic"), ("hi", "Hindi"),
        ("pl", "Polish"), ("nl", "Dutch"), ("sv", "Swedish"), ("th", "Thai"),
        ("tr", "Turkish"), ("vi", "Vietnamese"), ("id", "Indonesian"), ("other", "Other"),
    ]

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Button {
                    onBack()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                        Text("Back")
                    }
                    .font(.subheadline)
                }
                .buttonStyle(.plain)

                Spacer()

                Text("Edit Stream Info")
                    .font(.title3.bold())

                Spacer()

                // Platform badge
                Text(platform.rawValue)
                    .font(.caption.weight(.medium))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(platformColor.opacity(0.2))
                    .foregroundStyle(platformColor)
                    .cornerRadius(6)
            }
            .padding(.bottom, 16)

            // Scrollable form
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Title (universal)
                    fieldSection(label: "Title", counter: "\(streamTitle.count)/\(Self.titleLimit)") {
                        styledTextField("Stream title", text: $streamTitle)
                            .onChange(of: streamTitle) { _, newValue in
                                if newValue.count > Self.titleLimit {
                                    streamTitle = String(newValue.prefix(Self.titleLimit))
                                }
                            }
                    }

                    // Twitch: Go Live Notification
                    if platform == .twitch {
                        fieldSection(label: "Go Live Notification", counter: "\(goLiveNotification.count)/\(Self.titleLimit)") {
                            styledTextField("Notification text for followers", text: $goLiveNotification)
                                .onChange(of: goLiveNotification) { _, newValue in
                                    if newValue.count > Self.titleLimit {
                                        goLiveNotification = String(newValue.prefix(Self.titleLimit))
                                    }
                                }
                        }
                    }

                    // YouTube: Description
                    if platform == .youtube {
                        fieldSection(label: "Description", counter: "\(youtubeDescription.count)/\(Self.descriptionLimit)") {
                            TextEditor(text: $youtubeDescription)
                                .font(.body)
                                .frame(minHeight: 60, maxHeight: 100)
                                .padding(6)
                                .background(.background.opacity(0.5))
                                .cornerRadius(8)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8)
                                        .stroke(.white.opacity(0.2), lineWidth: 1)
                                )
                                .onChange(of: youtubeDescription) { _, newValue in
                                    if newValue.count > Self.descriptionLimit {
                                        youtubeDescription = String(newValue.prefix(Self.descriptionLimit))
                                    }
                                }
                        }
                    }

                    // Twitch: Category search
                    if platform == .twitch {
                        fieldSection(label: "Category") {
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    styledTextField("Search categories", text: $categoryName)
                                        .onChange(of: categoryName) { _, newValue in
                                            debouncedCategorySearch(query: newValue)
                                        }

                                    if isSearchingCategories {
                                        ProgressView()
                                            .scaleEffect(0.7)
                                    }
                                }

                                if showCategoryResults && !categorySearchResults.isEmpty {
                                    VStack(spacing: 0) {
                                        ForEach(categorySearchResults) { category in
                                            Button {
                                                categoryName = category.name
                                                categoryId = category.id
                                                showCategoryResults = false
                                                categorySearchResults = []
                                            } label: {
                                                Text(category.name)
                                                    .frame(maxWidth: .infinity, alignment: .leading)
                                                    .padding(.horizontal, 10)
                                                    .padding(.vertical, 6)
                                                    .contentShape(Rectangle())
                                            }
                                            .buttonStyle(.plain)

                                            if category.id != categorySearchResults.last?.id {
                                                Divider().opacity(0.3)
                                            }
                                        }
                                    }
                                    .background(.background.opacity(0.8))
                                    .cornerRadius(8)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 8)
                                            .stroke(.white.opacity(0.15), lineWidth: 1)
                                    )
                                }
                            }
                        }
                    }

                    // YouTube: Privacy
                    if platform == .youtube {
                        fieldSection(label: "Privacy") {
                            Picker("", selection: $privacyStatus) {
                                Text("Public").tag("public")
                                Text("Unlisted").tag("unlisted")
                                Text("Private").tag("private")
                            }
                            .pickerStyle(.segmented)
                        }
                    }

                    // Tags (universal)
                    fieldSection(label: "Tags", counter: "\(tags.count)/\(Self.maxTags)") {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                styledTextField("Add a tag", text: $newTag)
                                    .onChange(of: newTag) { _, newValue in
                                        if newValue.count > Self.tagCharLimit {
                                            newTag = String(newValue.prefix(Self.tagCharLimit))
                                        }
                                    }
                                    .onSubmit { addTag() }

                                Button {
                                    addTag()
                                } label: {
                                    Image(systemName: "plus.circle.fill")
                                        .font(.title3)
                                }
                                .buttonStyle(.plain)
                                .disabled(newTag.isEmpty || tags.count >= Self.maxTags)
                            }

                            Text("Up to \(Self.maxTags) tags. Each tag max \(Self.tagCharLimit) characters.")
                                .font(.caption2)
                                .foregroundStyle(.secondary)

                            if !tags.isEmpty {
                                FlowLayout(spacing: 6) {
                                    ForEach(tags, id: \.self) { tag in
                                        HStack(spacing: 4) {
                                            Text(tag)
                                                .font(.caption)
                                            Button {
                                                tags.removeAll { $0 == tag }
                                            } label: {
                                                Image(systemName: "xmark")
                                                    .font(.system(size: 9, weight: .bold))
                                            }
                                            .buttonStyle(.plain)
                                        }
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 4)
                                        .background(Color.accentColor.opacity(0.2))
                                        .cornerRadius(6)
                                    }
                                }
                            }
                        }
                    }

                    // Language (universal)
                    fieldSection(label: "Stream Language") {
                        Picker("", selection: $language) {
                            ForEach(Self.languages, id: \.code) { lang in
                                Text(lang.name).tag(lang.code)
                            }
                        }
                        .labelsHidden()
                    }

                    // Twitch: Content Classification
                    if platform == .twitch {
                        fieldSection(label: "Content Classification") {
                            VStack(alignment: .leading, spacing: 8) {
                                Toggle("Rerun", isOn: $isRerun)
                                    .font(.subheadline)
                                Text("Let viewers know your stream was previously recorded.")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)

                                Toggle("Branded Content", isOn: $isBrandedContent)
                                    .font(.subheadline)
                                Text("Let viewers know if your stream features branded content.")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }

            // Error / Re-auth
            if needsReauth {
                HStack {
                    Image(systemName: "exclamationmark.triangle")
                    Text("Please reconnect \(platform.rawValue) to update stream info.")
                        .font(.caption)
                }
                .foregroundStyle(.orange)
                .padding(8)
                .frame(maxWidth: .infinity)
                .background(.orange.opacity(0.1))
                .cornerRadius(8)
                .padding(.top, 8)
            }

            if let saveError {
                Text(saveError)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .padding(8)
                    .frame(maxWidth: .infinity)
                    .background(.red.opacity(0.1))
                    .cornerRadius(8)
                    .padding(.top, 8)
            }

            // Start Streaming button
            Button {
                Task { await saveAndStartStream() }
            } label: {
                HStack {
                    if isSaving {
                        ProgressView()
                            .progressViewStyle(.circular)
                            .scaleEffect(0.8)
                    } else {
                        Image(systemName: "antenna.radiowaves.left.and.right")
                    }
                    Text("Start Streaming")
                }
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(
                    LinearGradient(colors: [.blue, .purple], startPoint: .leading, endPoint: .trailing)
                )
                .foregroundColor(.white)
                .cornerRadius(12)
            }
            .buttonStyle(.plain)
            .disabled(isSaving)
            .padding(.top, 12)
        }
        .onAppear { loadFromPlatform() }
    }

    // MARK: - Platform color

    private var platformColor: Color {
        switch platform {
        case .twitch: .purple
        case .youtube: .red
        default: .blue
        }
    }

    // MARK: - Helpers

    private func styledTextField(_ placeholder: String, text: Binding<String>) -> some View {
        TextField(placeholder, text: text)
            .textFieldStyle(.plain)
            .padding(10)
            .background(.background.opacity(0.5))
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(.white.opacity(0.2), lineWidth: 1)
            )
    }

    private func fieldSection<Content: View>(label: String, counter: String? = nil, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(label)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
                Spacer()
                if let counter {
                    Text(counter)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            content()
        }
    }

    private func addTag() {
        let cleaned = newTag
            .trimmingCharacters(in: .whitespaces)
            .lowercased()
            .filter { $0.isLetter || $0.isNumber || $0 == "_" }

        guard !cleaned.isEmpty,
              cleaned.count <= Self.tagCharLimit,
              tags.count < Self.maxTags,
              !tags.contains(where: { $0.lowercased() == cleaned }) else {
            return
        }

        tags.append(cleaned)
        newTag = ""
    }

    // MARK: - Twitch category search

    private func debouncedCategorySearch(query: String) {
        categorySearchTask?.cancel()
        guard !query.isEmpty else {
            categorySearchResults = []
            showCategoryResults = false
            return
        }

        categorySearchTask = Task {
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled, let twitch = twitchClient else { return }

            isSearchingCategories = true
            do {
                let results = try await twitch.searchCategories(query: query)
                if !Task.isCancelled {
                    categorySearchResults = results
                    showCategoryResults = true
                }
            } catch {
                if !Task.isCancelled {
                    categorySearchResults = []
                }
            }
            isSearchingCategories = false
        }
    }

    // MARK: - Load / Save

    private func loadFromPlatform() {
        switch platform {
        case .twitch:
            guard let twitch = twitchClient else { return }
            streamTitle = twitch.channelTitle ?? twitch.streamTitle ?? ""
            goLiveNotification = ""
            categoryName = twitch.gameName ?? ""
            categoryId = twitch.gameId ?? ""
            tags = twitch.channelTags
            language = twitch.broadcasterLanguage ?? "en"
            isBrandedContent = twitch.isBrandedContent

        case .youtube:
            streamTitle = ""
            youtubeDescription = ""
            language = "en"
            // privacyStatus is bound from StreamViewModel — preserve user's selection across form re-entries.

        default:
            break
        }
    }

    private func saveAndStartStream() async {
        isSaving = true
        saveError = nil
        needsReauth = false

        switch platform {
        case .twitch:
            await saveTwitchAndStart()
        case .youtube:
            // YouTube broadcast info is set at creation time;
            // title is passed through StreamViewModel.title
            await onStartStream()
        default:
            await onStartStream()
        }

        isSaving = false
    }

    private func saveTwitchAndStart() async {
        guard let twitch = twitchClient else {
            await onStartStream()
            return
        }

        do {
            let ccls: [TwitchContentLabel] = []
            try await twitch.updateChannelInfo(
                title: streamTitle.isEmpty ? nil : streamTitle,
                gameId: categoryId.isEmpty ? nil : categoryId,
                language: language,
                tags: tags.isEmpty ? nil : tags,
                contentClassificationLabels: ccls.isEmpty ? nil : ccls,
                isBrandedContent: isBrandedContent
            )
            await onStartStream()
        } catch TwitchError.scopeRequired {
            needsReauth = true
            await onStartStream()
        } catch {
            saveError = "Failed to update stream info: \(error.localizedDescription)"
            await onStartStream()
        }
    }
}
