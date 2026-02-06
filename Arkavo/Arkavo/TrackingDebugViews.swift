//
//  TrackingDebugViews.swift
//  Arkavo
//
//  Debug overlays for ARKit face and body tracking visualization
//  Redesigned for high visibility and better usability
//

import ARKit
import SwiftUI

// MARK: - Size Constants

enum DebugOverlaySize {
    static let compact = CGSize(width: 160, height: 200)
    static let standard = CGSize(width: 200, height: 280)
    static let expanded = CGSize(width: 240, height: 320)
}

// MARK: - Shared Components

/// Status indicator dot with pulse animation
private struct StatusIndicator: View {
    let isActive: Bool
    let color: Color
    let label: String

    @State private var isPulsing = false

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(isActive ? color : Color.gray)
                .frame(width: 10, height: 10)
                .overlay(
                    Circle()
                        .stroke(isActive ? color.opacity(0.4) : Color.gray.opacity(0.3), lineWidth: 3)
                        .scaleEffect(isPulsing ? 1.8 : 1.0)
                        .opacity(isPulsing ? 0 : 1)
                )
                .animation(isActive ? .easeOut(duration: 1.0).repeatForever(autoreverses: false) : .default, value: isPulsing)

            Text(label)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(isActive ? .white : .gray)
        }
        .onAppear {
            isPulsing = isActive
        }
        .onChange(of: isActive) { _, newValue in
            isPulsing = newValue
        }
    }
}

/// Expandable section header
private struct SectionHeader: View {
    let title: String
    let systemImage: String
    let color: Color
    let count: Int?

    var body: some View {
        HStack {
            Image(systemName: systemImage)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(color)

            Text(title)
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(.white)

            Spacer()

            if let count = count {
                Text("\(count)")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(color.opacity(0.8))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(color.opacity(0.15))
                    .clipShape(Capsule())
            }
        }
    }
}

// MARK: - Body Tracking Debug View

/// Debug overlay showing 2D skeleton visualization of ARKit body tracking
struct BodyTrackingDebugView: View {
    let skeleton: ARSkeleton3D?
    let isTracking: Bool
    var size: CGSize = DebugOverlaySize.standard

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
        mainContent
    }

    private var mainContent: some View {
        VStack(spacing: 0) {
            headerView
            skeletonCanvas
            Spacer()
            footerView
        }
        .frame(width: size.width, height: size.height)
        .background(backgroundView)
        .shadow(color: isTracking ? Color.green.opacity(0.3) : Color.clear, radius: 10, x: 0, y: 4)
    }

    private var headerView: some View {
        SectionHeader(
            title: "Body Tracking",
            systemImage: "figure.walk",
            color: .green,
            count: isTracking ? skeleton?.definition.jointNames.count : nil
        )
        .padding(.horizontal, 12)
        .padding(.top, 12)
        .padding(.bottom, 8)
    }

    private var footerView: some View {
        StatusIndicator(
            isActive: isTracking,
            color: .green,
            label: isTracking ? "Tracking Active" : "Searching..."
        )
        .padding(.horizontal, 12)
        .padding(.bottom, 12)
    }

    private var backgroundView: some View {
        RoundedRectangle(cornerRadius: 16)
            .fill(Color.black.opacity(0.85))
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(isTracking ? Color.green.opacity(0.6) : Color.gray.opacity(0.4), lineWidth: 2)
            )
    }

    private var skeletonCanvas: some View {
        Canvas { context, canvasSize in
            drawSkeleton(in: &context, canvasSize: canvasSize)
        }
        .frame(height: size.height - 70)
    }

    private func drawSkeleton(in context: inout GraphicsContext, canvasSize: CGSize) {
        guard let skeleton = skeleton, isTracking else {
            drawNoTrackingState(in: &context, canvasSize: canvasSize)
            return
        }

        let positions2D = calculateJointPositions(skeleton: skeleton, canvasSize: canvasSize)
        drawBoneConnections(in: &context, positions2D: positions2D)
        drawJointCircles(in: &context, positions2D: positions2D)
    }

    private func drawNoTrackingState(in context: inout GraphicsContext, canvasSize: CGSize) {
        let config = UIImage.SymbolConfiguration(pointSize: 32, weight: .light)
        let image = UIImage(systemName: "figure.walk", withConfiguration: config)

        if let cgImage = image?.cgImage {
            let imageSize = CGSize(width: 40, height: 40)
            let rect = CGRect(
                x: (canvasSize.width - imageSize.width) / 2,
                y: (canvasSize.height - imageSize.height) / 2 - 10,
                width: imageSize.width,
                height: imageSize.height
            )
            context.draw(Image(cgImage, scale: 1.0, label: Text("")), in: rect)
        }

        let text = Text("No body detected")
            .font(.system(size: 11, weight: .medium))
            .foregroundColor(.gray)
        context.draw(text, at: CGPoint(x: canvasSize.width / 2, y: canvasSize.height / 2 + 25))
    }

    private func calculateJointPositions(skeleton: ARSkeleton3D, canvasSize: CGSize) -> [String: CGPoint] {
        let jointNames = skeleton.definition.jointNames

        var minX: Float = .infinity, maxX: Float = -.infinity
        var minY: Float = .infinity, maxY: Float = -.infinity
        var validPositions: [(String, SIMD3<Float>)] = []

        for (index, jointName) in jointNames.enumerated() {
            guard index < skeleton.jointModelTransforms.count else { continue }
            let transform = skeleton.jointModelTransforms[index]
            let pos3D = SIMD3<Float>(
                transform.columns.3.x,
                transform.columns.3.y,
                transform.columns.3.z
            )
            validPositions.append((jointName, pos3D))
            minX = min(minX, pos3D.x)
            maxX = max(maxX, pos3D.x)
            minY = min(minY, pos3D.y)
            maxY = max(maxY, pos3D.y)
        }

        let padding: CGFloat = 20
        let availableWidth = canvasSize.width - padding * 2
        let availableHeight = canvasSize.height - padding * 2

        let xRange = maxX - minX
        let yRange = maxY - minY
        let scaleX = xRange > 0 ? availableWidth / CGFloat(xRange) : 1.0
        let scaleY = yRange > 0 ? availableHeight / CGFloat(yRange) : 1.0
        let scale = min(scaleX, scaleY, 80)

        var positions2D: [String: CGPoint] = [:]
        for (jointName, pos3D) in validPositions {
            let x = CGFloat(pos3D.x - (minX + maxX) / 2) * scale + canvasSize.width / 2
            let y = canvasSize.height / 2 - CGFloat(pos3D.y - (minY + maxY) / 2) * scale
            positions2D[jointName] = CGPoint(x: x, y: y)
        }

        return positions2D
    }

    private func drawBoneConnections(in context: inout GraphicsContext, positions2D: [String: CGPoint]) {
        for (parent, child) in boneConnections {
            guard let p1 = positions2D[parent],
                  let p2 = positions2D[child]
            else { continue }

            var path = Path()
            path.move(to: p1)
            path.addLine(to: p2)

            let lineWidth: CGFloat = parent.contains("spine") || parent.contains("hips") ? 3 : 2

            context.stroke(
                path,
                with: .color(.green.opacity(0.9)),
                lineWidth: lineWidth
            )
        }
    }

    private func drawJointCircles(in context: inout GraphicsContext, positions2D: [String: CGPoint]) {
        for (jointName, position) in positions2D {
            let isImportant = jointName.contains("head") || jointName.contains("hand") || jointName.contains("foot")
            let radius: CGFloat = isImportant ? 5 : 3

            let rect = CGRect(
                x: position.x - radius,
                y: position.y - radius,
                width: radius * 2,
                height: radius * 2
            )

            context.fill(
                Circle().path(in: rect.insetBy(dx: -2, dy: -2)),
                with: .color(.green.opacity(0.3))
            )

            context.fill(
                Circle().path(in: rect),
                with: .color(isImportant ? .yellow : .green)
            )
        }
    }
}

// MARK: - Face Tracking Debug View

/// Debug overlay showing ARKit face blend shape values with expandable sections
struct FaceTrackingDebugView: View {
    let blendShapes: [ARFaceAnchor.BlendShapeLocation: NSNumber]?
    let isTracking: Bool
    var size: CGSize = DebugOverlaySize.standard

    @State private var expandedSections: Set<String> = ["Eyes", "Mouth"]

    // Key blend shapes organized by facial region
    private let sections: [(name: String, icon: String, shapes: [(String, ARFaceAnchor.BlendShapeLocation)])] = [
        ("Eyes", "eye", [
            ("Blink L", .eyeBlinkLeft),
            ("Blink R", .eyeBlinkRight),
            ("Wide L", .eyeWideLeft),
            ("Wide R", .eyeWideRight),
            ("Look Up", .eyeLookUpLeft),
            ("Look Down", .eyeLookDownLeft),
        ]),
        ("Brows", "eyebrow", [
            ("Inner Up", .browInnerUp),
            ("Outer Up L", .browOuterUpLeft),
            ("Outer Up R", .browOuterUpRight),
            ("Down L", .browDownLeft),
            ("Down R", .browDownRight),
        ]),
        ("Mouth", "mouth", [
            ("Jaw Open", .jawOpen),
            ("Smile L", .mouthSmileLeft),
            ("Smile R", .mouthSmileRight),
            ("Pucker", .mouthPucker),
            ("Funnel", .mouthFunnel),
            ("Left", .mouthLeft),
            ("Right", .mouthRight),
        ]),
        ("Cheeks/Nose", "face.smiling", [
            ("Cheek Puff", .cheekPuff),
            ("Squint L", .eyeSquintLeft),
            ("Squint R", .eyeSquintRight),
            ("Nose Wrinkle", .noseSneerLeft),
        ]),
    ]

    var body: some View {
        VStack(spacing: 0) {
            // Header
            SectionHeader(
                title: "Face Tracking",
                systemImage: "face.smiling",
                color: .cyan,
                count: isTracking ? blendShapes?.count : nil
            )
            .padding(.horizontal, 12)
            .padding(.top, 12)
            .padding(.bottom, 8)

            if let shapes = blendShapes, isTracking {
                // Scrollable sections
                ScrollView(.vertical, showsIndicators: true) {
                    VStack(spacing: 8) {
                        ForEach(sections, id: \.name) { section in
                            BlendShapeSection(
                                title: section.name,
                                icon: section.icon,
                                shapes: section.shapes,
                                blendShapes: shapes,
                                isExpanded: expandedSections.contains(section.name)
                            ) {
                                if expandedSections.contains(section.name) {
                                    expandedSections.remove(section.name)
                                } else {
                                    expandedSections.insert(section.name)
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 10)
                }
                .frame(height: size.height - 90)
            } else {
                // No tracking state
                VStack(spacing: 12) {
                    Image(systemName: "face.smiling")
                        .font(.system(size: 40))
                        .foregroundColor(.gray.opacity(0.4))

                    Text("No face detected")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.gray)

                    Text("Position face in camera")
                        .font(.system(size: 10))
                        .foregroundColor(.gray.opacity(0.7))
                }
                .frame(height: size.height - 90)
            }

            Spacer()

            // Status footer
            StatusIndicator(
                isActive: isTracking,
                color: .cyan,
                label: isTracking ? "Tracking Active" : "Searching..."
            )
            .padding(.horizontal, 12)
            .padding(.bottom, 12)
        }
        .frame(width: size.width, height: size.height)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.black.opacity(0.85))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(isTracking ? Color.cyan.opacity(0.6) : Color.gray.opacity(0.4), lineWidth: 2)
                )
        )
        .shadow(color: isTracking ? Color.cyan.opacity(0.3) : Color.clear, radius: 10, x: 0, y: 4)
    }
}

/// Expandable section for blend shape groups
private struct BlendShapeSection: View {
    let title: String
    let icon: String
    let shapes: [(String, ARFaceAnchor.BlendShapeLocation)]
    let blendShapes: [ARFaceAnchor.BlendShapeLocation: NSNumber]
    let isExpanded: Bool
    let action: () -> Void

    var body: some View {
        VStack(spacing: 4) {
            // Section header button
            Button(action: action) {
                HStack {
                    Image(systemName: icon)
                        .font(.system(size: 10))
                        .foregroundColor(.cyan.opacity(0.8))

                    Text(title)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(.cyan.opacity(0.9))

                    Spacer()

                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 10))
                        .foregroundColor(.gray)
                }
            }
            .buttonStyle(.plain)

            // Expandable content
            if isExpanded {
                VStack(spacing: 3) {
                    ForEach(shapes, id: \.0) { displayName, location in
                        BlendShapeBar(
                            name: displayName,
                            value: blendShapes[location]?.floatValue ?? 0
                        )
                    }
                }
                .padding(.top, 4)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(8)
        .background(Color.white.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

/// A single blend shape value displayed as a progress bar
private struct BlendShapeBar: View {
    let name: String
    let value: Float

    var body: some View {
        HStack(spacing: 6) {
            Text(name)
                .font(.system(size: 9, design: .monospaced))
                .foregroundColor(.white.opacity(0.8))
                .frame(width: 55, alignment: .leading)

            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    // Background
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.white.opacity(0.1))

                    // Fill with gradient
                    RoundedRectangle(cornerRadius: 2)
                        .fill(
                            LinearGradient(
                                colors: [barColor.opacity(0.7), barColor],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: geometry.size.width * CGFloat(min(value, 1.0)))
                        .animation(.easeOut(duration: 0.1), value: value)
                }
            }
            .frame(height: 8)

            Text(String(format: "%02.0f%%", value * 100))
                .font(.system(size: 8, weight: .medium, design: .monospaced))
                .foregroundColor(barColor)
                .frame(width: 28, alignment: .trailing)
        }
        .frame(height: 12)
    }

    private var barColor: Color {
        if value < 0.3 {
            return .cyan.opacity(0.8)
        } else if value < 0.7 {
            return .cyan
        } else {
            return .green
        }
    }
}

// MARK: - Compact Tracking Indicator

/// Minimal indicator for when screen space is limited
struct CompactTrackingIndicator: View {
    let isFaceTracking: Bool
    let isBodyTracking: Bool
    let faceCount: Int?
    let bodyCount: Int?

    var body: some View {
        HStack(spacing: 12) {
            if isFaceTracking || !isBodyTracking {
                TrackingPill(
                    icon: "face.smiling",
                    label: "Face",
                    count: faceCount,
                    color: .cyan,
                    isActive: isFaceTracking
                )
            }

            if isBodyTracking || !isFaceTracking {
                TrackingPill(
                    icon: "figure.walk",
                    label: "Body",
                    count: bodyCount,
                    color: .green,
                    isActive: isBodyTracking
                )
            }
        }
    }
}

private struct TrackingPill: View {
    let icon: String
    let label: String
    let count: Int?
    let color: Color
    let isActive: Bool

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 10))
            Text(label)
                .font(.system(size: 10, weight: .medium))
            if let count = count {
                Text("\(count)")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(color)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(color.opacity(0.2))
                    .clipShape(Capsule())
            }
        }
        .foregroundColor(isActive ? .white : .gray)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(isActive ? color.opacity(0.25) : Color.gray.opacity(0.15))
        .overlay(
            Capsule()
                .stroke(isActive ? color.opacity(0.5) : Color.clear, lineWidth: 1)
        )
        .clipShape(Capsule())
    }
}

// MARK: - Previews

#Preview("Body Debug - Active") {
    BodyTrackingDebugView(skeleton: nil, isTracking: true)
        .padding()
        .background(Color.black)
}

#Preview("Body Debug - Inactive") {
    BodyTrackingDebugView(skeleton: nil, isTracking: false)
        .padding()
        .background(Color.black)
}

#Preview("Face Debug - Active") {
    FaceTrackingDebugView(blendShapes: nil, isTracking: true)
        .padding()
        .background(Color.black)
}

#Preview("Face Debug - Inactive") {
    FaceTrackingDebugView(blendShapes: nil, isTracking: false)
        .padding()
        .background(Color.black)
}

#Preview("Compact Indicator") {
    VStack(spacing: 16) {
        CompactTrackingIndicator(
            isFaceTracking: true,
            isBodyTracking: false,
            faceCount: 52,
            bodyCount: nil
        )

        CompactTrackingIndicator(
            isFaceTracking: false,
            isBodyTracking: true,
            faceCount: nil,
            bodyCount: 91
        )

        CompactTrackingIndicator(
            isFaceTracking: true,
            isBodyTracking: true,
            faceCount: 52,
            bodyCount: 91
        )

        CompactTrackingIndicator(
            isFaceTracking: false,
            isBodyTracking: false,
            faceCount: nil,
            bodyCount: nil
        )
    }
    .padding()
    .background(Color.black)
}
