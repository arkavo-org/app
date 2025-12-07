import AVFoundation
import CoreMedia
import CryptoKit
import Foundation
import OpenTDFKit

/// Error types for NTDF streaming subscriber operations
public enum NTDFSubscriberError: Error, LocalizedError {
    case notInitialized
    case notPlaying
    case missingHeader
    case decryptionFailed(String)
    case connectionFailed(String)
    case unsupportedFormat

    public var errorDescription: String? {
        switch self {
        case .notInitialized:
            return "NTDFStreamingSubscriber not initialized"
        case .notPlaying:
            return "Not currently playing"
        case .missingHeader:
            return "Missing NanoTDF header from stream metadata"
        case let .decryptionFailed(message):
            return "Decryption failed: \(message)"
        case let .connectionFailed(message):
            return "Connection failed: \(message)"
        case .unsupportedFormat:
            return "Unsupported media format"
        }
    }
}

/// Subscriber for NTDF-encrypted RTMP streams
///
/// Combines RTMPSubscriber with NanoTDF decryption for receiving
/// and decrypting live encrypted video/audio streams.
public actor NTDFStreamingSubscriber {
    // MARK: - Types

    public enum State: Sendable, Equatable {
        case idle
        case connecting
        case waitingForHeader
        case playing
        case error(String)
    }

    /// Decrypted media frame ready for rendering
    public struct DecryptedFrame: @unchecked Sendable {
        public enum FrameType: Sendable {
            case video
            case audio
        }

        public let type: FrameType
        public let data: Data
        public let timestamp: UInt32
        public let isKeyframe: Bool
        public let sampleBuffer: CMSampleBuffer?  // Note: CMSampleBuffer is not Sendable but safe here
    }

    // MARK: - Properties

    private let kasURL: URL
    private let ntdfToken: String
    private let rtmpSubscriber: RTMPSubscriber
    private var decryptor: StreamingCollectionDecryptor?
    private var state: State = .idle

    // Video/Audio decoder configuration
    private var videoConfig: FLVDemuxer.AVCDecoderConfig?
    private var audioConfig: FLVDemuxer.AACDecoderConfig?
    private var videoFormatDescription: CMVideoFormatDescription?
    private var audioFormatDescription: CMAudioFormatDescription?

    // Callbacks
    private var onDecryptedFrame: ((DecryptedFrame) async -> Void)?
    private var onStateChange: ((State) async -> Void)?

    public var currentState: State { state }

    // MARK: - Initialization

    /// Initialize with KAS URL and NTDF token for key access
    /// - Parameters:
    ///   - kasURL: URL of the KAS server for key rewrap
    ///   - ntdfToken: NTDF token for authentication with KAS
    public init(kasURL: URL, ntdfToken: String) {
        self.kasURL = kasURL
        self.ntdfToken = ntdfToken
        self.rtmpSubscriber = RTMPSubscriber()
    }

    // MARK: - Public Methods

    /// Set callback for decrypted frames
    public func setFrameHandler(_ handler: @escaping (DecryptedFrame) async -> Void) {
        onDecryptedFrame = handler
    }

    /// Set callback for state changes
    public func setStateHandler(_ handler: @escaping (State) async -> Void) {
        onStateChange = handler
    }

    /// Connect to encrypted RTMP stream and start playing
    public func connect(rtmpURL: String, streamName: String) async throws {
        state = .connecting
        await onStateChange?(state)

        // Set up metadata handler to capture ntdf_header
        await rtmpSubscriber.setMetadataHandler { [weak self] metadata in
            await self?.handleMetadata(metadata)
        }

        // Set up frame handler
        await rtmpSubscriber.setFrameHandler { [weak self] frame in
            await self?.handleRawFrame(frame)
        }

        // Connect to RTMP server
        do {
            try await rtmpSubscriber.connect(url: rtmpURL, streamName: streamName)
            state = .waitingForHeader
            await onStateChange?(state)
            print("📡 Connected, waiting for ntdf_header...")
        } catch {
            state = .error(error.localizedDescription)
            await onStateChange?(state)
            throw NTDFSubscriberError.connectionFailed(error.localizedDescription)
        }
    }

    /// Disconnect from stream
    public func disconnect() async {
        await rtmpSubscriber.disconnect()
        decryptor = nil
        videoConfig = nil
        audioConfig = nil
        videoFormatDescription = nil
        audioFormatDescription = nil
        state = .idle
        await onStateChange?(state)
        print("✅ NTDF subscriber disconnected")
    }

    // MARK: - Private Methods

    private func handleMetadata(_ metadata: RTMPSubscriber.StreamMetadata) async {
        print("📥 Received stream metadata")

        // Check for ntdf_header
        guard let ntdfHeaderBase64 = metadata.ntdfHeader else {
            print("⚠️ No ntdf_header in metadata - stream may not be encrypted")
            state = .playing
            await onStateChange?(state)
            return
        }

        // Decode base64 header
        guard let headerBytes = Data(base64Encoded: ntdfHeaderBase64) else {
            print("❌ Failed to decode ntdf_header base64")
            state = .error("Invalid ntdf_header encoding")
            await onStateChange?(state)
            return
        }

        print("🔐 Initializing decryptor with header: \(headerBytes.count) bytes")

        // Initialize decryptor with NTDF token
        do {
            decryptor = try await StreamingCollectionDecryptor(
                headerBytes: headerBytes,
                kasURL: kasURL,
                ntdfToken: ntdfToken
            )
            state = .playing
            await onStateChange?(state)
            print("✅ Decryptor initialized, ready to decrypt frames")
        } catch {
            print("❌ Failed to create decryptor: \(error)")
            state = .error("Decryptor initialization failed: \(error.localizedDescription)")
            await onStateChange?(state)
        }
    }

    private func handleRawFrame(_ frame: RTMPSubscriber.MediaFrame) async {
        switch frame.type {
        case .video:
            await handleVideoFrame(frame)
        case .audio:
            await handleAudioFrame(frame)
        case .metadata:
            // Already handled via metadata callback
            break
        }
    }

    private func handleVideoFrame(_ frame: RTMPSubscriber.MediaFrame) async {
        // Check if this is a sequence header
        if frame.data.count > 1 {
            let codecId = frame.data[0] & 0x0F
            if codecId == 7, frame.data[1] == 0 {
                // AVC sequence header - not encrypted
                do {
                    videoConfig = try FLVDemuxer.parseAVCSequenceHeader(frame.data)
                    videoFormatDescription = try videoConfig?.createFormatDescription()
                    print("📥 Video sequence header parsed: \(videoConfig?.sps.count ?? 0) SPS, \(videoConfig?.pps.count ?? 0) PPS")
                } catch {
                    print("❌ Failed to parse video sequence header: \(error)")
                }
                return
            }
        }

        // Decrypt if we have a decryptor
        let decryptedData: Data
        if let decryptor {
            do {
                decryptedData = try await decryptor.decrypt(frame.data)
            } catch {
                print("❌ Video decryption failed: \(error)")
                return
            }
        } else {
            // Not encrypted
            decryptedData = frame.data
        }

        // Parse decrypted FLV video frame
        guard let config = videoConfig else {
            print("⚠️ Received video frame before sequence header")
            return
        }

        do {
            let videoFrame = try FLVDemuxer.parseAVCVideoFrame(
                decryptedData,
                naluLengthSize: Int(config.naluLengthSize),
                baseTimestamp: frame.timestamp
            )

            // Create sample buffer if we have format description
            var sampleBuffer: CMSampleBuffer?
            if let formatDesc = videoFormatDescription {
                sampleBuffer = try? FLVDemuxer.createVideoSampleBuffer(
                    frame: videoFrame,
                    formatDescription: formatDesc,
                    naluLengthSize: Int(config.naluLengthSize)
                )
            }

            // Combine NALUs for callback
            var naluData = Data()
            for nalu in videoFrame.nalus {
                naluData.append(nalu)
            }

            let decryptedFrame = DecryptedFrame(
                type: .video,
                data: naluData,
                timestamp: frame.timestamp,
                isKeyframe: videoFrame.isKeyframe,
                sampleBuffer: sampleBuffer
            )

            await onDecryptedFrame?(decryptedFrame)
        } catch {
            print("❌ Failed to parse video frame: \(error)")
        }
    }

    private func handleAudioFrame(_ frame: RTMPSubscriber.MediaFrame) async {
        // Check if this is a sequence header
        if frame.data.count > 1 {
            let soundFormat = (frame.data[0] >> 4) & 0x0F
            if soundFormat == 10, frame.data[1] == 0 {
                // AAC sequence header - not encrypted
                do {
                    audioConfig = try FLVDemuxer.parseAACSequenceHeader(frame.data)
                    audioFormatDescription = try audioConfig?.createFormatDescription()
                    print("📥 Audio sequence header parsed: \(audioConfig?.sampleRate ?? 0) Hz, \(audioConfig?.channelCount ?? 0) ch")
                } catch {
                    print("❌ Failed to parse audio sequence header: \(error)")
                }
                return
            }
        }

        // Decrypt if we have a decryptor
        let decryptedData: Data
        if let decryptor {
            do {
                decryptedData = try await decryptor.decrypt(frame.data)
            } catch {
                print("❌ Audio decryption failed: \(error)")
                return
            }
        } else {
            decryptedData = frame.data
        }

        // Parse decrypted FLV audio frame
        do {
            let audioFrame = try FLVDemuxer.parseAACAudioFrame(decryptedData, baseTimestamp: frame.timestamp)

            // Create sample buffer if we have format description
            var sampleBuffer: CMSampleBuffer?
            if let formatDesc = audioFormatDescription {
                sampleBuffer = try? FLVDemuxer.createAudioSampleBuffer(
                    frame: audioFrame,
                    formatDescription: formatDesc
                )
            }

            let decryptedFrame = DecryptedFrame(
                type: .audio,
                data: audioFrame.data,
                timestamp: frame.timestamp,
                isKeyframe: false,
                sampleBuffer: sampleBuffer
            )

            await onDecryptedFrame?(decryptedFrame)
        } catch {
            print("❌ Failed to parse audio frame: \(error)")
        }
    }

    /// Get video format description (available after receiving sequence header)
    public var videoFormat: CMVideoFormatDescription? {
        videoFormatDescription
    }

    /// Get audio format description (available after receiving sequence header)
    public var audioFormat: CMAudioFormatDescription? {
        audioFormatDescription
    }
}

// MARK: - Streaming Collection Decryptor

/// Decryptor for NanoTDF Collection items in streaming context
///
/// Wraps OpenTDFKit's NanoTDFCollectionDecryptor with KAS rewrap integration.
/// Parses the collection header, performs KAS rewrap to obtain the symmetric key,
/// and provides per-frame decryption using the shared key.
actor StreamingCollectionDecryptor {
    /// The parsed NanoTDF header
    private let header: Header

    /// The raw header bytes (needed for KAS rewrap request)
    private let headerBytes: Data

    /// KAS URL for key rewrap
    private let kasURL: URL

    /// NTDF token for KAS authentication
    private let ntdfToken: String

    /// The underlying OpenTDFKit decryptor (initialized after KAS rewrap)
    private var decryptor: OpenTDFKit.NanoTDFCollectionDecryptor?

    /// Cipher configuration from header
    private let cipher: Cipher

    /// Tag size for parsing encrypted items
    private let tagSize: Int

    /// Initialize with header bytes, KAS URL, and NTDF token
    /// - Parameters:
    ///   - headerBytes: Raw NanoTDF collection header bytes from stream metadata
    ///   - kasURL: URL of the KAS server for key rewrap
    ///   - ntdfToken: NTDF token for KAS authentication
    /// - Throws: If header parsing fails or KAS rewrap fails
    init(headerBytes: Data, kasURL: URL, ntdfToken: String) async throws {
        self.headerBytes = headerBytes
        self.kasURL = kasURL
        self.ntdfToken = ntdfToken

        // Parse the NanoTDF header using BinaryParser
        print("🔐 Parsing NanoTDF header: \(headerBytes.count) bytes")
        let parser = BinaryParser(data: headerBytes)
        do {
            self.header = try parser.parseHeader()
        } catch {
            throw NTDFSubscriberError.decryptionFailed("Failed to parse NanoTDF header: \(error)")
        }

        // Get cipher and tag size from header
        self.cipher = header.payloadSignatureConfig.payloadCipher ?? .aes256GCM128
        self.tagSize = cipher.tagSize

        print("🔐 Header parsed - cipher: \(cipher), tag size: \(tagSize) bytes")

        // Perform KAS rewrap to get symmetric key
        try await performKASRewrap()
    }

    /// Perform KAS rewrap to obtain the symmetric key for decryption
    private func performKASRewrap() async throws {
        print("🔐 Performing KAS rewrap with NTDF token...")

        // Generate ephemeral key pair for this rewrap request
        let privateKey = P256.KeyAgreement.PrivateKey()
        let publicKeyData = privateKey.publicKey.compressedRepresentation

        // Create ephemeral key pair structure
        let clientKeyPair = EphemeralKeyPair(
            privateKey: privateKey.rawRepresentation,
            publicKey: publicKeyData,
            curve: .secp256r1
        )

        // Create KAS rewrap client with NTDF token
        let kasRewrapClient = KASRewrapClient(kasURL: kasURL, oauthToken: ntdfToken)

        do {
            // Send rewrap request
            let (wrappedKey, sessionPublicKey) = try await kasRewrapClient.rewrapNanoTDF(
                header: headerBytes,
                parsedHeader: header,
                clientKeyPair: clientKeyPair
            )

            print("🔐 Received wrapped key: \(wrappedKey.count) bytes, session key: \(sessionPublicKey.count) bytes")

            // Unwrap the key using ECDH with session public key
            let symmetricKey = try unwrapKey(
                wrappedKey: wrappedKey,
                sessionPublicKey: sessionPublicKey,
                clientPrivateKey: privateKey
            )

            print("✅ Symmetric key derived: \(symmetricKey.bitCount) bits")

            // Create the OpenTDFKit decryptor with the unwrapped key
            self.decryptor = OpenTDFKit.NanoTDFCollectionDecryptor.withUnwrappedKey(
                symmetricKey: symmetricKey,
                cipher: cipher
            )

            print("✅ Decryptor initialized successfully")

        } catch {
            print("❌ KAS rewrap failed: \(error)")
            throw NTDFSubscriberError.decryptionFailed("KAS rewrap failed: \(error.localizedDescription)")
        }
    }

    /// Unwrap the symmetric key from KAS response
    private func unwrapKey(
        wrappedKey: Data,
        sessionPublicKey: Data,
        clientPrivateKey: P256.KeyAgreement.PrivateKey
    ) throws -> SymmetricKey {
        // KAS returns the key wrapped with ECDH-derived key
        // Format: nonce (12 bytes) + ciphertext + tag (16 bytes)

        guard wrappedKey.count > 28 else {
            throw NTDFSubscriberError.decryptionFailed("Wrapped key too short: \(wrappedKey.count) bytes")
        }

        // Parse session public key (may be compressed or uncompressed)
        let kasSessionKey: P256.KeyAgreement.PublicKey
        do {
            if sessionPublicKey.count == 33 {
                kasSessionKey = try P256.KeyAgreement.PublicKey(compressedRepresentation: sessionPublicKey)
            } else if sessionPublicKey.count == 65 {
                kasSessionKey = try P256.KeyAgreement.PublicKey(x963Representation: sessionPublicKey)
            } else {
                throw NTDFSubscriberError.decryptionFailed("Invalid session public key size: \(sessionPublicKey.count)")
            }
        } catch {
            throw NTDFSubscriberError.decryptionFailed("Failed to parse session public key: \(error)")
        }

        // Perform ECDH to derive shared secret
        let sharedSecret: SharedSecret
        do {
            sharedSecret = try clientPrivateKey.sharedSecretFromKeyAgreement(with: kasSessionKey)
        } catch {
            throw NTDFSubscriberError.decryptionFailed("ECDH failed: \(error)")
        }

        // Derive unwrapping key via HKDF
        // Use NanoTDF salt: SHA256(magicNumber + version)
        let magicAndVersion = Data([0x4C, 0x31, Header.version])  // "L1M"
        let salt = Data(SHA256.hash(data: magicAndVersion))

        let unwrapKey = sharedSecret.hkdfDerivedSymmetricKey(
            using: SHA256.self,
            salt: salt,
            sharedInfo: Data(),
            outputByteCount: 32
        )

        // Parse wrapped key format from KAS
        // Platform returns: nonce (12 bytes) + ciphertext + tag (16 bytes)
        let nonce = wrappedKey.prefix(12)
        let ciphertextWithTag = wrappedKey.dropFirst(12)

        // Decrypt using AES-GCM
        do {
            let gcmNonce = try AES.GCM.Nonce(data: nonce)
            let sealedBox = try AES.GCM.SealedBox(combined: nonce + ciphertextWithTag)
            let payloadKeyData = try AES.GCM.open(sealedBox, using: unwrapKey)
            return SymmetricKey(data: payloadKeyData)
        } catch {
            throw NTDFSubscriberError.decryptionFailed("Failed to unwrap payload key: \(error)")
        }
    }

    /// Decrypt a single encrypted collection item
    /// - Parameter encryptedData: The encrypted frame data in collection wire format
    /// - Returns: Decrypted plaintext data
    /// - Throws: If decryption fails
    func decrypt(_ encryptedData: Data) async throws -> Data {
        guard let decryptor else {
            throw NTDFSubscriberError.decryptionFailed("Decryptor not initialized")
        }

        // Parse collection item wire format:
        // - 3 bytes: IV counter (big-endian)
        // - 3 bytes: length of ciphertext + tag (big-endian)
        // - N bytes: ciphertext + tag

        guard encryptedData.count >= 6 else {
            throw NTDFSubscriberError.decryptionFailed("Encrypted data too short: \(encryptedData.count) bytes")
        }

        // Parse IV counter (3 bytes, big-endian)
        let ivCounter = UInt32(encryptedData[0]) << 16 |
                        UInt32(encryptedData[1]) << 8 |
                        UInt32(encryptedData[2])

        // Parse payload length (3 bytes, big-endian)
        let payloadLength = Int(encryptedData[3]) << 16 |
                           Int(encryptedData[4]) << 8 |
                           Int(encryptedData[5])

        // Validate we have enough data
        let expectedTotal = 6 + payloadLength
        guard encryptedData.count >= expectedTotal else {
            throw NTDFSubscriberError.decryptionFailed(
                "Incomplete encrypted data: have \(encryptedData.count), need \(expectedTotal)"
            )
        }

        // Extract ciphertext + tag
        let ciphertextWithTag = encryptedData.subdata(in: 6..<(6 + payloadLength))

        // Create CollectionItem for decryption
        let item = CollectionItem(
            ivCounter: ivCounter,
            ciphertextWithTag: ciphertextWithTag,
            tagSize: tagSize
        )

        // Decrypt using OpenTDFKit
        do {
            return try await decryptor.decryptItem(item)
        } catch {
            throw NTDFSubscriberError.decryptionFailed("Decryption failed: \(error)")
        }
    }
}
