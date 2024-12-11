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
        Server(
            id: "2",
            name: "Sewing Hub",
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
    ]
}

// MARK: - Main View

struct DiscordView: View {
    @State private var selectedServer: Server? = Server.sampleServers.first
    @State private var selectedChannel: Channel?

    var body: some View {
        VStack(spacing: 0) {
            // Custom header with server selector
            ServerHeader(
                selectedServer: $selectedServer,
                selectedChannel: $selectedChannel
            )
            .padding(.horizontal)
            .padding(.vertical, 8)
            .background(Color(uiColor: .systemGroupedBackground))

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
        }
    }
}

// MARK: - Server Header

struct ServerHeader: View {
    @Binding var selectedServer: Server?
    @Binding var selectedChannel: Channel?

    var body: some View {
        Menu {
            ForEach(Server.sampleServers) { server in
                Button {
                    selectedServer = server
                    selectedChannel = nil
                } label: {
                    HStack {
                        Image(systemName: "bubble.left.fill")
                            .foregroundColor(.blue)
                            .font(.title3)
                        Text(server.name)
                            .font(.body)
                        Spacer()
                        if server.hasNotification {
                            Text("\(server.unreadCount)")
                                .font(.caption2)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.red)
                                .foregroundColor(.white)
                                .clipShape(Capsule())
                        }
                    }
                }
            }
        } label: {
            HStack {
                if let server = selectedServer {
                    Image(systemName: "bubble.left.fill")
                        .foregroundColor(.blue)
                        .font(.title3)
                    Text(server.name)
                        .font(.headline)
                }
                Spacer()
                Image(systemName: "chevron.down")
                    .foregroundColor(.secondary)
                    .font(.subheadline)
            }
            .padding(.vertical, 4)
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
