import SwiftUI

/// A pulsing LIVE badge indicator for live streams in the feed
struct LiveBadge: View {
    @State private var isAnimating = false

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(.white)
                .frame(width: 8, height: 8)
                .scaleEffect(isAnimating ? 1.3 : 1.0)
                .opacity(isAnimating ? 0.7 : 1.0)

            Text("LIVE")
                .font(.caption.bold())
                .foregroundStyle(.white)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(.red)
        .clipShape(Capsule())
        .shadow(color: .black.opacity(0.3), radius: 4, x: 0, y: 2)
        .onAppear {
            withAnimation(
                .easeInOut(duration: 0.8)
                    .repeatForever(autoreverses: true)
            ) {
                isAnimating = true
            }
        }
    }
}

/// Positioned LIVE badge overlay for use in feed items
struct LiveBadgeOverlay: View {
    var body: some View {
        VStack {
            HStack {
                Spacer()
                LiveBadge()
                    .padding(.top, 60) // Below status bar
                    .padding(.trailing, 16)
            }
            Spacer()
        }
    }
}

#Preview("Live Badge") {
    ZStack {
        Color.black
        LiveBadge()
    }
}

#Preview("Live Badge Overlay") {
    ZStack {
        Color.gray
        LiveBadgeOverlay()
    }
}
