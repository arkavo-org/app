import ArkavoKit
import CryptoKit
import FlatBuffers
import Foundation
import OpenTDFKit
import SwiftUI

struct ChatView: View {
    @StateObject var viewModel: ChatViewModel
    @State private var messageText = ""
    @State private var showingAttachmentPicker = false
    @State private var isConnecting = false
    @State private var showError = false
    @State private var errorMessage = ""
    @State private var keyboardHeight: CGFloat = 0
    @Environment(\.presentationMode) var presentationMode

    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 0) {
                // Direct message header, only shown when in direct message mode
                if viewModel.isDirectMessageChat {
                    VStack(spacing: 0) {
                        HStack {
                            Button(action: {
                                // Clear the direct message profile when dismissing
                                let sharedState = ViewModelFactory.shared.getSharedState()
                                // Use NSNull() since nil isn't compatible with Any
                                sharedState.setState(NSNull(), forKey: "selectedDirectMessageProfile")
                            }) {
                                HStack {
                                    Image(systemName: "chevron.left")
                                    Text("Back")
                                }
                                .foregroundColor(.blue)
                            }

                            Spacer()

                            Text("Chat with \(viewModel.directMessageRecipientName)")
                                .font(.headline)
                                .foregroundColor(.primary)

                            Spacer()
                        }
                        .padding(.horizontal)
                        .padding(.vertical, 8)

                        Divider()
                    }
                    .background(Color(.secondarySystemBackground))
                }

                ScrollViewReader { scrollProxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 16) {
                            ForEach(viewModel.messages) { message in
                                MessageRow(message: message)
                                    .id(message.id) // Ensure each message has an id for scrolling
                            }
                        }
                        .padding()
                    }
                    .frame(maxHeight: max(100, geometry.size.height - keyboardHeight - 56))
                    .onChange(of: viewModel.messages) { _, _ in
                        // Scroll to the last message with animation
                        if let lastMessage = viewModel.messages.last {
                            withAnimation {
                                scrollProxy.scrollTo(lastMessage.id, anchor: .bottom)
                            }
                        }
                    }
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
                    },
                )
            }
        }
        .alert("Error", isPresented: $showError) {
            Button("OK") {
                // acknowledge to close
            }
        } message: {
            Text(errorMessage)
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { notification in
            if let keyboardFrame = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect {
                withAnimation(.easeOut(duration: 0.16)) {
                    keyboardHeight = keyboardFrame.height
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
            withAnimation(.easeOut(duration: 0.16)) {
                keyboardHeight = 0
            }
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
                        .foregroundColor(.blue),
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
                    case .text, .post, .say:
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
                                        .foregroundColor(.gray),
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
                                        .foregroundColor(.gray),
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
    var streamPublicID: Data

    var body: some View {
        ZStack {
            // Semi-transparent background
            Color.black.opacity(0.7)
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
                ChatView(
                    viewModel: ViewModelFactory.shared.makeChatViewModel(
                        streamPublicID: streamPublicID,
                    ),
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .focused($isChatFieldFocused)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.top, 44) // Start below status bar
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

    private func getAppropriateStreamPublicID() -> Data? {
        // If there's a selected server, use that
        if let selectedServer = sharedState.selectedStreamPublicID {
            return selectedServer
        }

        // Otherwise, get the appropriate stream based on content type
//        if let account = ViewModelFactory.shared.getCurrentAccount() {
//            if sharedState.selectedVideo != nil {
//                return account.streams.first
//            } else if let thought = sharedState.selectedThought {
//                return account.streams.first { stream in
//                    stream.thoughts.contains { $0.id == thought.id }
//                }
//            }
//        }

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
