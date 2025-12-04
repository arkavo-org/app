import AVFoundation
import Combine
import SwiftUI

#if canImport(ArkavoStreaming)
    import ArkavoStreaming
#endif

/// ViewModel for live stream playback
@MainActor
class LiveStreamViewModel: ObservableObject {
    // MARK: - Published Properties

    @Published var isConnecting = false
    @Published var isPlaying = false
    @Published var errorMessage: String?
    @Published var metadata: LiveStreamMetadata?
    @Published var framesReceived: Int = 0

    // MARK: - Display Layer

    var displayLayer: AVSampleBufferDisplayLayer?

    // MARK: - Private Properties

    #if canImport(ArkavoStreaming)
        private var subscriber: NTDFStreamingSubscriber?
    #endif

    private let kasURL = URL(string: "https://100.arkavo.net")!

    /// NTDF token for KAS authentication (must be set before connecting)
    var ntdfToken: String?

    // MARK: - Initialization

    init() {}

    // MARK: - Public Methods

    /// Connect to RTMP stream
    /// - Parameters:
    ///   - url: RTMP URL to connect to
    ///   - streamName: Stream name/key to subscribe to
    ///   - ntdfToken: Optional NTDF token (uses stored token if not provided)
    func connect(url: String, streamName: String, ntdfToken: String? = nil) async {
        isConnecting = true
        errorMessage = nil

        // Use provided token or stored token
        guard let token = ntdfToken ?? self.ntdfToken else {
            isConnecting = false
            errorMessage = "NTDF token required for encrypted stream playback"
            return
        }

        #if canImport(ArkavoStreaming)
            // Create subscriber with NTDF token
            subscriber = NTDFStreamingSubscriber(kasURL: kasURL, ntdfToken: token)

            // Set up frame handler
            await subscriber?.setFrameHandler { [weak self] frame in
                await self?.handleFrame(frame)
            }

            // Set up state handler
            await subscriber?.setStateHandler { [weak self] state in
                await self?.handleStateChange(state)
            }

            do {
                try await subscriber?.connect(rtmpURL: url, streamName: streamName)
                isConnecting = false
                isPlaying = true
            } catch {
                isConnecting = false
                errorMessage = error.localizedDescription
            }
        #else
            // Fallback for when ArkavoStreaming is not available
            isConnecting = false
            errorMessage = "Streaming not available"
        #endif
    }

    /// Disconnect from stream
    func disconnect() async {
        #if canImport(ArkavoStreaming)
            await subscriber?.disconnect()
            subscriber = nil
        #endif
        isPlaying = false
    }

    // MARK: - Private Methods

    #if canImport(ArkavoStreaming)
        private func handleFrame(_ frame: NTDFStreamingSubscriber.DecryptedFrame) async {
            framesReceived += 1

            // Enqueue sample buffer for display
            if let sampleBuffer = frame.sampleBuffer,
               let displayLayer,
               frame.type == .video
            {
                // Check if layer is ready
                if displayLayer.status == .failed {
                    displayLayer.flush()
                }

                displayLayer.enqueue(sampleBuffer)
            }
        }

        private func handleStateChange(_ state: NTDFStreamingSubscriber.State) async {
            switch state {
            case .idle:
                isPlaying = false
                isConnecting = false
            case .connecting:
                isConnecting = true
            case .waitingForHeader:
                isConnecting = true
            case .playing:
                isConnecting = false
                isPlaying = true
            case let .error(message):
                isConnecting = false
                isPlaying = false
                errorMessage = message
            }
        }
    #endif
}

// MARK: - Mock for non-streaming builds

#if !canImport(ArkavoStreaming)
    // Placeholder for when ArkavoStreaming is not available
    enum NTDFStreamingSubscriber {
        struct DecryptedFrame {
            enum FrameType { case video, audio }
            let type: FrameType
        }

        enum State { case idle, connecting, waitingForHeader, playing, error(String) }
    }
#endif
