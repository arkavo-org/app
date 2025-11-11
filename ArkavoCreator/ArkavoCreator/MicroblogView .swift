import ArkavoKit
import SwiftUI

struct MicroblogRootView: View {
    @ObservedObject var micropubClient: MicropubClient
    @State private var newPostContent: String = ""
    @State private var selectedPostType: PostType?
    @State private var selectedChannel: Channel?
    @State private var isPosting: Bool = false
    @State private var postError: Error?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let error = micropubClient.error {
                ErrorBanner(message: error.localizedDescription)
            }

            if let postError {
                ErrorBanner(message: postError.localizedDescription)
                    .onDisappear {
                        self.postError = nil
                    }
            }

            // Quick Post Section
            VStack(alignment: .leading, spacing: 8) {
                Text("Quick Post")
                    .font(.headline)

                if let config = micropubClient.siteConfig {
                    HStack {
                        if !config.postTypes.isEmpty {
                            Picker("Type", selection: $selectedPostType) {
                                Text("Select Type").tag(nil as PostType?)
                                ForEach(config.postTypes) { type in
                                    Text(type.name).tag(Optional(type))
                                }
                            }
                            .frame(maxWidth: 150)
                        }

                        if !config.channels.isEmpty {
                            Picker("Channel", selection: $selectedChannel) {
                                Text("Default Channel").tag(nil as Channel?)
                                ForEach(config.channels) { channel in
                                    Text(channel.name).tag(Optional(channel))
                                }
                            }
                            .frame(maxWidth: 150)
                        }
                    }
                }

                TextEditor(text: $newPostContent)
                    .frame(height: 100)
                    .overlay(
                        RoundedRectangle(cornerRadius: 4)
                            .stroke(Color.gray.opacity(0.2), lineWidth: 1),
                    )

                HStack {
                    if let config = micropubClient.siteConfig,
                       !config.destinations.isEmpty
                    {
                        Text("Posting to: \(config.destinations.first(where: { $0.microblogDefault })?.name ?? "Default")")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Button {
                        Task {
                            await postContent()
                        }
                    } label: {
                        if isPosting {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Text("Post")
                        }
                    }
                    .disabled(newPostContent.isEmpty || isPosting || micropubClient.siteConfig == nil)
                    .buttonStyle(.borderedProminent)
                }
            }

            if micropubClient.siteConfig == nil {
                HStack {
                    ProgressView()
                        .controlSize(.small)
                    Text("Loading site configuration...")
                        .foregroundStyle(.secondary)
                }
            }

            // Site Info Section
            if let config = micropubClient.siteConfig {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Site Configuration")
                        .font(.headline)

                    if config.mediaEndpoint != nil {
                        Label("Media uploads supported", systemImage: "photo")
                            .foregroundColor(.green)
                    }

                    if !config.channels.isEmpty {
                        Text("Available Channels:")
                            .font(.subheadline)
                        ForEach(config.channels) { channel in
                            Text("• \(channel.name)")
                                .font(.caption)
                        }
                    }

                    if let destination = config.destinations.first(where: { $0.microblogDefault }) {
                        Text("Default Destination: \(destination.name)")
                            .font(.caption)
                    }
                }
            }
        }
    }

    private func postContent() async {
        isPosting = true
        postError = nil

        do {
            var properties: [String: Any] = [:]
            if let channel = selectedChannel {
                properties["mp-channel"] = channel.uid
            }

            let _ = try await micropubClient.createPost(content: newPostContent)
            newPostContent = ""
            selectedPostType = nil
            selectedChannel = nil
        } catch {
            postError = error
        }

        isPosting = false
    }
}

struct ErrorBanner: View {
    let message: String

    var body: some View {
        HStack {
            Image(systemName: "exclamationmark.triangle")
            Text(message)
        }
        .padding()
        .foregroundColor(.white)
        .background(Color.red.opacity(0.8))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}
