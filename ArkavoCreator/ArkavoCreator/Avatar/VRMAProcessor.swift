//
//  VRMAProcessor.swift
//  ArkavoCreator
//
//  Post-processes VRMASession to clean up motion capture data before export.
//  Processing steps: T-pose calibration, outlier removal, quaternion normalization, EMA smoothing.
//

import Foundation
import simd
import VRMMetalKit

/// Post-processes VRMASession to clean up motion capture data
public enum VRMAProcessor {

    // MARK: - Options

    /// Processing options
    public struct Options: Sendable {
        /// Apply EMA smoothing to rotations (0 = off, higher = more smoothing)
        public var smoothingFactor: Float = 0.3

        /// Remove frames with rotation angle > threshold from previous frame (degrees)
        public var outlierThreshold: Float = 45.0

        /// Use first N frames as T-pose reference for calibration (0 = disabled)
        public var calibrationFrames: Int = 0

        /// Normalize all quaternions
        public var normalizeQuaternions: Bool = true

        /// Maximum allowed outlier ratio before failing (0.0 - 1.0)
        public var maxOutlierRatio: Float = 0.3

        /// Minimum required frames with body data (0.0 - 1.0)
        public var minBodyFrameRatio: Float = 0.5

        public init(
            smoothingFactor: Float = 0.3,
            outlierThreshold: Float = 45.0,
            calibrationFrames: Int = 0,
            normalizeQuaternions: Bool = true,
            maxOutlierRatio: Float = 0.3,
            minBodyFrameRatio: Float = 0.5
        ) {
            self.smoothingFactor = smoothingFactor
            self.outlierThreshold = outlierThreshold
            self.calibrationFrames = calibrationFrames
            self.normalizeQuaternions = normalizeQuaternions
            self.maxOutlierRatio = maxOutlierRatio
            self.minBodyFrameRatio = minBodyFrameRatio
        }

        /// Default processing options
        public static let `default` = Options()

        /// No processing - pass through raw data
        public static let none = Options(
            smoothingFactor: 0,
            outlierThreshold: 180,
            calibrationFrames: 0,
            normalizeQuaternions: false,
            maxOutlierRatio: 1.0,
            minBodyFrameRatio: 0.0
        )
    }

    // MARK: - Errors

    /// Processing errors
    public enum ProcessingError: LocalizedError {
        case tooManyOutliers(ratio: Float, threshold: Float)
        case insufficientBodyData(ratio: Float, required: Float)
        case noFrames
        case allFramesInvalid

        public var errorDescription: String? {
            switch self {
            case .tooManyOutliers(let ratio, let threshold):
                return "Too many outlier frames: \(Int(ratio * 100))% (max \(Int(threshold * 100))%)"
            case .insufficientBodyData(let ratio, let required):
                return "Insufficient body tracking: \(Int(ratio * 100))% (need \(Int(required * 100))%)"
            case .noFrames:
                return "No frames captured"
            case .allFramesInvalid:
                return "All frames failed validation"
            }
        }
    }

    // MARK: - Quality Report

    /// Quality report from processing
    public struct QualityReport {
        /// Number of input frames
        public let inputFrames: Int

        /// Number of output frames after processing
        public let outputFrames: Int

        /// Number of frames identified as outliers
        public let outlierFrames: Int

        /// Ratio of frames with body data (0.0 - 1.0)
        public let bodyFrameRatio: Float

        /// Ratio of outlier frames (0.0 - 1.0)
        public let outlierRatio: Float

        /// Human-readable summary
        public var summary: String {
            "Frames: \(inputFrames)->\(outputFrames), Body: \(Int(bodyFrameRatio * 100))%, Outliers: \(Int(outlierRatio * 100))%"
        }
    }

    // MARK: - Processing

    /// Process a recorded session - throws if quality is too low
    /// - Parameters:
    ///   - session: The raw recorded session
    ///   - options: Processing options
    /// - Returns: Tuple of processed session and quality report
    /// - Throws: ProcessingError if quality validation fails
    public static func process(_ session: VRMASession, options: Options = .default) throws -> (VRMASession, QualityReport) {
        guard !session.frames.isEmpty else {
            throw ProcessingError.noFrames
        }

        var frames = session.frames

        // Count frames with body data
        let framesWithBody = frames.filter { $0.bodyJoints != nil && !($0.bodyJoints?.isEmpty ?? true) }.count
        let bodyFrameRatio = Float(framesWithBody) / Float(frames.count)

        // Validate minimum body data
        if bodyFrameRatio < options.minBodyFrameRatio {
            throw ProcessingError.insufficientBodyData(ratio: bodyFrameRatio, required: options.minBodyFrameRatio)
        }

        // Track outliers for reporting
        var outlierCount = 0

        // Step 1: T-Pose Calibration
        if options.calibrationFrames > 0 {
            frames = applyCalibration(frames, calibrationCount: options.calibrationFrames)
        }

        // Step 2: Outlier Removal
        if options.outlierThreshold < 180 {
            let (processedFrames, outliers) = removeOutliers(frames, threshold: options.outlierThreshold)
            frames = processedFrames
            outlierCount = outliers
        }

        // Calculate outlier ratio
        let outlierRatio = Float(outlierCount) / Float(session.frames.count)

        // Validate outlier ratio
        if outlierRatio > options.maxOutlierRatio {
            throw ProcessingError.tooManyOutliers(ratio: outlierRatio, threshold: options.maxOutlierRatio)
        }

        // Step 3: Quaternion Normalization
        if options.normalizeQuaternions {
            frames = normalizeQuaternions(frames)
        }

        // Step 4: EMA Smoothing
        if options.smoothingFactor > 0 {
            frames = applySmoothing(frames, factor: options.smoothingFactor)
        }

        // Verify we have valid frames
        let validFrames = frames.filter { $0.bodyJoints != nil || $0.faceBlendShapes != nil }
        guard !validFrames.isEmpty else {
            throw ProcessingError.allFramesInvalid
        }

        let processedSession = VRMASession(
            name: session.name,
            duration: session.duration,
            frameRate: session.frameRate,
            frames: frames,
            createdAt: session.createdAt
        )

        let report = QualityReport(
            inputFrames: session.frames.count,
            outputFrames: frames.count,
            outlierFrames: outlierCount,
            bodyFrameRatio: bodyFrameRatio,
            outlierRatio: outlierRatio
        )

        return (processedSession, report)
    }

    // MARK: - Calibration

    /// Apply T-pose calibration using first N frames as reference
    /// - Parameters:
    ///   - frames: Input frames
    ///   - calibrationCount: Number of frames to use for calibration
    /// - Returns: Calibrated frames
    private static func applyCalibration(_ frames: [VRMAFrame], calibrationCount: Int) -> [VRMAFrame] {
        let calibrationEnd = min(calibrationCount, frames.count)
        guard calibrationEnd > 0 else { return frames }

        // Compute average rotation per bone from calibration frames
        var referenceRotations: [VRMHumanoidBone: simd_quatf] = [:]
        var boneCounts: [VRMHumanoidBone: Int] = [:]

        for i in 0..<calibrationEnd {
            guard let joints = frames[i].bodyJoints else { continue }
            for (bone, rotation) in joints {
                if let existing = referenceRotations[bone] {
                    // Average quaternions using slerp
                    let count = Float(boneCounts[bone] ?? 1)
                    let t = 1.0 / (count + 1.0)
                    referenceRotations[bone] = simd_slerp(existing, rotation, t)
                    boneCounts[bone] = (boneCounts[bone] ?? 1) + 1
                } else {
                    referenceRotations[bone] = rotation
                    boneCounts[bone] = 1
                }
            }
        }

        // Apply inverse reference to all frames (skip calibration frames)
        return frames.enumerated().map { index, frame in
            guard index >= calibrationEnd, var joints = frame.bodyJoints else {
                return frame
            }

            for (bone, rotation) in joints {
                if let reference = referenceRotations[bone] {
                    // delta = inverse(reference) * rotation
                    joints[bone] = simd_mul(simd_inverse(reference), rotation)
                }
            }

            return VRMAFrame(
                time: frame.time,
                faceBlendShapes: frame.faceBlendShapes,
                headTransform: frame.headTransform,
                bodyJoints: joints,
                hipsTranslation: frame.hipsTranslation
            )
        }
    }

    // MARK: - Outlier Removal

    /// Remove outlier frames by interpolating from neighbors
    /// - Parameters:
    ///   - frames: Input frames
    ///   - threshold: Angular threshold in degrees
    /// - Returns: Tuple of processed frames and outlier count
    private static func removeOutliers(_ frames: [VRMAFrame], threshold: Float) -> ([VRMAFrame], Int) {
        let thresholdRadians = threshold * .pi / 180.0
        var result = frames
        var outlierCount = 0

        for i in 1..<(frames.count - 1) {
            guard var currentJoints = result[i].bodyJoints,
                  let prevJoints = result[i - 1].bodyJoints,
                  let nextJoints = result[i + 1].bodyJoints else { continue }

            var modified = false
            var frameIsOutlier = false

            for (bone, rotation) in currentJoints {
                guard let prevRot = prevJoints[bone] else { continue }

                // Calculate angular difference
                let dot = abs(simd_dot(rotation, prevRot))
                let angle = 2.0 * acos(min(1.0, dot))

                if angle > thresholdRadians {
                    // Interpolate from neighbors
                    if let nextRot = nextJoints[bone] {
                        currentJoints[bone] = simd_slerp(prevRot, nextRot, 0.5)
                        modified = true
                        frameIsOutlier = true
                    }
                }
            }

            if frameIsOutlier {
                outlierCount += 1
            }

            if modified {
                result[i] = VRMAFrame(
                    time: result[i].time,
                    faceBlendShapes: result[i].faceBlendShapes,
                    headTransform: result[i].headTransform,
                    bodyJoints: currentJoints,
                    hipsTranslation: result[i].hipsTranslation
                )
            }
        }

        return (result, outlierCount)
    }

    // MARK: - Normalization

    /// Normalize all quaternions to unit length
    /// - Parameter frames: Input frames
    /// - Returns: Frames with normalized quaternions
    private static func normalizeQuaternions(_ frames: [VRMAFrame]) -> [VRMAFrame] {
        return frames.map { frame in
            guard var joints = frame.bodyJoints else { return frame }

            for (bone, rotation) in joints {
                joints[bone] = simd_normalize(rotation)
            }

            return VRMAFrame(
                time: frame.time,
                faceBlendShapes: frame.faceBlendShapes,
                headTransform: frame.headTransform,
                bodyJoints: joints,
                hipsTranslation: frame.hipsTranslation
            )
        }
    }

    // MARK: - Smoothing

    /// Apply exponential moving average smoothing to rotations
    /// - Parameters:
    ///   - frames: Input frames
    ///   - factor: Smoothing factor (0 = no smoothing, higher = more smoothing)
    /// - Returns: Smoothed frames
    private static func applySmoothing(_ frames: [VRMAFrame], factor: Float) -> [VRMAFrame] {
        guard frames.count > 1 else { return frames }

        var result = frames
        var previousSmoothed: [VRMHumanoidBone: simd_quatf] = [:]

        // Initialize with first frame
        if let firstJoints = frames.first?.bodyJoints {
            previousSmoothed = firstJoints
        }

        for i in 1..<frames.count {
            guard var currentJoints = result[i].bodyJoints else { continue }

            for (bone, rotation) in currentJoints {
                if let prevSmoothed = previousSmoothed[bone] {
                    // EMA: smoothed = slerp(prevSmoothed, current, 1 - factor)
                    let smoothed = simd_slerp(prevSmoothed, rotation, 1.0 - factor)
                    currentJoints[bone] = smoothed
                    previousSmoothed[bone] = smoothed
                } else {
                    previousSmoothed[bone] = rotation
                }
            }

            result[i] = VRMAFrame(
                time: result[i].time,
                faceBlendShapes: result[i].faceBlendShapes,
                headTransform: result[i].headTransform,
                bodyJoints: currentJoints,
                hipsTranslation: result[i].hipsTranslation
            )
        }

        return result
    }
}
