import AVKit
import SwiftUI

// Simplified video model
struct Video: Identifiable {
    let id: UUID = .init()
    let url: URL
    let creatorName: String
    let description: String
    var likes: Int
    var comments: Int
    var shares: Int
}

struct TikTokFeedView: View {
    @State private var currentIndex = 0
    @State private var showComments = false
    @State private var scale = 1.0
    @State private var rotation = 0.0
    @State private var bounce = false

    // Sample videos - replace with your actual data
    @State private var videos: [Video] = [
        Video(
            url: URL(string: "https://example.com/video1.mp4")!,
            creatorName: "creator1",
            description: "First video",
            likes: 100,
            comments: 50,
            shares: 25
        ),
        Video(
            url: URL(string: "https://example.com/video2.mp4")!,
            creatorName: "creator2",
            description: "Second video",
            likes: 200,
            comments: 75,
            shares: 30
        ),
    ]

    var body: some View {
        GeometryReader { geometry in
            TabView(selection: $currentIndex) {
                ForEach(videos.indices, id: \.self) { index in
                    ZStack {
                        Color.black // Placeholder for video
                            .overlay(
                                Text("Video \(index + 1)")
                                    .foregroundColor(.white)
                                    .font(.largeTitle)
                                    .scaleEffect(scale)
                                    .rotationEffect(.degrees(rotation))
                                    .offset(y: bounce ? -20 : 0)
                                    .onAppear {
                                        // Start the animations when view appears
                                        withAnimation(
                                            .easeInOut(duration: 2)
                                                .repeatForever(autoreverses: true)
                                        ) {
                                            scale = 1.3
                                        }

                                        withAnimation(
                                            .linear(duration: 4)
                                                .repeatForever(autoreverses: false)
                                        ) {
                                            rotation = 360
                                        }

                                        withAnimation(
                                            .spring(response: 0.5, dampingFraction: 0.5)
                                                .repeatForever(autoreverses: true)
                                        ) {
                                            bounce = true
                                        }
                                    }
                            )

                        // Overlay controls
                        VStack {
                            Spacer()
                            HStack {
                                // Video info
                                VStack(alignment: .leading) {
                                    Text("@\(videos[index].creatorName)")
                                        .foregroundColor(.white)
                                        .font(.headline)
                                    Text(videos[index].description)
                                        .foregroundColor(.white)
                                        .font(.subheadline)
                                }
                                .padding()

                                Spacer()

                                // Action buttons
                                VStack(spacing: 20) {
                                    Button(action: {}) {
                                        VStack {
                                            Image(systemName: "heart")
                                                .font(.title)
                                            Text("\(videos[index].likes)")
                                                .font(.caption)
                                        }
                                        .foregroundColor(.white)
                                    }

                                    Button(action: { showComments = true }) {
                                        VStack {
                                            Image(systemName: "message")
                                                .font(.title)
                                            Text("\(videos[index].comments)")
                                                .font(.caption)
                                        }
                                        .foregroundColor(.white)
                                    }

                                    Button(action: {}) {
                                        VStack {
                                            Image(systemName: "square.and.arrow.up")
                                                .font(.title)
                                            Text("\(videos[index].shares)")
                                                .font(.caption)
                                        }
                                        .foregroundColor(.white)
                                    }
                                }
                                .padding(.trailing)
                            }
                            .padding(.bottom)
                        }
                    }
                    .frame(width: geometry.size.width, height: geometry.size.height)
                    .tag(index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .ignoresSafeArea()
        }
        .sheet(isPresented: $showComments) {
            NavigationView {
                Text("Comments")
                    .navigationTitle("Comments")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .navigationBarTrailing) {
                            Button("Done") {
                                showComments = false
                            }
                        }
                    }
            }
        }
    }
}

#Preview {
    TikTokFeedView()
}
