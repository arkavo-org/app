import ArkavoSocial
import Foundation

@MainActor
class StreamMessageRouter: ObservableObject {
    private var streamHandlers: [Data: (Data) -> Void] = [:]
    private let client: ArkavoClient
    private let persistenceController: PersistenceController
    private let videoCache: VideoStreamCache

    init(client: ArkavoClient, persistenceController: PersistenceController) {
        self.client = client
        self.persistenceController = persistenceController
        videoCache = VideoStreamCache()

        // Set up NATS message handler
        client.setNATSMessageHandler { [weak self] messageData in
            Task { @MainActor in
                self?.routeMessage(messageData)
            }
        }
    }

    func getVideoCache() -> VideoStreamCache {
        videoCache
    }

    func subscribe(stream: Stream) {
        // Use stream.sources[0] to determine routing behavior
        if let source = stream.sources.first {
            switch source.metadata.mediaType {
            case .text:
                subscribeTextStream(stream)
            case .video:
                subscribeVideoStream(stream)
            case .image:
                subscribeImageStream(stream)
            case .audio:
                subscribeAudioStream(stream)
            }
        } else {
            print(stream.publicID, "has no sources")
        }
    }

    private func subscribeTextStream(_ stream: Stream) {
        streamHandlers[stream.publicID] = { [weak self] data in
            guard let self else { return }
            Task { @MainActor in
                // Create a new Thought and add to stream
                let metadata = Thought.extractMetadata(from: data)
                let thought = Thought(nano: data, metadata: metadata)
                stream.thoughts.append(thought)
                try? await self.persistenceController.saveChanges()
            }
        }
    }

    private func subscribeVideoStream(_ stream: Stream) {
        streamHandlers[stream.publicID] = { [weak self] data in
            guard let self else { return }
            Task { @MainActor in
                do {
                    // Add to video cache
                    try self.videoCache.addVideo(data)

                    // Create thought for the video
                    let metadata = ThoughtMetadata(
                        creator: UUID(),
                        mediaType: .video,
                        createdAt: Date(),
                        summary: "Video content",
                        contributors: []
                    )

                    let thought = Thought(nano: data, metadata: metadata)
                    stream.thoughts.append(thought)

                    try await self.persistenceController.saveChanges()
                } catch {
                    print("Error handling video data: \(error)")
                }
            }
        }
    }

    private func subscribeImageStream(_ stream: Stream) {
        streamHandlers[stream.publicID] = { [weak self] data in
            guard let self else { return }
            Task { @MainActor in
                // Create a new Thought and add to stream
                let metadata = Thought.extractMetadata(from: data)
                let thought = Thought(nano: data, metadata: metadata)
                stream.thoughts.append(thought)
                try? await self.persistenceController.saveChanges()
            }
        }
    }

    private func subscribeAudioStream(_ stream: Stream) {
        streamHandlers[stream.publicID] = { [weak self] data in
            guard let self else { return }
            Task { @MainActor in
                let metadata = Thought.extractMetadata(from: data)
                let thought = Thought(nano: data, metadata: metadata)
                stream.thoughts.append(thought)
                try? await self.persistenceController.saveChanges()
            }
        }
    }

    func unsubscribe(stream: Stream) {
        streamHandlers.removeValue(forKey: stream.publicID)
    }

    private func routeMessage(_ message: Data) {
        // Extract stream publicID from message
        guard message.count > 33 else { return }
        let streamID = message[1 ..< 33]

        if let handler = streamHandlers[Data(streamID)] {
            let payload = message.dropFirst(33)
            handler(Data(payload))
        }
    }
}
