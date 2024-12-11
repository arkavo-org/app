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
                    ],
                    isExpanded: true
                ),
                ChannelCategory(
                    id: "2",
                    name: "TEXT CHANNELS",
                    channels: [
                        Channel(id: "4", name: "off-topic", type: .text, unreadCount: 2, isActive: false),
                    ],
                    isExpanded: true
                ),
                ChannelCategory(
                    id: "3",
                    name: "VOICE CHANNELS",
                    channels: [
                        Channel(id: "5", name: "General Voice", type: .voice, unreadCount: 0, isActive: false),
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
    @State private var showingServerSheet = false
    @State private var showingChatSheet = false

    var body: some View {
        HStack {
            VStack(spacing: 0) {
                ServerHeader(
                    selectedServer: $selectedServer,
                    selectedChannel: $selectedChannel,
                    showingServerSheet: $showingServerSheet
                )
                .padding(.horizontal)
                .padding(.vertical, 8)

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
        .sheet(isPresented: $showingServerSheet) {
            List(Server.sampleServers) { server in
                Button {
                    selectedServer = server
                    selectedChannel = nil
                    showingServerSheet = false
                } label: {
                    HStack {
                        Label {
                            Text(server.name)
                                .font(.body)
                        } icon: {
                            Image(systemName: "bubble.left.and.bubble.right.fill")
                                .foregroundStyle(server.id == selectedServer?.id ? .blue : .gray)
                        }

                        Spacer()

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
                }
                .foregroundColor(.primary)
            }
        }
        .sheet(isPresented: Binding(
            get: { selectedChannel != nil },
            set: { if !$0 { selectedChannel = nil } }
        )) {
            if let channel = selectedChannel {
                NavigationStack {
                    ChatView(channel: channel)
                }
            }
        }
    }
}

// MARK: - Server Header

struct ServerHeader: View {
    @Binding var selectedServer: Server?
    @Binding var selectedChannel: Channel?
    @Binding var showingServerSheet: Bool

    var body: some View {
        Button {
            showingServerSheet = true
        } label: {
            HStack {
                if let server = selectedServer {
                    Label {
                        Text(server.name)
                            .font(.headline)

                        Spacer()

                        if server.hasNotification {
                            Text("\(server.unreadCount)")
                                .font(.caption)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(.red)
                                .foregroundColor(.white)
                                .clipShape(Capsule())
                        }
                    } icon: {
                        Image(systemName: "bubble.left.and.bubble.right.fill")
                            .foregroundStyle(.blue)
                    }
                }

                Image(systemName: "chevron.down")
                    .foregroundColor(.secondary)
                    .font(.caption)
            }
            .padding(8)
            .background(.bar)
            .clipShape(RoundedRectangle(cornerRadius: 8))
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
                if category.isExpanded {
                    ForEach(category.channels) { channel in
                        ChannelRow(channel: channel)
                            .tag(channel)
                    }
                }
            } header: {
                CategoryHeader(category: category) {
                    if let index = categories.firstIndex(where: { $0.id == category.id }) {
                        withAnimation {
                            categories[index].isExpanded.toggle()
                        }
                    }
                }
            }
        }
        .listStyle(.inset)
    }
}

struct CategoryHeader: View {
    let category: ChannelCategory
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                Image(systemName: category.isExpanded ? "chevron.down" : "chevron.right")
                    .font(.caption2)
                    .foregroundColor(.secondary)

                Text(category.name)
                    .font(.caption)
                    .bold()
                    .foregroundColor(.secondary)
            }
        }
    }
}

struct ChannelRow: View {
    let channel: Channel

    var body: some View {
        HStack {
            Label {
                Text(channel.name)
                    .font(.body)
            } icon: {
                Image(systemName: channel.type.icon)
                    .foregroundStyle(channel.type.color)
            }

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
        .padding(.vertical, 2)
    }
}

// MARK: - Preview

#Preview {
    DiscordView()
}
