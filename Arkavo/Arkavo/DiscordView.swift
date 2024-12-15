import SwiftUI

// MARK: - Models

@MainActor
class DiscordViewModel: ObservableObject {
    @Published var servers = Server.sampleServers
    @Published var selectedServer: Server? = Server.sampleServers.first
    @Published var selectedChannel: Channel?
}

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
    @ObservedObject var viewModel: DiscordViewModel
    @Binding var showCreateView: Bool

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 20) {
                ForEach(viewModel.servers) { server in
                    ServerDetailView(
                        server: server,
                        selectedChannel: $selectedChannel
                    )
                    .padding(.horizontal)
                }
            }
            .padding(.vertical)
        }
        .background(Color(.systemGroupedBackground))
    }
}

struct ServerDetailView: View {
    let server: Server
    @Binding var selectedChannel: Channel?
    @State private var isExpanded = true

    var body: some View {
        VStack(spacing: 0) {
            // Server Header
            Button {
                withAnimation(.spring(response: 0.3)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack {
                    // Server Icon
                    ZStack {
                        Circle()
                            .fill(Color.blue.opacity(0.1))
                            .frame(width: 40, height: 40)

                        if let url = server.imageURL {
                            AsyncImage(url: URL(string: url)) { image in
                                image
                                    .resizable()
                                    .clipShape(Circle())
                            } placeholder: {
                                Image(systemName: "bubble.left.and.bubble.right.fill")
                                    .foregroundStyle(.blue)
                            }
                            .frame(width: 40, height: 40)
                        } else {
                            Image(systemName: "bubble.left.and.bubble.right.fill")
                                .foregroundStyle(.blue)
                        }
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

                        let totalMembers = server.categories
                            .flatMap(\.channels)
                            .filter { $0.type == .voice }
                            .count
                        Text("\(totalMembers) voice channels")
                            .font(.caption)
                            .foregroundStyle(.secondary)
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
                // Channels List
                VStack(spacing: 0) {
                    ForEach(server.categories) { category in
                        ForEach(category.channels) { channel in
                            Button {
                                selectedChannel = channel
                            } label: {
                                ChannelRow(channel: channel)
                                    .padding(.horizontal)
                                    .padding(.vertical, 8)
                                    .background(
                                        channel.id == selectedChannel?.id ?
                                            Color.blue.opacity(0.1) : Color.clear
                                    )
                            }
                            .buttonStyle(.plain)

                            if channel != category.channels.last {
                                Divider()
                                    .padding(.leading, 44)
                            }
                        }
                    }
                }
                .background(Color(.secondarySystemGroupedBackground))
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .transition(.move(edge: .top).combined(with: .opacity))
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
