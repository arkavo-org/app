import SwiftUI

// MARK: - Models

struct Server: Identifiable, Hashable {
    let id: String
    let name: String
    let imageURL: String?
    let channels: [Channel]
    let categories: [ChannelCategory]
    var unreadCount: Int
    var hasNotification: Bool
}

struct ChannelCategory: Identifiable, Hashable {
    let id: String
    let name: String
    let channels: [Channel]
    var isExpanded: Bool
}

struct Channel: Identifiable, Hashable {
    let id: String
    let name: String
    let type: ChannelType
    var unreadCount: Int
    var isActive: Bool

    // Hashable conformance
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
        case .text: "number"
        case .voice: "speaker.wave.2.fill"
        case .announcement: "megaphone.fill"
        }
    }
}

// MARK: - Sample Data

extension Server {
    static let sampleServers = [
        Server(
            id: "1",
            name: "Gaming Hub",
            imageURL: nil,
            channels: [],
            categories: [
                ChannelCategory(
                    id: "1",
                    name: "INFORMATION",
                    channels: [
                        Channel(id: "1", name: "announcements", type: .announcement, unreadCount: 0, isActive: false),
                        Channel(id: "2", name: "rules", type: .text, unreadCount: 0, isActive: false),
                    ],
                    isExpanded: true
                ),
                ChannelCategory(
                    id: "2",
                    name: "TEXT CHANNELS",
                    channels: [
                        Channel(id: "3", name: "general", type: .text, unreadCount: 5, isActive: true),
                        Channel(id: "4", name: "off-topic", type: .text, unreadCount: 2, isActive: false),
                    ],
                    isExpanded: true
                ),
                ChannelCategory(
                    id: "3",
                    name: "VOICE CHANNELS",
                    channels: [
                        Channel(id: "5", name: "General Voice", type: .voice, unreadCount: 0, isActive: false),
                        Channel(id: "6", name: "Gaming Voice", type: .voice, unreadCount: 0, isActive: false),
                    ],
                    isExpanded: true
                ),
            ],
            unreadCount: 7,
            hasNotification: true
        ),
        // Add more sample servers...
    ]
}

// MARK: - Main View

struct DiscordView: View {
    @State private var selectedServer: Server? = Server.sampleServers.first
    @State private var selectedChannel: Channel?
    @State private var showServerList = false // For iPhone
    @State private var messageText = ""

    var body: some View {
        NavigationSplitView {
            ServerListView(
                servers: Server.sampleServers,
                selectedServer: $selectedServer
            )
            .navigationTitle("Servers")
        } content: {
            if let server = selectedServer {
                ChannelListView(
                    server: server,
                    selectedChannel: $selectedChannel
                )
            } else {
                ContentUnavailableView(
                    "Select a Server",
                    systemImage: "server.rack",
                    description: Text("Choose a server to see its channels")
                )
            }
        } detail: {
            if let channel = selectedChannel {
                ChatView(channel: channel)
            } else {
                ContentUnavailableView(
                    "Select a Channel",
                    systemImage: "number.square.fill",
                    description: Text("Choose a channel to start chatting")
                )
            }
        }
    }
}

// MARK: - Server List View

struct ServerListView: View {
    let servers: [Server]
    @Binding var selectedServer: Server?

    var body: some View {
        List(servers, selection: $selectedServer) { server in
            ServerRow(server: server)
                .tag(server)
        }
        .listStyle(.sidebar)
    }
}

struct ServerRow: View {
    let server: Server

    var body: some View {
        HStack {
            ZStack(alignment: .topTrailing) {
                Group {
                    if let imageURL = server.imageURL {
                        AsyncImage(url: URL(string: imageURL)) { image in
                            image
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                        } placeholder: {
                            Color.gray.opacity(0.3)
                        }
                    } else {
                        Text(server.name.prefix(1))
                            .font(.title2.bold())
                            .foregroundColor(.white)
                            .frame(width: 48, height: 48)
                            .background(Color.blue)
                    }
                }
                .frame(width: 48, height: 48)
                .clipShape(RoundedRectangle(cornerRadius: 12))

                if server.hasNotification {
                    Circle()
                        .fill(Color.red)
                        .frame(width: 16, height: 16)
                        .overlay(
                            Text("\(server.unreadCount)")
                                .font(.caption2)
                                .foregroundColor(.white)
                        )
                }
            }

            Text(server.name)
                .font(.headline)
        }
    }
}

// MARK: - Channel List View

struct ChannelListView: View {
    let server: Server
    @Binding var selectedChannel: Channel?
    @State private var categories: [ChannelCategory]

    init(server: Server, selectedChannel: Binding<Channel?>) {
        self.server = server
        _selectedChannel = selectedChannel
        _categories = State(initialValue: server.categories)
    }

    var body: some View {
        List(categories, selection: $selectedChannel) { category in
            Section {
                ForEach(category.channels) { channel in
                    ChannelRow(channel: channel)
                        .tag(channel)
                }
            } header: {
                CategoryHeader(category: category) {
                    if let index = categories.firstIndex(where: { $0.id == category.id }) {
                        categories[index].isExpanded.toggle()
                    }
                }
            }
        }
        .navigationTitle(server.name)
    }
}

struct CategoryHeader: View {
    let category: ChannelCategory
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                Image(systemName: "chevron.right")
                    .rotationEffect(.degrees(category.isExpanded ? 90 : 0))
                Text(category.name)
                    .font(.caption)
                    .bold()
            }
            .foregroundColor(.primary)
        }
    }
}

struct ChannelRow: View {
    let channel: Channel

    var body: some View {
        HStack {
            Image(systemName: channel.type.icon)
                .foregroundColor(.secondary)

            Text(channel.name)
                .font(.body)

            if channel.unreadCount > 0 {
                Spacer()
                Text("\(channel.unreadCount)")
                    .font(.caption2)
                    .padding(4)
                    .background(Color.red)
                    .foregroundColor(.white)
                    .clipShape(Circle())
            }
        }
    }
}

// MARK: - Preview

#Preview {
    DiscordView()
}
