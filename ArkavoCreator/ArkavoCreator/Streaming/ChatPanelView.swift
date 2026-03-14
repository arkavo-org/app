import SwiftUI

struct ChatPanelView: View {
    @Bindable var viewModel: ChatPanelViewModel
    @Binding var isVisible: Bool
    @State private var isScrolledToBottom = true
    @State private var newMessageCount = 0

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Circle()
                    .fill(viewModel.isConnected ? Color.green : Color.red)
                    .frame(width: 8, height: 8)
                Text("Chat")
                    .font(.headline)
                Spacer()
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isVisible = false
                    }
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(.ultraThinMaterial)
            .overlay(Rectangle().frame(height: 1).foregroundColor(.white.opacity(0.1)), alignment: .bottom)

            // Messages
            ZStack(alignment: .bottom) {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 4) {
                            ForEach(viewModel.messages) { message in
                                ChatMessageRow(message: message)
                                    .id(message.id)
                            }
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .onChange(of: viewModel.messages.count) { _, _ in
                            if isScrolledToBottom {
                                if let lastID = viewModel.messages.last?.id {
                                    withAnimation(.easeOut(duration: 0.1)) {
                                        proxy.scrollTo(lastID, anchor: .bottom)
                                    }
                                }
                            } else {
                                newMessageCount += 1
                            }
                        }
                    }
                    .onScrollGeometryChange(for: Bool.self) { geometry in
                        let atBottom = geometry.contentOffset.y + geometry.containerSize.height >= geometry.contentSize.height - 40
                        return atBottom
                    } action: { _, newValue in
                        isScrolledToBottom = newValue
                        if newValue {
                            newMessageCount = 0
                        }
                    }

                    // "New Messages" pill
                    if !isScrolledToBottom && newMessageCount > 0 {
                        Button {
                            if let lastID = viewModel.messages.last?.id {
                                withAnimation {
                                    proxy.scrollTo(lastID, anchor: .bottom)
                                }
                            }
                            isScrolledToBottom = true
                            newMessageCount = 0
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "arrow.down")
                                    .font(.caption2)
                                Text("\(newMessageCount) new")
                                    .font(.caption2.weight(.medium))
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(Color.accentColor)
                            .foregroundColor(.white)
                            .clipShape(Capsule())
                            .shadow(radius: 4)
                        }
                        .buttonStyle(.plain)
                        .padding(.bottom, 8)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                }

                // Empty state
                if viewModel.messages.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "bubble.left.and.bubble.right")
                            .font(.system(size: 32))
                            .foregroundStyle(.secondary)
                        Text(viewModel.isConnected ? "Waiting for messages..." : "Chat will appear when you go live on Twitch")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }

            // Error display
            if let error = viewModel.error {
                Text(error)
                    .font(.caption2)
                    .foregroundStyle(.red)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .frame(maxWidth: .infinity)
                    .background(Color.red.opacity(0.1))
            }
        }
        .frame(width: 280)
        .background(.ultraThinMaterial)
    }
}

// MARK: - Chat Message Row

private struct ChatMessageRow: View {
    let message: ChatMessage

    var body: some View {
        HStack(alignment: .top, spacing: 4) {
            // Badges
            ForEach(message.badges, id: \.self) { badge in
                Image(systemName: badgeIcon(for: badge))
                    .font(.caption2)
                    .foregroundStyle(badgeColor(for: badge))
            }

            // Display name + message
            Text("\(Text(message.displayName).font(.caption.weight(.bold)).foregroundStyle(usernameColor(for: message.username))): \(message.content)")
                .font(.caption)
                .lineLimit(nil)
        }
        .padding(.vertical, 2)
        .padding(.horizontal, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(message.isHighlighted ? Color.yellow.opacity(0.15) : Color.clear)
        .cornerRadius(4)
    }

    private func badgeIcon(for badge: String) -> String {
        switch badge {
        case "broadcaster": "crown.fill"
        case "moderator": "shield.fill"
        case "subscriber": "star.fill"
        case "vip": "star.circle.fill"
        default: "person.fill"
        }
    }

    private func badgeColor(for badge: String) -> Color {
        switch badge {
        case "broadcaster": .red
        case "moderator": .green
        case "subscriber": .purple
        case "vip": .pink
        default: .secondary
        }
    }

    private func usernameColor(for username: String) -> Color {
        let colors: [Color] = [
            .red, .blue, .green, .orange, .purple, .pink, .teal, .cyan, .mint, .indigo
        ]
        let hash = abs(username.hashValue)
        return colors[hash % colors.count]
    }
}
