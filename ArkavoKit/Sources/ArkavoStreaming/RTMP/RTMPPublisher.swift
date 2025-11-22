import Foundation
import Network
@preconcurrency import AVFoundation
import ArkavoMedia

/// RTMP publisher for live streaming video/audio
///
/// Implements RTMP protocol for publishing live streams to servers like Twitch, YouTube, etc.
/// Supports FLV container format with H.264 video and AAC audio.
public actor RTMPPublisher {

    // MARK: - Types

    public enum State: Sendable, Equatable {
        case disconnected
        case connecting
        case connected
        case publishing
        case error(String)

        public static func == (lhs: State, rhs: State) -> Bool {
            switch (lhs, rhs) {
            case (.disconnected, .disconnected),
                 (.connecting, .connecting),
                 (.connected, .connected),
                 (.publishing, .publishing):
                return true
            case (.error(let lhsMsg), .error(let rhsMsg)):
                return lhsMsg == rhsMsg
            default:
                return false
            }
        }
    }

    public enum RTMPError: Error, LocalizedError {
        case invalidURL
        case connectionFailed(String)
        case handshakeFailed
        case publishFailed(String)
        case notConnected

        public var errorDescription: String? {
            switch self {
            case .invalidURL:
                return "Invalid RTMP URL"
            case .connectionFailed(let reason):
                return "Connection failed: \(reason)"
            case .handshakeFailed:
                return "RTMP handshake failed"
            case .publishFailed(let reason):
                return "Publish failed: \(reason)"
            case .notConnected:
                return "Not connected to RTMP server"
            }
        }
    }

    public struct Destination: Sendable {
        public let url: String  // rtmp://server.com/app/streamkey
        public let platform: String  // "twitch", "youtube", "custom"

        public init(url: String, platform: String) {
            self.url = url
            self.platform = platform
        }
    }

    // MARK: - Properties

    private var connection: NWConnection?
    private var state: State = .disconnected
    private var isHandshakeComplete = false
    private var connectionContinuationResumed = false

    // Stream configuration
    private var destination: Destination?
    private var streamKey: String?
    private var streamId: UInt32 = 1  // Stream ID from createStream response
    private var transactionId: Double = 0  // Transaction counter for invoke commands (incremented before each use)
    private var firstMediaTimestamp: CMTime?  // First media frame timestamp (for normalizing to stream start = 0)

    // Statistics
    private var bytesSent: UInt64 = 0
    private var bytesReceived: UInt64 = 0
    private var framesSent: UInt64 = 0
    private var startTime: Date?
    private var windowAckSize: UInt32 = 2500000  // Our window size (what we tell server)
    private var serverWindowAckSize: UInt32 = 250000  // Server's window size (for our acks) - default 250KB
    private var lastAckSent: UInt64 = 0
    private var lastReceivedMessageType: UInt8 = 0  // Track message type from last received chunk
    private var receiveChunkSize: Int = 128  // Current chunk size for receiving (updated by server's SetChunkSize)
    private var sendChunkSize: Int = 4096  // Our chunk size for sending (set via SetChunkSize message)

    // Background task for handling server messages
    private var serverMessageTask: Task<Void, Never>?

    public var currentState: State {
        state
    }

    public var statistics: StreamStatistics {
        StreamStatistics(
            bytesSent: bytesSent,
            framesSent: framesSent,
            duration: startTime.map { Date().timeIntervalSince($0) } ?? 0,
            bitrate: calculateBitrate()
        )
    }

    public struct StreamStatistics: Sendable {
        public let bytesSent: UInt64
        public let framesSent: UInt64
        public let duration: TimeInterval
        public let bitrate: Double  // bits per second
    }

    // MARK: - Initialization

    public init() {}

    // MARK: - Public Methods

    /// Connect to RTMP server and start publishing
    public func connect(to destination: Destination, streamKey: String) async throws {
        self.destination = destination
        self.streamKey = streamKey

        // Parse RTMP URL
        guard let url = parseRTMPURL(destination.url) else {
            throw RTMPError.invalidURL
        }

        print("📡 Connecting to RTMP: \(url.host):\(url.port)")

        // Create TCP connection
        let host = NWEndpoint.Host(url.host)
        let port = NWEndpoint.Port(integerLiteral: UInt16(url.port))

        connection = NWConnection(host: host, port: port, using: .tcp)

        state = .connecting
        connectionContinuationResumed = false

        // Start connection
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            connection?.stateUpdateHandler = { [weak self] newState in
                Task { [weak self] in
                    await self?.handleConnectionState(newState, continuation: continuation)
                }
            }

            connection?.start(queue: .global(qos: .userInitiated))
        }

        // Perform RTMP handshake
        try await performHandshake()

        // Connect to application
        try await connectToApp(url.app, streamKey: streamKey)

        state = .publishing
        startTime = Date()

        print("✅ RTMP publishing started")
    }

    /// Normalize timestamp to stream start (OBS pattern: first frame = 0ms)
    private func normalizeTimestamp(_ timestamp: CMTime) -> UInt32 {
        // Store first media timestamp as reference point
        if firstMediaTimestamp == nil {
            firstMediaTimestamp = timestamp
            print("📊 First media timestamp: \(timestamp.seconds)s - normalizing to 0ms")
            return 0
        }

        // Calculate relative timestamp in milliseconds
        let relativeTime = timestamp - firstMediaTimestamp!
        let timestampMs = UInt32(max(0, relativeTime.seconds * 1000))
        return timestampMs
    }

    /// Publish video frame
    public func publishVideo(buffer: CMSampleBuffer, timestamp: CMTime) async throws {
        guard state == .publishing else {
            throw RTMPError.notConnected
        }

        // Check if connection is still valid
        guard let connection = connection, connection.state == .ready else {
            throw RTMPError.connectionFailed("Connection not ready")
        }

        // Determine if this is a keyframe
        let attachments = CMSampleBufferGetSampleAttachmentsArray(buffer, createIfNecessary: false) as? [[CFString: Any]]
        let isKeyframe = attachments?.first?[kCMSampleAttachmentKey_NotSync] == nil

        // Create video payload and send via RTMP message
        let payload = try FLVMuxer.createVideoPayload(sampleBuffer: buffer, isKeyframe: isKeyframe)
        let timestampMs = normalizeTimestamp(timestamp)
        try await sendRTMPVideoMessage(data: payload, timestamp: timestampMs)

        framesSent += 1
    }

    /// Publish audio sample
    /// Publish video sequence header (AVC/H.264 configuration - SPS/PPS)
    public func publishVideoSequenceHeader(formatDescription: CMFormatDescription, timestamp: CMTime) async throws {
        guard state == .publishing else {
            throw RTMPError.notConnected
        }

        // Create video sequence header payload
        let payload = try FLVMuxer.createVideoSequenceHeaderPayload(formatDescription: formatDescription)

        // Send as RTMP message (message type 9 = video, chunk stream 6 for video)
        // Sequence headers should always be sent with timestamp 0
        try await sendRTMPVideoMessage(data: payload, timestamp: 0)
        print("✅ Sent video sequence header via RTMP message")
    }

    /// Publish audio sequence header (AAC configuration)
    public func publishAudioSequenceHeader(formatDescription: CMFormatDescription, timestamp: CMTime) async throws {
        guard state == .publishing else {
            throw RTMPError.notConnected
        }

        // Create AAC sequence header payload
        let payload = FLVMuxer.createAudioSequenceHeaderPayload(formatDescription: formatDescription)

        // Send as RTMP message (message type 8 = audio, chunk stream 4 for audio)
        // Sequence headers should always be sent with timestamp 0
        try await sendRTMPAudioMessage(data: payload, timestamp: 0)
        print("✅ Sent audio sequence header via RTMP message")
    }

    public func publishAudio(buffer: CMSampleBuffer, timestamp: CMTime) async throws {
        guard state == .publishing else {
            throw RTMPError.notConnected
        }

        // Check if connection is still valid
        guard let connection = connection, connection.state == .ready else {
            throw RTMPError.connectionFailed("Connection not ready")
        }

        // Create audio payload and send via RTMP message
        let payload = try FLVMuxer.createAudioPayload(sampleBuffer: buffer)
        let timestampMs = normalizeTimestamp(timestamp)
        try await sendRTMPAudioMessage(data: payload, timestamp: timestampMs)
    }

    // MARK: - Simplified API for EncodedFrames

    /// Send encoded video frame
    public func send(video frame: EncodedVideoFrame) async throws {
        guard state == .publishing else {
            throw RTMPError.notConnected
        }

        guard let connection = connection, connection.state == .ready else {
            throw RTMPError.connectionFailed("Connection not ready")
        }

        // Create video payload from encoded frame
        let payload = FLVMuxer.createVideoPayload(from: frame)
        let timestampMs = normalizeTimestamp(frame.pts)
        try await sendRTMPVideoMessage(data: payload, timestamp: timestampMs)

        framesSent += 1
    }

    /// Send encoded audio frame
    public func send(audio frame: EncodedAudioFrame) async throws {
        guard state == .publishing else {
            throw RTMPError.notConnected
        }

        guard let connection = connection, connection.state == .ready else {
            throw RTMPError.connectionFailed("Connection not ready")
        }

        // Create audio payload from encoded frame
        let payload = FLVMuxer.createAudioPayload(from: frame)
        let timestampMs = normalizeTimestamp(frame.pts)
        try await sendRTMPAudioMessage(data: payload, timestamp: timestampMs)
    }

    /// Send video sequence header (SPS/PPS)
    public func sendVideoSequenceHeader(formatDescription: CMVideoFormatDescription) async throws {
        guard state == .publishing else {
            throw RTMPError.notConnected
        }

        // Create video sequence header payload
        let payload = try FLVMuxer.createVideoSequenceHeader(from: formatDescription)

        // Send as RTMP message (timestamp 0 for sequence headers)
        try await sendRTMPVideoMessage(data: payload, timestamp: 0)
        print("✅ Sent video sequence header")
    }

    /// Send audio sequence header (AudioSpecificConfig)
    public func sendAudioSequenceHeader(asc: Data) async throws {
        guard state == .publishing else {
            throw RTMPError.notConnected
        }

        // Create AAC sequence header payload
        let payload = FLVMuxer.createAudioSequenceHeader(asc: asc)

        // Send as RTMP message (timestamp 0 for sequence headers)
        try await sendRTMPAudioMessage(data: payload, timestamp: 0)
        print("✅ Sent audio sequence header")
    }

    /// Disconnect from server
    public func disconnect() async {
        print("📡 Disconnecting RTMP...")

        // Cancel background server message handler
        if let task = serverMessageTask {
            print("🛑 Cancelling background server message handler task...")
            task.cancel()
            serverMessageTask = nil
        }

        connection?.cancel()
        connection = nil
        state = .disconnected
        isHandshakeComplete = false
        bytesSent = 0
        framesSent = 0
        startTime = nil
        firstMediaTimestamp = nil  // Reset timestamp normalization for next stream
    }

    // MARK: - Private Methods

    private struct RTMPURL {
        let host: String
        let port: Int
        let app: String
    }

    private func parseRTMPURL(_ urlString: String) -> RTMPURL? {
        // Parse rtmp://server:port/app/streamkey
        guard let url = URL(string: urlString) else { return nil }
        guard url.scheme == "rtmp" || url.scheme == "rtmps" else { return nil }

        let host = url.host ?? ""
        let port = url.port ?? 1935
        let pathComponents = url.pathComponents.filter { $0 != "/" }
        let app = pathComponents.first ?? "live"

        return RTMPURL(host: host, port: port, app: app)
    }

    private func handleConnectionState(_ newState: NWConnection.State, continuation: CheckedContinuation<Void, Error>) {
        // Only resume the continuation once
        guard !connectionContinuationResumed else {
            print("⚠️ Connection state changed to \(newState) but continuation already resumed")
            return
        }

        switch newState {
        case .ready:
            print("✅ TCP connection established")
            state = .connected
            connectionContinuationResumed = true
            continuation.resume()
        case .failed(let error):
            print("❌ Connection failed: \(error)")
            let errorMsg = error.localizedDescription
            state = .error(errorMsg)
            connectionContinuationResumed = true
            continuation.resume(throwing: RTMPError.connectionFailed(errorMsg))
        case .waiting(let error):
            print("⏳ Connection waiting: \(error)")
        case .cancelled:
            print("🚫 Connection cancelled")
            connectionContinuationResumed = true
            continuation.resume(throwing: RTMPError.connectionFailed("Cancelled"))
        default:
            break
        }
    }

    private func performHandshake() async throws {
        print("🤝 Performing RTMP handshake...")

        // C0: Version byte (0x03)
        let c0 = Data([0x03])

        // C1: 1536 bytes (timestamp + zeros + random)
        var c1 = Data(count: 1536)
        c1.replaceSubrange(0..<4, with: UInt32(0).bigEndianBytes)  // timestamp
        c1.replaceSubrange(4..<8, with: UInt32(0).bigEndianBytes)  // zero
        // Rest is random data
        for i in 8..<1536 {
            c1[i] = UInt8.random(in: 0...255)
        }

        // Send C0 + C1
        try await sendData(c0 + c1)

        // Receive S0 + S1 + S2 (must receive all 3073 bytes)
        let responseLength = 1 + 1536 + 1536
        guard let response = try await receiveDataExact(length: responseLength),
              response.count == responseLength else {
            throw RTMPError.handshakeFailed
        }

        print("✅ Received handshake response: \(response.count) bytes")

        // Validate S0
        guard response[0] == 0x03 else {
            throw RTMPError.handshakeFailed
        }

        // Send C2 (echo of S1)
        let s1 = response.subdata(in: 1..<1537)
        try await sendData(s1)

        isHandshakeComplete = true
        print("✅ RTMP handshake complete")
    }

    private func connectToApp(_ app: String, streamKey: String) async throws {
        print("📡 Connecting to app: \(app)")

        guard let destination = destination else {
            throw RTMPError.notConnected
        }

        // Send SetChunkSize message (set to 4096 bytes)
        var chunkSizeData = Data()
        let newChunkSize: UInt32 = 4096
        chunkSizeData.append(contentsOf: newChunkSize.bigEndianBytes)

        try await sendRTMPMessage(
            chunkStreamId: 2,
            messageTypeId: 1,  // Set Chunk Size
            messageStreamId: 0,
            payload: chunkSizeData
        )
        print("✅ Sent SetChunkSize: \(newChunkSize)")

        // Send Window Acknowledgement Size to inform server of our window size
        var windowAckData = Data()
        let clientWindowSize: UInt32 = 2500000  // 2.5MB window
        windowAckData.append(contentsOf: clientWindowSize.bigEndianBytes)

        try await sendRTMPMessage(
            chunkStreamId: 2,
            messageTypeId: 5,  // Window Acknowledgement Size
            messageStreamId: 0,
            payload: windowAckData
        )
        print("✅ Sent Window Acknowledgement Size: \(clientWindowSize)")

        // Reset transaction counter for new connection
        transactionId = 0

        // Create RTMP connect command (transaction ID 1)
        transactionId += 1  // = 1
        let tcUrl = "rtmp://\(destination.url.split(separator: "/").prefix(3).joined(separator: "/"))"
        let connectCommand = AMF0.createConnectCommand(
            app: app,
            tcUrl: tcUrl
        )

        // Send connect command (wrapped in RTMP chunk)
        print("📤 Sending connect command (txnId=\(transactionId)): \(connectCommand.count) bytes")
        try await sendRTMPMessage(
            chunkStreamId: 3,
            messageTypeId: 20,  // AMF0 command
            messageStreamId: 0,
            payload: connectCommand
        )

        print("✅ Connect command sent")

        // Wait for connect response (_result or _error)
        print("⏳ Waiting for connect response...")
        let (connectResponseData, connectResponseBytes) = try await receiveRTMPChunk()
        bytesReceived += UInt64(connectResponseBytes)
        print("✅ Received connect response")

        // Release stream (transaction ID 2)
        transactionId += 1  // = 2
        let releaseStreamCommand = AMF0.createReleaseStreamCommand(streamName: streamKey, transactionId: transactionId)
        print("📤 Sending releaseStream command (txnId=\(transactionId))")
        try await sendRTMPMessage(
            chunkStreamId: 3,
            messageTypeId: 20,
            messageStreamId: 0,
            payload: releaseStreamCommand
        )

        // FCPublish (transaction ID 3)
        transactionId += 1  // = 3
        let fcPublishCommand = AMF0.createFCPublishCommand(streamName: streamKey, transactionId: transactionId)
        print("📤 Sending FCPublish command (txnId=\(transactionId))")
        try await sendRTMPMessage(
            chunkStreamId: 3,
            messageTypeId: 20,
            messageStreamId: 0,
            payload: fcPublishCommand
        )

        // CreateStream (transaction ID 4)
        transactionId += 1  // = 4
        let createStreamCommand = AMF0.createCreateStreamCommand(transactionId: transactionId)
        print("📤 Sending createStream command (txnId=\(transactionId))")
        try await sendRTMPMessage(
            chunkStreamId: 3,
            messageTypeId: 20,
            messageStreamId: 0,
            payload: createStreamCommand
        )

        print("✅ CreateStream command sent, waiting for stream ID...")

        // Wait for createStream _result response (might receive other messages first)
        var receivedStreamId = false
        responseLoop: for _ in 0..<10 {  // Try up to 10 messages
            let (messageType, messageData, messageBytes) = try await receiveRTMPMessage()
            bytesReceived += UInt64(messageBytes)

            // Process control messages even while waiting for createStream response
            switch messageType {
            case 1:  // Set Chunk Size - CRITICAL to process immediately!
                if messageData.count >= 4 {
                    let chunkSize = UInt32(messageData[0]) << 24 | UInt32(messageData[1]) << 16 |
                                   UInt32(messageData[2]) << 8 | UInt32(messageData[3])
                    receiveChunkSize = Int(chunkSize)
                    print("📥 Server Set Chunk Size: \(chunkSize) (processed during createStream wait)")
                }
                continue

            case 4:  // User Control
                try await handleUserControlMessage(messageData)
                continue

            case 5:  // Window Acknowledgement Size
                if messageData.count >= 4 {
                    serverWindowAckSize = UInt32(messageData[0]) << 24 | UInt32(messageData[1]) << 16 |
                                         UInt32(messageData[2]) << 8 | UInt32(messageData[3])
                    print("📥 Server Window Ack Size: \(serverWindowAckSize) (processed during createStream wait)")
                }
                continue

            case 6:  // Set Peer Bandwidth
                print("📥 Server Set Peer Bandwidth (processed during createStream wait)")
                continue

            case 20:  // AMF0 Command
                // Check if this is a _result message for createStream (transaction ID 4)
                if let parsedStreamId = try? parseCreateStreamResponse(messageData) {
                    streamId = parsedStreamId
                    print("✅ Received stream ID from _result: \(streamId)")
                    receivedStreamId = true
                    break responseLoop  // Exit the for loop, not just the switch
                }
                print("📥 Skipping AMF message (not createStream _result)")

            default:
                print("📥 Skipping message type \(messageType) while waiting for createStream response")
            }
        }

        if !receivedStreamId {
            print("⚠️ Could not parse stream ID from _result, using default: \(streamId)")
        }

        // Send publish command to start streaming (transaction ID 5)
        transactionId += 1  // = 5
        print("📤 Preparing to send publish command with streamKey=\(streamKey) streamId=\(streamId) txnId=\(transactionId)")
        let publishCommand = AMF0.createPublishCommand(
            streamName: streamKey,
            publishingName: "live",
            transactionId: transactionId
        )
        print("📤 Publish command created, payload size: \(publishCommand.count) bytes")
        try await sendRTMPMessage(
            chunkStreamId: 4,  // OBS uses 0x04 for publish (source channel), not 0x03
            messageTypeId: 20,
            messageStreamId: streamId,
            payload: publishCommand
        )

        print("✅ Publish command sent (txnId=\(transactionId)), stream is now live!")

        // Wait for publish success status (NetStream.Publish.Start)
        let (publishStatusData, publishStatusBytes) = try await receiveRTMPChunk()
        bytesReceived += UInt64(publishStatusBytes)
        print("✅ Received publish status")

        // Start background task to read server messages (acknowledgements, bandwidth notifications, pings, etc.)
        print("🚀 Starting background server message handler task...")
        serverMessageTask = Task {
            await handleServerMessages()
        }
        print("✅ Background server message handler task started")

        print("✅ App connection complete, ready to stream")
    }

    /// Handle incoming server messages during streaming
    private func handleServerMessages() async {
        print("📥 Background message handler STARTED - will listen for server messages (pings, acks, etc.)")
        var iterationCount = 0

        while state == .publishing {
            iterationCount += 1

            // Log every 50 iterations (~5 seconds) to show handler is alive
            if iterationCount % 50 == 0 {
                print("📥 Background handler alive: iteration \(iterationCount), state=\(state), bytesReceived=\(bytesReceived)")
            }

            do {
                // Try to receive a message (non-blocking - returns nil if no data available)
                if let (messageType, messageData, messageBytes) = try await receiveRTMPMessageNonBlocking() {
                    // Got a message! Process it
                    bytesReceived += UInt64(messageBytes)

                    print("📥 Server message: type=\(messageType) payloadLen=\(messageData.count) totalBytes=\(messageBytes) totalReceived=\(bytesReceived)")

                    // Handle specific message types
                    switch messageType {
                    case 1: // Set Chunk Size
                        if messageData.count >= 4 {
                            let chunkSize = UInt32(messageData[0]) << 24 | UInt32(messageData[1]) << 16 |
                                           UInt32(messageData[2]) << 8 | UInt32(messageData[3])
                            receiveChunkSize = Int(chunkSize)
                            print("📥 Server Set Chunk Size: \(chunkSize) - Updated receive chunk size")
                        }

                    case 3: // Acknowledgement
                        print("📥 Server sent Acknowledgement")

                    case 4: // User Control Message (ping, pong, stream begin, etc.)
                        try await handleUserControlMessage(messageData)

                    case 5: // Window Acknowledgement Size
                        if messageData.count >= 4 {
                            serverWindowAckSize = UInt32(messageData[0]) << 24 | UInt32(messageData[1]) << 16 |
                                                 UInt32(messageData[2]) << 8 | UInt32(messageData[3])
                            print("📥 Server Window Ack Size: \(serverWindowAckSize) - This is the window we should use for sending acks")
                        }

                    case 6: // Set Peer Bandwidth
                        if messageData.count >= 4 {
                            let bandwidth = UInt32(messageData[0]) << 24 | UInt32(messageData[1]) << 16 |
                                           UInt32(messageData[2]) << 8 | UInt32(messageData[3])
                            print("📥 Server Set Peer Bandwidth: \(bandwidth)")
                        }

                    case 20: // AMF0 Command (onStatus, etc.)
                        handleAMFCommand(messageData)

                    default:
                        print("📥 Unhandled message type: \(messageType)")
                    }

                    // Send acknowledgement if we've received enough data
                    // OBS sends every window_size/10 bytes (not every full window)
                    let ackThreshold = UInt64(serverWindowAckSize) / 10
                    if bytesReceived - lastAckSent >= ackThreshold {
                        try await sendWindowAcknowledgement(bytesReceived: UInt32(bytesReceived))
                        lastAckSent = bytesReceived
                        print("✅ Sent Acknowledgement: \(bytesReceived) bytes (threshold: \(ackThreshold), window: \(serverWindowAckSize))")
                    }
                }
                // If no message was available, that's normal - we'll check again after sleeping

            } catch {
                // If we get an error, the connection might be closed
                let errorMsg = error.localizedDescription
                print("📥 ❌ Error reading server message: \(errorMsg)")

                if errorMsg.contains("Connection closed") ||
                   errorMsg.contains("Connection reset") ||
                   errorMsg.contains("No message available") {
                    print("⚠️ Server connection closed, exiting background handler")
                    break
                }
                // For other errors, log but continue (will retry after sleep)
                print("📥 Non-fatal error, will retry after sleep")
            }

            // Always yield control and sleep between iterations
            // This prevents busy-waiting and gives other tasks a chance to run
            try? await Task.sleep(nanoseconds: 100_000_000) // 100ms between polls
        }

        print("📥 Background message handler STOPPED (final state=\(state), iterations=\(iterationCount))")
    }

    /// Handle AMF0 command messages (onStatus, etc.)
    private func handleAMFCommand(_ data: Data) {
        // AMF0 is a binary format, but we can extract strings from it
        // For debugging, dump the hex and try to extract readable strings
        let hexString = data.prefix(64).map { String(format: "%02x", $0) }.joined(separator: " ")
        print("📥 AMF0 command (first 64 bytes): \(hexString)")

        // Try to extract any readable strings from the binary data
        var strings: [String] = []
        var i = 0
        while i < data.count {
            // AMF0 string format: 0x02 (string marker) + 2 bytes length + string data
            if data[i] == 0x02 && i + 2 < data.count {
                let length = Int(data[i+1]) << 8 | Int(data[i+2])
                if length > 0 && i + 3 + length <= data.count {
                    if let str = String(data: data[(i+3)..<(i+3+length)], encoding: .utf8) {
                        strings.append(str)
                        print("📥 AMF0 string found: '\(str)'")
                    }
                    i += 3 + length
                    continue
                }
            }
            i += 1
        }

        // Check for specific status messages
        let combinedStr = strings.joined(separator: " ")
        if combinedStr.contains("onStatus") {
            print("📥 onStatus message received")

            if combinedStr.contains("error") {
                print("❌ onStatus: ERROR level detected")
            }
            if combinedStr.contains("NetStream.Publish.Denied") {
                print("❌ NetStream.Publish.Denied - Stream rejected!")
            }
            if combinedStr.contains("NetStream.Publish.Start") {
                print("✅ NetStream.Publish.Start - Stream started")
            }
            if combinedStr.contains("NetConnection.Connect.Success") {
                print("✅ NetConnection.Connect.Success - Connection accepted")
            }
        }
    }

    /// Handle User Control Messages (type 4)
    /// Format: 2 bytes event type + event data
    private func handleUserControlMessage(_ data: Data) async throws {
        guard data.count >= 2 else {
            print("📥 Invalid User Control Message: too short")
            return
        }

        let eventType = UInt16(data[0]) << 8 | UInt16(data[1])

        switch eventType {
        case 0: // Stream Begin
            if data.count >= 6 {
                let streamId = UInt32(data[2]) << 24 | UInt32(data[3]) << 16 |
                              UInt32(data[4]) << 8 | UInt32(data[5])
                print("📥 User Control: Stream Begin (stream ID: \(streamId))")
            }

        case 1: // Stream EOF
            print("📥 User Control: Stream EOF")

        case 2: // Stream Dry
            print("📥 User Control: Stream Dry")

        case 3: // SetBufferLength
            if data.count >= 10 {
                let streamId = UInt32(data[2]) << 24 | UInt32(data[3]) << 16 |
                              UInt32(data[4]) << 8 | UInt32(data[5])
                let bufferLength = UInt32(data[6]) << 24 | UInt32(data[7]) << 16 |
                                  UInt32(data[8]) << 8 | UInt32(data[9])
                print("📥 User Control: SetBufferLength (stream: \(streamId), buffer: \(bufferLength)ms)")
            }

        case 6: // Ping Request
            if data.count >= 6 {
                let timestamp = UInt32(data[2]) << 24 | UInt32(data[3]) << 16 |
                               UInt32(data[4]) << 8 | UInt32(data[5])
                print("🏓 📥 PING REQUEST from server (timestamp: \(timestamp)) - sending Pong response...")
                // Send Pong Response
                try await sendPongResponse(timestamp: timestamp)
                print("🏓 ✅ Pong response sent successfully")
            }

        case 7: // Ping Response (Pong)
            if data.count >= 6 {
                let timestamp = UInt32(data[2]) << 24 | UInt32(data[3]) << 16 |
                               UInt32(data[4]) << 8 | UInt32(data[5])
                print("📥 User Control: Pong Response (timestamp: \(timestamp))")
            }

        default:
            print("📥 User Control: Unknown event type \(eventType)")
        }
    }

    /// Send Pong Response to server's Ping Request
    private func sendPongResponse(timestamp: UInt32) async throws {
        var pongData = Data()
        // Event type 7 (Pong Response)
        pongData.append(contentsOf: [0x00, 0x07])
        // Echo back the timestamp
        pongData.append(contentsOf: timestamp.bigEndianBytes)

        print("🏓 📤 Sending Pong Response: eventType=7, timestamp=\(timestamp), payload=\(pongData.map { String(format: "%02x", $0) }.joined(separator: " "))")

        try await sendRTMPMessage(
            chunkStreamId: 2,
            messageTypeId: 4,  // User Control Message
            messageStreamId: 0,
            payload: pongData
        )

        print("🏓 ✅ Pong Response sent successfully to server (timestamp: \(timestamp))")
    }

    /// Send Window Acknowledgement message to server
    private func sendWindowAcknowledgement(bytesReceived: UInt32) async throws {
        var ackData = Data()
        ackData.append(contentsOf: bytesReceived.bigEndianBytes)

        try await sendRTMPMessage(
            chunkStreamId: 2,
            messageTypeId: 3,  // Acknowledgement (bytes received report)
            messageStreamId: 0,
            payload: ackData
        )
        print("✅ Sent Window Acknowledgement: \(bytesReceived) bytes")
    }

    /// Send RTMP chunk message
    private func sendRTMPMessage(
        chunkStreamId: UInt8,
        messageTypeId: UInt8,
        messageStreamId: UInt32,
        payload: Data,
        timestamp: UInt32 = 0
    ) async throws {
        let messageLength = UInt32(payload.count)

        // Build Type 0 header (full header with all fields)
        var header = Data()

        // Basic header (1 byte): Format bits (00 for Type 0) + chunk stream ID
        header.append(chunkStreamId & 0x3F)

        // Message header (11 bytes for Type 0)
        // Timestamp (3 bytes)
        header.append(UInt8((timestamp >> 16) & 0xFF))
        header.append(UInt8((timestamp >> 8) & 0xFF))
        header.append(UInt8(timestamp & 0xFF))

        // Message length (3 bytes)
        header.append(UInt8((messageLength >> 16) & 0xFF))
        header.append(UInt8((messageLength >> 8) & 0xFF))
        header.append(UInt8(messageLength & 0xFF))

        // Message type ID (1 byte)
        header.append(messageTypeId)

        // Message stream ID (4 bytes, little endian)
        var streamId = messageStreamId.littleEndian
        header.append(Data(bytes: &streamId, count: 4))

        // Split payload into chunks and send
        var offset = 0
        var chunkCount = 0

        while offset < payload.count {
            let remaining = payload.count - offset
            let chunkSize = min(remaining, sendChunkSize)

            var chunk = Data()
            let fmt: UInt8

            if chunkCount == 0 {
                // First chunk: Type 0 header + data
                fmt = 0
                chunk.append(header)
                chunk.append(payload[offset..<(offset + chunkSize)])
            } else {
                // Continuation chunks: Type 3 header (1 byte) + data
                // Type 3: Format bits 11 (0xC0) + chunk stream ID
                fmt = 3
                chunk.append(0xC0 | (chunkStreamId & 0x3F))
                chunk.append(payload[offset..<(offset + chunkSize)])
            }

            // Detailed logging for large multi-chunk messages
            if payload.count > sendChunkSize {
                print("📤 Chunk[\(chunkCount)]: fmt=\(fmt) csid=\(chunkStreamId) dataLen=\(chunkSize) offset=\(offset) totalPayload=\(payload.count)")
            }

            try await sendData(chunk)

            offset += chunkSize
            chunkCount += 1
        }

        if chunkCount > 1 {
            print("📤 RTMP message chunked: type=\(messageTypeId) csid=\(chunkStreamId) ts=\(timestamp) payloadLen=\(payload.count) chunks=\(chunkCount) chunkSize=\(sendChunkSize)")
        } else {
            print("📤 RTMP message: type=\(messageTypeId) csid=\(chunkStreamId) ts=\(timestamp) payloadLen=\(payload.count)")
        }
    }

    /// Send video data as RTMP message (type 9)
    private func sendRTMPVideoMessage(data: Data, timestamp: UInt32) async throws {
        try await sendRTMPMessage(
            chunkStreamId: 6,  // Video chunk stream (must be different from audio)
            messageTypeId: 9,  // Video message
            messageStreamId: streamId,
            payload: data,
            timestamp: timestamp
        )
    }

    /// Send audio data as RTMP message (type 8)
    private func sendRTMPAudioMessage(data: Data, timestamp: UInt32) async throws {
        try await sendRTMPMessage(
            chunkStreamId: 4,  // Audio chunk stream (must be different from video)
            messageTypeId: 8,  // Audio message
            messageStreamId: streamId,
            payload: data,
            timestamp: timestamp
        )
    }

    /// Send raw data packet to RTMP stream
    private func sendData(_ data: Data) async throws {
        guard let connection = connection else {
            state = .error("Connection lost")
            throw RTMPError.notConnected
        }

        // Check connection state before sending
        guard connection.state == .ready else {
            state = .error("Connection not ready")
            throw RTMPError.connectionFailed("Connection state: \(connection.state)")
        }

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            connection.send(content: data, completion: .contentProcessed { [weak self] error in
                if let error = error {
                    Task { [weak self] in
                        await self?.handleSendError(error)
                    }
                    continuation.resume(throwing: RTMPError.connectionFailed(error.localizedDescription))
                } else {
                    Task { [weak self] in
                        await self?.updateBytesSent(UInt64(data.count))
                    }
                    continuation.resume()
                }
            })
        }
    }

    private func handleSendError(_ error: Error) {
        state = .error("Send failed: \(error.localizedDescription)")
        print("❌ RTMP send error: \(error)")
    }

    /// Receive RTMP message and return (messageType, payload, totalBytes)
    private func receiveRTMPMessage() async throws -> (UInt8, Data, Int) {
        let (payload, totalBytes) = try await receiveRTMPChunk()
        // We need to extract message type from the last received chunk
        // The message type is stored during receiveRTMPChunk parsing
        return (lastReceivedMessageType, payload, totalBytes)
    }

    /// Non-blocking variant of receiveRTMPMessage that returns nil if no data is available
    /// Used by background message handler to avoid blocking when server isn't sending messages
    private func receiveRTMPMessageNonBlocking() async throws -> (UInt8, Data, Int)? {
        // Try to peek if any data is available (just 1 byte to check)
        guard let peekData = try await receiveDataNonBlocking(length: 1), peekData.count > 0 else {
            // No data available - return nil (not an error)
            return nil
        }

        // Data is available! Now we need to parse the full chunk
        // Unfortunately we can't "un-read" the peeked byte, so we need a different approach
        // Instead, we'll use the fact that receiveDataNonBlocking returns immediately if data exists

        // Parse the chunk basic header from the peeked byte
        let firstByte = peekData[0]
        let format = (firstByte >> 6) & 0x03

        // Read message header based on format type
        var headerSize = 0
        switch format {
        case 0: headerSize = 11  // Type 0: Full header
        case 1: headerSize = 7   // Type 1: No message stream ID
        case 2: headerSize = 3   // Type 2: Only timestamp delta
        case 3: headerSize = 0   // Type 3: No header
        default: break
        }

        // We've already read 1 byte (basic header), now read the rest
        // Since we know data is available, use the regular blocking receive for the rest
        // This is safe because we've confirmed the message has started
        let (payload, totalBytes) = try await receiveRTMPChunk()
        return (lastReceivedMessageType, payload, totalBytes)
    }

    /// Receive and parse an RTMP chunk from the server
    /// Returns (payload, totalBytesRead) where totalBytesRead includes all headers
    private func receiveRTMPChunk() async throws -> (Data, Int) {
        // Track total bytes for acknowledgements (includes headers + payload)
        var totalBytesRead = 0

        // Read chunk basic header (1 byte minimum)
        print("📥 Waiting to receive RTMP chunk...")
        guard let basicHeaderData = try await receiveDataExact(length: 1), basicHeaderData.count > 0 else {
            throw RTMPError.connectionFailed("Failed to receive chunk basic header")
        }
        totalBytesRead += 1

        let firstByte = basicHeaderData[0]
        let format = (firstByte >> 6) & 0x03
        let chunkStreamId = firstByte & 0x3F
        print("📥 Chunk header: format=\(format) csid=\(chunkStreamId)")

        // Read message header based on format type
        var headerSize = 0
        switch format {
        case 0: headerSize = 11  // Type 0: Full header
        case 1: headerSize = 7   // Type 1: No message stream ID
        case 2: headerSize = 3   // Type 2: Only timestamp delta
        case 3: headerSize = 0   // Type 3: No header
        default: break
        }

        var messageHeader = Data()
        if headerSize > 0 {
            guard let header = try await receiveDataExact(length: headerSize), header.count == headerSize else {
                throw RTMPError.connectionFailed("Failed to receive message header")
            }
            messageHeader = header
            totalBytesRead += headerSize
        }

        // Parse message length and type from header (for type 0 and 1)
        var messageLength = 128  // Default chunk size
        if format == 0 || format == 1 {
            if messageHeader.count >= 6 {
                messageLength = Int(messageHeader[3]) << 16 | Int(messageHeader[4]) << 8 | Int(messageHeader[5])
            }
            // For type 0, message type ID is at byte 6
            if format == 0 && messageHeader.count >= 7 {
                lastReceivedMessageType = messageHeader[6]
            }
        }

        // Read the payload in chunks (use current receive chunk size set by server)
        var payload = Data()
        var remaining = messageLength

        print("📥 Reading payload: messageLength=\(messageLength) chunkSize=\(receiveChunkSize)")

        while remaining > 0 {
            let toRead = min(remaining, receiveChunkSize)
            guard let chunk = try await receiveDataExact(length: toRead), chunk.count > 0 else {
                throw RTMPError.connectionFailed("Failed to receive chunk payload")
            }
            payload.append(chunk)
            remaining -= chunk.count
            totalBytesRead += chunk.count

            // If more chunks needed, read type 3 header (1 byte)
            if remaining > 0 {
                _ = try await receiveDataExact(length: 1)
                totalBytesRead += 1
            }
        }

        print("📥 Received complete chunk: \(payload.count) bytes (total with headers: \(totalBytesRead) bytes)")
        return (payload, totalBytesRead)
    }

    /// Receive exact amount of data, accumulating until we have it all
    private func receiveDataExact(length: Int) async throws -> Data? {
        var accumulated = Data()
        var remaining = length

        while remaining > 0 {
            guard let chunk = try await receiveData(length: remaining) else {
                if accumulated.isEmpty {
                    return nil
                }
                break
            }

            accumulated.append(chunk)
            remaining -= chunk.count

            if chunk.isEmpty {
                // No more data available
                break
            }
        }

        return accumulated.isEmpty ? nil : accumulated
    }

    /// Parse the createStream response to extract stream ID
    /// Format: "_result", transaction ID (4.0), info object, stream ID
    private func parseCreateStreamResponse(_ data: Data) throws -> UInt32 {
        guard data.count > 10 else {
            throw RTMPError.publishFailed("Response too short")
        }

        var offset = 0

        // Verify this is "_result"
        guard data[offset] == 0x02 else {
            throw RTMPError.publishFailed("Not a string command")
        }
        offset += 1
        let nameLen = Int(data[offset]) << 8 | Int(data[offset + 1])
        offset += 2
        guard nameLen == 7,
              offset + nameLen <= data.count,
              String(data: data[offset..<(offset + nameLen)], encoding: .utf8) == "_result" else {
            throw RTMPError.publishFailed("Not _result")
        }
        offset += nameLen

        // Read transaction ID - should be 4.0 for createStream (after connect=1, releaseStream=2, FCPublish=3)
        guard offset + 9 <= data.count, data[offset] == 0x00 else {
            throw RTMPError.publishFailed("No transaction ID")
        }
        offset += 1
        var txnIdBits: UInt64 = 0
        for i in 0..<8 {
            txnIdBits = (txnIdBits << 8) | UInt64(data[offset + i])
        }
        let txnId = Double(bitPattern: txnIdBits)
        offset += 8

        // Verify transaction ID is 4.0 (createStream)
        guard txnId == 4.0 else {
            throw RTMPError.publishFailed("Wrong transaction ID: \(txnId), expected 4.0")
        }

        // Skip command object (could be null 0x05 or object 0x03)
        guard offset < data.count else {
            throw RTMPError.publishFailed("No command object")
        }

        if data[offset] == 0x05 {  // Null
            offset += 1
        } else if data[offset] == 0x03 {  // Object
            offset += 1
            // Skip object properties until we hit object end marker (0x00 0x00 0x09)
            while offset + 2 < data.count {
                // Check for object end marker
                if data[offset] == 0x00 && data[offset + 1] == 0x00 && data[offset + 2] == 0x09 {
                    offset += 3
                    break
                }
                // Skip property name (2 bytes length + string)
                let propNameLen = Int(data[offset]) << 8 | Int(data[offset + 1])
                offset += 2 + propNameLen
                // Skip property value (need to parse type)
                guard offset < data.count else { break }
                let valueType = data[offset]
                offset += 1
                switch valueType {
                case 0x00:  // Number
                    offset += 8
                case 0x01:  // Boolean
                    offset += 1
                case 0x02:  // String
                    if offset + 2 <= data.count {
                        let strLen = Int(data[offset]) << 8 | Int(data[offset + 1])
                        offset += 2 + strLen
                    }
                default:
                    break  // Stop if unknown type
                }
            }
        }

        // Read stream ID number
        guard offset + 9 <= data.count, data[offset] == 0x00 else {
            throw RTMPError.publishFailed("No stream ID at offset \(offset)")
        }
        offset += 1
        var streamIdBits: UInt64 = 0
        for i in 0..<8 {
            streamIdBits = (streamIdBits << 8) | UInt64(data[offset + i])
        }
        let streamIdValue = Double(bitPattern: streamIdBits)
        let streamId = UInt32(streamIdValue)
        print("✅ Parsed stream ID: \(streamId) (transaction ID: \(txnId))")
        return streamId
    }

    private func receiveData(length: Int) async throws -> Data? {
        guard let connection = connection else {
            throw RTMPError.notConnected
        }

        return try await withCheckedThrowingContinuation { continuation in
            // Use minimumIncompleteLength of 1 to start receiving as soon as any data arrives
            // Then accumulate until we have the full length
            connection.receive(minimumIncompleteLength: 1, maximumLength: length) { data, _, isComplete, error in
                if let error = error {
                    print("❌ Receive error: \(error.localizedDescription)")
                    continuation.resume(throwing: RTMPError.connectionFailed(error.localizedDescription))
                    return
                }

                if let data = data {
                    print("📥 Received \(data.count) bytes (requested \(length))")
                    // If we got some data but not enough, we need to read more
                    if data.count < length {
                        // For now, just return what we got - the caller will need to read more
                        // This is a limitation of the current architecture
                        continuation.resume(returning: data)
                    } else {
                        continuation.resume(returning: data)
                    }
                } else if isComplete {
                    print("❌ Connection closed by server (isComplete=true, no data)")
                    continuation.resume(throwing: RTMPError.connectionFailed("Connection closed"))
                } else {
                    print("⚠️ No data available (isComplete=false)")
                    continuation.resume(returning: nil)
                }
            }
        }
    }

    /// Non-blocking variant of receiveData that returns immediately if no data is available
    /// Uses minimumIncompleteLength: 0 to allow immediate return
    private func receiveDataNonBlocking(length: Int) async throws -> Data? {
        guard let connection = connection else {
            throw RTMPError.notConnected
        }

        return try await withCheckedThrowingContinuation { continuation in
            var resumed = false

            // Use minimumIncompleteLength: 0 to return IMMEDIATELY if no data is ready
            // This prevents blocking when server isn't sending anything
            connection.receive(minimumIncompleteLength: 0, maximumLength: length) { data, _, isComplete, error in
                guard !resumed else { return }
                resumed = true

                if let error = error {
                    continuation.resume(throwing: RTMPError.connectionFailed(error.localizedDescription))
                    return
                }

                if let data = data, data.count > 0 {
                    // Got some data - return it
                    continuation.resume(returning: data)
                } else if isComplete {
                    // Connection closed
                    continuation.resume(throwing: RTMPError.connectionFailed("Connection closed"))
                } else {
                    // No data available right now - return nil (not an error)
                    continuation.resume(returning: nil)
                }
            }
        }
    }

    private func updateBytesSent(_ bytes: UInt64) {
        bytesSent += bytes
    }

    private func calculateBitrate() -> Double {
        guard let startTime = startTime else { return 0 }
        let duration = Date().timeIntervalSince(startTime)
        guard duration > 0 else { return 0 }
        return Double(bytesSent * 8) / duration  // bits per second
    }

    /// Execute an async operation with a timeout
    private func withTimeout<T: Sendable>(seconds: TimeInterval, operation: @escaping @Sendable () async throws -> T) async throws -> T? {
        return try await withThrowingTaskGroup(of: T?.self) { group in
            group.addTask {
                try await operation()
            }
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                return nil
            }
            let result = try await group.next()
            group.cancelAll()
            return result ?? nil
        }
    }
}
