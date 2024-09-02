import CryptoKit
import SwiftData
import SwiftUI

struct StreamManagementView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var accounts: [Account]
    @Query private var streams: [Stream]
    @State private var showingCreateStream = false

    var body: some View {
        List {
            Section(header: Text("My Streams")) {
                ForEach(streams) { stream in
                    CompactStreamProfileView(viewModel: StreamProfileViewModel(profile: stream.profile, participantCount: 2))
                }
                .onDelete(perform: deleteStreams)
            }

            Button("Create New Stream") {
                showingCreateStream = true
            }
        }
        .navigationTitle("My Streams")
        .sheet(isPresented: $showingCreateStream) {
            CreateStreamProfileView { profile, _ in
                createNewStream(with: profile)
            }
        }
    }

    private func createNewStream(with streamProfile: Profile) {
        if let account = accounts.first,
            let accountProfile = account.profile {
            let newStream = Stream(name: streamProfile.name, ownerUUID: accountProfile.id, profile: streamProfile)
            modelContext.insert(newStream)
            do {
                try modelContext.save()
            } catch {
                print("Failed to save new stream: \(error)")
            }
        }
        else {
            print("No profile found")
        }
    }

    private func deleteStreams(at offsets: IndexSet) {
        for index in offsets {
            let stream = streams[index]
            modelContext.delete(stream)
        }
        do {
            try modelContext.save()
        } catch {
            print("Failed to delete stream(s): \(error)")
        }
    }
}

struct StreamManagementView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationView {
            StreamManagementView()
        }
        .modelContainer(for: [Account.self, Stream.self, Profile.self], inMemory: true)
    }
}
