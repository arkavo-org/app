//
//  SkeletonDebugView.swift
//  ArkavoCreator
//
//  Created for body tracking debug visualization
//

import SwiftUI
import VRMMetalKit

/// Debug overlay showing 2D skeleton visualization of ARKit body tracking
///
/// Displays detected body joints and bone connections independent of 3D avatar rendering.
/// Useful for diagnosing tracking data reception vs 3D positioning issues.
struct SkeletonDebugView: View {
    let skeleton: ARKitBodySkeleton?

    // Define bone connections (parent -> child)
    private let boneConnections: [(ARKitJoint, ARKitJoint)] = [
        // Spine chain
        (.hips, .spine),
        (.spine, .chest),
        (.chest, .upperChest),
        (.upperChest, .neck),
        (.neck, .head),

        // Left arm
        (.upperChest, .leftShoulder),
        (.leftShoulder, .leftUpperArm),
        (.leftUpperArm, .leftLowerArm),
        (.leftLowerArm, .leftHand),

        // Right arm
        (.upperChest, .rightShoulder),
        (.rightShoulder, .rightUpperArm),
        (.rightUpperArm, .rightLowerArm),
        (.rightLowerArm, .rightHand),

        // Left leg
        (.hips, .leftUpperLeg),
        (.leftUpperLeg, .leftLowerLeg),
        (.leftLowerLeg, .leftFoot),
        (.leftFoot, .leftToes),

        // Right leg
        (.hips, .rightUpperLeg),
        (.rightUpperLeg, .rightLowerLeg),
        (.rightLowerLeg, .rightFoot),
        (.rightFoot, .rightToes),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header
            HStack {
                Image(systemName: "figure.walk")
                    .foregroundColor(.green)
                Text("Body Tracking Debug")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(.white)
            }
            .padding(.horizontal, 8)
            .padding(.top, 8)

            // Canvas for skeleton visualization
            Canvas { context, size in
                guard let skeleton = skeleton, skeleton.isTracked else {
                    // Draw "No tracking" message
                    let text = Text("No body tracking")
                        .font(.caption)
                        .foregroundColor(.gray)
                    let textSize = CGSize(width: size.width, height: 20)
                    context.draw(text, in: CGRect(origin: CGPoint(x: 0, y: size.height / 2 - 10), size: textSize))
                    return
                }

                // Extract 2D positions from 3D transforms
                var positions2D: [ARKitJoint: CGPoint] = [:]

                for (joint, transform) in skeleton.joints {
                    // Extract position from 4x4 matrix (4th column)
                    let pos3D = SIMD3<Float>(
                        transform.columns.3.x,
                        transform.columns.3.y,
                        transform.columns.3.z
                    )

                    // Simple orthographic projection (drop Z)
                    // Scale and center to canvas
                    let scale: CGFloat = 80 // Adjust for comfortable viewing
                    let x = CGFloat(pos3D.x) * scale + size.width / 2
                    let y = size.height / 2 - CGFloat(pos3D.y) * scale // Flip Y (ARKit Y-up → Canvas Y-down)

                    positions2D[joint] = CGPoint(x: x, y: y)
                }

                // Draw bone connections (lines)
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
                    let rect = CGRect(x: position.x - 4, y: position.y - 4,
                                      width: 8, height: 8)
                    context.fill(Circle().path(in: rect), with: .color(.yellow))
                }

                // Draw joint count
                let jointCount = skeleton.joints.count
                let countText = Text("\(jointCount) joints")
                    .font(.caption2)
                    .foregroundColor(.white)
                context.draw(countText, at: CGPoint(x: size.width - 35, y: 10))
            }
            .frame(height: 250)

            // Status footer
            HStack {
                Circle()
                    .fill(skeleton?.isTracked == true ? Color.green : Color.red)
                    .frame(width: 6, height: 6)
                Text(skeleton?.isTracked == true ? "Tracking" : "Not Tracking")
                    .font(.caption2)
                    .foregroundColor(.gray)
            }
            .padding(.horizontal, 8)
            .padding(.bottom, 8)
        }
        .frame(width: 200, height: 300)
        .background(Color.black.opacity(0.8))
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(skeleton?.isTracked == true ? Color.green.opacity(0.5) : Color.gray.opacity(0.3), lineWidth: 1)
        )
    }
}

#Preview {
    SkeletonDebugView(skeleton: nil)
        .padding()
        .background(Color.gray)
}
