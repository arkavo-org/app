import ArkavoSocial
import SwiftUI

struct RedditRootView: View {
    @ObservedObject var redditClient: RedditClient
    @State private var userInfo: RedditUserInfo?
    @State private var isLoading = false
    @State private var error: Error?

    var body: some View {
        VStack(spacing: 16) {
            if isLoading {
                ProgressView()
            } else if let error {
                VStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.largeTitle)
                        .foregroundColor(.orange)
                    Text("Failed to load Reddit profile")
                        .font(.headline)
                    Text(error.localizedDescription)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    Button("Retry") {
                        Task {
                            await loadUserInfo()
                        }
                    }
                    .buttonStyle(.bordered)
                }
            } else if let userInfo {
                // User Profile Section
                VStack(alignment: .leading, spacing: 16) {
                    HStack(spacing: 16) {
                        Circle()
                            .fill(Color.orange)
                            .frame(width: 60, height: 60)
                            .overlay(
                                Image(systemName: "person.fill")
                                    .foregroundColor(.white)
                            )

                        VStack(alignment: .leading, spacing: 4) {
                            Text(userInfo.name)
                                .font(.title2)
                                .fontWeight(.bold)

                            Text("Reddit User")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }

                        Spacer()

                        Button(action: { redditClient.logout() }) {
                            Text("Sign Out")
                        }
                        .buttonStyle(.borderless)
                    }

                    // Stats Grid
                    LazyVGrid(columns: [
                        GridItem(.flexible()),
                        GridItem(.flexible()),
                        GridItem(.flexible()),
                    ], spacing: 16) {
                        StatCard(title: "Link Karma", value: "\(userInfo.link_karma)")
                        StatCard(title: "Comment Karma", value: "\(userInfo.comment_karma)")
                        StatCard(title: "Account Age", value: formattedAge(from: userInfo.created))
                    }
                }
                .padding()
                .background(Color(NSColor.windowBackgroundColor))
                .cornerRadius(12)
            }
        }
        .task {
            await loadUserInfo()
        }
    }

    private func loadUserInfo() async {
        isLoading = true
        error = nil
        do {
            userInfo = try await redditClient.fetchUserInfo()
        } catch {
            self.error = error
        }
        isLoading = false
    }

    private func formattedAge(from timestamp: Double) -> String {
        let date = Date(timeIntervalSince1970: timestamp)
        let calendar = Calendar.current
        let components = calendar.dateComponents([.year, .month], from: date, to: Date())

        if let years = components.year, years > 0 {
            return "\(years)y"
        } else if let months = components.month, months > 0 {
            return "\(months)m"
        } else {
            return "New"
        }
    }
}

struct StatCard: View {
    let title: String
    let value: String

    var body: some View {
        VStack(spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
            Text(value)
                .font(.headline)
                .fontWeight(.bold)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(Color.gray.opacity(0.1))
        .cornerRadius(8)
    }
}
