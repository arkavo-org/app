#!/usr/bin/env swift
//
//  vrma-processor-test.swift
//  Test VRMAProcessor on a VRMA file
//

import Foundation
import simd

// MARK: - Minimal Types

enum VRMHumanoidBone: String, CaseIterable {
    case hips, spine, chest, upperChest, neck, head
    case leftShoulder, leftUpperArm, leftLowerArm, leftHand
    case rightShoulder, rightUpperArm, rightLowerArm, rightHand
    case leftUpperLeg, leftLowerLeg, leftFoot, leftToes
    case rightUpperLeg, rightLowerLeg, rightFoot, rightToes
    case leftEye, rightEye, jaw
}

struct VRMAFrame {
    let time: Float
    let faceBlendShapes: [String: Float]?
    let headTransform: simd_float4x4?
    let bodyJoints: [VRMHumanoidBone: simd_quatf]?
    let hipsTranslation: simd_float3?
}

struct VRMASession {
    let name: String
    let duration: Float
    let frameRate: Int
    let frames: [VRMAFrame]
    let createdAt: Date
}

// MARK: - VRMAProcessor

enum VRMAProcessor {
    struct Options {
        var smoothingFactor: Float = 0.3
        var outlierThreshold: Float = 45.0
        var calibrationFrames: Int = 0
        var normalizeQuaternions: Bool = true
        var maxOutlierRatio: Float = 0.3
        var minBodyFrameRatio: Float = 0.5
        static let `default` = Options()
    }

    enum ProcessingError: Error {
        case tooManyOutliers(ratio: Float, threshold: Float)
        case insufficientBodyData(ratio: Float, required: Float)
        case noFrames
        case allFramesInvalid
    }

    struct QualityReport {
        let inputFrames: Int
        let outputFrames: Int
        let outlierFrames: Int
        let bodyFrameRatio: Float
        let outlierRatio: Float
    }

    static func process(_ session: VRMASession, options: Options = .default) throws -> (VRMASession, QualityReport) {
        guard !session.frames.isEmpty else { throw ProcessingError.noFrames }

        var frames = session.frames
        let framesWithBody = frames.filter { $0.bodyJoints != nil && !($0.bodyJoints?.isEmpty ?? true) }.count
        let bodyFrameRatio = Float(framesWithBody) / Float(frames.count)

        if bodyFrameRatio < options.minBodyFrameRatio {
            throw ProcessingError.insufficientBodyData(ratio: bodyFrameRatio, required: options.minBodyFrameRatio)
        }

        var outlierCount = 0

        if options.outlierThreshold < 180 {
            let (processed, outliers) = removeOutliers(frames, threshold: options.outlierThreshold)
            frames = processed
            outlierCount = outliers
        }

        let outlierRatio = Float(outlierCount) / Float(session.frames.count)
        if outlierRatio > options.maxOutlierRatio {
            throw ProcessingError.tooManyOutliers(ratio: outlierRatio, threshold: options.maxOutlierRatio)
        }

        if options.normalizeQuaternions {
            frames = normalizeQuaternions(frames)
        }

        if options.smoothingFactor > 0 {
            frames = applySmoothing(frames, factor: options.smoothingFactor)
        }

        let processed = VRMASession(name: session.name, duration: session.duration,
                                    frameRate: session.frameRate, frames: frames, createdAt: session.createdAt)
        let report = QualityReport(inputFrames: session.frames.count, outputFrames: frames.count,
                                   outlierFrames: outlierCount, bodyFrameRatio: bodyFrameRatio, outlierRatio: outlierRatio)
        return (processed, report)
    }

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
                let dot = abs(simd_dot(rotation, prevRot))
                let angle = 2.0 * acos(min(1.0, dot))

                if angle > thresholdRadians {
                    if let nextRot = nextJoints[bone] {
                        currentJoints[bone] = simd_slerp(prevRot, nextRot, 0.5)
                        modified = true
                        frameIsOutlier = true
                    }
                }
            }
            if frameIsOutlier { outlierCount += 1 }
            if modified {
                result[i] = VRMAFrame(time: result[i].time, faceBlendShapes: result[i].faceBlendShapes,
                                      headTransform: result[i].headTransform, bodyJoints: currentJoints,
                                      hipsTranslation: result[i].hipsTranslation)
            }
        }
        return (result, outlierCount)
    }

    private static func normalizeQuaternions(_ frames: [VRMAFrame]) -> [VRMAFrame] {
        return frames.map { frame in
            guard var joints = frame.bodyJoints else { return frame }
            for (bone, rotation) in joints { joints[bone] = simd_normalize(rotation) }
            return VRMAFrame(time: frame.time, faceBlendShapes: frame.faceBlendShapes,
                            headTransform: frame.headTransform, bodyJoints: joints, hipsTranslation: frame.hipsTranslation)
        }
    }

    private static func applySmoothing(_ frames: [VRMAFrame], factor: Float) -> [VRMAFrame] {
        guard frames.count > 1 else { return frames }
        var result = frames
        var prevSmoothed: [VRMHumanoidBone: simd_quatf] = frames.first?.bodyJoints ?? [:]

        for i in 1..<frames.count {
            guard var currentJoints = result[i].bodyJoints else { continue }
            for (bone, rotation) in currentJoints {
                if let prev = prevSmoothed[bone] {
                    let smoothed = simd_slerp(prev, rotation, 1.0 - factor)
                    currentJoints[bone] = smoothed
                    prevSmoothed[bone] = smoothed
                } else {
                    prevSmoothed[bone] = rotation
                }
            }
            result[i] = VRMAFrame(time: result[i].time, faceBlendShapes: result[i].faceBlendShapes,
                                  headTransform: result[i].headTransform, bodyJoints: currentJoints,
                                  hipsTranslation: result[i].hipsTranslation)
        }
        return result
    }
}

// MARK: - VRMA Parser

func parseVRMA(at url: URL) -> VRMASession? {
    guard let data = try? Data(contentsOf: url), data.count >= 20 else { return nil }

    let jsonLength = data.withUnsafeBytes { $0.load(fromByteOffset: 12, as: UInt32.self) }
    let jsonData = data.subdata(in: 20..<(20 + Int(jsonLength)))
    guard let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any] else { return nil }

    let binOffset = 20 + Int(jsonLength)
    let binChunkLength = data.withUnsafeBytes { $0.load(fromByteOffset: binOffset, as: UInt32.self) }
    let binData = data.subdata(in: (binOffset + 8)..<(binOffset + 8 + Int(binChunkLength)))

    guard let accessors = json["accessors"] as? [[String: Any]],
          let bufferViews = json["bufferViews"] as? [[String: Any]],
          let animations = json["animations"] as? [[String: Any]],
          let animation = animations.first,
          let channels = animation["channels"] as? [[String: Any]],
          let samplers = animation["samplers"] as? [[String: Any]] else { return nil }

    guard let firstSampler = samplers.first,
          let timeAccessorIdx = firstSampler["input"] as? Int,
          timeAccessorIdx < accessors.count else { return nil }

    let timeAccessor = accessors[timeAccessorIdx]
    let frameCount = timeAccessor["count"] as? Int ?? 0
    let minTime = (timeAccessor["min"] as? [Double])?.first ?? 0
    let maxTime = (timeAccessor["max"] as? [Double])?.first ?? 0
    let duration = Float(maxTime - minTime)

    guard let timeBufferViewIdx = timeAccessor["bufferView"] as? Int,
          timeBufferViewIdx < bufferViews.count else { return nil }
    let timeBufferView = bufferViews[timeBufferViewIdx]
    let timeOffset = timeBufferView["byteOffset"] as? Int ?? 0

    var times: [Float] = []
    for i in 0..<frameCount {
        let offset = timeOffset + i * 4
        times.append(binData.withUnsafeBytes { $0.load(fromByteOffset: offset, as: Float.self) })
    }

    var nodeBoneMap: [Int: VRMHumanoidBone] = [:]
    if let ext = (json["extensions"] as? [String: Any])?["VRMC_vrm_animation"] as? [String: Any],
       let humanoid = ext["humanoid"] as? [String: Any],
       let humanBones = humanoid["humanBones"] as? [String: Any] {
        for (boneName, nodeInfo) in humanBones {
            if let bone = VRMHumanoidBone(rawValue: boneName),
               let nodeDict = nodeInfo as? [String: Any],
               let nodeIdx = nodeDict["node"] as? Int {
                nodeBoneMap[nodeIdx] = bone
            }
        }
    }

    var boneRotations: [VRMHumanoidBone: [simd_quatf]] = [:]
    var hipsTranslations: [simd_float3] = []

    for channel in channels {
        guard let target = channel["target"] as? [String: Any],
              let nodeIdx = target["node"] as? Int,
              let path = target["path"] as? String,
              let samplerIdx = channel["sampler"] as? Int,
              samplerIdx < samplers.count else { continue }

        let sampler = samplers[samplerIdx]
        guard let outputAccessorIdx = sampler["output"] as? Int,
              outputAccessorIdx < accessors.count else { continue }

        let outputAccessor = accessors[outputAccessorIdx]
        guard let bufferViewIdx = outputAccessor["bufferView"] as? Int,
              bufferViewIdx < bufferViews.count else { continue }

        let bufferView = bufferViews[bufferViewIdx]
        let byteOffset = bufferView["byteOffset"] as? Int ?? 0
        let count = outputAccessor["count"] as? Int ?? 0

        if path == "rotation", let bone = nodeBoneMap[nodeIdx] {
            var rotations: [simd_quatf] = []
            for i in 0..<count {
                let o = byteOffset + i * 16
                let x = binData.withUnsafeBytes { $0.load(fromByteOffset: o, as: Float.self) }
                let y = binData.withUnsafeBytes { $0.load(fromByteOffset: o + 4, as: Float.self) }
                let z = binData.withUnsafeBytes { $0.load(fromByteOffset: o + 8, as: Float.self) }
                let w = binData.withUnsafeBytes { $0.load(fromByteOffset: o + 12, as: Float.self) }
                rotations.append(simd_quatf(ix: x, iy: y, iz: z, r: w))
            }
            boneRotations[bone] = rotations
        } else if path == "translation" && nodeBoneMap[nodeIdx] == .hips {
            for i in 0..<count {
                let o = byteOffset + i * 12
                let x = binData.withUnsafeBytes { $0.load(fromByteOffset: o, as: Float.self) }
                let y = binData.withUnsafeBytes { $0.load(fromByteOffset: o + 4, as: Float.self) }
                let z = binData.withUnsafeBytes { $0.load(fromByteOffset: o + 8, as: Float.self) }
                hipsTranslations.append(simd_float3(x, y, z))
            }
        }
    }

    var frames: [VRMAFrame] = []
    for i in 0..<frameCount {
        var joints: [VRMHumanoidBone: simd_quatf] = [:]
        for (bone, rots) in boneRotations where i < rots.count { joints[bone] = rots[i] }
        let hips = i < hipsTranslations.count ? hipsTranslations[i] : nil
        frames.append(VRMAFrame(time: times[i], faceBlendShapes: nil, headTransform: nil,
                               bodyJoints: joints.isEmpty ? nil : joints, hipsTranslation: hips))
    }

    let fps = duration > 0 ? Int(Float(frameCount) / duration) : 30
    return VRMASession(name: url.deletingPathExtension().lastPathComponent, duration: duration,
                       frameRate: fps, frames: frames, createdAt: Date())
}

// MARK: - Jitter Analysis

func analyzeJitter(_ frames: [VRMAFrame], _ bone: VRMHumanoidBone) -> (avg: Float, max: Float, count: Int) {
    var deltas: [Float] = []
    var jitterCount = 0
    let threshold: Float = 5.0 * .pi / 180.0

    for i in 1..<frames.count {
        guard let curr = frames[i].bodyJoints?[bone], let prev = frames[i-1].bodyJoints?[bone] else { continue }
        let dot = abs(simd_dot(curr, prev))
        let angle = 2.0 * acos(min(1.0, dot))
        deltas.append(angle * 180.0 / .pi)
        if angle > threshold { jitterCount += 1 }
    }

    let avg = deltas.isEmpty ? 0 : deltas.reduce(0, +) / Float(deltas.count)
    return (avg, deltas.max() ?? 0, jitterCount)
}

// MARK: - Main

let path = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "/Users/arkavo/Projects/Muse/Muse/Resources/VRMA/latest.vrma"
let url = URL(fileURLWithPath: path)

print("======================================================================")
print("VRMA PROCESSOR TEST")
print("======================================================================")
print("File: \(url.lastPathComponent)")

guard let session = parseVRMA(at: url) else {
    print("ERROR: Failed to parse VRMA")
    exit(1)
}

print("\n--- INPUT SESSION ---")
print("Frames:   \(session.frames.count)")
print("Duration: \(session.duration)s")
print("FPS:      \(session.frameRate)")

let bones = session.frames.first?.bodyJoints?.keys.sorted { $0.rawValue < $1.rawValue } ?? []
print("Bones:    \(bones.count)")

print("\n--- PRE-PROCESSING JITTER ---")
var totalBefore = 0
for bone in bones {
    let (avg, maxVal, count) = analyzeJitter(session.frames, bone)
    totalBefore += count
    if count > 0 {
        print("  \(bone.rawValue): avg=\(avg)° max=\(maxVal)° jitter=\(count)")
    }
}
print("  TOTAL jitter frames: \(totalBefore)")

print("\n--- PROCESSING (smoothing=0.3, outlierThreshold=45°) ---")

do {
    let (processed, report) = try VRMAProcessor.process(session, options: .default)

    print("\n--- QUALITY REPORT ---")
    print("Input frames:     \(report.inputFrames)")
    print("Output frames:    \(report.outputFrames)")
    print("Body frame ratio: \(Int(report.bodyFrameRatio * 100))%")
    print("Outlier frames:   \(report.outlierFrames) (\(Int(report.outlierRatio * 100))%)")
    print("Status:           PASSED")

    print("\n--- POST-PROCESSING JITTER ---")
    var totalAfter = 0
    for bone in bones {
        let (avg, maxVal, count) = analyzeJitter(processed.frames, bone)
        totalAfter += count
        if count > 0 {
            print("  \(bone.rawValue): avg=\(avg)° max=\(maxVal)° jitter=\(count)")
        }
    }
    print("  TOTAL jitter frames: \(totalAfter)")

    print("\n--- SUMMARY ---")
    print("Jitter reduced: \(totalBefore) -> \(totalAfter)")
    if totalBefore > 0 {
        let reduction = Float(totalBefore - totalAfter) / Float(totalBefore) * 100
        print("Reduction:      \(Int(reduction))%")
    }
    print("Outliers fixed: \(report.outlierFrames)")

} catch {
    print("\nERROR: \(error)")
    print("Status: FAILED")
}

print("\n======================================================================")
