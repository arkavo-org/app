import ArkavoSocial
import AVKit
import SwiftUI

// MARK: - TDFVideoPlayerView

/// Video player view for TDF-protected content using FairPlay DRM
///
/// This view:
/// 1. Sets up AVContentKeySession with FairPlay
/// 2. Adds the encrypted payload as a content key recipient
/// 3. Plays the video using hardware-backed decryption
///
/// The key exchange happens automatically when AVPlayer requests keys,
/// handled by TDFContentKeyDelegate.
struct TDFVideoPlayerView: View {
    /// URL to the encrypted payload file (written to temp directory)
    let payloadURL: URL

    /// TDF manifest containing encryption metadata
    let manifest: TDFManifestLite

    /// Optional user ID for session tracking
    var userId: String = "anonymous"

    @Environment(\.dismiss) private var dismiss
    @State private var player: AVPlayer?
    @State private var contentKeySession: AVContentKeySession?
    @State private var keyDelegate: TDFContentKeyDelegate?
    @State private var error: Error?
    @State private var isLoading = true

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()

                if let error {
                    VStack(spacing: 16) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 48))
                            .foregroundColor(.yellow)

                        Text("Playback Error")
                            .font(.headline)
                            .foregroundColor(.white)

                        Text(error.localizedDescription)
                            .font(.subheadline)
                            .foregroundColor(.gray)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)

                        Button("Try Again") {
                            self.error = nil
                            setupPlayer()
                        }
                        .buttonStyle(.borderedProminent)
                        .padding(.top)
                    }
                } else if isLoading {
                    VStack(spacing: 16) {
                        ProgressView()
                            .scaleEffect(1.5)
                            .tint(.white)

                        Text("Preparing playback...")
                            .foregroundColor(.gray)
                    }
                } else if let player {
                    VideoPlayer(player: player)
                        .ignoresSafeArea()
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        cleanupPlayer()
                        dismiss()
                    }
                    .foregroundColor(.white)
                }
            }
            .toolbarBackground(.hidden, for: .navigationBar)
        }
        .onAppear {
            setupPlayer()
        }
        .onDisappear {
            cleanupPlayer()
        }
    }

    // MARK: - Player Setup

    private func setupPlayer() {
        isLoading = true
        error = nil

        do {
            // 1. Create content key session with FairPlay
            contentKeySession = AVContentKeySession(keySystem: .fairPlayStreaming)

            // 2. Create key delegate with TDF manifest
            keyDelegate = TDFContentKeyDelegate(
                manifest: manifest,
                userId: userId
            )
            contentKeySession?.setDelegate(keyDelegate, queue: .main)

            // 3. Create asset from encrypted payload
            let asset = AVURLAsset(url: payloadURL)

            // 4. Add asset as content key recipient
            contentKeySession?.addContentKeyRecipient(asset)

            // 5. Create player item and player
            let playerItem = AVPlayerItem(asset: asset)

            // Listen for player item status
            Task {
                for await status in playerItem.publisher(for: \.status).values {
                    await handlePlayerItemStatus(status, playerItem: playerItem)
                }
            }

            player = AVPlayer(playerItem: playerItem)
            isLoading = false
            player?.play()

        } catch {
            self.error = error
            isLoading = false
        }
    }

    @MainActor
    private func handlePlayerItemStatus(
        _ status: AVPlayerItem.Status,
        playerItem: AVPlayerItem
    ) {
        switch status {
        case .readyToPlay:
            isLoading = false
        case .failed:
            error = playerItem.error
            isLoading = false
        case .unknown:
            break
        @unknown default:
            break
        }
    }

    private func cleanupPlayer() {
        player?.pause()
        player?.replaceCurrentItem(with: nil)
        player = nil

        // Remove content key recipient
        if let asset = (player?.currentItem?.asset as? AVURLAsset) {
            contentKeySession?.removeContentKeyRecipient(asset)
        }

        contentKeySession = nil
        keyDelegate = nil

        // Clean up temp file
        try? FileManager.default.removeItem(at: payloadURL)
    }
}

// MARK: - Preview

#Preview {
    TDFVideoPlayerView(
        payloadURL: URL(fileURLWithPath: "/tmp/test.ts"),
        manifest: TDFManifestLite(
            kasURL: "https://100.arkavo.net/kas",
            wrappedKey: "test",
            algorithm: "AES-128-CBC",
            iv: "test",
            assetID: UUID().uuidString,
            protectedAt: ISO8601DateFormatter().string(from: Date())
        )
    )
}
