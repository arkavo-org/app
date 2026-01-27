//
//  VRMAExporter.swift
//  ArkavoCreator
//
//  Exports motion capture sessions to VRMA format (GLB with VRMC_vrm_animation extension).
//  VRMA is the industry standard for VRM animations, compatible with Unity, VSeeFace, VRoid, etc.
//

import Foundation
import simd
import VRMMetalKit

/// Error types for VRMA export
public enum VRMAExportError: LocalizedError {
    case noFrames
    case serializationFailed(String)
    case fileWriteFailed(String)

    public var errorDescription: String? {
        switch self {
        case .noFrames:
            return "Cannot export: session has no frames"
        case .serializationFailed(let reason):
            return "VRMA serialization failed: \(reason)"
        case .fileWriteFailed(let reason):
            return "Failed to write VRMA file: \(reason)"
        }
    }
}

/// Exports VRMASession to VRMA format
public enum VRMAExporter {

    // MARK: - Public API

    /// Export recorded motion to VRMA Data
    /// - Parameters:
    ///   - session: The motion capture session to export
    ///   - restPose: Optional VRM model to extract rest pose from (uses T-pose if nil)
    /// - Returns: GLB-formatted Data with VRMC_vrm_animation extension
    public static func export(session: VRMASession, restPose: VRMModel? = nil) throws -> Data {
        guard !session.frames.isEmpty else {
            throw VRMAExportError.noFrames
        }

        // Build the glTF/VRMA JSON structure
        let vrmaJSON = try buildVRMAJSON(session: session, restPose: restPose)

        // Build binary buffer (keyframe data)
        let binaryData = buildBinaryBuffer(session: session)

        // Create GLB file
        let glbData = try createGLB(json: vrmaJSON, binaryData: binaryData)

        return glbData
    }

    /// Export recorded motion to VRMA file
    /// - Parameters:
    ///   - session: The motion capture session to export
    ///   - url: Destination file URL
    ///   - restPose: Optional VRM model to extract rest pose from (uses T-pose if nil)
    public static func export(session: VRMASession, to url: URL, restPose: VRMModel? = nil) throws {
        let data = try export(session: session, restPose: restPose)

        do {
            try data.write(to: url)
            print("[VRMAExporter] Wrote \(data.count) bytes to \(url.lastPathComponent)")
        } catch {
            throw VRMAExportError.fileWriteFailed(error.localizedDescription)
        }
    }

    // MARK: - JSON Building

    private static func buildVRMAJSON(session: VRMASession, restPose: VRMModel?) throws -> [String: Any] {
        var gltf: [String: Any] = [:]

        // Asset info
        gltf["asset"] = [
            "version": "2.0",
            "generator": "ArkavoCreator VRMAExporter"
        ]

        // Determine which bones have animation data
        let animatedBones = collectAnimatedBones(session: session)
        let hasExpressions = session.frames.first?.faceBlendShapes != nil
        let expressionKeys = hasExpressions ? collectExpressionKeys(session: session) : []

        // Build nodes (skeleton hierarchy + expression nodes)
        let (nodes, humanBoneNodeMap, expressionNodeMap) = buildNodes(
            animatedBones: animatedBones,
            expressionKeys: expressionKeys,
            restPose: restPose
        )
        gltf["nodes"] = nodes

        // Build scene referencing root node
        gltf["scenes"] = [["nodes": [0]]]
        gltf["scene"] = 0

        // Build buffer views and accessors for animation data
        let (bufferViews, accessors, bufferByteLength) = buildAccessors(
            session: session,
            animatedBones: animatedBones,
            expressionKeys: expressionKeys
        )
        gltf["bufferViews"] = bufferViews
        gltf["accessors"] = accessors

        // Single buffer for all animation data
        gltf["buffers"] = [["byteLength": bufferByteLength]]

        // Build animation
        let animation = buildAnimation(
            session: session,
            animatedBones: animatedBones,
            humanBoneNodeMap: humanBoneNodeMap,
            expressionKeys: expressionKeys,
            expressionNodeMap: expressionNodeMap
        )
        gltf["animations"] = [animation]

        // Build VRMC_vrm_animation extension
        var extensions: [String: Any] = [:]
        extensions["VRMC_vrm_animation"] = buildVRMAExtension(
            animatedBones: animatedBones,
            humanBoneNodeMap: humanBoneNodeMap,
            expressionKeys: expressionKeys,
            expressionNodeMap: expressionNodeMap
        )
        gltf["extensions"] = extensions

        gltf["extensionsUsed"] = ["VRMC_vrm_animation"]

        return gltf
    }

    /// Collect all bones that have animation data
    private static func collectAnimatedBones(session: VRMASession) -> [VRMHumanoidBone] {
        var bones = Set<VRMHumanoidBone>()

        for frame in session.frames {
            if let joints = frame.bodyJoints {
                for bone in joints.keys {
                    bones.insert(bone)
                }
            }
            // Include head bone if we have head transform from face tracking
            if frame.headTransform != nil {
                bones.insert(.head)
                bones.insert(.neck)  // Also animate neck for natural head movement
            }
        }

        // Sort for consistent ordering
        return bones.sorted { $0.rawValue < $1.rawValue }
    }

    /// Build node hierarchy for skeleton and expressions
    private static func buildNodes(
        animatedBones: [VRMHumanoidBone],
        expressionKeys: [String],
        restPose: VRMModel?
    ) -> ([[String: Any]], [VRMHumanoidBone: Int], [String: Int]) {
        var nodes: [[String: Any]] = []
        var humanBoneNodeMap: [VRMHumanoidBone: Int] = [:]
        var expressionNodeMap: [String: Int] = [:]

        // Always include hips as root even if not animated (or a root node for expressions-only)
        let allBones: [VRMHumanoidBone] = animatedBones.isEmpty ? [] : Array(Set(animatedBones + [.hips])).sorted { $0.rawValue < $1.rawValue }

        // If no bones but have expressions, create a root node
        if allBones.isEmpty && !expressionKeys.isEmpty {
            nodes.append([
                "name": "root",
                "translation": [0, 0, 0],
                "rotation": [0, 0, 0, 1]
            ])
        }

        // Add humanoid bone nodes
        for bone in allBones {
            let nodeIndex = nodes.count
            humanBoneNodeMap[bone] = nodeIndex

            var node: [String: Any] = [
                "name": bone.rawValue
            ]

            // Set rest pose rotation (identity/T-pose if no model provided)
            if let model = restPose,
               let humanoid = model.humanoid,
               let humanBone = humanoid.humanBones[bone],
               humanBone.node < model.nodes.count {
                let vrmNode = model.nodes[humanBone.node]
                node["rotation"] = [
                    vrmNode.rotation.imag.x,
                    vrmNode.rotation.imag.y,
                    vrmNode.rotation.imag.z,
                    vrmNode.rotation.real
                ]
                node["translation"] = [
                    vrmNode.translation.x,
                    vrmNode.translation.y,
                    vrmNode.translation.z
                ]
            } else {
                // T-pose default
                node["rotation"] = [0, 0, 0, 1]
                node["translation"] = [0, 0, 0]
            }

            nodes.append(node)
        }

        // Add expression nodes (VRMA uses translation.x for expression weight)
        for key in expressionKeys {
            let nodeIndex = nodes.count
            expressionNodeMap[key] = nodeIndex

            nodes.append([
                "name": "Expression_\(key)",
                "translation": [0, 0, 0]  // x will be animated for weight
            ])
        }

        return (nodes, humanBoneNodeMap, expressionNodeMap)
    }

    /// Build buffer views and accessors for animation keyframes
    private static func buildAccessors(
        session: VRMASession,
        animatedBones: [VRMHumanoidBone],
        expressionKeys: [String]
    ) -> ([[String: Any]], [[String: Any]], Int) {
        var bufferViews: [[String: Any]] = []
        var accessors: [[String: Any]] = []
        var byteOffset = 0

        let frameCount = session.frames.count

        // Time accessor (shared by all channels)
        let timeByteLength = frameCount * MemoryLayout<Float>.size
        bufferViews.append([
            "buffer": 0,
            "byteOffset": byteOffset,
            "byteLength": timeByteLength
        ])
        accessors.append([
            "bufferView": bufferViews.count - 1,
            "componentType": 5126, // FLOAT
            "count": frameCount,
            "type": "SCALAR",
            "min": [0.0],
            "max": [Double(session.duration)]
        ])
        byteOffset += timeByteLength

        // Rotation accessors for each bone (VEC4 quaternions)
        for _ in animatedBones {
            let quatByteLength = frameCount * 4 * MemoryLayout<Float>.size
            bufferViews.append([
                "buffer": 0,
                "byteOffset": byteOffset,
                "byteLength": quatByteLength
            ])
            accessors.append([
                "bufferView": bufferViews.count - 1,
                "componentType": 5126, // FLOAT
                "count": frameCount,
                "type": "VEC4"
            ])
            byteOffset += quatByteLength
        }

        // Hips translation accessor (if we have body data)
        if animatedBones.contains(.hips) {
            let translationByteLength = frameCount * 3 * MemoryLayout<Float>.size
            bufferViews.append([
                "buffer": 0,
                "byteOffset": byteOffset,
                "byteLength": translationByteLength
            ])
            accessors.append([
                "bufferView": bufferViews.count - 1,
                "componentType": 5126, // FLOAT
                "count": frameCount,
                "type": "VEC3"
            ])
            byteOffset += translationByteLength
        }

        // Expression translation accessors (VEC3 per expression, x = weight)
        for _ in expressionKeys {
            let translationByteLength = frameCount * 3 * MemoryLayout<Float>.size
            bufferViews.append([
                "buffer": 0,
                "byteOffset": byteOffset,
                "byteLength": translationByteLength
            ])
            accessors.append([
                "bufferView": bufferViews.count - 1,
                "componentType": 5126, // FLOAT
                "count": frameCount,
                "type": "VEC3"
            ])
            byteOffset += translationByteLength
        }

        return (bufferViews, accessors, byteOffset)
    }

    /// Collect all unique expression keys from session
    private static func collectExpressionKeys(session: VRMASession) -> [String] {
        var keys = Set<String>()
        for frame in session.frames {
            if let shapes = frame.faceBlendShapes {
                for key in shapes.keys {
                    keys.insert(key)
                }
            }
        }
        return keys.sorted()
    }

    /// Build animation channels and samplers
    private static func buildAnimation(
        session: VRMASession,
        animatedBones: [VRMHumanoidBone],
        humanBoneNodeMap: [VRMHumanoidBone: Int],
        expressionKeys: [String],
        expressionNodeMap: [String: Int]
    ) -> [String: Any] {
        var channels: [[String: Any]] = []
        var samplers: [[String: Any]] = []

        // Time accessor is always index 0
        let timeAccessorIndex = 0
        var outputAccessorIndex = 1

        // Rotation channels for each bone
        for bone in animatedBones {
            guard let nodeIndex = humanBoneNodeMap[bone] else { continue }

            samplers.append([
                "input": timeAccessorIndex,
                "output": outputAccessorIndex,
                "interpolation": "LINEAR"
            ])

            channels.append([
                "sampler": samplers.count - 1,
                "target": [
                    "node": nodeIndex,
                    "path": "rotation"
                ]
            ])

            outputAccessorIndex += 1
        }

        // Hips translation channel
        if animatedBones.contains(.hips), let hipsNodeIndex = humanBoneNodeMap[.hips] {
            samplers.append([
                "input": timeAccessorIndex,
                "output": outputAccessorIndex,
                "interpolation": "LINEAR"
            ])

            channels.append([
                "sampler": samplers.count - 1,
                "target": [
                    "node": hipsNodeIndex,
                    "path": "translation"
                ]
            ])

            outputAccessorIndex += 1
        }

        // Expression channels (translation.x = weight on dedicated expression nodes)
        for key in expressionKeys {
            guard let nodeIndex = expressionNodeMap[key] else { continue }

            samplers.append([
                "input": timeAccessorIndex,
                "output": outputAccessorIndex,
                "interpolation": "LINEAR"
            ])

            channels.append([
                "sampler": samplers.count - 1,
                "target": [
                    "node": nodeIndex,
                    "path": "translation"
                ]
            ])

            outputAccessorIndex += 1
        }

        return [
            "name": session.name,
            "channels": channels,
            "samplers": samplers
        ]
    }

    /// Build VRMC_vrm_animation extension data
    private static func buildVRMAExtension(
        animatedBones: [VRMHumanoidBone],
        humanBoneNodeMap: [VRMHumanoidBone: Int],
        expressionKeys: [String],
        expressionNodeMap: [String: Int]
    ) -> [String: Any] {
        var extension_: [String: Any] = [
            "specVersion": "1.0"
        ]

        // Humanoid bone mapping
        var humanBones: [String: Any] = [:]
        for bone in animatedBones {
            if let nodeIndex = humanBoneNodeMap[bone] {
                humanBones[bone.rawValue] = ["node": nodeIndex]
            }
        }
        extension_["humanoid"] = ["humanBones": humanBones]

        // Expression mapping
        if !expressionKeys.isEmpty {
            var preset: [String: Any] = [:]
            var custom: [String: Any] = [:]

            // Map ARKit blend shapes to VRM preset expressions
            // Keys are in camelCase format after ARKitDataConverter conversion
            let arkitToVRMPreset: [String: String] = [
                // Blink
                "eyeBlinkLeft": "blinkLeft",
                "eyeBlinkRight": "blinkRight",
                // Happy (smile)
                "mouthSmileLeft": "happy",
                "mouthSmileRight": "happy",
                // Angry (brow down)
                "browDownLeft": "angry",
                "browDownRight": "angry",
                // Sad (frown)
                "mouthFrownLeft": "sad",
                "mouthFrownRight": "sad",
                // Surprised (wide eyes)
                "eyeWideLeft": "surprised",
                "eyeWideRight": "surprised",
                // Mouth shapes for lip sync
                "jawOpen": "aa",
                "mouthPucker": "ou",
                "mouthFunnel": "ou"
            ]

            for key in expressionKeys {
                guard let nodeIndex = expressionNodeMap[key] else { continue }

                if let presetName = arkitToVRMPreset[key] {
                    // Only use first ARKit shape for each VRM preset
                    if preset[presetName] == nil {
                        preset[presetName] = ["node": nodeIndex]
                    }
                } else {
                    // All other ARKit shapes go to custom
                    custom[key] = ["node": nodeIndex]
                }
            }

            extension_["expressions"] = [
                "preset": preset,
                "custom": custom
            ]
        }

        return extension_
    }

    // MARK: - Binary Buffer Building

    /// Build binary buffer containing all keyframe data
    private static func buildBinaryBuffer(session: VRMASession) -> Data {
        var buffer = Data()
        let animatedBones = collectAnimatedBones(session: session)
        let expressionKeys = session.frames.first?.faceBlendShapes != nil ? collectExpressionKeys(session: session) : []

        // Write time values
        for frame in session.frames {
            var time = frame.time
            buffer.append(Data(bytes: &time, count: MemoryLayout<Float>.size))
        }

        // Write rotation values for each bone
        for bone in animatedBones {
            for frame in session.frames {
                var quat: simd_quatf

                if let bodyQuat = frame.bodyJoints?[bone] {
                    // Use body tracking data if available
                    quat = bodyQuat
                } else if (bone == .head || bone == .neck), let headTransform = frame.headTransform {
                    // Extract rotation from face tracking head transform
                    let rawQuat = extractRotation(from: headTransform)
                    // Convert ARKit to glTF (negate Z for axis flip)
                    quat = simd_quatf(
                        ix: rawQuat.imag.x,
                        iy: rawQuat.imag.y,
                        iz: -rawQuat.imag.z,
                        r: rawQuat.real
                    )
                    // Neck gets partial rotation (30% of head)
                    if bone == .neck {
                        quat = simd_slerp(simd_quatf(ix: 0, iy: 0, iz: 0, r: 1), quat, 0.3)
                    }
                } else {
                    quat = simd_quatf(ix: 0, iy: 0, iz: 0, r: 1)
                }

                // glTF quaternion order: x, y, z, w
                var x = quat.imag.x
                var y = quat.imag.y
                var z = quat.imag.z
                var w = quat.real
                buffer.append(Data(bytes: &x, count: MemoryLayout<Float>.size))
                buffer.append(Data(bytes: &y, count: MemoryLayout<Float>.size))
                buffer.append(Data(bytes: &z, count: MemoryLayout<Float>.size))
                buffer.append(Data(bytes: &w, count: MemoryLayout<Float>.size))
            }
        }

        // Write hips translation values
        if animatedBones.contains(.hips) {
            for frame in session.frames {
                var translation = frame.hipsTranslation ?? simd_float3(0, 0, 0)
                buffer.append(Data(bytes: &translation.x, count: MemoryLayout<Float>.size))
                buffer.append(Data(bytes: &translation.y, count: MemoryLayout<Float>.size))
                buffer.append(Data(bytes: &translation.z, count: MemoryLayout<Float>.size))
            }
        }

        // Write expression translation values (x = weight, y = 0, z = 0)
        for key in expressionKeys {
            for frame in session.frames {
                var weight = frame.faceBlendShapes?[key] ?? 0.0
                var zero: Float = 0.0
                buffer.append(Data(bytes: &weight, count: MemoryLayout<Float>.size))
                buffer.append(Data(bytes: &zero, count: MemoryLayout<Float>.size))
                buffer.append(Data(bytes: &zero, count: MemoryLayout<Float>.size))
            }
        }

        return buffer
    }

    // MARK: - GLB Creation

    private static func createGLB(json: [String: Any], binaryData: Data) throws -> Data {
        // GLB structure:
        // Header (12 bytes):
        //   - magic: 0x46546C67 ("glTF")
        //   - version: 2
        //   - length: total file size
        // JSON chunk:
        //   - chunkLength
        //   - chunkType: 0x4E4F534A ("JSON")
        //   - chunkData (padded to 4-byte boundary with spaces)
        // BIN chunk:
        //   - chunkLength
        //   - chunkType: 0x004E4942 ("BIN\0")
        //   - chunkData (padded to 4-byte boundary with zeros)

        // Serialize JSON
        let jsonData: Data
        do {
            jsonData = try JSONSerialization.data(withJSONObject: json, options: [.sortedKeys])
        } catch {
            throw VRMAExportError.serializationFailed(error.localizedDescription)
        }

        // Pad JSON to 4-byte boundary with spaces (0x20)
        let jsonPadding = (4 - (jsonData.count % 4)) % 4
        var paddedJSON = jsonData
        if jsonPadding > 0 {
            paddedJSON.append(Data(repeating: 0x20, count: jsonPadding))
        }

        // Pad binary data to 4-byte boundary with zeros (0x00)
        let binaryPadding = (4 - (binaryData.count % 4)) % 4
        var paddedBinary = binaryData
        if binaryPadding > 0 {
            paddedBinary.append(Data(repeating: 0x00, count: binaryPadding))
        }

        // Calculate total length
        let headerLength = 12
        let jsonChunkHeaderLength = 8
        let binaryChunkHeaderLength = 8
        let totalLength = headerLength + jsonChunkHeaderLength + paddedJSON.count + binaryChunkHeaderLength + paddedBinary.count

        // Build GLB
        var glbData = Data()

        // Header
        glbData.append(littleEndianUInt32(0x46546C67)) // magic "glTF"
        glbData.append(littleEndianUInt32(2)) // version 2
        glbData.append(littleEndianUInt32(UInt32(totalLength))) // total length

        // JSON chunk header
        glbData.append(littleEndianUInt32(UInt32(paddedJSON.count))) // chunk length
        glbData.append(littleEndianUInt32(0x4E4F534A)) // chunk type "JSON"

        // JSON chunk data
        glbData.append(paddedJSON)

        // Binary chunk
        glbData.append(littleEndianUInt32(UInt32(paddedBinary.count))) // chunk length
        glbData.append(littleEndianUInt32(0x004E4942)) // chunk type "BIN\0"
        glbData.append(paddedBinary)

        return glbData
    }

    /// Convert UInt32 to little-endian Data
    private static func littleEndianUInt32(_ value: UInt32) -> Data {
        var value = value.littleEndian
        return Data(bytes: &value, count: MemoryLayout<UInt32>.size)
    }

    /// Extract rotation quaternion from a 4x4 transform matrix
    private static func extractRotation(from transform: simd_float4x4) -> simd_quatf {
        let col0 = simd_float3(transform.columns.0.x, transform.columns.0.y, transform.columns.0.z)
        let col1 = simd_float3(transform.columns.1.x, transform.columns.1.y, transform.columns.1.z)
        let col2 = simd_float3(transform.columns.2.x, transform.columns.2.y, transform.columns.2.z)

        // Normalize columns to remove scale
        let x = simd_normalize(col0)
        let y = simd_normalize(col1)
        let z = simd_normalize(col2)

        let rotationMatrix = simd_float3x3(x, y, z)
        return simd_quatf(rotationMatrix)
    }
}
