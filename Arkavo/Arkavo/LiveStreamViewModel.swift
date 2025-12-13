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

    // MARK: - Display Layer and Audio

    var displayLayer: AVSampleBufferDisplayLayer?
    var audioRenderer: AVSampleBufferAudioRenderer?
    var synchronizer: AVSampleBufferRenderSynchronizer?

    // MARK: - Private Properties

    #if canImport(ArkavoStreaming)
        private var subscriber: NTDFStreamingSubscriber?
    #endif

    private let kasURL = URL(string: "https://100.arkavo.net/kas")!

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
            print("📺 [LiveStreamVM] ❌ No NTDF token")
            isConnecting = false
            errorMessage = "NTDF token required for encrypted stream playback"
            return
        }

        #if canImport(ArkavoStreaming)
            subscriber = NTDFStreamingSubscriber(kasURL: kasURL, ntdfToken: token)

            await subscriber?.setFrameHandler { @Sendable [weak self] frame in
                await self?.handleFrame(frame)
            }

            await subscriber?.setStateHandler { @Sendable [weak self] state in
                await self?.handleStateChange(state)
            }

            do {
                try await subscriber?.connect(rtmpURL: url, streamName: streamName)
                isConnecting = false
                isPlaying = true
            } catch {
                print("📺 [LiveStreamVM] ❌ Connection error: \(error)")
                isConnecting = false
                errorMessage = error.localizedDescription
            }
        #else
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
        private var videoFramesReceived: UInt64 = 0
        private var audioFramesReceived: UInt64 = 0
        private var videoFramesEnqueued: UInt64 = 0
        private var audioFramesEnqueued: UInt64 = 0
        private var waitingForKeyframe = true
        private var hasReceivedFirstKeyframe = false
        private var playbackStarted = false

        /// Start synchronized playback using the synchronizer
        private func startPlayback(firstPTS: CMTime) {
            guard !playbackStarted, let synchronizer else { return }

            // Set the synchronizer's time to match the first frame's PTS and start playback
            synchronizer.setRate(1.0, time: firstPTS)

            playbackStarted = true
            print("📺 [LiveStreamVM] ✅ Playback started at PTS: \(firstPTS.seconds)s")
        }

        private func handleFrame(_ frame: NTDFStreamingSubscriber.DecryptedFrame) async {
            framesReceived += 1

            if frame.type == .video {
                videoFramesReceived += 1
            } else {
                audioFramesReceived += 1
            }

            // Handle video frames
            if let sampleBuffer = frame.sampleBuffer,
               let displayLayer,
               frame.type == .video
            {
                // Check if layer has failed and needs recovery
                if displayLayer.sampleBufferRenderer.status == .failed {
                    print("📺 [LiveStreamVM] ⚠️ Display layer failed, flushing...")
                    if let error = displayLayer.sampleBufferRenderer.error {
                        print("📺 [LiveStreamVM] Error: \(error)")
                    }
                    displayLayer.sampleBufferRenderer.flush()
                    audioRenderer?.flush()
                    waitingForKeyframe = true
                    playbackStarted = false
                }

                // Wait for keyframe after flush or at start
                if waitingForKeyframe {
                    if frame.isKeyframe {
                        print("📺 [LiveStreamVM] ✅ KEYFRAME received - starting playback (after \(videoFramesReceived) video frames)")
                        waitingForKeyframe = false
                        hasReceivedFirstKeyframe = true

                        // Start synchronized playback on first keyframe
                        let pts = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
                        startPlayback(firstPTS: pts)
                    } else {
                        // Log waiting status periodically
                        if videoFramesReceived == 1 || videoFramesReceived % 100 == 0 {
                            print("📺 [LiveStreamVM] ⏳ Waiting for keyframe... (\(videoFramesReceived) video frames)")
                        }
                        return
                    }
                }

                displayLayer.sampleBufferRenderer.enqueue(sampleBuffer)
                videoFramesEnqueued += 1

                // Log playback status periodically
                if videoFramesEnqueued == 1 {
                    print("📺 [LiveStreamVM] ▶️ First video frame enqueued!")
                } else if videoFramesEnqueued % 300 == 0 {
                    print("📺 [LiveStreamVM] 📊 Status: video=\(videoFramesEnqueued), audio=\(audioFramesEnqueued) enqueued")
                }
            } else if frame.type == .video && frame.sampleBuffer == nil && videoFramesReceived <= 5 {
                print("📺 [LiveStreamVM] ⚠️ No sampleBuffer for video frame \(videoFramesReceived)")
            }

            // Handle audio frames
            if let sampleBuffer = frame.sampleBuffer,
               let audioRenderer,
               frame.type == .audio,
               playbackStarted  // Only enqueue audio after playback has started
            {
                // Check if audio renderer has failed
                if audioRenderer.status == .failed {
                    print("📺 [LiveStreamVM] ⚠️ Audio renderer failed, flushing...")
                    if let error = audioRenderer.error {
                        print("📺 [LiveStreamVM] Audio error: \(error)")
                    }
                    audioRenderer.flush()
                }

                audioRenderer.enqueue(sampleBuffer)
                audioFramesEnqueued += 1

                if audioFramesEnqueued == 1 {
                    // Log audio format info
                    if let formatDesc = CMSampleBufferGetFormatDescription(sampleBuffer) {
                        let mediaType = CMFormatDescriptionGetMediaType(formatDesc)
                        let mediaSubType = CMFormatDescriptionGetMediaSubType(formatDesc)
                        print("📺 [LiveStreamVM] 🔊 First audio frame enqueued! format=\(mediaType)/\(mediaSubType), status=\(audioRenderer.status.rawValue)")
                    } else {
                        print("📺 [LiveStreamVM] 🔊 First audio frame enqueued! (no format desc)")
                    }
                }
            }
        }

        private func handleStateChange(_ state: NTDFStreamingSubscriber.State) async {
            switch state {
            case .idle:
                isPlaying = false
                isConnecting = false
            case .connecting:
                print("📺 [LiveStreamVM] 🔄 Connecting...")
                isConnecting = true
            case .waitingForHeader:
                print("📺 [LiveStreamVM] 🔐 Waiting for NTDF header...")
                isConnecting = true
            case .playing:
                print("📺 [LiveStreamVM] ✅ Stream ready")
                isConnecting = false
                isPlaying = true
            case let .error(message):
                print("📺 [LiveStreamVM] ❌ Error: \(message)")
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
