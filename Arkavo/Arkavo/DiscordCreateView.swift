import SwiftUI

struct CreateServerView: View {
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var sharedState: SharedState
    @StateObject private var viewModel: DiscordViewModel = ViewModelFactory.shared.makeDiscordViewModel()

    @State private var serverName = ""
    @State private var selectedIcon: String? = nil

    let icons = ["gamecontroller", "leaf", "book", "music.note", "star", "heart"]

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
                                    .foregroundColor(.primary)
                                    .frame(width: 60, height: 60)
                                    .background(
                                        Circle()
                                            .fill(selectedIcon == icon ? Color.blue.opacity(0.2) : Color.clear)
                                    )
                                    .overlay(
                                        Circle()
                                            .stroke(selectedIcon == icon ? Color.blue : Color.gray, lineWidth: 2)
                                    )
                                    .contentShape(Circle())
                            }
                        }
                    }
                    .padding(.vertical, 8)
                }
                .listRowInsets(EdgeInsets())
            }
        }
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
            icon: selectedIcon ?? "message",
            channels: [],
            categories: [
                ChannelCategory(
                    id: UUID().uuidString,
                    name: "TEXT CHANNELS",
                    channels: [
                        Channel(id: UUID().uuidString, name: "general", type: .text, unreadCount: 0, isActive: false),
                        Channel(id: UUID().uuidString, name: "shared", type: .text, unreadCount: 0, isActive: false),
                    ],
                    isExpanded: true
                ),
            ],
            unreadCount: 0,
            hasNotification: false
        )
        viewModel.servers.insert(newServer, at: 0)
        sharedState.showCreateView.toggle()
    }
}
