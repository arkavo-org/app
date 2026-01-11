import ArkavoMediaKit
import ArkavoSocial
import AVKit
import CryptoKit
import OpenTDFKit
import SwiftUI

/// Video player view for HLS-packaged TDF content
///
/// This view:
/// 1. Extracts HLS content from TDF archive
/// 2. Sets up custom resource loader for segment decryption
/// 3. Obtains decryption key from KAS
/// 4. Plays video with on-the-fly segment decryption
///
/// Use this for TDF archives created with `tdf-create --hls`
@available(iOS 26.0, macOS 26.0, tvOS 26.0, *)
struct HLSTDFVideoPlayerView: View {
    /// Raw TDF archive data containing HLS content
    let tdfData: Data

    /// KAS URL for key unwrapping
    let kasURL: URL

    /// Asset ID for tracking
    let assetID: String

    /// NTDF token for KAS authentication (issued by authnz-rs during registration)
    let ntdfToken: String

    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel = HLSTDFPlayerViewModel()

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()

                if let error = viewModel.error {
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
                            Task {
                                await viewModel.load(
                                    tdfData: tdfData,
                                    kasURL: kasURL,
                                    assetID: assetID,
                                    ntdfToken: ntdfToken
                                )
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .padding(.top)
                    }
                } else if viewModel.isLoading {
                    VStack(spacing: 16) {
                        ProgressView()
                            .scaleEffect(1.5)
                            .tint(.white)

                        Text(viewModel.loadingMessage)
                            .foregroundColor(.gray)
                    }
                } else if let player = viewModel.player {
                    VideoPlayer(player: player)
                        .ignoresSafeArea()
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        viewModel.stop()
                        dismiss()
                    }
                    .foregroundColor(.white)
                }
            }
            .toolbarBackground(.hidden, for: .navigationBar)
        }
        .task {
            await viewModel.load(
                tdfData: tdfData,
                kasURL: kasURL,
                assetID: assetID,
                ntdfToken: ntdfToken
            )
        }
        .onDisappear {
            viewModel.stop()
        }
    }
}

/// View model for HLS TDF playback
@available(iOS 26.0, macOS 26.0, tvOS 26.0, *)
@MainActor
final class HLSTDFPlayerViewModel: ObservableObject {
    @Published var player: AVPlayer?
    @Published var isLoading = false
    @Published var loadingMessage = "Preparing playback..."
    @Published var error: Error?

    private var streamingPlayer: TDF3StreamingPlayer?
    private var localAsset: LocalHLSAsset?

    func load(
        tdfData: Data,
        kasURL: URL,
        assetID: String,
        ntdfToken: String
    ) async {
        isLoading = true
        error = nil
        loadingMessage = "Extracting content..."

        do {
            // Create temp directory for extracted content
            let tempDir = FileManager.default.temporaryDirectory
                .appendingPathComponent("hls-player-\(UUID().uuidString)")

            // Extract HLS from TDF
            loadingMessage = "Extracting HLS segments..."
            let extractor = HLSTDFExtractor(kasURL: kasURL)
            let localAsset = try await extractor.extract(
                tdfData: tdfData,
                outputDirectory: tempDir
            )
            self.localAsset = localAsset

            // Create the streaming player
            loadingMessage = "Setting up player..."

            // Create key provider callback using KAS rewrap protocol
            let keyProvider: (HLSManifest) async throws -> SymmetricKey = { manifest in
                // Unwrap key from KAS using proper rewrap protocol
                try await self.unwrapKeyFromKAS(
                    manifest: manifest,
                    ntdfToken: ntdfToken
                )
            }

            // Create asset with custom resource loader
            let playlistURL = URL(string: "\(tdfHLSScheme)://playlist.m3u8")!
            let asset = AVURLAsset(url: playlistURL)

            // Create and configure resource loader delegate
            let delegate = HLSResourceLoaderDelegate(
                localAsset: localAsset,
                extractor: extractor
            )
            delegate.onKeyRequest = keyProvider

            // Set delegate on resource loader
            let loaderQueue = DispatchQueue(label: "com.arkavo.hlsPlayer")
            asset.resourceLoader.setDelegate(delegate, queue: loaderQueue)

            // Pre-fetch the key
            loadingMessage = "Obtaining decryption key..."
            let key = try await keyProvider(localAsset.manifest)
            delegate.setSymmetricKey(key)

            // Create player
            loadingMessage = "Starting playback..."
            let playerItem = AVPlayerItem(asset: asset)
            let avPlayer = AVPlayer(playerItem: playerItem)

            self.player = avPlayer
            isLoading = false

            // Start playback
            avPlayer.play()

        } catch {
            self.error = error
            isLoading = false
        }
    }

    func stop() {
        player?.pause()
        player?.replaceCurrentItem(with: nil)
        player = nil

        // Clean up extracted content
        if let localAsset {
            try? FileManager.default.removeItem(at: localAsset.outputDirectory)
            self.localAsset = nil
        }
    }

    /// Unwrap the DEK from KAS using the standard TDF rewrap protocol
    ///
    /// This uses OpenTDFKit's KASRewrapClient for proper:
    /// - JWT-signed requests
    /// - ECDH key exchange
    /// - Policy validation
    private func unwrapKeyFromKAS(
        manifest: HLSManifest,
        ntdfToken: String
    ) async throws -> SymmetricKey {
        // Build TDFManifest from HLSManifest for KAS rewrap
        guard let policy = manifest.policy,
              let policyBindingAlg = manifest.policyBindingAlg,
              let policyBindingHash = manifest.policyBindingHash
        else {
            throw HLSPlayerError.missingPolicyData
        }

        // Create TDF manifest structures
        let policyBinding = TDFPolicyBinding(alg: policyBindingAlg, hash: policyBindingHash)

        let keyAccess = TDFKeyAccessObject(
            type: .wrapped,
            url: manifest.kasURL.absoluteString,
            protocolValue: .kas,
            wrappedKey: manifest.wrappedKey,
            policyBinding: policyBinding,
            encryptedMetadata: nil,
            kid: nil,
            sid: nil,
            schemaVersion: nil,
            ephemeralPublicKey: nil
        )

        // Extract IV from algorithm string or use default
        let method = TDFMethodDescriptor(
            algorithm: manifest.algorithm,
            iv: manifest.segmentIVs.first ?? "",
            isStreamable: true
        )

        let encInfo = TDFEncryptionInformation(
            type: .split,
            keyAccess: [keyAccess],
            method: method,
            integrityInformation: nil,
            policy: policy
        )

        let payloadDescriptor = TDFPayloadDescriptor(
            type: .reference,
            url: "playlist.m3u8",
            protocolValue: .zip,
            isEncrypted: true,
            mimeType: "application/x-mpegURL"
        )

        let tdfManifest = TDFManifest(
            schemaVersion: "4.3.0",
            payload: payloadDescriptor,
            encryptionInformation: encInfo,
            assertions: nil
        )

        // Generate ephemeral P-256 key pair for ECDH
        let clientPrivateKey = P256.KeyAgreement.PrivateKey()
        let clientPublicKeyPEM = clientPrivateKey.publicKey.pemRepresentation

        // Create KAS rewrap client
        // Note: KASRewrapClient uses 'oauthToken' parameter name but we pass the NTDF token
        let kasClient = KASRewrapClient(
            kasURL: manifest.kasURL,
            oauthToken: ntdfToken
        )

        // Perform rewrap request
        let result = try await kasClient.rewrapTDF(
            manifest: tdfManifest,
            clientPublicKeyPEM: clientPublicKeyPEM
        )

        // Get wrapped key from result
        guard let wrappedKeyData = result.wrappedKeys.values.first else {
            throw HLSPlayerError.keyUnwrapFailed
        }

        // Extract session public key from PEM and unwrap
        guard let sessionPEM = result.sessionPublicKeyPEM else {
            throw HLSPlayerError.keyUnwrapFailed
        }

        let sessionKey = try extractCompressedKeyFromPEM(sessionPEM)

        // Unwrap using ECDH
        return try KASRewrapClient.unwrapKey(
            wrappedKey: wrappedKeyData,
            sessionPublicKey: sessionKey,
            clientPrivateKey: Data(clientPrivateKey.rawRepresentation)
        )
    }

    /// Extract compressed P256 public key from PEM format
    private func extractCompressedKeyFromPEM(_ pem: String) throws -> Data {
        let normalizedPEM = pem
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        let markers = [
            "-----BEGIN PUBLIC KEY-----",
            "-----END PUBLIC KEY-----",
            "-----BEGIN EC PUBLIC KEY-----",
            "-----END EC PUBLIC KEY-----"
        ]

        var base64Content = normalizedPEM
        for marker in markers {
            base64Content = base64Content.replacingOccurrences(of: marker, with: "")
        }
        base64Content = base64Content.components(separatedBy: .whitespacesAndNewlines).joined()

        guard let keyData = Data(base64Encoded: base64Content) else {
            throw HLSPlayerError.invalidKASResponse
        }

        // Parse the key and return compressed form
        let publicKey: P256.KeyAgreement.PublicKey
        if keyData.count == 65, keyData[0] == 0x04 {
            publicKey = try P256.KeyAgreement.PublicKey(x963Representation: keyData)
        } else if keyData.count == 33, keyData[0] == 0x02 || keyData[0] == 0x03 {
            publicKey = try P256.KeyAgreement.PublicKey(compressedRepresentation: keyData)
        } else if keyData.count >= 70 {
            publicKey = try P256.KeyAgreement.PublicKey(derRepresentation: keyData)
        } else {
            throw HLSPlayerError.invalidKASResponse
        }

        return publicKey.compressedRepresentation
    }
}

/// Errors for HLS TDF playback
enum HLSPlayerError: Error, LocalizedError {
    case invalidKASURL
    case invalidKASResponse
    case keyUnwrapFailed
    case extractionFailed
    case missingPolicyData
    case authenticationRequired

    var errorDescription: String? {
        switch self {
        case .invalidKASURL:
            "Invalid KAS URL"
        case .invalidKASResponse:
            "Invalid response from KAS"
        case .keyUnwrapFailed:
            "Failed to unwrap decryption key"
        case .extractionFailed:
            "Failed to extract HLS content from TDF"
        case .missingPolicyData:
            "TDF manifest missing policy or policyBinding data"
        case .authenticationRequired:
            "Authentication required to access content"
        }
    }
}

// MARK: - Preview

@available(iOS 26.0, macOS 26.0, tvOS 26.0, *)
#Preview {
    HLSTDFVideoPlayerView(
        tdfData: Data(),
        kasURL: URL(string: "https://100.arkavo.net")!,
        assetID: UUID().uuidString,
        ntdfToken: "preview-token"
    )
}
