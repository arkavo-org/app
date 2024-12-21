import SwiftUI

struct CreateServerView: View {
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var sharedState: SharedState
    @StateObject private var viewModel: DiscordViewModel = ViewModelFactory.shared.makeDiscordViewModel()

    @State private var serverName = ""
    @State private var selectedIcon: String? = "bubble.left.and.bubble.right.fill"
    @State private var showError = false
    @State private var errorMessage = ""

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
                    Task {
                        await createServer()
                        sharedState.showCreateView = false
                    }
                }
                .disabled(serverName.isEmpty)
            }
        }
        .alert("Error", isPresented: $showError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage)
        }
    }

    private func createServer() async {
        do {
            // Create a new profile for the server
            let serverProfile = Profile(name: serverName)

            // Create a new stream
            let newStream = Stream(
                creatorPublicID: ViewModelFactory.shared.getCurrentProfile()!.publicID,
                profile: serverProfile,
                admissionPolicy: .open,
                interactionPolicy: .open,
                agePolicy: .forAll
            )

            // Create server view model
            let server = Server(
                id: newStream.id.uuidString,
                name: serverName,
                imageURL: nil,
                icon: selectedIcon ?? "bubble.left.and.bubble.right.fill",
                channels: [],
                categories: [
                    ChannelCategory(
                        id: "\(newStream.id)_default",
                        name: "GENERAL",
                        channels: [
                            Channel(
                                id: newStream.id.uuidString,
                                name: "general",
                                type: .text,
                                unreadCount: 0,
                                isActive: false
                            ),
                        ],
                        isExpanded: true
                    ),
                ],
                unreadCount: 0,
                hasNotification: false
            )

            // Add stream to account
            let account = ViewModelFactory.shared.getCurrentAccount()!
            account.streams.append(newStream)

            // Save changes
            try await PersistenceController.shared.saveChanges()

            // Update shared state
            await MainActor.run {
                sharedState.selectedServer = server
                sharedState.servers.append(server)
                sharedState.showCreateView = false
            }
            dismiss()
        } catch {
            await MainActor.run {
                errorMessage = "Failed to create server: \(error.localizedDescription)"
                showError = true
            }
        }
    }
}
