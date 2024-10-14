import SwiftUI

final class ThoughtViewModel: ObservableObject, Identifiable, Equatable {
    let id = UUID()
    @Published var creator: Profile
    @Published var streamPublicIDString: String
    @Published var content: Data
    @Published var mediaType: MediaType

    init(mediaType: MediaType, content: Data, creator: Profile, streamPublicIDString: String) {
        self.mediaType = mediaType
        self.content = content
        self.creator = creator
        self.streamPublicIDString = streamPublicIDString
    }

    static func == (lhs: ThoughtViewModel, rhs: ThoughtViewModel) -> Bool {
        lhs.id == rhs.id
    }

    static func createText(creatorProfile: Profile, streamPublicIDString: String, text: String) -> ThoughtViewModel {
        ThoughtViewModel(mediaType: .text, content: text.isEmpty ? Data() : text.data(using: .utf8) ?? Data(), creator: creatorProfile, streamPublicIDString: streamPublicIDString)
    }

    static func createImage(creatorProfile: Profile, streamPublicIDString: String, imageData: Data) -> ThoughtViewModel {
        let imageContent = "Image data: \(imageData.count) bytes"
        print(imageContent)
        return ThoughtViewModel(mediaType: .image, content: imageData, creator: creatorProfile, streamPublicIDString: streamPublicIDString)
    }

    static func createAudio(creatorProfile: Profile, streamPublicIDString: String, audioData: Data) -> ThoughtViewModel {
        let audioContent = "Audio data: \(audioData.count) bytes"
        print(audioContent)
        return ThoughtViewModel(mediaType: .audio, content: audioData, creator: creatorProfile, streamPublicIDString: streamPublicIDString)
    }

    static func createVideo(creatorProfile: Profile, streamPublicIDString: String, videoData: Data) -> ThoughtViewModel {
        let videoContent = "Video data: \(videoData.count) bytes"
        print(videoContent)
        return ThoughtViewModel(mediaType: .video, content: videoData, creator: creatorProfile, streamPublicIDString: streamPublicIDString)
    }
}

struct MessageBubble: View {
    let viewModel: ThoughtViewModel
    let isCurrentUser: Bool
    @State private var isLongPressed = false
    @State private var showMenu = false
    @State private var isResendingOrRecalling = false

    var body: some View {
        HStack {
            if isCurrentUser {
                Spacer()
            }
            VStack(alignment: isCurrentUser ? .trailing : .leading) {
                Text(viewModel.creator.name)
                    .font(.caption)
                    .foregroundColor(.secondary)
                messageContent
                    .padding(10)
                    .background(isCurrentUser ? Color.blue : Color(.gray))
                    .foregroundColor(isCurrentUser ? .white : .primary)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .scaleEffect(isLongPressed ? 1.05 : 1.0)
                    .opacity(isResendingOrRecalling ? 0.5 : 1.0)
                    .animation(.easeInOut(duration: 0.2), value: isLongPressed)
                    .animation(.easeInOut(duration: 0.2), value: isResendingOrRecalling)
                    .gesture(
                        LongPressGesture(minimumDuration: 0.5)
                            .onEnded { _ in
                                isLongPressed = true
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                    showMenu = true
                                }
                            }
                    )
                    .contextMenu {
                        if isCurrentUser {
                            Button(action: resendMessage) {
                                Label("Resend", systemImage: "arrow.clockwise")
                            }
                            Button(action: recallMessage) {
                                Label("Recall", systemImage: "trash")
                            }
                        }
                    }
            }
            if !isCurrentUser {
                Spacer()
            }
        }
    }

    @ViewBuilder
    private var messageContent: some View {
        switch viewModel.mediaType {
        case .text:
            if let text = String(data: viewModel.content, encoding: .utf8) {
                Text(text)
            } else {
                Text("Unable to decode text")
                    .foregroundColor(.red)
            }
        case .image:
            #if os(iOS) || os(visionOS) || targetEnvironment(macCatalyst)
                if let uiImage = UIImage(data: viewModel.content) {
                    Image(uiImage: uiImage)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: 200, maxHeight: 200)
                } else {
                    Text("Unable to load image")
                        .foregroundColor(.red)
                }
            #endif
        case .audio:
            Text("Audio message")
                .foregroundColor(.secondary)
        case .video:
            Text("Video message")
                .foregroundColor(.secondary)
        }
    }

    private func resendMessage() {
        isResendingOrRecalling = true
        // TODO: Implement resend functionality
        print("Resending message")
    }

    private func recallMessage() {
        isResendingOrRecalling = true
        // TODO: Implement recall functionality
        print("Recalling message")
    }
}

struct MessageBubble_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            MessageBubble(viewModel: ThoughtViewModel.createText(
                creatorProfile: Profile(name: "John Doe"),
                streamPublicIDString: "stream1",
                text: "Hello, this is a test message!"
            ),
            isCurrentUser: true)
                .previewDisplayName("Current User")

            MessageBubble(viewModel: ThoughtViewModel.createText(
                creatorProfile: Profile(name: "Jane Smith"),
                streamPublicIDString: "stream1",
                text: "Hi there! This is a response."
            ),
            isCurrentUser: false)
                .previewDisplayName("Other User")
        }
        .padding()
        .previewLayout(.sizeThatFits)
    }
}
