//
//  TrackingDebugViews.swift
//  Arkavo
//
//  Debug overlays for ARKit face and body tracking visualization
//

import ARKit
import SwiftUI

// MARK: - Body Tracking Debug View

/// Debug overlay showing 2D skeleton visualization of ARKit body tracking
struct BodyTrackingDebugView: View {
    let skeleton: ARSkeleton3D?
    let isTracking: Bool

    // Define bone connections using string joint names (ARKit uses these)
    private let boneConnections: [(String, String)] = [
        // Spine chain
        ("hips_joint", "spine_1_joint"),
        ("spine_1_joint", "spine_2_joint"),
        ("spine_2_joint", "spine_3_joint"),
        ("spine_3_joint", "spine_4_joint"),
        ("spine_4_joint", "spine_5_joint"),
        ("spine_5_joint", "spine_6_joint"),
        ("spine_6_joint", "spine_7_joint"),
        ("spine_7_joint", "neck_1_joint"),
        ("neck_1_joint", "head_joint"),

        // Left arm
        ("spine_7_joint", "left_shoulder_1_joint"),
        ("left_shoulder_1_joint", "left_arm_joint"),
        ("left_arm_joint", "left_forearm_joint"),
        ("left_forearm_joint", "left_hand_joint"),

        // Right arm
        ("spine_7_joint", "right_shoulder_1_joint"),
        ("right_shoulder_1_joint", "right_arm_joint"),
        ("right_arm_joint", "right_forearm_joint"),
        ("right_forearm_joint", "right_hand_joint"),

        // Left leg
        ("hips_joint", "left_upLeg_joint"),
        ("left_upLeg_joint", "left_leg_joint"),
        ("left_leg_joint", "left_foot_joint"),
        ("left_foot_joint", "left_toes_joint"),

        // Right leg
        ("hips_joint", "right_upLeg_joint"),
        ("right_upLeg_joint", "right_leg_joint"),
        ("right_leg_joint", "right_foot_joint"),
        ("right_foot_joint", "right_toes_joint"),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header
            HStack {
                Image(systemName: "figure.walk")
                    .foregroundColor(.green)
                Text("Body Tracking")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(.white)
            }
            .padding(.horizontal, 8)
            .padding(.top, 8)

            // Canvas for skeleton visualization
            Canvas { context, size in
                guard let skeleton = skeleton, isTracking else {
                    // Draw "No tracking" message
                    let text = Text("No body detected")
                        .font(.caption)
                        .foregroundColor(.gray)
                    context.draw(text, at: CGPoint(x: size.width / 2, y: size.height / 2))
                    return
                }

                // Extract 2D positions from 3D transforms
                var positions2D: [String: CGPoint] = [:]
                let jointNames = skeleton.definition.jointNames

                for (index, jointName) in jointNames.enumerated() {
                    guard index < skeleton.jointModelTransforms.count else { continue }
                    let transform = skeleton.jointModelTransforms[index]

                    // Extract position from 4x4 matrix (4th column)
                    let pos3D = SIMD3<Float>(
                        transform.columns.3.x,
                        transform.columns.3.y,
                        transform.columns.3.z
                    )

                    // Simple orthographic projection (drop Z)
                    let scale: CGFloat = 60
                    let x = CGFloat(pos3D.x) * scale + size.width / 2
                    let y = size.height / 2 - CGFloat(pos3D.y) * scale

                    positions2D[jointName] = CGPoint(x: x, y: y)
                }

                // Draw bone connections
                for (parent, child) in boneConnections {
                    guard let p1 = positions2D[parent],
                          let p2 = positions2D[child]
                    else { continue }

                    var path = Path()
                    path.move(to: p1)
                    path.addLine(to: p2)
                    context.stroke(path, with: .color(.green), lineWidth: 2)
                }

                // Draw joint circles
                for (_, position) in positions2D {
                    let rect = CGRect(x: position.x - 3, y: position.y - 3, width: 6, height: 6)
                    context.fill(Circle().path(in: rect), with: .color(.yellow))
                }

                // Draw joint count
                let jointCount = jointNames.count
                let countText = Text("\(jointCount) joints")
                    .font(.caption2)
                    .foregroundColor(.white)
                context.draw(countText, at: CGPoint(x: size.width - 30, y: 10))
            }
            .frame(height: 180)

            // Status footer
            HStack {
                Circle()
                    .fill(isTracking ? Color.green : Color.red)
                    .frame(width: 6, height: 6)
                Text(isTracking ? "Tracking" : "Not Tracking")
                    .font(.caption2)
                    .foregroundColor(.gray)
            }
            .padding(.horizontal, 8)
            .padding(.bottom, 8)
        }
        .frame(width: 160, height: 230)
        .background(Color.black.opacity(0.85))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(isTracking ? Color.green.opacity(0.5) : Color.gray.opacity(0.3), lineWidth: 1)
        )
    }
}

// MARK: - Face Tracking Debug View

/// Debug overlay showing ARKit face blend shape values
struct FaceTrackingDebugView: View {
    let blendShapes: [ARFaceAnchor.BlendShapeLocation: NSNumber]?
    let isTracking: Bool

    // Key blend shapes to display
    private let eyeShapes: [(String, ARFaceAnchor.BlendShapeLocation)] = [
        ("Blink L", .eyeBlinkLeft),
        ("Blink R", .eyeBlinkRight),
        ("Wide L", .eyeWideLeft),
        ("Wide R", .eyeWideRight),
    ]

    private let browShapes: [(String, ARFaceAnchor.BlendShapeLocation)] = [
        ("Brow Up", .browInnerUp),
        ("Brow L", .browDownLeft),
        ("Brow R", .browDownRight),
    ]

    private let mouthShapes: [(String, ARFaceAnchor.BlendShapeLocation)] = [
        ("Jaw", .jawOpen),
        ("Smile L", .mouthSmileLeft),
        ("Smile R", .mouthSmileRight),
        ("Pucker", .mouthPucker),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            // Header
            HStack {
                Image(systemName: "face.smiling")
                    .foregroundColor(.cyan)
                Text("Face Tracking")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(.white)
            }
            .padding(.horizontal, 8)
            .padding(.top, 8)

            if let shapes = blendShapes, isTracking {
                VStack(alignment: .leading, spacing: 6) {
                    FaceBlendShapeGroup(title: "Eyes", shapes: eyeShapes, blendShapes: shapes)
                    FaceBlendShapeGroup(title: "Brows", shapes: browShapes, blendShapes: shapes)
                    FaceBlendShapeGroup(title: "Mouth", shapes: mouthShapes, blendShapes: shapes)
                }
                .padding(.horizontal, 8)
            } else {
                VStack {
                    Spacer()
                    Text("No face detected")
                        .font(.caption)
                        .foregroundColor(.gray)
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            }

            Spacer()

            // Status footer
            HStack {
                Circle()
                    .fill(isTracking ? Color.cyan : Color.red)
                    .frame(width: 6, height: 6)
                Text(isTracking ? "Tracking" : "Not Tracking")
                    .font(.caption2)
                    .foregroundColor(.gray)
                Spacer()
                if let shapes = blendShapes {
                    Text("\(shapes.count)")
                        .font(.caption2)
                        .foregroundColor(.gray)
                }
            }
            .padding(.horizontal, 8)
            .padding(.bottom, 8)
        }
        .frame(width: 160, height: 230)
        .background(Color.black.opacity(0.85))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(isTracking ? Color.cyan.opacity(0.5) : Color.gray.opacity(0.3), lineWidth: 1)
        )
    }
}

/// A group of blend shapes with a title header
private struct FaceBlendShapeGroup: View {
    let title: String
    let shapes: [(String, ARFaceAnchor.BlendShapeLocation)]
    let blendShapes: [ARFaceAnchor.BlendShapeLocation: NSNumber]

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(size: 9))
                .fontWeight(.medium)
                .foregroundColor(.cyan.opacity(0.8))

            ForEach(shapes, id: \.0) { displayName, location in
                FaceBlendShapeBar(
                    name: displayName,
                    value: blendShapes[location]?.floatValue ?? 0
                )
            }
        }
    }
}

/// A single blend shape value displayed as a progress bar
private struct FaceBlendShapeBar: View {
    let name: String
    let value: Float

    var body: some View {
        HStack(spacing: 4) {
            Text(name)
                .font(.system(size: 8, design: .monospaced))
                .foregroundColor(.white.opacity(0.7))
                .frame(width: 50, alignment: .leading)

            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Rectangle()
                        .fill(Color.white.opacity(0.1))

                    Rectangle()
                        .fill(barColor)
                        .frame(width: geometry.size.width * CGFloat(min(value, 1.0)))
                }
            }
            .frame(height: 6)
            .cornerRadius(2)

            Text(String(format: "%.1f", value))
                .font(.system(size: 7, design: .monospaced))
                .foregroundColor(.white.opacity(0.5))
                .frame(width: 20, alignment: .trailing)
        }
        .frame(height: 10)
    }

    private var barColor: Color {
        if value < 0.3 {
            return .cyan.opacity(0.6)
        } else if value < 0.7 {
            return .cyan
        } else {
            return .green
        }
    }
}

// MARK: - Previews

#Preview("Body Debug") {
    BodyTrackingDebugView(skeleton: nil, isTracking: false)
        .padding()
        .background(Color.gray)
}

#Preview("Face Debug") {
    FaceTrackingDebugView(blendShapes: nil, isTracking: false)
        .padding()
        .background(Color.gray)
}
