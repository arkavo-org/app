import OpenTDFKit
import SwiftData
import SwiftUI

struct ThoughtStreamView: View {
    @StateObject var viewModel: ThoughtStreamViewModel
    @State private var inputText = ""
    @FocusState private var isInputFocused: Bool
    @State private var isSending = false
    @State private var isShareSheetPresented = false

    var body: some View {
        VStack(spacing: 0) {
            #if os(iOS)
                HStack {
                    shareButton
                        .padding(.top, 20)
                        .padding(.leading, 20)
                    Spacer()
                }
            #endif
            VStack {
                Spacer()
                    .frame(height: 40)
                ScrollViewReader { _ in
                    ScrollView {
                        if viewModel.creatorProfile != nil {
                            HStack {
                                TextField("Type a message...", text: $inputText)
                                    .padding(10)
                                    .background(Color.blue.opacity(0.3))
                                    .foregroundColor(.white)
                                    .clipShape(RoundedRectangle(cornerRadius: 10))
                                    .disabled(isSending)
                                    .focused($isInputFocused)
                                    .onSubmit {
                                        Task {
                                            await sendThought()
                                        }
                                    }
                            }
                            .padding()
                        } else {
                            VStack {
                                Spacer()
                                    .frame(height: 100)
                                Text("No stream profile")
                                    .font(.headline)
                            }
                        }
                        LazyVStack(spacing: 8) {
                            ForEach(Array(viewModel.thoughts.reversed().enumerated()), id: \.element.id) { index, thoughtViewModel in
                                let totalThoughts = 8
                                let opacity = Double(totalThoughts - min(index, totalThoughts - 1)) / Double(totalThoughts)
                                MessageBubble(viewModel: thoughtViewModel, isCurrentUser: thoughtViewModel.creator.name == viewModel.creatorProfile?.name)
                                    .opacity(opacity)
                                    .id(thoughtViewModel.id)
                            }
                        }
                    }
                }
            }
        }
        .onTapGesture {
            isInputFocused = true
        }
        #if os(macOS)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                shareButton
            }
        }
        #endif
        .sheet(isPresented: $isShareSheetPresented) {
            ShareSheet(activityItems: [shareURL].compactMap { $0 },
                       isPresented: $isShareSheetPresented)
        }
    }

    private var shareButton: some View {
        Button(action: {
            isShareSheetPresented = true
        }) {
            Image(systemName: "square.and.arrow.up")
        }
    }

    private var shareURL: URL? {
        guard let publicID = viewModel.stream?.publicID.base58EncodedString
        else {
            return nil
        }
        return URL(string: "https://app.arkavo.com/stream/\(publicID)")
    }

    private func sendThought() async {
        guard !inputText.isEmpty else { return }
        let streamPublicIDString = viewModel.stream?.publicID.base58EncodedString ?? ""
        let thoughtViewModel = ThoughtViewModel.createText(creatorProfile: viewModel.creatorProfile!, streamPublicIDString: streamPublicIDString, text: inputText)
        await viewModel.send(thoughtViewModel)
        inputText = ""
    }
}

@MainActor
class ThoughtStreamViewModel: ObservableObject {
    @Published var service: ThoughtService
    @Published var stream: Stream?
    @Published var creatorProfile: Profile?
    @Published var thoughts: [ThoughtViewModel] = []

    init(service: ThoughtService) {
        self.service = service
    }

    func loadAndDecrypt(for _: Stream) {
        guard let stream else { return }
        for thought in stream.thoughts {
            do {
                try service.sendThought(thought.nano)
            } catch {
                print("sendThought error: \(error)")
            }
        }
//        print("stream.thoughts load count: \(stream.thoughts.count)")
    }

    func receive(_ serviceModel: ThoughtServiceModel) {
        let creatorProfile = Profile(name: serviceModel.creatorID.uuidString)
        let streamPublicIDString = stream?.publicID.base58EncodedString ?? ""
        let viewModel: ThoughtViewModel
        switch serviceModel.mediaType {
        case .text:
            let text = String(decoding: serviceModel.content, as: UTF8.self)
            viewModel = ThoughtViewModel.createText(creatorProfile: creatorProfile, streamPublicIDString: streamPublicIDString, text: text)
        case .image:
            viewModel = ThoughtViewModel.createImage(creatorProfile: creatorProfile, streamPublicIDString: streamPublicIDString, imageData: serviceModel.content)
        case .audio:
            viewModel = ThoughtViewModel.createAudio(creatorProfile: creatorProfile, streamPublicIDString: streamPublicIDString, audioData: serviceModel.content)
        case .video:
            viewModel = ThoughtViewModel.createVideo(creatorProfile: creatorProfile, streamPublicIDString: streamPublicIDString, videoData: serviceModel.content)
        }
        DispatchQueue.main.async {
            self.thoughts.append(viewModel)
        }
//        print("thoughts receive count: \(thoughts.count)")
    }

    func send(_ viewModel: ThoughtViewModel) async {
        Task {
            do {
                let nano = try service.createNano(viewModel, stream: stream!)
                // persist
                let thought = Thought(nano: nano)
                thought.stream = stream
                thought.publicID = try Thought.decodePublicID(from: viewModel.streamPublicIDString)
                PersistenceController.shared.container.mainContext.insert(thought)
                stream?.thoughts.append(thought)
                try await PersistenceController.shared.saveChanges()
                // show
                receive(viewModel)
                // send
                try service.sendThought(nano)
            } catch {
                print("error sending thought: \(error.localizedDescription)")
            }
        }
    }

    func receive(_ viewModel: ThoughtViewModel) {
        if !thoughts.contains(where: { $0 == viewModel }) {
            DispatchQueue.main.async { [self] in
                thoughts.append(viewModel)
            }
        }
    }
}

final class ThoughtViewModel: ObservableObject, Identifiable, Equatable {
    let id = UUID()
    @Published var creator: Profile
    @Published var streamPublicIDString: String
    // TODO: change to Data
    @Published var content: String
    @Published var mediaType: MediaType

    init(mediaType: MediaType, content: String, creator: Profile, streamPublicIDString: String) {
        self.mediaType = mediaType
        self.content = content
        self.creator = creator
        self.streamPublicIDString = streamPublicIDString
    }

    static func == (lhs: ThoughtViewModel, rhs: ThoughtViewModel) -> Bool {
        lhs.id == rhs.id
    }

    static func createText(creatorProfile: Profile, streamPublicIDString: String, text: String) -> ThoughtViewModel {
        ThoughtViewModel(mediaType: .text, content: text, creator: creatorProfile, streamPublicIDString: streamPublicIDString)
    }

    static func createImage(creatorProfile: Profile, streamPublicIDString: String, imageData: Data) -> ThoughtViewModel {
        // Handle image data appropriately
        let imageContent = "Image data: \(imageData.count) bytes"
        return ThoughtViewModel(mediaType: .image, content: imageContent, creator: creatorProfile, streamPublicIDString: streamPublicIDString)
    }

    static func createAudio(creatorProfile: Profile, streamPublicIDString: String, audioData: Data) -> ThoughtViewModel {
        // Handle audio data appropriately
        let audioContent = "Audio data: \(audioData.count) bytes"
        return ThoughtViewModel(mediaType: .audio, content: audioContent, creator: creatorProfile, streamPublicIDString: streamPublicIDString)
    }

    static func createVideo(creatorProfile: Profile, streamPublicIDString: String, videoData: Data) -> ThoughtViewModel {
        // Handle video data appropriately
        let videoContent = "Video data: \(videoData.count) bytes"
        return ThoughtViewModel(mediaType: .video, content: videoContent, creator: creatorProfile, streamPublicIDString: streamPublicIDString)
    }
}

struct MessageBubble: View {
    let viewModel: ThoughtViewModel
    let isCurrentUser: Bool

    init(viewModel: ThoughtViewModel, isCurrentUser: Bool) {
        self.viewModel = viewModel
        self.isCurrentUser = isCurrentUser
    }

    var body: some View {
        HStack {
            if isCurrentUser {
                Spacer()
            }
            VStack(alignment: isCurrentUser ? .trailing : .leading) {
                Text(viewModel.creator.name)
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text(viewModel.content)
                    .padding(10)
                    .background(isCurrentUser ? Color.blue : Color(.gray))
                    .foregroundColor(isCurrentUser ? .white : .primary)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                Text(viewModel.streamPublicIDString)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            if !isCurrentUser {
                Spacer()
            }
        }
    }
}

struct ThoughtStreamView_Previews: PreviewProvider {
    static var previews: some View {
        ThoughtStreamView(viewModel: previewViewModel)
            .modelContainer(previewContainer)
    }

    static var previewViewModel: ThoughtStreamViewModel {
        let service = ThoughtService(ArkavoService())
        let viewModel = ThoughtStreamViewModel(service: service)

        // Set up mock data
        viewModel.creatorProfile = Profile(name: "Preview User")
        viewModel.stream = previewStream

        // Add some sample thoughts
        viewModel.thoughts = [
            ThoughtViewModel.createText(creatorProfile: Profile(name: "Alice"), streamPublicIDString: "abc123", text: "Hello, this is a test message!"),
            ThoughtViewModel.createText(creatorProfile: Profile(name: "Bob"), streamPublicIDString: "abc123", text: "Hi Alice, great to see you here!"),
            ThoughtViewModel.createText(creatorProfile: Profile(name: "Preview User"), streamPublicIDString: "abc123", text: "Welcome everyone to this stream!"),
        ]

        return viewModel
    }

    static var previewStream: Stream {
        let account = Account()
        let profile = Profile(name: "Preview Stream")
        return Stream(account: account, profile: profile, admissionPolicy: .open, interactionPolicy: .open)
    }

    static var previewContainer: ModelContainer {
        let schema = Schema([Account.self, Profile.self, Stream.self])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)

        do {
            let container = try ModelContainer(for: schema, configurations: [configuration])
            let context = container.mainContext

            // Create and save sample data
            let account = Account()
            try context.save()

            let profile = Profile(name: "Preview Stream")
            let stream = Stream(account: account, profile: profile, admissionPolicy: .open, interactionPolicy: .open)
            account.streams.append(stream)
            try context.save()

            return container
        } catch {
            fatalError("Failed to create preview container: \(error.localizedDescription)")
        }
    }
}
