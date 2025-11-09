import Foundation

/// Network-safe payload describing remote camera frames or metadata updates.
public struct RemoteCameraMessage: Codable, Sendable {
    public enum Kind: String, Codable, Sendable {
        case frame
        case metadata
        case handshake
    }

    public struct FramePayload: Codable, Sendable {
        public let sourceID: String
        public let timestamp: TimeInterval
        public let width: Int
        public let height: Int
        public let imageData: Data

        public init(sourceID: String, timestamp: TimeInterval, width: Int, height: Int, imageData: Data) {
            self.sourceID = sourceID
            self.timestamp = timestamp
            self.width = width
            self.height = height
            self.imageData = imageData
        }
    }

    public struct HandshakePayload: Codable, Sendable {
        public let sourceID: String
        public let deviceName: String

        public init(sourceID: String, deviceName: String) {
            self.sourceID = sourceID
            self.deviceName = deviceName
        }
    }

    public let kind: Kind
    public let frame: FramePayload?
    public let metadata: CameraMetadataEvent?
    public let handshake: HandshakePayload?

    public init(kind: Kind, frame: FramePayload? = nil, metadata: CameraMetadataEvent? = nil, handshake: HandshakePayload? = nil) {
        self.kind = kind
        self.frame = frame
        self.metadata = metadata
        self.handshake = handshake
    }

    public static func frame(_ payload: FramePayload) -> RemoteCameraMessage {
        RemoteCameraMessage(kind: .frame, frame: payload)
    }

    public static func metadata(_ event: CameraMetadataEvent) -> RemoteCameraMessage {
        RemoteCameraMessage(kind: .metadata, metadata: event)
    }

    public static func handshake(sourceID: String, deviceName: String) -> RemoteCameraMessage {
        RemoteCameraMessage(kind: .handshake, handshake: HandshakePayload(sourceID: sourceID, deviceName: deviceName))
    }
}
