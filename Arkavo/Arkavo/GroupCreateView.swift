import SwiftUI

struct GroupCreateView: View {
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var sharedState: SharedState
    @StateObject private var viewModel: DiscordViewModel = ViewModelFactory.shared.makeDiscordViewModel()

    @State private var serverName = ""
    @State private var showError = false
    @State private var errorMessage = ""
    @FocusState private var isNameFieldFocused: Bool

    var body: some View {
        Form {
            Section {
                TextField("Server Name", text: $serverName)
                    .focused($isNameFieldFocused)
                    .autocapitalization(.words)
                    .textContentType(.organizationName)
            } header: {
                Text("Server Details")
            } footer: {
                Text("This will be the name of your new community")
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button("Cancel") {
                    sharedState.showCreateView = false
                    dismiss()
                }
            }

            ToolbarItem(placement: .navigationBarTrailing) {
                Button("Create") {
                    Task {
                        await createServer()
                        sharedState.showCreateView = false
                        dismiss()
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
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                isNameFieldFocused = true
            }
        }
    }

    private func createServer() async {
        do {
            let serverProfile = Profile(name: serverName)

            let newStream = Stream(
                creatorPublicID: ViewModelFactory.shared.getCurrentProfile()!.publicID,
                profile: serverProfile,
                policies: Policies(admission: .open, interaction: .open, age: .onlyKids)
            )
            print("newStream newStream \(newStream.publicID.base58EncodedString)")
            let server = Server(
                id: newStream.id.uuidString,
                name: serverName,
                imageURL: nil,
                icon: "bubble.left.and.bubble.right",
                unreadCount: 0,
                hasNotification: false,
                description: "description",
                policies: StreamPolicies(
                    agePolicy: .onlyKids,
                    admissionPolicy: .open,
                    interactionPolicy: .open
                )
            )

            let account = ViewModelFactory.shared.getCurrentAccount()!
            account.streams.append(newStream)

            try await PersistenceController.shared.saveChanges()

            await MainActor.run {
                sharedState.selectedServer = server
            }
        } catch {
            await MainActor.run {
                errorMessage = "Failed to create server: \(error.localizedDescription)"
                showError = true
            }
        }
    }
}
