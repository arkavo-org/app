import CryptoKit
import SwiftData
import SwiftUI

final class StreamViewModel: ObservableObject, Identifiable {
    var thoughtStreamViewModel: ThoughtStreamViewModel

    init(thoughtStreamViewModel: ThoughtStreamViewModel) {
        self.thoughtStreamViewModel = thoughtStreamViewModel
    }
}

struct StreamView: View {
    @Query private var accounts: [Account]
    @State private var showingCreateStream = false
    @State private var selectedStream: Stream?
    @State private var showingThoughtView = false
    @StateObject var viewModel: StreamViewModel

    var body: some View {
        if showingThoughtView, let selectedStream {
            let account = accounts.first { $0.id == selectedStream.account.id }
            ThoughtView(viewModel: viewModel.thoughtStreamViewModel)
                .onAppear {
                    viewModel.thoughtStreamViewModel.stream = selectedStream
                    viewModel.thoughtStreamViewModel.creatorProfile = account?.profile
                }
        } else {
            VStack {
                Spacer(minLength: 40)
                VStack {
                    HStack {
                        Text("My Streams")
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
                            ForEach(accounts.first?.streams ?? []) { stream in
                                HStack {
                                    CompactStreamProfileView(viewModel: StreamProfileViewModel(stream: stream))
                                        .onTapGesture {
                                            viewModel.thoughtStreamViewModel.stream = stream
                                        }
                                    Spacer()
                                    Button(action: {
                                        selectedStream = stream
                                        viewModel.thoughtStreamViewModel.stream = stream
                                        showingThoughtView = true
                                    }) {
                                        Image(systemName: "arrow.right.circle")
                                            .foregroundColor(.blue)
                                    }
                                }
                            }
                            .onDelete { indexSet in
                                Task {
                                    await deleteStreams(at: indexSet)
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
                        await saveNewStream(with: profile, admissionPolicy: admissionPolicy, interactionPolicy: interactionPolicy)
                    }
                }
            }
            .sheet(item: $selectedStream) { stream in
                DetailedStreamProfileView(viewModel: StreamProfileViewModel(stream: stream))
            }
        }
    }

    private func saveNewStream(with streamProfile: Profile, admissionPolicy: AdmissionPolicy, interactionPolicy: InteractionPolicy) async {
        guard let account = accounts.first else {
            print("No account found")
            return
        }
        do {
            let stream = Stream(account: account, profile: streamProfile, admissionPolicy: admissionPolicy, interactionPolicy: interactionPolicy)
            try account.addStream(stream)
            try await PersistenceController.shared.saveChanges()
        } catch {
            print("Stream creation failed: \(error.localizedDescription)")
        }
    }

    private func deleteStreams(at offsets: IndexSet) async {
        guard let account = accounts.first else {
            print("No account found")
            return
        }
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
}

struct StreamManagementView_Previews: PreviewProvider {
    static var previews: some View {
        let account = Account()
        let profile = Profile(name: "TestProfile")
        let admissionPolicy = AdmissionPolicy(rawValue: "test")
        let interactionPolicy = InteractionPolicy(rawValue: "test")
        let stream = Stream(account: account, profile: profile, admissionPolicy: .open, interactionPolicy: .open)
//        let viewModel = ThoughtStreamViewModel(service: ThoughtService(nanoTDFManager: NanoTDFManager(), webSocketManager: WebSocketManager(), kasPublicKeyProvider: nil)
        Group {
//            StreamView(viewModel: StreamViewModel(thoughtStreamViewModel: viewModel))

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
