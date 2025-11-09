import XCTest
@testable import ArkavoRecorderShared

final class ArkavoRecorderSharedTests: XCTestCase {
    func testCameraMetadataEncoding() throws {
        let blendShapes: [String: Float] = ["jawOpen": 0.5, "mouthSmile": 0.75]
        let faceMetadata = ARFaceMetadata(blendShapes: blendShapes, trackingState: .normal)
        let metadata = CameraMetadata.arFace(faceMetadata)

        let encoder = JSONEncoder()
        let data = try encoder.encode(metadata)

        let decoder = JSONDecoder()
        let decoded = try decoder.decode(CameraMetadata.self, from: data)

        if case let .arFace(decodedFace) = decoded {
            XCTAssertEqual(decodedFace.blendShapes, blendShapes)
            XCTAssertEqual(decodedFace.trackingState, .normal)
        } else {
            XCTFail("Expected arFace metadata")
        }
    }

    func testRemoteCameraMessageHandshake() throws {
        let message = RemoteCameraMessage.handshake(sourceID: "test-device", deviceName: "Test iPhone")

        XCTAssertEqual(message.kind, .handshake)
        XCTAssertNotNil(message.handshake)
        XCTAssertEqual(message.handshake?.sourceID, "test-device")
        XCTAssertEqual(message.handshake?.deviceName, "Test iPhone")

        let encoder = JSONEncoder()
        let data = try encoder.encode(message)

        let decoder = JSONDecoder()
        let decoded = try decoder.decode(RemoteCameraMessage.self, from: data)

        XCTAssertEqual(decoded.kind, .handshake)
        XCTAssertEqual(decoded.handshake?.sourceID, "test-device")
    }

    func testRemoteCameraConstants() {
        XCTAssertEqual(RemoteCameraConstants.serviceType, "_arkavo-remote._tcp.")
    }
}
