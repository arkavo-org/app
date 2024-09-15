import OpenTDFKit
import SwiftUI

final class ThoughtViewModel: ObservableObject, Identifiable {
    let id = UUID()
    @Published var creator: Profile
    @Published var stream: Profile
    // TODO: change to Data
    @Published var content: String
    @Published var mediaType: MediaType

    init(mediaType: MediaType, content: String, creator: Profile, stream: Profile) {
        self.mediaType = mediaType
        self.content = content
        self.creator = creator
        self.stream = stream
    }
}

func createThoughtViewModelText(creator: Profile, stream: Profile, text: String) -> ThoughtViewModel {
    ThoughtViewModel(mediaType: .text, content: text, creator: creator, stream: stream)
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

struct ThoughtView: View {
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
        let thoughtViewModel = createThoughtViewModelText(creator: viewModel.creatorProfile!, stream: viewModel.stream!.profile, text: inputText)
        viewModel.sendThought(thoughtViewModel)
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

    func receiveThought(_: Thought) {
        // TODO: covert Thought to ThoughtViewModel
        DispatchQueue.main.async {
//            self.addThought(newThought)
        }
    }

    func sendThought(_ viewModel: ThoughtViewModel) {
        do {
            let nano = try service.createNano(viewModel, stream: stream!)
            try service.sendThought(nano)
        } catch {
            print("error sending thought: \(error.localizedDescription)")
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
