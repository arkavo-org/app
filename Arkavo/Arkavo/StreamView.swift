import SwiftData
import SwiftUI

struct StreamView: View {
    @State var service: StreamService
    @State var showingCreateStream = false
    @State var showingThoughtView = false
    @State var showingDetailedStreamProfileView = false
    @State var selectedStream: Stream?
    @Query var streams: [Stream]
    @State var accountProfile: Profile?

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
                        if streams.isEmpty {
                            VStack {
                                Text("Empty")
                            }
                        } else {
                            ForEach(streams) { stream in
                                HStack {
                                    CompactStreamProfileView(viewModel: StreamViewModel(stream: stream))
                                        .onTapGesture {
                                            selectedStream = stream
                                            showingDetailedStreamProfileView = true
                                        }
                                    Spacer()
                                    Button(action: {
                                        selectedStream = stream
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
            CreateStreamProfileView { profile, admissionPolicy, interactionPolicy, _ in
                Task {
                    try await saveNewStream(with: profile, admissionPolicy: admissionPolicy, interactionPolicy: interactionPolicy)
                }
            }
        }
        .sheet(isPresented: $showingThoughtView) {
            if let thoughtService = service.service.thoughtService,
               let accountProfile,
               let selectedStream
            {
                let accountProfileViewModel = AccountProfileViewModel(profile: accountProfile)
                let streamBadgeViewModel = StreamBadgeViewModel(stream: selectedStream, ownerProfile: accountProfileViewModel)
                let thoughtStreamViewModel = ThoughtStreamViewModel(service: thoughtService, stream: selectedStream)
                ThoughtStreamView(service: thoughtService, streamService: service, viewModel: thoughtStreamViewModel, streamBadgeViewModel: streamBadgeViewModel)
            } else {
                Text("Stream not set")
            }
        }
        .sheet(isPresented: $showingDetailedStreamProfileView) {
            if let selectedStream {
                DetailedStreamProfileView(viewModel: StreamViewModel(stream: selectedStream))
            }
        }
        .onChange(of: showingThoughtView) { _, newValue in
            if newValue == false {
                selectedStream = nil
            }
        }
        .onChange(of: showingDetailedStreamProfileView) { _, newValue in
            if newValue == false {
                selectedStream = nil
            }
        }
        .onAppear {
            Task {
                let account = try await PersistenceController.shared.getOrCreateAccount()
                accountProfile = account.profile
            }
        }
    }

    private func saveNewStream(with streamProfile: Profile, admissionPolicy: AdmissionPolicy, interactionPolicy: InteractionPolicy) async throws {
        let account = try await PersistenceController.shared.getOrCreateAccount()
        guard let creatorPublicID = account.profile?.publicID else {
            fatalError("Account profile must have a public ID to create a stream")
        }
        let stream = Stream(creatorPublicID: creatorPublicID, profile: streamProfile, admissionPolicy: admissionPolicy, interactionPolicy: interactionPolicy, agePolicy: .forAll)
        account.streams.append(stream)
        try await PersistenceController.shared.saveChanges()
    }

    private func deleteStreams(at offsets: IndexSet) async throws {
        let account = try await PersistenceController.shared.getOrCreateAccount()
        try await PersistenceController.shared.deleteStreams(at: offsets, from: account)
    }
}

struct StreamManagementView_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            CreateStreamProfileView { _, _, _, _ in
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
                let stream = Stream(creatorPublicID: Data(), profile: profile, admissionPolicy: .open, interactionPolicy: .moderated, agePolicy: .forAll)
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
