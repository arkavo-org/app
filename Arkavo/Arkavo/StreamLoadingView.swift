import SwiftUI

struct StreamLoadingView: View {
    @State var service: StreamService
    @State var state: LoadingState = .loading
    @State var stream: Stream?
    var publicID: Data

    var body: some View {
        VStack {
            switch state {
            case .loading:
                ProgressView("Loading stream...")
            case .loaded:
                Text("Stream found TODO show badge")
//                StreamProfileBadge(stream: stream!)
            case let .error(error):
                Text("Error loading stream: \(error.localizedDescription)")
            case .notFound:
                Text("Stream not found")
            }
        }
        .task {
            await loadStream()
        }
    }

    @MainActor
    func loadStream() async {
        state = .loading
        do {
            if let stream = try await service.fetchStream(withPublicID: publicID) {
                self.stream = stream
                state = .loaded
            } else {
                state = .notFound
                print("Stream not found for publicID: \(publicID.base58EncodedString)")
            }
        } catch {
            state = .error(error)
            print("Error loading stream: \(error.localizedDescription)")
        }
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
    override func fetchStream(withPublicID _: Data) async throws -> Stream? {
        switch mockState {
        case .loading:
            // Simulate loading delay
            try await Task.sleep(for: .seconds(100))
            return nil
        case .loaded:
            return Stream(account: Account(), profile: Profile(name: "Mock Stream"), admissionPolicy: .open, interactionPolicy: .open)
        case let .error(error):
            throw error
        case .notFound:
            return nil
        }
    }
}
