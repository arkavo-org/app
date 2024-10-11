import SwiftUI

struct StreamLoadingView: View {
    @Environment(\.dismiss) private var dismiss
    @State var service: StreamService
    @State var streamBadgeViewModel: StreamBadgeViewModel?
    @State var state: LoadingState = .loading
    @State var stream: Stream?
    @State private var showThoughtStream = false
    var publicID: Data

    var body: some View {
        VStack {
            switch state {
            case .loading:
                ProgressView("Loading stream...")
            case .loaded:
                if let viewModel = streamBadgeViewModel {
                    StreamProfileBadge(viewModel: viewModel)
                    Button("Join stream") {
                        showThoughtStream = true
                    }
                    .fullScreenCover(isPresented: $showThoughtStream) {
                        if let stream,
                           let thoughtService = service.service.thoughtService,
                           let streamBadgeViewModel
                        {
                            let thoughtStreamViewModel = ThoughtStreamViewModel(service: thoughtService, stream: stream)
                            ThoughtStreamView(service: thoughtService, streamService: service, viewModel: thoughtStreamViewModel, streamBadgeViewModel: streamBadgeViewModel)
                        } else {
                            Text("Service misconfigured")
                        }
                    }
                } else {
                    Text("Stream corrupted")
                }
            case let .error(error):
                Text("Error loading stream: \(error.localizedDescription)")
            case .notFound:
                Text("Stream not found")
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

        for attempt in 1 ... maxRetries {
            do {
                if let stream = try await service.requestStream(withPublicID: publicID) {
                    self.stream = stream
                    streamBadgeViewModel = createStreamBadgeViewModel(from: stream)
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

            // Wait before the next retry
            try? await Task.sleep(for: .milliseconds(Int(retryDelay * 1000)))
        }
    }

    private func createStreamBadgeViewModel(from stream: Stream) -> StreamBadgeViewModel {
        // TODO: populate
        StreamBadgeViewModel(
            stream: stream,
            isHighlighted: false,
            isExpanded: true,
            topicTags: ["Placeholder"],
            membersProfile: [],
            ownerProfile: AccountProfileViewModel(profile: stream.profile, activityService: ActivityServiceModel()),
            activityLevel: .medium
        )
    }
}

enum LoadingState {
    case loading
    case loaded
    case error(Error)
    case notFound
}

struct StreamLoadingView_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            // Preview for loading state
            StreamLoadingView(service: MockStreamService(mockState: .loading), publicID: Data())
                .previewDisplayName("Loading State")

            // Preview for loaded state
            StreamLoadingView(service: MockStreamService(mockState: .loaded), publicID: Data())
                .previewDisplayName("Loaded State")

            // Preview for error state
            StreamLoadingView(service: MockStreamService(mockState: .error(NSError(domain: "", code: 0, userInfo: [NSLocalizedDescriptionKey: "Mock Error"]))), publicID: Data())
                .previewDisplayName("Error State")

            // Preview for not found state
            StreamLoadingView(service: MockStreamService(mockState: .notFound), publicID: Data())
                .previewDisplayName("Not Found State")
        }
    }
}

// Mock StreamService for preview
class MockStreamService: StreamService {
    var mockState: LoadingState

    init(mockState: LoadingState) {
        self.mockState = mockState
        super.init(ArkavoService())
    }

    @MainActor
    override func requestStream(withPublicID _: Data) async throws -> Stream? {
        switch mockState {
        case .loading:
            // Simulate loading delay
            try await Task.sleep(for: .seconds(100))
            return nil
        case .loaded:
            return Stream(creatorPublicID: Data(), profile: Profile(name: "Mock Stream"), admissionPolicy: .open, interactionPolicy: .open)
        case let .error(error):
            throw error
        case .notFound:
            return nil
        }
    }
}
