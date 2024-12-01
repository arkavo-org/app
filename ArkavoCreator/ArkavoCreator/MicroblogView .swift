import ArkavoSocial
import SwiftUI

struct MicroblogRootView: View {
    @ObservedObject var micropubClient: MicropubClient
    @State private var newPostContent: String = ""
    @State private var isPostingEnabled: Bool = false
    @State private var isLoading: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let error = micropubClient.error {
                ErrorBanner(message: error.localizedDescription)
            }

            // Quick Post Section
            VStack(alignment: .leading, spacing: 8) {
                Text("Quick Post")
                    .font(.headline)

                TextEditor(text: $newPostContent)
                    .frame(height: 100)
                    .overlay(
                        RoundedRectangle(cornerRadius: 4)
                            .stroke(Color.gray.opacity(0.2), lineWidth: 1)
                    )

                HStack {
                    Spacer()
                    Button("Post") {
                        Task {
                            isLoading = true
                            do {
                                let _ = try await micropubClient.createPost(content: newPostContent)
                                newPostContent = ""
                            } catch {
                                // Error is already handled by the client
                            }
                            isLoading = false
                        }
                    }
                    .disabled(newPostContent.isEmpty || isLoading)
                    .buttonStyle(.borderedProminent)
                }
            }

            // Site Info Section
            if let config = micropubClient.siteConfig {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Site Configuration")
                        .font(.headline)

                    if let mediaEndpoint = config.mediaEndpoint {
                        Label("Media uploads supported", systemImage: "photo")
                            .foregroundColor(.green)
                    }

                    if let syndication = config.syndicateTo, !syndication.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Syndication Targets:")
                                .font(.subheadline)
                            ForEach(syndication, id: \.uid) { target in
                                Text("• \(target.name)")
                                    .font(.caption)
                            }
                        }
                    }
                }
            }
        }
        .disabled(isLoading)
        .overlay {
            if isLoading {
                ProgressView()
            }
        }
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
