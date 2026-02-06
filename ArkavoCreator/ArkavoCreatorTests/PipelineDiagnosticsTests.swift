//
// PipelineDiagnosticsTests.swift
// ArkavoCreatorTests
//
// Unit tests for pipeline diagnostics infrastructure.
//

import XCTest
import simd
import ArkavoKit
@testable import ArkavoCreator

final class PipelineDiagnosticsTests: XCTestCase {

    // MARK: - Config Tests

    func testConfigDefaultValues() {
        let config = PipelineDiagnosticsConfig()

        XCTAssertFalse(config.enabled)
        XCTAssertTrue(config.captureRawARKit)
        XCTAssertTrue(config.captureConversion)
        XCTAssertTrue(config.captureVRMMapping)
        XCTAssertTrue(config.captureRecording)
        XCTAssertTrue(config.captureProcessing)
        XCTAssertEqual(config.maxFramesToCapture, 1000)
        XCTAssertTrue(config.includeTransforms)
    }

    func testConfigCustomValues() {
        let config = PipelineDiagnosticsConfig(
            enabled: true,
            captureRawARKit: false,
            captureConversion: true,
            captureVRMMapping: false,
            captureRecording: true,
            captureProcessing: false,
            maxFramesToCapture: 500,
            includeTransforms: false
        )

        XCTAssertTrue(config.enabled)
        XCTAssertFalse(config.captureRawARKit)
        XCTAssertTrue(config.captureConversion)
        XCTAssertFalse(config.captureVRMMapping)
        XCTAssertTrue(config.captureRecording)
        XCTAssertFalse(config.captureProcessing)
        XCTAssertEqual(config.maxFramesToCapture, 500)
        XCTAssertFalse(config.includeTransforms)
    }

    func testConfigCodable() throws {
        let original = PipelineDiagnosticsConfig(
            enabled: true,
            maxFramesToCapture: 250
        )

        let encoder = JSONEncoder()
        let data = try encoder.encode(original)

        let decoder = JSONDecoder()
        let decoded = try decoder.decode(PipelineDiagnosticsConfig.self, from: data)

        XCTAssertEqual(original.enabled, decoded.enabled)
        XCTAssertEqual(original.maxFramesToCapture, decoded.maxFramesToCapture)
        XCTAssertEqual(original.captureRawARKit, decoded.captureRawARKit)
    }

    // MARK: - SIMD Capture Tests

    func testSIMD3Capture() {
        let vector = SIMD3<Float>(1.0, 2.0, 3.0)
        let capture = SIMD3Capture(vector)

        XCTAssertEqual(capture.x, 1.0)
        XCTAssertEqual(capture.y, 2.0)
        XCTAssertEqual(capture.z, 3.0)

        let restored = capture.simd
        XCTAssertEqual(restored.x, vector.x)
        XCTAssertEqual(restored.y, vector.y)
        XCTAssertEqual(restored.z, vector.z)
    }

    func testSIMD4Capture() {
        let quat = simd_quatf(ix: 0.1, iy: 0.2, iz: 0.3, r: 0.9)
        let capture = SIMD4Capture(quat)

        XCTAssertEqual(capture.x, 0.1, accuracy: 0.0001)
        XCTAssertEqual(capture.y, 0.2, accuracy: 0.0001)
        XCTAssertEqual(capture.z, 0.3, accuracy: 0.0001)
        XCTAssertEqual(capture.w, 0.9, accuracy: 0.0001)

        let restored = capture.simdQuaternion
        XCTAssertEqual(restored.imag.x, quat.imag.x, accuracy: 0.0001)
        XCTAssertEqual(restored.imag.y, quat.imag.y, accuracy: 0.0001)
        XCTAssertEqual(restored.imag.z, quat.imag.z, accuracy: 0.0001)
        XCTAssertEqual(restored.real, quat.real, accuracy: 0.0001)
    }

    func testSIMD3CaptureCodable() throws {
        let original = SIMD3Capture(x: 1.5, y: 2.5, z: 3.5)

        let encoder = JSONEncoder()
        let data = try encoder.encode(original)

        let decoder = JSONDecoder()
        let decoded = try decoder.decode(SIMD3Capture.self, from: data)

        XCTAssertEqual(original.x, decoded.x)
        XCTAssertEqual(original.y, decoded.y)
        XCTAssertEqual(original.z, decoded.z)
    }

    func testSIMD4CaptureCodable() throws {
        let original = SIMD4Capture(x: 0.1, y: 0.2, z: 0.3, w: 0.9)

        let encoder = JSONEncoder()
        let data = try encoder.encode(original)

        let decoder = JSONDecoder()
        let decoded = try decoder.decode(SIMD4Capture.self, from: data)

        XCTAssertEqual(original.x, decoded.x, accuracy: 0.0001)
        XCTAssertEqual(original.y, decoded.y, accuracy: 0.0001)
        XCTAssertEqual(original.z, decoded.z, accuracy: 0.0001)
        XCTAssertEqual(original.w, decoded.w, accuracy: 0.0001)
    }

    // MARK: - Stage Capture Tests

    func testRawARKitCaptureFace() {
        let faceData = RawARKitCapture.RawFaceData(
            blendShapes: ["eyeBlinkLeft": 0.5, "jawOpen": 0.3],
            headTransform: [1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1],
            trackingState: "normal"
        )

        let capture = RawARKitCapture(
            sourceID: "test-source",
            eventTimestamp: Date(),
            metadataType: .face,
            faceData: faceData,
            bodyData: nil
        )

        XCTAssertEqual(capture.sourceID, "test-source")
        XCTAssertEqual(capture.metadataType, .face)
        XCTAssertNotNil(capture.faceData)
        XCTAssertNil(capture.bodyData)
        XCTAssertEqual(capture.faceData?.blendShapes["eyeBlinkLeft"], 0.5)
        XCTAssertEqual(capture.faceData?.trackingState, "normal")
    }

    func testRawARKitCaptureBody() {
        let bodyData = RawARKitCapture.RawBodyData(
            jointNames: ["hips_joint", "spine_1_joint", "left_shoulder_1_joint"],
            jointTransforms: [
                [1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1],
                [1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0.5, 0, 1],
                [1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0.2, 0.8, 0, 1]
            ],
            jointConfidences: nil
        )

        let capture = RawARKitCapture(
            sourceID: "test-source",
            eventTimestamp: Date(),
            metadataType: .body,
            faceData: nil,
            bodyData: bodyData
        )

        XCTAssertEqual(capture.metadataType, .body)
        XCTAssertNil(capture.faceData)
        XCTAssertNotNil(capture.bodyData)
        XCTAssertEqual(capture.bodyData?.jointNames.count, 3)
        XCTAssertTrue(capture.bodyData?.jointNames.contains("left_shoulder_1_joint") ?? false)
    }

    func testConversionCapture() {
        let capture = ConversionCapture(
            inputJointCount: 91,
            mappedJoints: [
                "hips_joint": "hips",
                "left_shoulder_1_joint": "leftShoulder",
                "right_shoulder_1_joint": "rightShoulder"
            ],
            unmappedJoints: [
                ConversionCapture.UnmappedJoint(name: "jaw_joint", transform: nil)
            ],
            invalidTransformJoints: [],
            outputJointCount: 22,
            isTracked: true
        )

        XCTAssertEqual(capture.inputJointCount, 91)
        XCTAssertEqual(capture.outputJointCount, 22)
        XCTAssertTrue(capture.isTracked)
        XCTAssertEqual(capture.mappedJoints["left_shoulder_1_joint"], "leftShoulder")
        XCTAssertEqual(capture.mappedJoints["right_shoulder_1_joint"], "rightShoulder")
        XCTAssertEqual(capture.unmappedJoints.count, 1)
        XCTAssertEqual(capture.unmappedJoints.first?.name, "jaw_joint")
    }

    func testRecordingCapture() {
        let capture = RecordingCapture(
            time: 1.5,
            hasFaceBlendShapes: true,
            faceBlendShapeCount: 52,
            hasBodyJoints: true,
            bodyJointCount: 22,
            hasHipsTranslation: true,
            bodyJointNames: ["hips", "spine", "chest", "head"]
        )

        XCTAssertEqual(capture.time, 1.5)
        XCTAssertTrue(capture.hasFaceBlendShapes)
        XCTAssertEqual(capture.faceBlendShapeCount, 52)
        XCTAssertTrue(capture.hasBodyJoints)
        XCTAssertEqual(capture.bodyJointCount, 22)
        XCTAssertTrue(capture.hasHipsTranslation)
        XCTAssertEqual(capture.bodyJointNames.count, 4)
    }

    // MARK: - Session Tests

    func testSessionCreation() {
        let config = PipelineDiagnosticsConfig(enabled: true)
        let startTime = Date()
        let endTime = startTime.addingTimeInterval(10)

        let capture = PipelineStageCapture(
            stageId: "rawARKit",
            timestamp: startTime,
            frameIndex: 0,
            data: .rawARKit(RawARKitCapture(
                sourceID: "test",
                eventTimestamp: startTime,
                metadataType: .body,
                faceData: nil,
                bodyData: RawARKitCapture.RawBodyData(
                    jointNames: ["hips_joint"],
                    jointTransforms: [[1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1]],
                    jointConfidences: nil
                )
            ))
        )

        let session = PipelineDiagnosticsSession(
            startTime: startTime,
            endTime: endTime,
            config: config,
            captures: [capture]
        )

        XCTAssertEqual(session.version, "1.0")
        XCTAssertEqual(session.captures.count, 1)
        XCTAssertTrue(session.config.enabled)
        XCTAssertTrue(session.summary.contains("1 captures"))
    }

    func testSessionCodable() throws {
        let config = PipelineDiagnosticsConfig(enabled: true)
        let startTime = Date()
        let endTime = startTime.addingTimeInterval(5)

        let original = PipelineDiagnosticsSession(
            startTime: startTime,
            endTime: endTime,
            config: config,
            captures: []
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(original)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(PipelineDiagnosticsSession.self, from: data)

        XCTAssertEqual(original.version, decoded.version)
        XCTAssertEqual(original.config.enabled, decoded.config.enabled)
        XCTAssertEqual(original.captures.count, decoded.captures.count)
    }

    func testSessionExportAndLoad() throws {
        let config = PipelineDiagnosticsConfig(enabled: true)
        let session = PipelineDiagnosticsSession(
            startTime: Date(),
            endTime: Date(),
            config: config,
            captures: []
        )

        // Export to temp file
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("test_session_\(UUID().uuidString).json")

        try session.exportJSON(to: tempURL)

        // Verify file exists
        XCTAssertTrue(FileManager.default.fileExists(atPath: tempURL.path))

        // Load and verify
        let loaded = try PipelineDiagnosticsSession.load(from: tempURL)
        XCTAssertEqual(loaded.version, session.version)
        XCTAssertEqual(loaded.config.enabled, session.config.enabled)

        // Cleanup
        try? FileManager.default.removeItem(at: tempURL)
    }

    // MARK: - Processing Capture Tests

    func testProcessingCapture() {
        let options = ProcessingCapture.ProcessingOptionsCapture(
            smoothingFactor: 0.3,
            outlierThreshold: 45.0,
            calibrationFrames: 0,
            normalizeQuaternions: true
        )

        let report = ProcessingCapture.QualityReportCapture(
            inputFrames: 100,
            outputFrames: 98,
            outlierFrames: 2,
            bodyFrameRatio: 0.95,
            outlierRatio: 0.02
        )

        let boneStats = [
            ProcessingCapture.BoneStatisticsCapture(
                boneName: "hips",
                frameCount: 100,
                minAngle: 0.0,
                maxAngle: 15.0,
                avgAngle: 5.0
            )
        ]

        let capture = ProcessingCapture(
            inputFrameCount: 100,
            outputFrameCount: 98,
            options: options,
            qualityReport: report,
            boneStatistics: boneStats
        )

        XCTAssertEqual(capture.inputFrameCount, 100)
        XCTAssertEqual(capture.outputFrameCount, 98)
        XCTAssertEqual(capture.options.smoothingFactor, 0.3)
        XCTAssertEqual(capture.qualityReport.outlierRatio, 0.02, accuracy: 0.001)
        XCTAssertEqual(capture.boneStatistics.count, 1)
        XCTAssertEqual(capture.boneStatistics.first?.boneName, "hips")
    }

    // MARK: - Export Capture Tests

    func testExportCapture() {
        let channels = [
            ExportCapture.AnimationChannelCapture(
                targetNode: "hips",
                targetPath: "rotation",
                keyframeCount: 100
            ),
            ExportCapture.AnimationChannelCapture(
                targetNode: "hips",
                targetPath: "translation",
                keyframeCount: 100
            )
        ]

        let capture = ExportCapture(
            fileURL: "/path/to/animation.vrma",
            fileSizeBytes: 102400,
            sessionName: "test_animation",
            duration: 3.33,
            frameRate: 30,
            frameCount: 100,
            animationChannels: channels
        )

        XCTAssertEqual(capture.fileURL, "/path/to/animation.vrma")
        XCTAssertEqual(capture.fileSizeBytes, 102400)
        XCTAssertEqual(capture.sessionName, "test_animation")
        XCTAssertEqual(capture.duration, 3.33, accuracy: 0.01)
        XCTAssertEqual(capture.frameRate, 30)
        XCTAssertEqual(capture.frameCount, 100)
        XCTAssertEqual(capture.animationChannels.count, 2)
    }
}

// MARK: - Recorder Tests

@MainActor
final class PipelineDiagnosticsRecorderTests: XCTestCase {

    func testRecorderInitialState() {
        let recorder = PipelineDiagnosticsRecorder()

        XCTAssertFalse(recorder.config.enabled)
        XCTAssertFalse(recorder.isCapturing)
        XCTAssertEqual(recorder.captureCount, 0)
    }

    func testRecorderStartStopCapture() {
        let recorder = PipelineDiagnosticsRecorder()
        recorder.config.enabled = true

        recorder.startCapture()
        XCTAssertTrue(recorder.isCapturing)

        let session = recorder.stopCapture()
        XCTAssertFalse(recorder.isCapturing)
        XCTAssertEqual(session.captures.count, 0)
        XCTAssertTrue(session.config.enabled)
    }

    func testRecorderDoesNotCaptureWhenDisabled() {
        let recorder = PipelineDiagnosticsRecorder()
        recorder.config.enabled = false

        recorder.startCapture()
        XCTAssertFalse(recorder.isCapturing)
    }

    func testRecorderReset() {
        let recorder = PipelineDiagnosticsRecorder()
        recorder.config.enabled = true
        recorder.startCapture()

        XCTAssertTrue(recorder.isCapturing)

        recorder.reset()

        XCTAssertFalse(recorder.isCapturing)
        XCTAssertEqual(recorder.captureCount, 0)
    }

    func testRecorderMaxFramesLimit() {
        let recorder = PipelineDiagnosticsRecorder()
        recorder.config.enabled = true
        recorder.config.maxFramesToCapture = 5

        recorder.startCapture()

        // Create test recording captures
        for i in 0..<10 {
            let capture = RecordingCapture(
                time: Float(i) * 0.033,
                hasFaceBlendShapes: false,
                faceBlendShapeCount: 0,
                hasBodyJoints: true,
                bodyJointCount: 22,
                hasHipsTranslation: true,
                bodyJointNames: ["hips"]
            )
            recorder.captureRecording(frame: VRMAFrame(
                time: Float(i) * 0.033,
                bodyJoints: [:],
                hipsTranslation: nil
            ))
        }

        // Should be limited to maxFramesToCapture
        XCTAssertLessThanOrEqual(recorder.captureCount, 5)
    }
}
