import SwiftUI

struct GroupCreateView: View {
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var sharedState: SharedState
    @StateObject private var viewModel: GroupChatViewModel = ViewModelFactory.shared.makeGroupChatViewModel()

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
                policies: Policies(admission: .openInvitation, interaction: .open, age: .onlyKids)
            )
            print("newStream newStream \(newStream.publicID.base58EncodedString)")

            let account = ViewModelFactory.shared.getCurrentAccount()!
            account.streams.append(newStream)

            try await PersistenceController.shared.saveChanges()

            await MainActor.run {
                sharedState.selectedServer = newStream
            }
        } catch {
            await MainActor.run {
                errorMessage = "Failed to create server: \(error.localizedDescription)"
                showError = true
            }
        }
    }
}
