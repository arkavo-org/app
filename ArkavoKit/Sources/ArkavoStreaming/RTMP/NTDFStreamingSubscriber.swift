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

        // Check for ntdf_header in metadata (may be stripped by RTMP server)
        guard let ntdfHeaderBase64 = metadata.ntdfHeader else {
            print("⚠️ No ntdf_header in metadata - will check for header frame in video data")
            // Don't transition to .playing yet - wait for header frame or timeout
            return
        }

        // Decode base64 header
        guard let headerBytes = Data(base64Encoded: ntdfHeaderBase64) else {
            print("❌ Failed to decode ntdf_header base64")
            state = .error("Invalid ntdf_header encoding")
            await onStateChange?(state)
            return
        }

        await initializeDecryptorWithHeader(headerBytes)
    }

    /// Initialize decryptor with NTDF header bytes (from metadata or header frame)
    private func initializeDecryptorWithHeader(_ headerBytes: Data) async {
        // Skip if already initialized
        if decryptor != nil {
            print("🔐 [NTDFSub] Decryptor already initialized, skipping")
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

    private var videoFrameCount: UInt64 = 0

    /// Magic bytes to identify NTDF header frame: "NTDF" (0x4E544446)
    private static let ntdfHeaderMagic: [UInt8] = [0x4E, 0x54, 0x44, 0x46]

    private func handleVideoFrame(_ frame: RTMPSubscriber.MediaFrame) async {
        videoFrameCount += 1

        // Check if this is a sequence header or NTDF header frame
        if frame.data.count > 1 {
            let frameType = (frame.data[0] >> 4) & 0x0F
            let codecId = frame.data[0] & 0x0F
            let packetType = frame.data[1]

            // Debug: log first few video frames and any with packetType=2 (should be NTDF headers)
            if videoFrameCount <= 5 || packetType == 2 {
                let hexPrefix = frame.data.prefix(20).map { String(format: "%02X", $0) }.joined(separator: " ")
                print("🎬 [NTDFSub] Video frame #\(videoFrameCount): frameType=\(frameType) codecId=\(codecId) packetType=\(packetType) size=\(frame.data.count) bytes=\(hexPrefix)...")
            }

            // Check for NTDF header frame (special video frame with magic bytes)
            // Format: [17 02 00 00 00][4E 54 44 46][length 2 bytes][header bytes]
            // Note: Check for magic bytes regardless of packetType as RTMP server may modify it
            if codecId == 7, frame.data.count > 11 {
                // Check for NTDF magic bytes at offset 5 (after FLV video header)
                let magicOffset = 5
                if frame.data.count > magicOffset + 4 &&
                    frame.data[magicOffset] == Self.ntdfHeaderMagic[0] &&
                    frame.data[magicOffset + 1] == Self.ntdfHeaderMagic[1] &&
                    frame.data[magicOffset + 2] == Self.ntdfHeaderMagic[2] &&
                    frame.data[magicOffset + 3] == Self.ntdfHeaderMagic[3] {

                    // Extract header length (2 bytes big-endian) at offset 9
                    let headerLength = Int(frame.data[9]) << 8 | Int(frame.data[10])

                    // Extract header bytes
                    if frame.data.count >= 11 + headerLength {
                        let headerBytes = frame.data.subdata(in: 11..<(11 + headerLength))
                        print("🔐 [NTDFSub] Received NTDF header frame: \(headerLength) bytes (packetType=\(packetType))")
                        await initializeDecryptorWithHeader(headerBytes)
                    } else {
                        print("🎬 [NTDFSub] ⚠️ NTDF header frame too short: expected \(11 + headerLength), got \(frame.data.count)")
                    }
                    return
                }
            }

            if codecId == 7, packetType == 0 {
                // AVC sequence header - not encrypted
                do {
                    videoConfig = try FLVDemuxer.parseAVCSequenceHeader(frame.data)
                    videoFormatDescription = try videoConfig?.createFormatDescription()
                    print("🎬 [NTDFSub] ✅ Video sequence header parsed: \(videoConfig?.sps.count ?? 0) SPS, \(videoConfig?.pps.count ?? 0) PPS, naluLengthSize=\(videoConfig?.naluLengthSize ?? 0)")
                } catch {
                    print("🎬 [NTDFSub] ❌ Failed to parse video sequence header: \(error)")
                }
                return
            }
        }

        // Decrypt if we have a decryptor
        let decryptedData: Data
        if let decryptor {
            do {
                decryptedData = try await decryptor.decrypt(frame.data)
                if videoFrameCount <= 3 || videoFrameCount % 100 == 0 {
                    print("🎬 [NTDFSub] Decrypted frame #\(videoFrameCount): \(frame.data.count) -> \(decryptedData.count) bytes")
                }
            } catch {
                print("🎬 [NTDFSub] ❌ Video decryption failed for frame #\(videoFrameCount): \(error)")
                return
            }
        } else {
            // Not encrypted
            decryptedData = frame.data
            if videoFrameCount <= 3 {
                print("🎬 [NTDFSub] Unencrypted frame #\(videoFrameCount): \(decryptedData.count) bytes")
            }
        }

        // Parse decrypted FLV video frame
        guard let config = videoConfig else {
            print("🎬 [NTDFSub] ⚠️ Frame #\(videoFrameCount): Received video frame before sequence header")
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
                if sampleBuffer == nil && (videoFrameCount <= 3 || videoFrameCount % 100 == 0) {
                    print("🎬 [NTDFSub] ⚠️ Frame #\(videoFrameCount): createVideoSampleBuffer returned nil")
                }
            } else {
                if videoFrameCount <= 3 {
                    print("🎬 [NTDFSub] ⚠️ Frame #\(videoFrameCount): No videoFormatDescription available")
                }
            }

            // Log first few frames and periodically
            if videoFrameCount <= 3 || videoFrameCount % 100 == 0 {
                print("🎬 [NTDFSub] Frame #\(videoFrameCount): keyframe=\(videoFrame.isKeyframe), nalus=\(videoFrame.nalus.count), sampleBuffer=\(sampleBuffer != nil)")
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
            print("🎬 [NTDFSub] ❌ Failed to parse video frame #\(videoFrameCount): \(error)")
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
        print("🔐 [DEBUG] Policy type: \(header.policy.type)")
        if let policyBody = header.policy.body?.body {
            print("🔐 [DEBUG] Policy body: \(policyBody.count) bytes - \(policyBody.prefix(50).base64EncodedString())...")
        } else {
            print("🔐 [DEBUG] Policy body: nil")
        }

        // Perform KAS rewrap to get symmetric key
        try await performKASRewrap()
    }

    /// Perform KAS rewrap to obtain the symmetric key for decryption
    /// Uses KASRewrapClient from OpenTDFKit for proper PEM/JWT handling
    private func performKASRewrap() async throws {
        print("🔐 Performing KAS rewrap using OpenTDFKit KASRewrapClient...")

        // Generate client ephemeral key pair (matching OpenTDFKit CLI pattern)
        let privateKey = P256.KeyAgreement.PrivateKey()
        let clientKeyPair = EphemeralKeyPair(
            privateKey: privateKey.rawRepresentation,
            publicKey: privateKey.publicKey.compressedRepresentation,
            curve: .secp256r1
        )

        // Convert to PEM format for KAS request (matching OpenTDFKit CLI)
        let publicKeyPEM = try convertToSPKIPEM(compressedKey: clientKeyPair.publicKey)
        let pemKeyPair = EphemeralKeyPair(
            privateKey: clientKeyPair.privateKey,
            publicKey: publicKeyPEM.data(using: .utf8)!,
            curve: .secp256r1
        )
        print("🔐 Generated client ephemeral key pair with PEM public key")

        do {
            // Use OpenTDFKit's KASRewrapClient for proper request/response handling
            let kasClient = KASRewrapClient(kasURL: kasURL, oauthToken: ntdfToken)

            let (wrappedKey, sessionPublicKey) = try await kasClient.rewrapNanoTDF(
                header: headerBytes,
                parsedHeader: header,
                clientKeyPair: pemKeyPair
            )

            print("🔐 KAS rewrap successful - wrapped key: \(wrappedKey.count) bytes, session key: \(sessionPublicKey.count) bytes")

            // Unwrap the key using OpenTDFKit's unwrapKey (handles HKDF salt correctly)
            let symmetricKey = try KASRewrapClient.unwrapKey(
                wrappedKey: wrappedKey,
                sessionPublicKey: sessionPublicKey,
                clientPrivateKey: clientKeyPair.privateKey
            )

            print("✅ Symmetric key unwrapped: \(symmetricKey.bitCount) bits")

            // Create the OpenTDFKit decryptor with the unwrapped key
            self.decryptor = NanoTDFCollectionDecryptor.withUnwrappedKey(
                symmetricKey: symmetricKey,
                cipher: cipher
            )

            print("✅ Decryptor initialized successfully")

        } catch let error as KASRewrapError {
            print("❌ KAS rewrap failed: \(error.description)")
            throw NTDFSubscriberError.decryptionFailed("KAS rewrap failed: \(error.description)")
        } catch {
            print("❌ KAS rewrap failed: \(error)")
            throw NTDFSubscriberError.decryptionFailed("KAS rewrap failed: \(error.localizedDescription)")
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

    /// Convert compressed P256 public key to PEM format
    /// Note: KAS server expects raw SEC1 bytes (uncompressed point) in PEM wrapper,
    /// NOT standard SPKI format with ASN.1 structure
    private func convertToSPKIPEM(compressedKey: Data) throws -> String {
        guard compressedKey.count == 33 else {
            throw NTDFSubscriberError.decryptionFailed("Invalid compressed key size: \(compressedKey.count), expected 33")
        }

        // Convert compressed to uncompressed using x963Representation (65 bytes)
        // This is raw SEC1 format: 0x04 + X (32 bytes) + Y (32 bytes)
        let tempKey = try P256.KeyAgreement.PublicKey(compressedRepresentation: compressedKey)
        let sec1Bytes = tempKey.x963Representation

        // KAS server expects raw SEC1 bytes in PEM wrapper (non-standard but matching server's format)
        let base64String = sec1Bytes.base64EncodedString(options: [
            .lineLength64Characters,
            .endLineWithLineFeed
        ])

        // Build PEM string with raw SEC1 bytes (matching KAS server's public_key_to_pem output)
        let pemString = "-----BEGIN PUBLIC KEY-----\n\(base64String)-----END PUBLIC KEY-----"
        print("🔐 [DEBUG] Generated SEC1 PEM (\(pemString.count) chars, \(sec1Bytes.count) bytes SEC1)")
        return pemString
    }
}
