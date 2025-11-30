//
//  FaceDebugView.swift
//  ArkavoCreator
//
//  Created for face tracking debug visualization
//

import SwiftUI
import VRMMetalKit

/// Debug overlay showing ARKit face blend shape values
///
/// Displays detected face expressions independent of 3D avatar rendering.
/// Useful for diagnosing tracking data reception vs expression mapping issues.
struct FaceDebugView: View {
    let blendShapes: ARKitFaceBlendShapes?

    // Key blend shapes to display, grouped by category
    private let eyeShapes = [
        ("eyeBlinkL", "eyeBlinkLeft"),
        ("eyeBlinkR", "eyeBlinkRight"),
        ("eyeWideL", "eyeWideLeft"),
        ("eyeWideR", "eyeWideRight"),
    ]

    private let browShapes = [
        ("browInnerUp", "browInnerUp"),
        ("browDownL", "browDownLeft"),
        ("browDownR", "browDownRight"),
    ]

    private let mouthShapes = [
        ("jawOpen", "jawOpen"),
        ("smileL", "mouthSmileLeft"),
        ("smileR", "mouthSmileRight"),
        ("pucker", "mouthPucker"),
        ("funnel", "mouthFunnel"),
    ]

    private let cheekShapes = [
        ("cheekPuff", "cheekPuff"),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Header
            HStack {
                Image(systemName: "face.smiling")
                    .foregroundColor(.cyan)
                Text("Face Tracking Debug")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(.white)
            }
            .padding(.horizontal, 8)
            .padding(.top, 8)

            if let shapes = blendShapes {
                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        BlendShapeGroup(title: "Eyes", shapes: eyeShapes, blendShapes: shapes)
                        BlendShapeGroup(title: "Brows", shapes: browShapes, blendShapes: shapes)
                        BlendShapeGroup(title: "Mouth", shapes: mouthShapes, blendShapes: shapes)
                        BlendShapeGroup(title: "Cheeks", shapes: cheekShapes, blendShapes: shapes)
                    }
                    .padding(.horizontal, 8)
                }
            } else {
                VStack {
                    Spacer()
                    Text("No face tracking data")
                        .font(.caption)
                        .foregroundColor(.gray)
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            }

            // Status footer
            HStack {
                Circle()
                    .fill(blendShapes != nil ? Color.cyan : Color.red)
                    .frame(width: 6, height: 6)
                Text(blendShapes != nil ? "Tracking" : "Not Tracking")
                    .font(.caption2)
                    .foregroundColor(.gray)
                Spacer()
                if let shapes = blendShapes {
                    Text("\(shapes.shapes.count) shapes")
                        .font(.caption2)
                        .foregroundColor(.gray)
                }
            }
            .padding(.horizontal, 8)
            .padding(.bottom, 8)
        }
        .frame(width: 200, height: 300)
        .background(Color.black.opacity(0.8))
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(blendShapes != nil ? Color.cyan.opacity(0.5) : Color.gray.opacity(0.3), lineWidth: 1)
        )
    }
}

/// A group of blend shapes with a title header
private struct BlendShapeGroup: View {
    let title: String
    let shapes: [(String, String)] // (displayName, blendShapeKey)
    let blendShapes: ARKitFaceBlendShapes

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption2)
                .fontWeight(.medium)
                .foregroundColor(.cyan.opacity(0.8))

            ForEach(shapes, id: \.0) { displayName, key in
                BlendShapeBar(
                    name: displayName,
                    value: blendShapes.weight(for: key)
                )
            }
        }
    }
}

/// A single blend shape value displayed as a progress bar
private struct BlendShapeBar: View {
    let name: String
    let value: Float

    var body: some View {
        HStack(spacing: 4) {
            Text(name)
                .font(.system(size: 9, design: .monospaced))
                .foregroundColor(.white.opacity(0.7))
                .frame(width: 70, alignment: .leading)

            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    // Background
                    Rectangle()
                        .fill(Color.white.opacity(0.1))

                    // Value bar
                    Rectangle()
                        .fill(barColor)
                        .frame(width: geometry.size.width * CGFloat(min(value, 1.0)))
                }
            }
            .frame(height: 8)
            .cornerRadius(2)

            Text(String(format: "%.2f", value))
                .font(.system(size: 8, design: .monospaced))
                .foregroundColor(.white.opacity(0.5))
                .frame(width: 28, alignment: .trailing)
        }
        .frame(height: 12)
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

#Preview {
    FaceDebugView(blendShapes: nil)
        .padding()
        .background(Color.gray)
}
