import CryptoKit
import SwiftData
import SwiftUI

struct StreamManagementView: View {
    @Query private var accounts: [Account]
    @State private var showingCreateStream = false

    var body: some View {
        List {
            Section(header: Text("My Streams")) {
                ForEach(accounts.first!.streams) { stream in
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
        do {
            let account = try PersistenceController.shared.getOrCreateAccount()
            let stream = Stream(account: account, profile: streamProfile)
            try account.addStream(stream)
            try PersistenceController.shared.saveChanges()
        } catch {
            print("Stream creation failed: \(error.localizedDescription)")
        }
    }

    private func deleteStreams(at _: IndexSet) {
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
        Group {
            NavigationView {
                StreamManagementView()
            }
            .previewDisplayName("Main View")

            CreateStreamProfileView { _, _ in
                // This is just for preview, so we'll leave the closure empty
            }
            .previewDisplayName("Create Stream Sheet")
        }
        .modelContainer(previewContainer)
    }

    static var previewContainer: ModelContainer {
        let schema = Schema([Account.self, Profile.self, Stream.self])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)

        do {
            let container = try ModelContainer(for: schema, configurations: [configuration])
            let context = container.mainContext

            // Create and save sample data
            let account = Account()
            context.insert(account)
            try context.save()

            let profiles = [
                Profile(name: "Stream 1", blurb: "This is the first stream"),
                Profile(name: "Stream 2", blurb: "This is the second stream"),
                Profile(name: "Stream 3", blurb: "This is the third stream"),
            ]

            for profile in profiles {
                let stream = Stream(account: account, profile: profile)
                account.streams.append(stream)
                try context.save()
            }

            try context.save()

            return container
        } catch {
            fatalError("Failed to create preview container: \(error.localizedDescription)")
        }
    }
}
