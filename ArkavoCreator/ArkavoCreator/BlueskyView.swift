import ArkavoSocial
import Foundation
import SwiftUI

struct BlueskyRootView: View {
    @ObservedObject var blueskyClient: BlueskyClient
    @State private var newPostText: String = ""

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Profile Section
                if let profile = blueskyClient.profile {
                    ProfileSection(profile: profile)
                }

                // New Post Section
                VStack(alignment: .leading) {
                    Text("Create Post")
                        .font(.headline)

                    TextEditor(text: $newPostText)
                        .frame(height: 100)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                        )

                    HStack {
                        Spacer()
                        Button("Post") {
                            Task {
                                await blueskyClient.createPost(text: newPostText)
                                newPostText = ""
                                await loadTimeline()
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(newPostText.isEmpty || blueskyClient.isLoading)
                    }
                }
                .padding()
                .background(Color(NSColor.controlBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 12))

                // Timeline Section
                if let timeline = blueskyClient.timeline {
                    TimelineSection(timeline: timeline, blueskyClient: blueskyClient)
                }

                if blueskyClient.isLoading {
                    ProgressView()
                }

                if let error = blueskyClient.error {
                    Text(error.localizedDescription)
                        .foregroundColor(.red)
                        .padding()
                }
            }
            .padding()
        }
        .task {
            await loadProfile()
            await loadTimeline()
        }
    }

    private func loadProfile() async {
        await blueskyClient.getMyProfile()
    }

    private func loadTimeline() async {
        let _ = await blueskyClient.getTimeline()
    }
}

struct ProfileSection: View {
    let profile: ProfileViewResponse

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 16) {
                if let avatarURL = profile.avatar {
                    AsyncImage(url: URL(string: avatarURL)) { image in
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    } placeholder: {
                        Circle()
                            .fill(Color.gray.opacity(0.3))
                    }
                    .frame(width: 60, height: 60)
                    .clipShape(Circle())
                } else {
                    Circle()
                        .fill(Color.gray.opacity(0.3))
                        .frame(width: 60, height: 60)
                }

                VStack(alignment: .leading, spacing: 4) {
                    if let displayName = profile.displayName {
                        Text(displayName)
                            .font(.title2)
                            .fontWeight(.bold)
                    }
                    Text("@\(profile.handle)")
                        .foregroundColor(.secondary)
                }
            }

            if let description = profile.description {
                Text(description)
                    .foregroundColor(.secondary)
            }

            HStack(spacing: 24) {
                StatView(value: profile.postsCount, label: "Posts")
                StatView(value: profile.followersCount, label: "Followers")
                StatView(value: profile.followsCount, label: "Following")
            }
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

struct StatView: View {
    let value: Int
    let label: String

    var body: some View {
        VStack(spacing: 4) {
            Text("\(value)")
                .font(.headline)
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
}

struct TimelineSection: View {
    let timeline: TimelineResponse
    let blueskyClient: BlueskyClient

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Timeline")
                .font(.headline)

            ForEach(timeline.feed, id: \.post.uri) { feedView in
                PostView(post: feedView.post, blueskyClient: blueskyClient)
            }
        }
    }
}

struct PostView: View {
    let post: PostModelView
    let blueskyClient: BlueskyClient
    @State private var isLiked = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Author info
            HStack(spacing: 12) {
                if let avatarURL = post.author.avatar {
                    AsyncImage(url: URL(string: avatarURL)) { image in
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    } placeholder: {
                        Circle()
                            .fill(Color.gray.opacity(0.3))
                    }
                    .frame(width: 40, height: 40)
                    .clipShape(Circle())
                } else {
                    Circle()
                        .fill(Color.gray.opacity(0.3))
                        .frame(width: 40, height: 40)
                }

                VStack(alignment: .leading, spacing: 2) {
                    if let displayName = post.author.displayName {
                        Text(displayName)
                            .fontWeight(.semibold)
                    }
                    Text("@\(post.author.handle)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            // Post content
            Text(post.record.text)
                .fixedSize(horizontal: false, vertical: true)

            // Interactions
            HStack(spacing: 24) {
                Button(action: {
                    Task {
                        if isLiked {
                            await blueskyClient.unlikePost(uri: post.uri)
                        } else {
                            await blueskyClient.likePost(uri: post.uri, cid: post.cid)
                        }
                        isLiked.toggle()
                    }
                }) {
                    Label("\(post.likeCount)", systemImage: isLiked ? "heart.fill" : "heart")
                        .foregroundColor(isLiked ? .red : .primary)
                }
                .buttonStyle(.plain)

                Label("\(post.repostCount)", systemImage: "arrow.2.squarepath")
                    .foregroundColor(.primary)
            }
            .font(.caption)

            Text(formatDate(post.indexedAt))
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func formatDate(_ dateString: String) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSZ"
        guard let date = formatter.date(from: dateString) else { return dateString }

        let relativeFormatter = RelativeDateTimeFormatter()
        relativeFormatter.unitsStyle = .abbreviated
        return relativeFormatter.localizedString(for: date, relativeTo: Date())
    }
}
