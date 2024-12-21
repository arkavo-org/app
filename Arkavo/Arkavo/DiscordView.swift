import ArkavoSocial
import SwiftUI

// MARK: - Models

@MainActor
class DiscordViewModel: ObservableObject {
    let client: ArkavoClient
    let account: Account
    let profile: Profile
    @Published var streams: [Stream] = []
    private var chatViewModels: [String: ChatViewModel] = [:] // Cache of ChatViewModels

    init(client: ArkavoClient, account: Account, profile: Profile) {
        self.client = client
        self.account = account
        self.profile = profile
        Task {
            await loadStreams()
        }
    }

    private func loadStreams() async {
        streams = account.streams
    }

    func shareVideo(_ video: Video, to stream: Stream) async {
        if let defaultChannel = defaultChannel(for: stream) {
            print("Sharing video \(video.id) to stream \(stream.profile.name)")
            let chatViewModel = chatViewModel(for: defaultChannel)
            do {
                try await chatViewModel.sendMessage(content: "Shared video \(video.id) to stream \(stream.profile.name)")
            } catch {
                print("Error sending message: \(error)")
            }
        }
    }

    private func defaultChannel(for stream: Stream) -> Channel? {
        Channel(id: stream.id.uuidString,
                name: "default",
                type: .text,
                unreadCount: stream.thoughts.count,
                isActive: false)
    }

    func chatViewModel(for channel: Channel) -> ChatViewModel {
        if let existing = chatViewModels[channel.id] {
            return existing
        }
        let newViewModel = ViewModelFactory.shared.makeChatViewModel(channel: channel)
        chatViewModels[channel.id] = newViewModel
        return newViewModel
    }

    // Convert Stream to Server view model
    func serverFromStream(_ stream: Stream) -> Server {
        let defaultCategory = ChannelCategory(
            id: "\(stream.id)_default",
            name: "STREAM",
            channels: [
                defaultChannel(for: stream) ??
                    Channel(id: stream.id.uuidString,
                            name: "default",
                            type: .text,
                            unreadCount: stream.thoughts.count,
                            isActive: false),
            ],
            isExpanded: true
        )

        return Server(
            id: stream.id.uuidString,
            name: stream.profile.name,
            imageURL: nil,
            icon: iconForStream(stream),
            channels: [],
            categories: [defaultCategory],
            unreadCount: stream.thoughts.count,
            hasNotification: !stream.thoughts.isEmpty
        )
    }

    private func iconForStream(_ stream: Stream) -> String {
        switch stream.agePolicy {
        case .onlyAdults: "person.fill"
        case .onlyKids: "figure.child"
        case .onlyTeens: "figure.wave"
        case .forAll: "person.3.fill"
        }
    }
}

struct Server: Identifiable, Hashable {
    let id: String
    let name: String
    let imageURL: String?
    let icon: String
    let channels: [Channel]
    let categories: [ChannelCategory]
    var unreadCount: Int
    var hasNotification: Bool
}

struct ChannelCategory: Identifiable, Hashable {
    let id: String
    let name: String
    var channels: [Channel]
    var isExpanded: Bool
}

struct Channel: Identifiable, Hashable {
    let id: String
    let name: String
    let type: ChannelType
    var unreadCount: Int
    var isActive: Bool

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    static func == (lhs: Channel, rhs: Channel) -> Bool {
        lhs.id == rhs.id
    }
}

enum ChannelType {
    case text
    case voice
    case announcement

    var icon: String {
        switch self {
        case .text: "text.bubble.fill"
        case .voice: "waveform.circle.fill"
        case .announcement: "megaphone.fill"
        }
    }

    var color: Color {
        switch self {
        case .text: .blue
        case .voice: .green
        case .announcement: .orange
        }
    }
}

// MARK: - Main View

struct DiscordView: View {
    @EnvironmentObject var sharedState: SharedState
    @StateObject private var viewModel: DiscordViewModel = ViewModelFactory.shared.makeDiscordViewModel()
    @State private var navigationPath = NavigationPath()

    var body: some View {
        NavigationStack(path: $navigationPath) {
            ZStack {
                Color(.systemGroupedBackground)
                    .ignoresSafeArea()

                ScrollView(.vertical, showsIndicators: false) {
                    LazyVStack(spacing: 20) {
                        if viewModel.streams.isEmpty {
                            VStack(spacing: 16) {
                                Image(systemName: "bubble.left.and.bubble.right")
                                    .font(.system(size: 48))
                                    .foregroundStyle(.secondary)
                                Text("No Communities Yet")
                                    .font(.headline)
                                Text("Create or join a community to get started")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.top, 100)
                        } else if let selectedServer = sharedState.selectedServer {
                            ServerDetailView(
                                server: selectedServer,
                                onChannelSelect: { channel in
                                    navigationPath.append(channel)
                                }
                            )
                            .padding(.horizontal)
                        } else {
                            ForEach(viewModel.streams) { stream in
                                let server = viewModel.serverFromStream(stream)
                                ServerDetailView(
                                    server: server,
                                    stream: stream,
                                    onChannelSelect: { channel in
                                        navigationPath.append(channel)
                                    }
                                )
                                .padding(.horizontal)
                            }
                        }
                    }
                    .padding(.vertical)
                }
            }
            .navigationDestination(for: Channel.self) { channel in
                createChatView(for: channel)
            }
        }
    }

    func createChatView(for channel: Channel) -> some View {
        let chatViewModel = viewModel.chatViewModel(for: channel)
        let stream = viewModel.streams.first(where: { $0.id.uuidString == channel.id })

        return ChatView(viewModel: chatViewModel, stream: stream)
            .navigationTitle(channel.name)
    }
}

struct ServerDetailView: View {
    @EnvironmentObject var sharedState: SharedState
    let server: Server
    var stream: Stream? // Optional since selected server might not have associated stream
    let onChannelSelect: (Channel) -> Void
    @State private var isExpanded = true

    var body: some View {
        VStack(spacing: 0) {
            // Server Header
            Button {
                withAnimation(.spring(response: 0.3)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(spacing: 12) {
                    ZStack {
                        Circle()
                            .fill(Color.blue.opacity(0.1))
                            .frame(width: 40, height: 40)

                        Image(systemName: server.icon)
                            .font(.title3)
                            .foregroundStyle(.blue)
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        HStack {
                            Text(server.name)
                                .font(.headline)

                            if server.hasNotification {
                                Text("\(server.unreadCount)")
                                    .font(.caption2)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(.red)
                                    .foregroundColor(.white)
                                    .clipShape(Capsule())
                            }
                        }

                        if let stream, let latestThought = stream.thoughts.last {
                            Text(latestThought.nano.hexEncodedString())
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        } else {
                            Text("No thoughts yet")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Spacer()

                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                }
                .padding()
                .background(Color(.secondarySystemGroupedBackground))
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .buttonStyle(.plain)

            if isExpanded {
                VStack(spacing: 0) {
                    ForEach(server.categories) { category in
                        ForEach(category.channels) { channel in
                            Button {
                                sharedState.selectedChannel = channel
                                onChannelSelect(channel)
                            } label: {
                                ChannelRow(channel: channel)
                                    .padding(.horizontal)
                                    .padding(.vertical, 8)
                                    .background(
                                        channel.id == sharedState.selectedChannel?.id ?
                                            Color.blue.opacity(0.1) : Color.clear
                                    )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .background(Color(.secondarySystemGroupedBackground))
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
        }
    }
}

struct ChannelRow: View {
    let channel: Channel

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: channel.type.icon)
                .foregroundStyle(channel.type.color)
                .frame(width: 24)

            Text(channel.name)
                .font(.body)

            Spacer()

            if channel.unreadCount > 0 {
                Text("\(channel.unreadCount)")
                    .font(.caption2)
                    .padding(4)
                    .background(.red)
                    .foregroundColor(.white)
                    .clipShape(Circle())
            }
        }
    }
}
