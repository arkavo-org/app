import SwiftUI

struct CalibrationView: View {
    @State private var isCalibrated = false
    @State private var touchPoints: [CGPoint] = []

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color.white
                    .ignoresSafeArea()

                VStack {
                    Text("ArkavoTestHost Calibration")
                        .font(.title)
                        .padding(.top, 50)

                    Text(isCalibrated ? "Calibrated" : "Active")
                        .font(.headline)
                        .foregroundColor(isCalibrated ? .green : .orange)

                    Spacer()
                }

                // Calibration markers at corners and center
                ForEach(calibrationPoints(for: geometry.size), id: \.x) { point in
                    CalibrationMarker(position: point)
                }

                // Touch indicators
                ForEach(Array(touchPoints.enumerated()), id: \.offset) { _, point in
                    Circle()
                        .fill(Color.red.opacity(0.5))
                        .frame(width: 20, height: 20)
                        .position(point)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture { location in
                touchPoints.append(location)

                // Remove old touch points after a delay
                DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                    if !touchPoints.isEmpty {
                        touchPoints.removeFirst()
                    }
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Calibration View")
        .accessibilityAddTraits(.allowsDirectInteraction)
    }

    func calibrationPoints(for size: CGSize) -> [CGPoint] {
        let padding: CGFloat = 40
        return [
            // Corners
            CGPoint(x: padding, y: padding),
            CGPoint(x: size.width - padding, y: padding),
            CGPoint(x: padding, y: size.height - padding),
            CGPoint(x: size.width - padding, y: size.height - padding),
            // Center
            CGPoint(x: size.width / 2, y: size.height / 2),
            // Mid points
            CGPoint(x: size.width / 2, y: padding),
            CGPoint(x: size.width / 2, y: size.height - padding),
            CGPoint(x: padding, y: size.height / 2),
            CGPoint(x: size.width - padding, y: size.height / 2),
        ]
    }
}

struct CalibrationMarker: View {
    let position: CGPoint

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.blue, lineWidth: 2)
                .frame(width: 30, height: 30)

            Circle()
                .fill(Color.blue)
                .frame(width: 10, height: 10)

            // Crosshair
            Path { path in
                path.move(to: CGPoint(x: -20, y: 0))
                path.addLine(to: CGPoint(x: 20, y: 0))
                path.move(to: CGPoint(x: 0, y: -20))
                path.addLine(to: CGPoint(x: 0, y: 20))
            }
            .stroke(Color.blue, lineWidth: 1)
        }
        .position(position)
        .accessibilityElement()
        .accessibilityLabel("Calibration Marker at \(Int(position.x)), \(Int(position.y))")
    }
}

#Preview {
    CalibrationView()
}
