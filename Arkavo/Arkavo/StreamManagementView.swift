import CryptoKit
import SwiftData
import SwiftUI

struct StreamManagementView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var accounts: [Account]
    private var streams: [Stream]
    @State private var showingCreateStream = false

    init(streams: [Stream]) {
        self.streams = streams
    }
    
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
//            do {
//                try modelContext.save()
//            } catch {
//                print("Failed to save new stream: \(error)")
//            }
        }
        else {
            print("No profile found")
        }
    }

    private func deleteStreams(at offsets: IndexSet) {
//        for index in offsets {
//            let stream = streams[index]
//            modelContext.delete(stream)
//        }
//        do {
//            try modelContext.save()
//        } catch {
//            print("Failed to delete stream(s): \(error)")
//        }
        print("Failed to delete stream")
    }
}

struct StreamManagementView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationView {
            StreamManagementView(streams: mockStreams())
        }
        .modelContainer(for: [Account.self, Profile.self], inMemory: true)
    }
    static func mockStreams() -> [Stream] {
        let profile1 = Profile(name: "Stream 1", blurb: "This is the first stream")
        let stream1 = Stream(name: "Stream 1", ownerUUID: UUID(), profile: profile1)
        let profile2 = Profile(name: "Stream 2", blurb: "This is the second stream")
        let stream2 = Stream(name: "Stream 2", ownerUUID: UUID(), profile: profile2)
        let profile3 = Profile(name: "Stream 3", blurb: "This is the third stream")
        let stream3 = Stream(name: "Stream 3", ownerUUID: UUID(), profile: profile3)
        return [stream1, stream2, stream3]
    }
}
