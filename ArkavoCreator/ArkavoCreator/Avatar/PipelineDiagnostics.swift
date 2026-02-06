//
// PipelineDiagnostics.swift
// ArkavoCreator
//
// Pipeline diagnostics infrastructure for capturing and analyzing
// ARKit VRM motion capture data at each pipeline stage.
//

import Foundation
import simd

// MARK: - Configuration

/// Configuration for pipeline diagnostics capture
public struct PipelineDiagnosticsConfig: Sendable, Codable {
    /// Whether diagnostics capture is enabled
    public var enabled: Bool = false

    /// Capture raw ARKit data (Stage 1)
    public var captureRawARKit: Bool = true

    /// Capture conversion output (Stage 2)
    public var captureConversion: Bool = true

    /// Capture VRM mapping output (Stage 3)
    public var captureVRMMapping: Bool = true

    /// Capture recording frames (Stage 4)
    public var captureRecording: Bool = true

    /// Capture processing results (Stage 5)
    public var captureProcessing: Bool = true

    /// Maximum frames to capture (prevents memory issues)
    public var maxFramesToCapture: Int = 1000

    /// Whether to include transform matrices in output (large data)
    public var includeTransforms: Bool = true

    public init(
        enabled: Bool = false,
        captureRawARKit: Bool = true,
        captureConversion: Bool = true,
        captureVRMMapping: Bool = true,
        captureRecording: Bool = true,
        captureProcessing: Bool = true,
        maxFramesToCapture: Int = 1000,
        includeTransforms: Bool = true
    ) {
        self.enabled = enabled
        self.captureRawARKit = captureRawARKit
        self.captureConversion = captureConversion
        self.captureVRMMapping = captureVRMMapping
        self.captureRecording = captureRecording
        self.captureProcessing = captureProcessing
        self.maxFramesToCapture = maxFramesToCapture
        self.includeTransforms = includeTransforms
    }
}

// MARK: - Stage Data Types

/// Wrapper for stage-specific data
public enum StageData: Codable, Sendable {
    case rawARKit(RawARKitCapture)
    case conversion(ConversionCapture)
    case vrmMapping(VRMMappingCapture)
    case recording(RecordingCapture)
    case processing(ProcessingCapture)
    case export(ExportCapture)
}

/// A single captured pipeline stage event
public struct PipelineStageCapture: Codable, Sendable {
    /// Identifier for this stage
    public let stageId: String

    /// When this capture occurred
    public let timestamp: Date

    /// Frame index in the recording (if applicable)
    public let frameIndex: Int?

    /// The captured data for this stage
    public let data: StageData

    public init(stageId: String, timestamp: Date, frameIndex: Int? = nil, data: StageData) {
        self.stageId = stageId
        self.timestamp = timestamp
        self.frameIndex = frameIndex
        self.data = data
    }
}

// MARK: - Stage 1: Raw ARKit Capture

/// Captures raw ARKit data before any conversion
public struct RawARKitCapture: Codable, Sendable {
    /// Source identifier (device ID)
    public let sourceID: String

    /// Event timestamp
    public let eventTimestamp: Date

    /// Type of metadata (face or body)
    public let metadataType: MetadataType

    /// Raw face data (if face tracking)
    public let faceData: RawFaceData?

    /// Raw body data (if body tracking)
    public let bodyData: RawBodyData?

    public enum MetadataType: String, Codable, Sendable {
        case face
        case body
    }

    public struct RawFaceData: Codable, Sendable {
        /// Blend shape names and values
        public let blendShapes: [String: Float]

        /// Head transform as 16 floats (column-major)
        public let headTransform: [Float]?

        /// Tracking state
        public let trackingState: String

        public init(blendShapes: [String: Float], headTransform: [Float]?, trackingState: String) {
            self.blendShapes = blendShapes
            self.headTransform = headTransform
            self.trackingState = trackingState
        }
    }

    public struct RawBodyData: Codable, Sendable {
        /// Joint names from ARKit
        public let jointNames: [String]

        /// Joint transforms as arrays of 16 floats (column-major)
        public let jointTransforms: [[Float]]

        /// Joint confidence values (if available)
        public let jointConfidences: [Float]?

        public init(jointNames: [String], jointTransforms: [[Float]], jointConfidences: [Float]?) {
            self.jointNames = jointNames
            self.jointTransforms = jointTransforms
            self.jointConfidences = jointConfidences
        }
    }

    public init(
        sourceID: String,
        eventTimestamp: Date,
        metadataType: MetadataType,
        faceData: RawFaceData?,
        bodyData: RawBodyData?
    ) {
        self.sourceID = sourceID
        self.eventTimestamp = eventTimestamp
        self.metadataType = metadataType
        self.faceData = faceData
        self.bodyData = bodyData
    }
}

// MARK: - Stage 2: Conversion Capture

/// Captures ARKitDataConverter output
public struct ConversionCapture: Codable, Sendable {
    /// Input joint count
    public let inputJointCount: Int

    /// Successfully mapped joints (ARKitJoint raw value -> VRM name)
    public let mappedJoints: [String: String]

    /// Joints that couldn't be mapped
    public let unmappedJoints: [UnmappedJoint]

    /// Joints with invalid transforms
    public let invalidTransformJoints: [String]

    /// Output joint count
    public let outputJointCount: Int

    /// Whether skeleton is tracked
    public let isTracked: Bool

    /// Unmapped joint details
    public struct UnmappedJoint: Codable, Sendable {
        /// Original ARKit joint name
        public let name: String

        /// The transform that was discarded (as 16 floats)
        public let transform: [Float]?

        public init(name: String, transform: [Float]?) {
            self.name = name
            self.transform = transform
        }
    }

    public init(
        inputJointCount: Int,
        mappedJoints: [String: String],
        unmappedJoints: [UnmappedJoint],
        invalidTransformJoints: [String],
        outputJointCount: Int,
        isTracked: Bool
    ) {
        self.inputJointCount = inputJointCount
        self.mappedJoints = mappedJoints
        self.unmappedJoints = unmappedJoints
        self.invalidTransformJoints = invalidTransformJoints
        self.outputJointCount = outputJointCount
        self.isTracked = isTracked
    }
}

// MARK: - Stage 3: VRM Mapping Capture

/// Captures VRMARecorder.convertBodyToVRMBones output
public struct VRMMappingCapture: Codable, Sendable {
    /// Input ARKitJoint transforms
    public let inputJoints: [JointTransformCapture]

    /// Output VRM bone rotations
    public let outputRotations: [BoneRotationCapture]

    /// Joints where parent lookup failed
    public let missingParentJoints: [String]

    /// Hips translation extracted
    public let hipsTranslation: SIMD3Capture?

    /// Joint transform capture
    public struct JointTransformCapture: Codable, Sendable {
        public let jointName: String
        public let transform: [Float]  // 16 floats, column-major

        public init(jointName: String, transform: [Float]) {
            self.jointName = jointName
            self.transform = transform
        }
    }

    /// Bone rotation capture
    public struct BoneRotationCapture: Codable, Sendable {
        public let boneName: String
        public let quaternion: SIMD4Capture  // x, y, z, w
        public let usedFallback: Bool  // true if parent lookup failed

        public init(boneName: String, quaternion: SIMD4Capture, usedFallback: Bool) {
            self.boneName = boneName
            self.quaternion = quaternion
            self.usedFallback = usedFallback
        }
    }

    public init(
        inputJoints: [JointTransformCapture],
        outputRotations: [BoneRotationCapture],
        missingParentJoints: [String],
        hipsTranslation: SIMD3Capture?
    ) {
        self.inputJoints = inputJoints
        self.outputRotations = outputRotations
        self.missingParentJoints = missingParentJoints
        self.hipsTranslation = hipsTranslation
    }
}

// MARK: - Stage 4: Recording Capture

/// Captures VRMAFrame metadata
public struct RecordingCapture: Codable, Sendable {
    /// Frame time offset from recording start
    public let time: Float

    /// Whether frame has face blend shapes
    public let hasFaceBlendShapes: Bool

    /// Number of face blend shapes
    public let faceBlendShapeCount: Int

    /// Whether frame has body joints
    public let hasBodyJoints: Bool

    /// Number of body joints
    public let bodyJointCount: Int

    /// Whether frame has hips translation
    public let hasHipsTranslation: Bool

    /// Body joint names in this frame
    public let bodyJointNames: [String]

    public init(
        time: Float,
        hasFaceBlendShapes: Bool,
        faceBlendShapeCount: Int,
        hasBodyJoints: Bool,
        bodyJointCount: Int,
        hasHipsTranslation: Bool,
        bodyJointNames: [String]
    ) {
        self.time = time
        self.hasFaceBlendShapes = hasFaceBlendShapes
        self.faceBlendShapeCount = faceBlendShapeCount
        self.hasBodyJoints = hasBodyJoints
        self.bodyJointCount = bodyJointCount
        self.hasHipsTranslation = hasHipsTranslation
        self.bodyJointNames = bodyJointNames
    }
}

// MARK: - Stage 5: Processing Capture

/// Captures VRMAProcessor results
public struct ProcessingCapture: Codable, Sendable {
    /// Input frame count
    public let inputFrameCount: Int

    /// Output frame count
    public let outputFrameCount: Int

    /// Processing options used
    public let options: ProcessingOptionsCapture

    /// Quality report
    public let qualityReport: QualityReportCapture

    /// Per-bone statistics
    public let boneStatistics: [BoneStatisticsCapture]

    /// Processing options capture
    public struct ProcessingOptionsCapture: Codable, Sendable {
        public let smoothingFactor: Float
        public let outlierThreshold: Float
        public let calibrationFrames: Int
        public let normalizeQuaternions: Bool

        public init(
            smoothingFactor: Float,
            outlierThreshold: Float,
            calibrationFrames: Int,
            normalizeQuaternions: Bool
        ) {
            self.smoothingFactor = smoothingFactor
            self.outlierThreshold = outlierThreshold
            self.calibrationFrames = calibrationFrames
            self.normalizeQuaternions = normalizeQuaternions
        }
    }

    /// Quality report capture
    public struct QualityReportCapture: Codable, Sendable {
        public let inputFrames: Int
        public let outputFrames: Int
        public let outlierFrames: Int
        public let bodyFrameRatio: Float
        public let outlierRatio: Float

        public init(
            inputFrames: Int,
            outputFrames: Int,
            outlierFrames: Int,
            bodyFrameRatio: Float,
            outlierRatio: Float
        ) {
            self.inputFrames = inputFrames
            self.outputFrames = outputFrames
            self.outlierFrames = outlierFrames
            self.bodyFrameRatio = bodyFrameRatio
            self.outlierRatio = outlierRatio
        }
    }

    /// Per-bone statistics
    public struct BoneStatisticsCapture: Codable, Sendable {
        public let boneName: String
        public let frameCount: Int
        public let minAngle: Float
        public let maxAngle: Float
        public let avgAngle: Float

        public init(boneName: String, frameCount: Int, minAngle: Float, maxAngle: Float, avgAngle: Float) {
            self.boneName = boneName
            self.frameCount = frameCount
            self.minAngle = minAngle
            self.maxAngle = maxAngle
            self.avgAngle = avgAngle
        }
    }

    public init(
        inputFrameCount: Int,
        outputFrameCount: Int,
        options: ProcessingOptionsCapture,
        qualityReport: QualityReportCapture,
        boneStatistics: [BoneStatisticsCapture]
    ) {
        self.inputFrameCount = inputFrameCount
        self.outputFrameCount = outputFrameCount
        self.options = options
        self.qualityReport = qualityReport
        self.boneStatistics = boneStatistics
    }
}

// MARK: - Stage 6: Export Capture

/// Captures VRMAExporter output metadata
public struct ExportCapture: Codable, Sendable {
    /// Export file URL
    public let fileURL: String

    /// File size in bytes
    public let fileSizeBytes: Int64

    /// Session name
    public let sessionName: String

    /// Session duration
    public let duration: Float

    /// Frame rate
    public let frameRate: Int

    /// Total frame count
    public let frameCount: Int

    /// Animation channels created
    public let animationChannels: [AnimationChannelCapture]

    /// Animation channel info
    public struct AnimationChannelCapture: Codable, Sendable {
        public let targetNode: String
        public let targetPath: String  // rotation, translation, weights
        public let keyframeCount: Int

        public init(targetNode: String, targetPath: String, keyframeCount: Int) {
            self.targetNode = targetNode
            self.targetPath = targetPath
            self.keyframeCount = keyframeCount
        }
    }

    public init(
        fileURL: String,
        fileSizeBytes: Int64,
        sessionName: String,
        duration: Float,
        frameRate: Int,
        frameCount: Int,
        animationChannels: [AnimationChannelCapture]
    ) {
        self.fileURL = fileURL
        self.fileSizeBytes = fileSizeBytes
        self.sessionName = sessionName
        self.duration = duration
        self.frameRate = frameRate
        self.frameCount = frameCount
        self.animationChannels = animationChannels
    }
}

// MARK: - SIMD Helper Types

/// Codable wrapper for SIMD3<Float>
public struct SIMD3Capture: Codable, Sendable {
    public let x: Float
    public let y: Float
    public let z: Float

    public init(_ value: SIMD3<Float>) {
        self.x = value.x
        self.y = value.y
        self.z = value.z
    }

    public init(x: Float, y: Float, z: Float) {
        self.x = x
        self.y = y
        self.z = z
    }

    public var simd: SIMD3<Float> {
        SIMD3(x, y, z)
    }
}

/// Codable wrapper for SIMD4<Float> (quaternion)
public struct SIMD4Capture: Codable, Sendable {
    public let x: Float
    public let y: Float
    public let z: Float
    public let w: Float

    public init(_ value: simd_quatf) {
        self.x = value.imag.x
        self.y = value.imag.y
        self.z = value.imag.z
        self.w = value.real
    }

    public init(x: Float, y: Float, z: Float, w: Float) {
        self.x = x
        self.y = y
        self.z = z
        self.w = w
    }

    public var simdQuaternion: simd_quatf {
        simd_quatf(ix: x, iy: y, iz: z, r: w)
    }
}

// MARK: - Session

/// A complete diagnostics capture session
public struct PipelineDiagnosticsSession: Codable, Sendable {
    /// Format version
    public let version: String

    /// When capture started
    public let startTime: Date

    /// When capture ended
    public let endTime: Date

    /// Configuration used
    public let config: PipelineDiagnosticsConfig

    /// All captured stage events
    public let captures: [PipelineStageCapture]

    /// Session metadata
    public let metadata: SessionMetadata

    /// Session metadata
    public struct SessionMetadata: Codable, Sendable {
        public let deviceModel: String
        public let osVersion: String
        public let appVersion: String

        public init(deviceModel: String = "", osVersion: String = "", appVersion: String = "") {
            self.deviceModel = deviceModel
            self.osVersion = osVersion
            self.appVersion = appVersion
        }
    }

    public init(
        version: String = "1.0",
        startTime: Date,
        endTime: Date,
        config: PipelineDiagnosticsConfig,
        captures: [PipelineStageCapture],
        metadata: SessionMetadata = SessionMetadata()
    ) {
        self.version = version
        self.startTime = startTime
        self.endTime = endTime
        self.config = config
        self.captures = captures
        self.metadata = metadata
    }

    /// Export session to JSON file
    /// - Parameter url: File URL to write to
    public func exportJSON(to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(self)
        try data.write(to: url)
    }

    /// Load session from JSON file
    /// - Parameter url: File URL to read from
    /// - Returns: Loaded session
    public static func load(from url: URL) throws -> PipelineDiagnosticsSession {
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(PipelineDiagnosticsSession.self, from: data)
    }

    /// Summary statistics for the session
    public var summary: String {
        let duration = endTime.timeIntervalSince(startTime)
        let stageCount = Dictionary(grouping: captures, by: { $0.stageId }).count
        return "Session: \(captures.count) captures across \(stageCount) stages over \(String(format: "%.1f", duration))s"
    }
}
