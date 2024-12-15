import SwiftUI

// MARK: - Creation Views

struct CreateServerView: View {
    @Environment(\.dismiss) var dismiss
    @ObservedObject var viewModel: DiscordViewModel
    @Binding var showCreateView: Bool
    @State private var serverName = ""
    @State private var selectedIcon: String? = nil

    let icons = ["gamecontroller.fill", "leaf.fill", "book.fill", "music.note", "star.fill", "heart.fill"]

    var body: some View {
        Form {
            Section("Server Details") {
                TextField("Server Name", text: $serverName)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 16) {
                        ForEach(icons, id: \.self) { icon in
                            Button {
                                selectedIcon = icon
                            } label: {
                                Image(systemName: icon)
                                    .font(.title)
                                    .frame(width: 60, height: 60)
                                    .background(selectedIcon == icon ? .blue.opacity(0.2) : .clear)
                                    .clipShape(Circle())
                                    .overlay(
                                        Circle()
                                            .stroke(selectedIcon == icon ? .blue : .gray, lineWidth: 2)
                                    )
                            }
                        }
                    }
                    .padding(.vertical, 8)
                }
            }
        }
        .navigationTitle("Create Server")
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Create") {
                    createServer()
                    dismiss()
                }
                .disabled(serverName.isEmpty)
            }
        }
    }

    private func createServer() {
        let newServer = Server(
            id: UUID().uuidString,
            name: serverName,
            imageURL: nil,
            channels: [],
            categories: [
                ChannelCategory(
                    id: UUID().uuidString,
                    name: "TEXT CHANNELS",
                    channels: [
                        Channel(id: UUID().uuidString, name: "general", type: .text, unreadCount: 0, isActive: false),
                    ],
                    isExpanded: true
                ),
            ],
            unreadCount: 0,
            hasNotification: false
        )
        viewModel.servers.append(newServer)
        showCreateView.toggle()
    }
}

struct CreateChannelView: View {
    @Environment(\.dismiss) var dismiss
    let server: Server
    @Binding var categories: [ChannelCategory]

    @State private var channelName = ""
    @State private var selectedType: ChannelType = .text
    @State private var selectedCategory: ChannelCategory?

    var body: some View {
        NavigationStack {
            Form {
                Section("Channel Details") {
                    TextField("Channel Name", text: $channelName)

                    Picker("Channel Type", selection: $selectedType) {
                        Label("Text Channel", systemImage: ChannelType.text.icon)
                            .tag(ChannelType.text)
                        Label("Voice Channel", systemImage: ChannelType.voice.icon)
                            .tag(ChannelType.voice)
                        Label("Announcement", systemImage: ChannelType.announcement.icon)
                            .tag(ChannelType.announcement)
                    }

                    Picker("Category", selection: $selectedCategory) {
                        ForEach(categories) { category in
                            Text(category.name)
                                .tag(Optional(category))
                        }
                    }
                }
            }
            .navigationTitle("Create Channel")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") {
                        createChannel()
                        dismiss()
                    }
                    .disabled(channelName.isEmpty || selectedCategory == nil)
                }
            }
            .onAppear {
                selectedCategory = categories.first
            }
        }
    }

    private func createChannel() {
        guard let categoryIndex = categories.firstIndex(where: { $0.id == selectedCategory?.id }) else { return }

        let newChannel = Channel(
            id: UUID().uuidString,
            name: channelName.lowercased(),
            type: selectedType,
            unreadCount: 0,
            isActive: false
        )

        categories[categoryIndex].channels.append(newChannel)
    }
}
