//
// PipelineDiagnosticsRecorder.swift
// ArkavoCreator
//
// Records pipeline diagnostics data at each stage for analysis and test generation.
//

import Foundation
import simd
import VRMMetalKit
import ArkavoKit

#if os(iOS) || os(tvOS)
import UIKit
#endif

/// Records pipeline diagnostics for analysis and test generation
@MainActor
public class PipelineDiagnosticsRecorder: ObservableObject {

    // MARK: - Published Properties

    @Published public var config = PipelineDiagnosticsConfig()
    @Published public private(set) var isCapturing = false
    @Published public private(set) var captureCount = 0

    // MARK: - Private State

    private var captures: [PipelineStageCapture] = []
    private var startTime: Date?
    private var frameIndex = 0

    // MARK: - Capture Control

    /// Start capturing diagnostics
    public func startCapture() {
        guard config.enabled, !isCapturing else { return }

        captures.removeAll()
        frameIndex = 0
        captureCount = 0
        startTime = Date()
        isCapturing = true

        debugLog("[PipelineDiagnostics] Capture started")
    }

    /// Stop capturing and return the session
    public func stopCapture() -> PipelineDiagnosticsSession {
        guard isCapturing else {
            return PipelineDiagnosticsSession(
                startTime: Date(),
                endTime: Date(),
                config: config,
                captures: []
            )
        }

        isCapturing = false
        let endTime = Date()

        let session = PipelineDiagnosticsSession(
            startTime: startTime ?? endTime,
            endTime: endTime,
            config: config,
            captures: captures,
            metadata: createMetadata()
        )

        debugLog("[PipelineDiagnostics] Capture stopped: \(captures.count) events")

        captures.removeAll()
        startTime = nil

        return session
    }

    /// Reset without saving
    public func reset() {
        captures.removeAll()
        frameIndex = 0
        captureCount = 0
        startTime = nil
        isCapturing = false
    }

    // MARK: - Stage 1: Raw ARKit Capture

    /// Capture raw ARKit metadata event
    public func captureRawARKit(event: CameraMetadataEvent) {
        guard shouldCapture(stage: config.captureRawARKit) else { return }

        let capture: RawARKitCapture

        switch event.metadata {
        case .arFace(let faceMetadata):
            let faceData = RawARKitCapture.RawFaceData(
                blendShapes: faceMetadata.blendShapes,
                headTransform: faceMetadata.headTransform,
                trackingState: faceMetadata.trackingState.rawValue
            )
            capture = RawARKitCapture(
                sourceID: event.sourceID,
                eventTimestamp: event.timestamp,
                metadataType: .face,
                faceData: faceData,
                bodyData: nil
            )

        case .arBody(let bodyMetadata):
            let jointNames = bodyMetadata.joints.map { $0.name }
            let jointTransforms = bodyMetadata.joints.map { $0.transform }
            let bodyData = RawARKitCapture.RawBodyData(
                jointNames: jointNames,
                jointTransforms: jointTransforms,
                jointConfidences: nil
            )
            capture = RawARKitCapture(
                sourceID: event.sourceID,
                eventTimestamp: event.timestamp,
                metadataType: .body,
                faceData: nil,
                bodyData: bodyData
            )

        case .custom:
            // Skip custom metadata types - not part of ARKit pipeline
            return
        }

        addCapture(stageId: "rawARKit", data: .rawARKit(capture))
    }

    // MARK: - Stage 2: Conversion Capture

    /// Capture ARKitDataConverter results
    public func captureConversion(
        inputMetadata: ARBodyMetadata,
        outputSkeleton: ARKitBodySkeleton,
        mappedJoints: [String: String],
        unmappedJoints: [(name: String, transform: [Float]?)],
        invalidTransformJoints: [String]
    ) {
        guard shouldCapture(stage: config.captureConversion) else { return }

        let unmapped = unmappedJoints.map { joint in
            ConversionCapture.UnmappedJoint(
                name: joint.name,
                transform: config.includeTransforms ? joint.transform : nil
            )
        }

        let capture = ConversionCapture(
            inputJointCount: inputMetadata.joints.count,
            mappedJoints: mappedJoints,
            unmappedJoints: unmapped,
            invalidTransformJoints: invalidTransformJoints,
            outputJointCount: outputSkeleton.joints.count,
            isTracked: outputSkeleton.isTracked
        )

        addCapture(stageId: "conversion", data: .conversion(capture))
    }

    // MARK: - Stage 3: VRM Mapping Capture

    /// Capture VRM bone mapping results
    public func captureVRMMapping(
        inputJoints: [ARKitJoint: simd_float4x4],
        outputRotations: [VRMHumanoidBone: simd_quatf],
        missingParentJoints: [String],
        usedFallback: Set<VRMHumanoidBone>,
        hipsTranslation: simd_float3?
    ) {
        guard shouldCapture(stage: config.captureVRMMapping) else { return }

        let inputCaptures: [VRMMappingCapture.JointTransformCapture]
        if config.includeTransforms {
            inputCaptures = inputJoints.map { joint, transform in
                VRMMappingCapture.JointTransformCapture(
                    jointName: joint.rawValue,
                    transform: matrixToArray(transform)
                )
            }
        } else {
            inputCaptures = inputJoints.map { joint, _ in
                VRMMappingCapture.JointTransformCapture(
                    jointName: joint.rawValue,
                    transform: []
                )
            }
        }

        let outputCaptures = outputRotations.map { bone, rotation in
            VRMMappingCapture.BoneRotationCapture(
                boneName: bone.rawValue,
                quaternion: SIMD4Capture(rotation),
                usedFallback: usedFallback.contains(bone)
            )
        }

        let capture = VRMMappingCapture(
            inputJoints: inputCaptures,
            outputRotations: outputCaptures,
            missingParentJoints: missingParentJoints,
            hipsTranslation: hipsTranslation.map { SIMD3Capture($0) }
        )

        addCapture(stageId: "vrmMapping", data: .vrmMapping(capture))
    }

    // MARK: - Stage 4: Recording Capture

    /// Capture VRMAFrame metadata
    public func captureRecording(frame: VRMAFrame) {
        guard shouldCapture(stage: config.captureRecording) else { return }

        let bodyJointNames = frame.bodyJoints?.keys.map { $0.rawValue } ?? []

        let capture = RecordingCapture(
            time: frame.time,
            hasFaceBlendShapes: frame.faceBlendShapes != nil,
            faceBlendShapeCount: frame.faceBlendShapes?.count ?? 0,
            hasBodyJoints: frame.bodyJoints != nil,
            bodyJointCount: frame.bodyJoints?.count ?? 0,
            hasHipsTranslation: frame.hipsTranslation != nil,
            bodyJointNames: bodyJointNames
        )

        addCapture(stageId: "recording", data: .recording(capture), withFrameIndex: true)
    }

    // MARK: - Stage 5: Processing Capture

    /// Capture VRMAProcessor results
    public func captureProcessing(
        inputSession: VRMASession,
        outputSession: VRMASession,
        options: VRMAProcessor.Options,
        report: VRMAProcessor.QualityReport
    ) {
        guard shouldCapture(stage: config.captureProcessing) else { return }

        let optionsCapture = ProcessingCapture.ProcessingOptionsCapture(
            smoothingFactor: options.smoothingFactor,
            outlierThreshold: options.outlierThreshold,
            calibrationFrames: options.calibrationFrames,
            normalizeQuaternions: options.normalizeQuaternions
        )

        let reportCapture = ProcessingCapture.QualityReportCapture(
            inputFrames: report.inputFrames,
            outputFrames: report.outputFrames,
            outlierFrames: report.outlierFrames,
            bodyFrameRatio: report.bodyFrameRatio,
            outlierRatio: report.outlierRatio
        )

        // Calculate per-bone statistics
        let boneStats = calculateBoneStatistics(session: outputSession)

        let capture = ProcessingCapture(
            inputFrameCount: inputSession.frameCount,
            outputFrameCount: outputSession.frameCount,
            options: optionsCapture,
            qualityReport: reportCapture,
            boneStatistics: boneStats
        )

        addCapture(stageId: "processing", data: .processing(capture))
    }

    // MARK: - Stage 6: Export Capture

    /// Capture export metadata
    public func captureExport(
        fileURL: URL,
        session: VRMASession,
        animationChannels: [(targetNode: String, targetPath: String, keyframeCount: Int)]
    ) {
        let fileSize: Int64
        do {
            let attrs = try FileManager.default.attributesOfItem(atPath: fileURL.path)
            fileSize = (attrs[.size] as? Int64) ?? 0
        } catch {
            fileSize = 0
        }

        let channelCaptures = animationChannels.map { channel in
            ExportCapture.AnimationChannelCapture(
                targetNode: channel.targetNode,
                targetPath: channel.targetPath,
                keyframeCount: channel.keyframeCount
            )
        }

        let capture = ExportCapture(
            fileURL: fileURL.path,
            fileSizeBytes: fileSize,
            sessionName: session.name,
            duration: session.duration,
            frameRate: session.frameRate,
            frameCount: session.frameCount,
            animationChannels: channelCaptures
        )

        addCapture(stageId: "export", data: .export(capture))
    }

    // MARK: - Export

    /// Export captured session to Documents/Diagnostics directory
    /// - Parameter name: Optional filename prefix
    /// - Returns: URL of exported file
    @discardableResult
    public func exportSession(name: String = "diagnostics") throws -> URL {
        let session = stopCapture()

        let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let diagnosticsDir = documentsURL.appendingPathComponent("Diagnostics", isDirectory: true)

        try FileManager.default.createDirectory(at: diagnosticsDir, withIntermediateDirectories: true)

        let timestamp = ISO8601DateFormatter().string(from: Date())
            .replacingOccurrences(of: ":", with: "-")
            .replacingOccurrences(of: "T", with: "_")
        let filename = "\(name)_\(timestamp).json"
        let fileURL = diagnosticsDir.appendingPathComponent(filename)

        try session.exportJSON(to: fileURL)

        debugLog("[PipelineDiagnostics] Exported to: \(fileURL.path)")

        return fileURL
    }

    // MARK: - Helpers

    private func shouldCapture(stage: Bool) -> Bool {
        guard config.enabled, isCapturing, stage else { return false }
        return captures.count < config.maxFramesToCapture
    }

    private func addCapture(stageId: String, data: StageData, withFrameIndex: Bool = false) {
        let capture = PipelineStageCapture(
            stageId: stageId,
            timestamp: Date(),
            frameIndex: withFrameIndex ? frameIndex : nil,
            data: data
        )
        captures.append(capture)
        captureCount = captures.count

        if withFrameIndex {
            frameIndex += 1
        }
    }

    private func matrixToArray(_ matrix: simd_float4x4) -> [Float] {
        [
            matrix.columns.0.x, matrix.columns.0.y, matrix.columns.0.z, matrix.columns.0.w,
            matrix.columns.1.x, matrix.columns.1.y, matrix.columns.1.z, matrix.columns.1.w,
            matrix.columns.2.x, matrix.columns.2.y, matrix.columns.2.z, matrix.columns.2.w,
            matrix.columns.3.x, matrix.columns.3.y, matrix.columns.3.z, matrix.columns.3.w
        ]
    }

    private func calculateBoneStatistics(session: VRMASession) -> [ProcessingCapture.BoneStatisticsCapture] {
        var boneAngles: [VRMHumanoidBone: [Float]] = [:]

        for frame in session.frames {
            guard let joints = frame.bodyJoints else { continue }
            for (bone, rotation) in joints {
                // Calculate angle from identity (how far from rest pose)
                let dot = abs(rotation.real)  // w component
                let angle = 2.0 * acos(min(1.0, dot)) * 180.0 / .pi
                boneAngles[bone, default: []].append(angle)
            }
        }

        return boneAngles.map { bone, angles in
            let minAngle = angles.min() ?? 0
            let maxAngle = angles.max() ?? 0
            let avgAngle = angles.reduce(0, +) / Float(max(1, angles.count))
            return ProcessingCapture.BoneStatisticsCapture(
                boneName: bone.rawValue,
                frameCount: angles.count,
                minAngle: minAngle,
                maxAngle: maxAngle,
                avgAngle: avgAngle
            )
        }.sorted { $0.boneName < $1.boneName }
    }

    private func createMetadata() -> PipelineDiagnosticsSession.SessionMetadata {
        let deviceModel: String
        let osVersion: String

        #if os(iOS) || os(tvOS)
        deviceModel = UIDevice.current.model
        osVersion = UIDevice.current.systemVersion
        #elseif os(macOS)
        deviceModel = "Mac"
        osVersion = ProcessInfo.processInfo.operatingSystemVersionString
        #else
        deviceModel = "Unknown"
        osVersion = "Unknown"
        #endif

        let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Unknown"

        return PipelineDiagnosticsSession.SessionMetadata(
            deviceModel: deviceModel,
            osVersion: osVersion,
            appVersion: appVersion
        )
    }
}
