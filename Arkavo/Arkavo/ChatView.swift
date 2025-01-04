import ArkavoSocial
import CryptoKit
import FlatBuffers
import OpenTDFKit
import SwiftUI

struct ChatView: View {
    @StateObject var viewModel: ChatViewModel
    @State private var messageText = ""
    @State private var showingAttachmentPicker = false
    @State private var isConnecting = false
    @State private var showError = false
    @State private var errorMessage = ""

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 16) {
                    ForEach(viewModel.messages) { message in
                        MessageRow(message: message)
                    }
                }
                .padding()
            }

            MessageInputBar(
                messageText: $messageText,
                placeholder: "Type a message...",
                onAttachmentTap: { showingAttachmentPicker.toggle() },
                onSend: {
                    Task {
                        do {
                            try await viewModel.sendMessage(content: messageText)
                            messageText = ""
                        } catch {
                            errorMessage = error.localizedDescription
                            showError = true
                        }
                    }
                }
            )
        }
        .alert("Error", isPresented: $showError) {
            Button("OK") {
                // acknowledge to close
            }
        } message: {
            Text(errorMessage)
        }
    }
}

// MARK: - Supporting Views

struct MessageInputBar: View {
    @Binding var messageText: String
    let placeholder: String
    let onAttachmentTap: () -> Void
    let onSend: () -> Void
    @FocusState var isFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            Divider()
            HStack(spacing: 12) {
//                Button(action: onAttachmentTap) {
//                    Image(systemName: "plus.circle.fill")
//                        .font(.title2)
//                        .foregroundColor(.blue)
//                }

                TextField(placeholder, text: $messageText)
                    .textFieldStyle(.roundedBorder)
                    .focused($isFocused)

                Button(action: onSend) {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.title2)
                        .foregroundColor(messageText.isEmpty ? .gray : .blue)
                }
                .disabled(messageText.isEmpty)
            }
            .padding()
        }
        .background(.bar)
    }
}

struct MessageRow: View {
    let message: ChatMessage

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // Avatar
            Circle()
                .fill(Color.blue.opacity(0.2))
                .frame(width: 40, height: 40)
                .overlay(
                    Text(message.username.prefix(1))
                        .font(.headline)
                        .foregroundColor(.blue)
                )

            VStack(alignment: .leading, spacing: 4) {
                // Header
                HStack {
                    if message.isPinned {
                        Image(systemName: "pin.fill")
                            .foregroundColor(.orange)
                    }

                    Text(message.username)
                        .font(.headline)

                    Image(systemName: message.mediaType.icon)
                        .foregroundColor(.blue)

                    Text(message.timestamp, style: .relative)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                // Content
                Group {
                    switch message.mediaType {
                    case .text:
                        Text(message.content)
                            .font(.body)
                            .textSelection(.enabled)

                    case .image:
                        ImageMessageView(imageData: message.rawContent)

                    case .video:
                        VStack(alignment: .leading) {
                            Text(message.content)
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Rectangle()
                                .fill(Color.gray.opacity(0.2))
                                .frame(height: 200)
                                .overlay(
                                    Image(systemName: "play.rectangle.fill")
                                        .foregroundColor(.gray)
                                )
                        }

                    case .audio:
                        VStack(alignment: .leading) {
                            Text(message.content)
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Rectangle()
                                .fill(Color.gray.opacity(0.2))
                                .frame(height: 50)
                                .overlay(
                                    Image(systemName: "waveform")
                                        .foregroundColor(.gray)
                                )
                        }
                    }
                }

                // Reactions
                if !message.reactions.isEmpty {
                    HStack {
                        ForEach(message.reactions) { reaction in
                            ReactionButton(reaction: reaction)
                        }
                    }
                }
            }
        }
    }
}

struct ImageMessageView: View {
    let imageData: Data
    @State private var image: UIImage?
    @State private var isLoading = true
    @State private var isExpanded = false

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxHeight: 200)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .onTapGesture {
                        isExpanded = true
                    }
                    .fullScreenCover(isPresented: $isExpanded) {
                        FullScreenImageView(image: image)
                    }
            } else if isLoading {
                ProgressView()
                    .frame(height: 200)
            } else {
                errorView
            }
        }
        .onAppear {
            loadImage()
        }
    }

    private var errorView: some View {
        VStack {
            Image(systemName: "exclamationmark.triangle")
                .foregroundColor(.red)
            Text("Failed to load image")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(height: 200)
    }

    private func loadImage() {
        isLoading = true
        if let uiImage = UIImage(data: imageData) {
            image = uiImage
        }
        isLoading = false
    }
}

struct FullScreenImageView: View {
    @Environment(\.dismiss) private var dismiss
    let image: UIImage
    @State private var scale: CGFloat = 1.0
    @State private var lastScale: CGFloat = 1.0
    @GestureState private var magnifyBy = CGFloat(1.0)

    var body: some View {
        NavigationView {
            GeometryReader { proxy in
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: proxy.size.width, height: proxy.size.height)
                    .scaleEffect(scale * magnifyBy)
                    .gesture(magnification)
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Close") {
                        dismiss()
                    }
                }
            }
        }
    }

    private var magnification: some Gesture {
        MagnificationGesture()
            .updating($magnifyBy) { currentState, gestureState, _ in
                gestureState = currentState
            }
            .onEnded { value in
                scale *= value
            }
    }
}

struct ReactionButton: View {
    let reaction: MessageReaction

    var body: some View {
        Button(action: { /* Toggle reaction */ }) {
            HStack {
                Text(reaction.emoji)
                Text("\(reaction.count)")
                    .font(.caption)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(reaction.hasReacted ? Color.blue.opacity(0.2) : Color.secondary.opacity(0.2))
            .cornerRadius(12)
        }
    }
}

struct ChatOverlay: View {
    @EnvironmentObject var sharedState: SharedState
    @FocusState private var isChatFieldFocused: Bool

    var body: some View {
        ZStack {
            // Semi-transparent background
            Color.black.opacity(0.3)
                .ignoresSafeArea()
                .onTapGesture {
                    withAnimation {
                        sharedState.showChatOverlay = false
                    }
                }
                .zIndex(1)

            // Chat content
            VStack(spacing: 0) {
                // Header
                HStack {
                    Text("Comments")
                        .font(.headline)

                    Spacer()

                    Button {
                        withAnimation {
                            sharedState.showChatOverlay = false
                        }
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                    }
                }
                .padding()
                .background(.ultraThinMaterial)

                // Chat view
                if let stream = getAppropriateStream() {
                    ChatView(
                        viewModel: ViewModelFactory.shared.makeChatViewModel(
                            stream: stream
                        )
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .focused($isChatFieldFocused)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .padding(.top, 44) // Start below status bar
            .background(.regularMaterial)
            .ignoresSafeArea(.keyboard)
            .zIndex(2)
        }
        .transition(.move(edge: .bottom))
        .ignoresSafeArea()
        .onAppear {
            // Delay focus slightly to allow animation to complete
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                isChatFieldFocused = true
            }
        }
    }

    private func getAppropriateStream() -> Stream? {
        // If there's a selected server, use that
        if let selectedServer = sharedState.selectedStream {
            return selectedServer
        }

        // Otherwise, get the appropriate stream based on content type
        if let account = ViewModelFactory.shared.getCurrentAccount() {
            if sharedState.selectedVideo != nil {
                // For video content, use the first stream (as per existing logic)
                return account.streams.first
            } else if let thought = sharedState.selectedThought {
                // For posts/thoughts, find the matching stream
                return account.streams.first { stream in
                    stream.thoughts.contains { $0.id == thought.id }
                }
            }
        }

        return nil
    }
}

// MARK: - Enhanced Message Models

struct ChatMessage: Identifiable, Equatable {
    let id: String
    let userId: String
    let username: String
    let content: String
    let timestamp: Date
    let attachments: [MessageAttachment]
    var reactions: [MessageReaction]
    var isPinned: Bool
    let publicID: Data
    let creatorPublicID: Data
    let mediaType: MediaType
    let rawContent: Data // Store original content for media handling

    static func == (lhs: ChatMessage, rhs: ChatMessage) -> Bool {
        lhs.id == rhs.id
    }
}

struct MessageAttachment: Identifiable {
    let id: String
    let type: AttachmentType
    let url: String
}

enum AttachmentType {
    case image
    case video
    case file
}

struct MessageReaction: Identifiable {
    let id: String
    let emoji: String
    var count: Int
    var hasReacted: Bool
}
