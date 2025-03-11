import SwiftUI

struct GroupCreateView: View {
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var sharedState: SharedState
    @StateObject var viewModel: GroupViewModel

    @State private var groupName = ""
    @State private var showError = false
    @State private var errorMessage = ""
    @FocusState private var isNameFieldFocused: Bool

    var body: some View {
        Form {
            Section {
                TextField("Group Name", text: $groupName)
                    .focused($isNameFieldFocused)
                    .autocapitalization(.words)
                    .textContentType(.organizationName)
            } header: {
                Text("Group Details")
            } footer: {
                Text("This will be the name of your new group")
            }
            
            Section {
                Button(action: {
                    Task {
                        await createInnerCircleGroup()
                        sharedState.showCreateView = false
                        dismiss()
                    }
                }) {
                    HStack {
                        Image(systemName: "antenna.radiowaves.left.and.right")
                            .foregroundColor(.blue)
                        Text("Create Inner Circle (Local P2P)")
                            .foregroundColor(.primary)
                    }
                }
            } header: {
                Text("Special Groups")
            } footer: {
                Text("Inner Circle enables direct peer-to-peer communication with nearby devices")
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
                        await createGroup()
                        sharedState.showCreateView = false
                        dismiss()
                    }
                }
                .disabled(groupName.isEmpty)
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

    private func createGroup() async {
        do {
            let groupProfile = Profile(name: groupName)

            let newStream = Stream(
                creatorPublicID: ViewModelFactory.shared.getCurrentProfile()!.publicID,
                profile: groupProfile,
                policies: Policies(admission: .openInvitation, interaction: .open, age: .onlyKids)
            )
            print("newStream newStream \(newStream.publicID.base58EncodedString)")

            let account = ViewModelFactory.shared.getCurrentAccount()!
            account.streams.append(newStream)

            try await PersistenceController.shared.saveChanges()

            await MainActor.run {
                sharedState.selectedStreamPublicID = newStream.publicID
            }
        } catch {
            await MainActor.run {
                errorMessage = "Failed to create group: \(error.localizedDescription)"
                showError = true
            }
        }
    }
    
    private func createInnerCircleGroup() async {
        do {
            let groupProfile = Profile(name: "InnerCircle")
            
            let newStream = Stream(
                creatorPublicID: ViewModelFactory.shared.getCurrentProfile()!.publicID,
                profile: groupProfile,
                policies: Policies(admission: .openInvitation, interaction: .open, age: .forAll)
            )
            
            let account = ViewModelFactory.shared.getCurrentAccount()!
            account.streams.append(newStream)
            
            try await PersistenceController.shared.saveChanges()
            
            await MainActor.run {
                sharedState.selectedStreamPublicID = newStream.publicID
            }
        } catch {
            await MainActor.run {
                errorMessage = "Failed to create InnerCircle group: \(error.localizedDescription)"
                showError = true
            }
        }
    }
}
