import SwiftUI

/// A reusable empty state view that displays the wave animation with context-appropriate messaging
/// Automatically manages isAwaiting state and uses the appropriate message based on the current tab
struct WaveEmptyStateView: View {
    @EnvironmentObject var sharedState: SharedState
    
    var body: some View {
        VStack {
            Spacer()
            WaveLoadingView(message: sharedState.getCenterPrompt())
                .frame(maxWidth: .infinity)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemBackground))
        .onAppear { sharedState.isAwaiting = true }
        .onDisappear { sharedState.isAwaiting = false }
    }
}

/// Wave loading animation view that displays an animated logo on waves
struct WaveLoadingView: View {
    let message: String
    @State private var waveOffset = 0.0
    @State private var boatOffset = 0.0

    var body: some View {
        VStack(spacing: 40) {
            // Wave and logo container
            GeometryReader { _ in
                ZStack {
                    // Waves spanning full width
                    WaveShape(offset: waveOffset, waveHeight: 20)
                        .fill(Color(red: 0, green: 0.32, blue: 0.66))
                        .opacity(0.8)
                        .frame(height: 120)
                        .frame(maxWidth: .infinity) // Full width

                    WaveShape(offset: waveOffset + 0.5, waveHeight: 15)
                        .fill(Color(red: 0, green: 0.32, blue: 0.66))
                        .opacity(0.4)
                        .frame(height: 120)
                        .frame(maxWidth: .infinity) // Full width

                    // Animated Logo
                    Image("AppLogo")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 120, height: 120) // Kept large size
                        .foregroundColor(.orange)
                        .offset(y: CGFloat(sin(boatOffset) * 10))
                        .rotationEffect(.degrees(sin(boatOffset) * 3))
                }
            }
            .frame(height: 200) // Fixed height container

            // Message
            HStack(spacing: 4) {
                Text(message)
                    .foregroundColor(.gray)
                    .font(.title3)
            }
        }
        .onAppear {
            withAnimation(.linear(duration: 3).repeatForever(autoreverses: false)) {
                waveOffset = -.pi * 2
            }
            withAnimation(.linear(duration: 2).repeatForever(autoreverses: false)) {
                boatOffset = .pi * 2
            }
        }
    }
}

/// Shape that creates an animated wave effect
struct WaveShape: Shape {
    var offset: Double
    var waveHeight: Double

    var animatableData: Double {
        get { offset }
        set { offset = newValue }
    }

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let width = rect.width
        let height = rect.height
        let midHeight = height / 2

        // More points for smoother wave
        path.move(to: CGPoint(x: 0, y: midHeight))

        // Create smoother wave with more points
        for x in stride(from: 0, to: width, by: 1) {
            let relativeX = x / width
            let sine = sin(relativeX * .pi * 2 + offset)
            let y = midHeight + sine * waveHeight
            path.addLine(to: CGPoint(x: x, y: y))
        }

        // Ensure wave fills to bottom
        path.addLine(to: CGPoint(x: width, y: height))
        path.addLine(to: CGPoint(x: 0, y: height))
        path.closeSubpath()

        return path
    }
}

/// Alternative API for WaveLoadingView that provides the empty state functionality
extension WaveLoadingView {
    /// Creates a standard empty state view with automatic state management
    static func emptyState() -> some View {
        WaveEmptyStateView()
    }
}