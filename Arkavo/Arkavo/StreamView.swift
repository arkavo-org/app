import CryptoKit
import SwiftData
import SwiftUI

struct StreamView: View {
    @Query private var accounts: [Account]
    @State private var showingCreateStream = false
    @State private var selectedStream: Stream?

    var body: some View {
        VStack {
            Spacer(minLength: 40)
            VStack {
                HStack {
                    Text("My Stream")
                        .font(.title)
                    Spacer()
                }
                .padding()
                List {
                    Section(header:
                        HStack {
                            Text("Mine")
                            Spacer()
                            Button(action: {
                                showingCreateStream = true
                            }) {
                                Image(systemName: "plus.circle")
                                    .foregroundColor(.blue)
                            }
                        }
                    ) {
                        ForEach(accounts.first!.streams) { stream in
                            CompactStreamProfileView(viewModel: StreamViewModel(stream: stream))
                                .onTapGesture {
                                    selectedStream = stream
                                }
                        }
                        .onDelete(perform: deleteStreams)
                    }
                }
            }
            .safeAreaInset(edge: .top) {
                Color.clear.frame(height: 0)
            }
        }
        .sheet(isPresented: $showingCreateStream) {
            CreateStreamProfileView { profile, admissionPolicy, interactionPolicy in
                createNewStream(with: profile, admissionPolicy: admissionPolicy, interactionPolicy: interactionPolicy)
            }
        }
        .sheet(item: $selectedStream) { stream in
            DetailedStreamProfileView(viewModel: StreamViewModel(stream: stream))
        }
    }

    private func createNewStream(with streamProfile: Profile, admissionPolicy: AdmissionPolicy, interactionPolicy: InteractionPolicy) {
        guard let account = accounts.first else {
            print("No account found")
            return
        }
        do {
            let stream = Stream(account: account, profile: streamProfile, admissionPolicy: admissionPolicy, interactionPolicy: interactionPolicy)
            try account.addStream(stream)
            try PersistenceController.shared.saveChanges()
        } catch {
            print("Stream creation failed: \(error.localizedDescription)")
        }
    }

    private func deleteStreams(at offsets: IndexSet) {
        guard let account = accounts.first else {
            print("No account found")
            return
        }
        for offset in offsets {
            if offset < account.streams.count {
                account.streams.remove(at: offset)
                do {
                    try PersistenceController.shared.saveChanges()
                } catch {
                    print("Failed to delete stream(s): \(error)")
                }
            }
        }
    }
}

struct StreamManagementView_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            StreamView()
                .previewDisplayName("List Streams")

            CreateStreamProfileView { _, _, _ in
                // This is just for preview, so we'll leave the closure empty
            }
            .previewDisplayName("Create Stream")
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
//            let profiles: [Profile] = []
            for profile in profiles {
                let stream = Stream(account: account, profile: profile, admissionPolicy: .open, interactionPolicy: .moderated)
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
