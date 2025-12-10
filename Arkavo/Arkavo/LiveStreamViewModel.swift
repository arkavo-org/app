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
        print("📺 [LiveStreamVM] Connecting to \(url)/\(streamName)")
        isConnecting = true
        errorMessage = nil

        // Use provided token or stored token
        guard let token = ntdfToken ?? self.ntdfToken else {
            print("📺 [LiveStreamVM] ❌ No NTDF token available")
            isConnecting = false
            errorMessage = "NTDF token required for encrypted stream playback"
            return
        }
        print("📺 [LiveStreamVM] Using NTDF token: \(token.prefix(20))...")

        #if canImport(ArkavoStreaming)
            // Create subscriber with NTDF token
            print("📺 [LiveStreamVM] Creating NTDFStreamingSubscriber with KAS: \(kasURL)")
            subscriber = NTDFStreamingSubscriber(kasURL: kasURL, ntdfToken: token)

            // Set up frame handler with @Sendable closure
            await subscriber?.setFrameHandler { @Sendable [weak self] frame in
                await self?.handleFrame(frame)
            }

            // Set up state handler with @Sendable closure
            await subscriber?.setStateHandler { @Sendable [weak self] state in
                await self?.handleStateChange(state)
            }

            do {
                print("📺 [LiveStreamVM] Calling subscriber.connect()...")
                try await subscriber?.connect(rtmpURL: url, streamName: streamName)
                isConnecting = false
                isPlaying = true
                print("📺 [LiveStreamVM] ✅ Connected and playing")
            } catch {
                print("📺 [LiveStreamVM] ❌ Connection error: \(error)")
                isConnecting = false
                errorMessage = error.localizedDescription
            }
        #else
            // Fallback for when ArkavoStreaming is not available
            print("📺 [LiveStreamVM] ❌ ArkavoStreaming not available")
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

            // Log every 30 frames (~1 second at 30fps)
            if framesReceived % 30 == 0 {
                print("📺 [LiveStreamVM] Received \(framesReceived) frames (type: \(frame.type), keyframe: \(frame.isKeyframe), dataSize: \(frame.data.count))")
            }

            // Enqueue sample buffer for display
            if let sampleBuffer = frame.sampleBuffer,
               let displayLayer,
               frame.type == .video
            {
                // Log first video frame
                if framesReceived == 1 || framesReceived % 100 == 0 {
                    print("📺 [LiveStreamVM] Video frame \(framesReceived): sampleBuffer present, displayLayer status: \(displayLayer.status.rawValue)")
                }

                // Check if layer is ready
                if displayLayer.status == .failed {
                    print("📺 [LiveStreamVM] ⚠️ Display layer failed, flushing...")
                    if let error = displayLayer.error {
                        print("📺 [LiveStreamVM] Display layer error: \(error)")
                    }
                    displayLayer.flush()
                }

                displayLayer.enqueue(sampleBuffer)
            } else if frame.type == .video {
                // Log missing components
                if frame.sampleBuffer == nil {
                    print("📺 [LiveStreamVM] ⚠️ Frame \(framesReceived): No sampleBuffer for video frame")
                }
                if displayLayer == nil {
                    print("📺 [LiveStreamVM] ⚠️ Frame \(framesReceived): No displayLayer set!")
                }
            }
        }

        private func handleStateChange(_ state: NTDFStreamingSubscriber.State) async {
            print("📺 [LiveStreamVM] State changed to: \(state)")
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
                print("📺 [LiveStreamVM] ❌ Error state: \(message)")
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
