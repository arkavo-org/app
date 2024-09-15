import OpenTDFKit
import SwiftUI

final class ThoughtViewModel: ObservableObject, Identifiable, Equatable {
    let id = UUID()
    @Published var creator: Profile
    @Published var streamPublicIdString: String
    // TODO: change to Data
    @Published var content: String
    @Published var mediaType: MediaType

    init(mediaType: MediaType, content: String, creator: Profile, streamPublicIdString: String) {
        self.mediaType = mediaType
        self.content = content
        self.creator = creator
        self.streamPublicIdString = streamPublicIdString
    }

    static func == (lhs: ThoughtViewModel, rhs: ThoughtViewModel) -> Bool {
        lhs.id == rhs.id
    }

    static func createText(creatorProfile: Profile, streamPublicIdString: String, text: String) -> ThoughtViewModel {
        ThoughtViewModel(mediaType: .text, content: text, creator: creatorProfile, streamPublicIdString: streamPublicIdString)
    }

    static func createImage(creatorProfile: Profile, streamPublicIdString: String, imageData: Data) -> ThoughtViewModel {
        // Handle image data appropriately
        let imageContent = "Image data: \(imageData.count) bytes"
        return ThoughtViewModel(mediaType: .image, content: imageContent, creator: creatorProfile, streamPublicIdString: streamPublicIdString)
    }

    static func createAudio(creatorProfile: Profile, streamPublicIdString: String, audioData: Data) -> ThoughtViewModel {
        // Handle audio data appropriately
        let audioContent = "Audio data: \(audioData.count) bytes"
        return ThoughtViewModel(mediaType: .audio, content: audioContent, creator: creatorProfile, streamPublicIdString: streamPublicIdString)
    }

    static func createVideo(creatorProfile: Profile, streamPublicIdString: String, videoData: Data) -> ThoughtViewModel {
        // Handle video data appropriately
        let videoContent = "Video data: \(videoData.count) bytes"
        return ThoughtViewModel(mediaType: .video, content: videoContent, creator: creatorProfile, streamPublicIdString: streamPublicIdString)
    }
}

struct ThoughtListView: View {
    @StateObject var viewModel: ThoughtViewModel

    var body: some View {
        VStack {
            Text(viewModel.content)
                .font(.body)
            Text(viewModel.creator.name)
                .font(.caption)
                .foregroundColor(.gray)
        }
        .padding()
    }
}

struct ThoughtStreamView: View {
    @ObservedObject var viewModel: ThoughtStreamViewModel
    @State private var inputText = ""
    @FocusState private var isInputFocused: Bool
    @State private var isSending = false

    var body: some View {
        VStack(spacing: 0) {
            VStack {
                Spacer()
                    .frame(height: 90)
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
                                        sendThought()
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
                            ForEach(Array(viewModel.thoughts.enumerated()), id: \.element.id) { index, thoughtViewModel in
                                let totalThoughts = 20
                                let opacity = Double(totalThoughts - min(index, totalThoughts - 1)) / Double(totalThoughts)
                                MessageBubble(viewModel: thoughtViewModel, isCurrentUser: thoughtViewModel.creator.name == viewModel.creatorProfile!.name)
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
    }

    private func sendThought() {
        guard !inputText.isEmpty else { return }
        let streamPublicIdString = viewModel.stream?.publicId.map { String(format: "%02hhx", $0) }.joined() ?? ""
        let thoughtViewModel = ThoughtViewModel.createText(creatorProfile: viewModel.creatorProfile!, streamPublicIdString: streamPublicIdString, text: inputText)
        viewModel.send(thoughtViewModel)
        inputText = ""
    }
}

class ThoughtStreamViewModel: ObservableObject {
    @Published var service: ThoughtService
    @Published var stream: Stream?
    @Published var creatorProfile: Profile?
    @Published var thoughts: [ThoughtViewModel] = []

    init(service: ThoughtService) {
        self.service = service
    }

    func receive(_ serviceModel: ThoughtServiceModel) {
        let creatorProfile = Profile(name: serviceModel.creatorId.uuidString)
        let streamPublicIdString = stream?.publicId.map { String(format: "%02hhx", $0) }.joined() ?? ""
        let viewModel: ThoughtViewModel
        switch serviceModel.mediaType {
        case .text:
            let text = String(decoding: serviceModel.content, as: UTF8.self)
            viewModel = ThoughtViewModel.createText(creatorProfile: creatorProfile, streamPublicIdString: streamPublicIdString, text: text)
        case .image:
            viewModel = ThoughtViewModel.createImage(creatorProfile: creatorProfile, streamPublicIdString: streamPublicIdString, imageData: serviceModel.content)
        case .audio:
            viewModel = ThoughtViewModel.createAudio(creatorProfile: creatorProfile, streamPublicIdString: streamPublicIdString, audioData: serviceModel.content)
        case .video:
            viewModel = ThoughtViewModel.createVideo(creatorProfile: creatorProfile, streamPublicIdString: streamPublicIdString, videoData: serviceModel.content)
        }
        DispatchQueue.main.async {
            self.thoughts.append(viewModel)
        }
    }

    func send(_ viewModel: ThoughtViewModel) {
        do {
            let nano = try service.createNano(viewModel, stream: stream!)
            try service.sendThought(nano)
        } catch {
            print("error sending thought: \(error.localizedDescription)")
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
            }
            if !isCurrentUser {
                Spacer()
            }
        }
    }
}

// struct ThoughtStreamView_Previews: PreviewProvider {
//    static var previews: some View {
//        let account = Account()
//        let profile = Profile(name: "TestProfile")
//        let admissionPolicy = AdmissionPolicy(rawValue: "test")
//        let interactionPolicy = InteractionPolicy(rawValue: "test")
//        let stream = Stream(account: account, profile: profile, admissionPolicy: .open, interactionPolicy: .open)
//        let viewModel = ThoughtStreamViewModel(service: ThoughtService(nanoTDFManager: NanoTDFManager(), webSocketManager: WebSocketManager()))
//        ThoughtView(viewModel: viewModel)
//    }
// }
