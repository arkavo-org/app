import SwiftUI

/// Stream info editing form for Twitch (title, category, tags, language, content labels)
/// Embedded in the StreamDestinationPicker as step 2 of the go-live flow.
struct StreamInfoFormView: View {
    @ObservedObject var twitchClient: TwitchAuthClient

    // Stream info fields
    @State var streamTitle: String = ""
    @State var goLiveNotification: String = ""
    @State var categoryName: String = ""
    @State var categoryId: String = ""
    @State var tags: [String] = []
    @State var language: String = "en"
    @State var isRerun: Bool = false
    @State var isBrandedContent: Bool = false

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

                // Invisible spacer to balance the back button
                Color.clear.frame(width: 50, height: 1)
            }
            .padding(.bottom, 16)

            // Scrollable form
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Title
                    fieldSection(label: "Title", counter: "\(streamTitle.count)/\(Self.titleLimit)") {
                        TextField("Stream title", text: $streamTitle)
                            .textFieldStyle(.plain)
                            .padding(10)
                            .background(.background.opacity(0.5))
                            .cornerRadius(8)
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(.white.opacity(0.2), lineWidth: 1)
                            )
                            .onChange(of: streamTitle) { _, newValue in
                                if newValue.count > Self.titleLimit {
                                    streamTitle = String(newValue.prefix(Self.titleLimit))
                                }
                            }
                    }

                    // Go Live Notification
                    fieldSection(label: "Go Live Notification", counter: "\(goLiveNotification.count)/\(Self.titleLimit)") {
                        TextField("Notification text for followers", text: $goLiveNotification)
                            .textFieldStyle(.plain)
                            .padding(10)
                            .background(.background.opacity(0.5))
                            .cornerRadius(8)
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(.white.opacity(0.2), lineWidth: 1)
                            )
                            .onChange(of: goLiveNotification) { _, newValue in
                                if newValue.count > Self.titleLimit {
                                    goLiveNotification = String(newValue.prefix(Self.titleLimit))
                                }
                            }
                    }

                    // Category
                    fieldSection(label: "Category") {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                TextField("Search categories", text: $categoryName)
                                    .textFieldStyle(.plain)
                                    .padding(10)
                                    .background(.background.opacity(0.5))
                                    .cornerRadius(8)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 8)
                                            .stroke(.white.opacity(0.2), lineWidth: 1)
                                    )
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

                    // Tags
                    fieldSection(label: "Tags", counter: "\(tags.count)/\(Self.maxTags)") {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                TextField("Add a tag", text: $newTag)
                                    .textFieldStyle(.plain)
                                    .padding(10)
                                    .background(.background.opacity(0.5))
                                    .cornerRadius(8)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 8)
                                            .stroke(.white.opacity(0.2), lineWidth: 1)
                                    )
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

                            Text("Up to \(Self.maxTags) tags. Each tag max \(Self.tagCharLimit) characters, no spaces or special characters.")
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

                    // Language
                    fieldSection(label: "Stream Language") {
                        Picker("", selection: $language) {
                            ForEach(Self.languages, id: \.code) { lang in
                                Text(lang.name).tag(lang.code)
                            }
                        }
                        .labelsHidden()
                    }

                    // Content Classification
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

            // Error / Re-auth
            if needsReauth {
                HStack {
                    Image(systemName: "exclamationmark.triangle")
                    Text("Please reconnect Twitch to update stream info.")
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
        .onAppear { loadFromTwitch() }
    }

    // MARK: - Helpers

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

    private func debouncedCategorySearch(query: String) {
        categorySearchTask?.cancel()
        guard !query.isEmpty else {
            categorySearchResults = []
            showCategoryResults = false
            return
        }

        categorySearchTask = Task {
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }

            isSearchingCategories = true
            do {
                let results = try await twitchClient.searchCategories(query: query)
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

    private func loadFromTwitch() {
        streamTitle = twitchClient.channelTitle ?? twitchClient.streamTitle ?? ""
        goLiveNotification = ""
        categoryName = twitchClient.gameName ?? ""
        categoryId = twitchClient.gameId ?? ""
        tags = twitchClient.channelTags
        language = twitchClient.broadcasterLanguage ?? "en"
        isBrandedContent = twitchClient.isBrandedContent
    }

    private func saveAndStartStream() async {
        isSaving = true
        saveError = nil
        needsReauth = false

        do {
            // Build content classification labels
            var ccls: [TwitchContentLabel] = []
            // Rerun is not a standard CCL — it's handled differently on Twitch.
            // We include branded content via the is_branded_content param.

            try await twitchClient.updateChannelInfo(
                title: streamTitle.isEmpty ? nil : streamTitle,
                gameId: categoryId.isEmpty ? nil : categoryId,
                language: language,
                tags: tags.isEmpty ? nil : tags,
                contentClassificationLabels: ccls.isEmpty ? nil : ccls,
                isBrandedContent: isBrandedContent
            )

            // Success — now start the stream
            await onStartStream()
        } catch TwitchError.scopeRequired {
            needsReauth = true
            // Still allow streaming even if update fails
            await onStartStream()
        } catch {
            saveError = "Failed to update stream info: \(error.localizedDescription)"
            // Still allow streaming even if update fails
            await onStartStream()
        }

        isSaving = false
    }
}
