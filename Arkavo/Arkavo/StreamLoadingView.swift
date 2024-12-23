import SwiftUI

struct StreamLoadingView: View {
    @StateObject private var viewModel: DiscordViewModel = ViewModelFactory.shared.makeDiscordViewModel()
    let publicID: Data
    @State private var state: LoadingState = .loading
    @State private var stream: Stream?

    var body: some View {
        VStack {
            switch state {
            case .loading:
                ProgressView("Loading stream...")
            case .loaded:
                if let stream {
                    ChatView(viewModel: ViewModelFactory.shared.makeChatViewModel(stream: stream))
                        .navigationTitle(stream.profile.name)
                } else {
                    Text("Stream corrupted")
                }
            case let .error(error):
                VStack(spacing: 16) {
                    Text("Error loading stream")
                        .font(.headline)
                    Text(error.localizedDescription)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Button("Retry") {
                        Task {
                            await loadStreamWithRetry()
                        }
                    }
                }
            case .notFound:
                VStack(spacing: 16) {
                    Text("Stream not found")
                        .font(.headline)
                    Text("The stream you're looking for couldn't be found")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
            }
        }
        .task {
            await loadStreamWithRetry()
        }
    }

    @MainActor
    func loadStreamWithRetry() async {
        state = .loading
        let maxRetries = 3
        let retryDelay: TimeInterval = 0.5

        do {
            // First check if the stream exists in the database
            if let existingStream = try await PersistenceController.shared.fetchStream(withPublicID: publicID)?.first {
                print("Found existing stream in database: \(existingStream.profile.name)")
                stream = existingStream
                state = .loaded
                return
            }
        } catch {
            print("Error checking database: \(error.localizedDescription)")
            // Continue to retry logic even if database check fails
        }

        for attempt in 1 ... maxRetries {
            do {
                if let stream = try await viewModel.requestStream(withPublicID: publicID) {
                    self.stream = stream
                    state = .loaded
                    return
                } else if attempt == maxRetries {
                    state = .notFound
                    print("Stream not found for publicID: \(publicID.base58EncodedString)")
                    return
                }
            } catch {
                if attempt == maxRetries {
                    state = .error(error)
                    print("Error loading stream: \(error.localizedDescription)")
                    return
                }
            }

            try? await Task.sleep(for: .milliseconds(Int(retryDelay * 1000)))
        }
    }
}

enum LoadingState {
    case loading
    case loaded
    case error(Error)
    case notFound
}
