import SwiftData
import SwiftUI

struct StreamView: View {
    @State var service: StreamService
    @State var showingCreateStream = false
    @State var showingThoughtView = false
    @State var stream: Stream?
    @State var streams: [Stream]?

    var body: some View {
        VStack {
            Spacer(minLength: 40)
            VStack {
                HStack {
                    Text("Streams")
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
                        if streams == nil {
                            VStack {
                                Text("Loading...")
                            }
                        } else {
                            ForEach(streams!) { stream in
                                HStack {
                                    CompactStreamProfileView(viewModel: StreamViewModel(stream: stream))
                                        .onTapGesture {
                                            self.stream = stream
                                        }
                                    Spacer()
                                    Button(action: {
                                        self.stream = stream
                                        showingThoughtView = true
                                    }) {
                                        Image(systemName: "arrow.right.circle")
                                            .foregroundColor(.blue)
                                    }
                                }
                            }
                            .onDelete { indexSet in
                                Task {
                                    try await deleteStreams(at: indexSet)
                                }
                            }
                        }
                    }
                }
            }
            .safeAreaInset(edge: .top) {
                Color.clear.frame(height: 0)
            }
        }
        .sheet(isPresented: $showingCreateStream) {
            CreateStreamProfileView { profile, admissionPolicy, interactionPolicy in
                Task {
                    try await saveNewStream(with: profile, admissionPolicy: admissionPolicy, interactionPolicy: interactionPolicy)
                }
            }
        }
        .sheet(item: $stream) { stream in
            DetailedStreamProfileView(viewModel: StreamViewModel(stream: stream))
        }
        .task {
            await loadStreams()
        }
    }

    private func loadStreams() async {
        do {
            let account = try await PersistenceController.shared.getOrCreateAccount()
            streams = account.streams
        } catch {
            print("Failed to load streams: \(error)")
        }
    }

    private func saveNewStream(with streamProfile: Profile, admissionPolicy: AdmissionPolicy, interactionPolicy: InteractionPolicy) async throws {
        let account = try await PersistenceController.shared.getOrCreateAccount()
        let stream = Stream(account: account, profile: streamProfile, admissionPolicy: admissionPolicy, interactionPolicy: interactionPolicy)
        account.streams.append(stream)
        try await PersistenceController.shared.saveChanges()
    }

    private func deleteStreams(at offsets: IndexSet) async throws {
        let account = try await PersistenceController.shared.getOrCreateAccount()
        try await PersistenceController.shared.deleteStreams(at: offsets, from: account)
    }
}

private func saveNewStream(with streamProfile: Profile, admissionPolicy: AdmissionPolicy, interactionPolicy: InteractionPolicy) async throws {
    let account = try await PersistenceController.shared.getOrCreateAccount()
    do {
        let stream = Stream(account: account, profile: streamProfile, admissionPolicy: admissionPolicy, interactionPolicy: interactionPolicy)
        try account.addStream(stream)
        try await PersistenceController.shared.saveChanges()
    } catch {
        print("Stream creation failed: \(error.localizedDescription)")
    }
}

private func deleteStreams(at offsets: IndexSet) async throws {
    let account = try await PersistenceController.shared.getOrCreateAccount()
    for offset in offsets {
        if offset < account.streams.count {
            account.streams.remove(at: offset)
            do {
                try await PersistenceController.shared.saveChanges()
            } catch {
                print("Failed to delete stream(s): \(error)")
            }
        }
    }
}

struct StreamManagementView_Previews: PreviewProvider {
    static var previews: some View {
        Group {
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
