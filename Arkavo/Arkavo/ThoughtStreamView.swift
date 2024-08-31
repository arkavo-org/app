import Combine
import CryptoKit
import OpenTDFKit
import SwiftUI

// Wrapper struct for Thought
struct ThoughtWrapper: Identifiable {
    let id = UUID()
    let thought: Thought
}

struct ThoughtStreamView: View {
    @ObservedObject var viewModel: ThoughtStreamViewModel
    @State private var inputText = ""
    @FocusState private var isInputFocused: Bool
    @State private var isSending = false

    var body: some View {
        VStack(spacing: 0) {
            // Main chat area
            VStack {
                
                Spacer()
                
                // Messages
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(viewModel.allThoughts) { wrapper in
                            MessageBubble(thought: wrapper.thought, isCurrentUser: wrapper.thought.sender == viewModel.profile!.name)
                        }
                    }
                    .padding()
                }

                // Input area
                HStack {
                    TextField("Type a message...", text: $inputText)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .disabled(isSending)

                    Button(action: sendThought) {
                        Image(systemName: "arrow.up.circle.fill")
                            .foregroundColor(isSending ? .gray : .blue)
                            .font(.title)
                    }
                    .disabled(isSending)
                }
                .padding()
                
                Spacer()
            }
            .padding(.top, 30)
            .padding(.bottom, 30)
        }
       
    }

    private func sendThought() {
        guard !inputText.isEmpty else { return }
        
        //profile must be set
        guard ((viewModel.profile?.name.isEmpty) == nil) == false else { return }
        
        let newThought = Thought.createTextThoughtWithSender(inputText, sender: viewModel.profile!.name)
        viewModel.sendThought(thought: newThought)
        inputText = ""
    }
}

//struct ThoughtView: View {
//    let thought: Thought
//    let index: Int
//    let totalCount: Int
//    let screenHeight: CGFloat
//    let isTopThought: Bool
//    let color: Color
//
//    @State private var offset: CGFloat = 0
//
//    var body: some View {
//        Text(thought.content.first?.content ?? "")
//            .padding(8)
//            .background(color.opacity(0.7))
//            .foregroundColor(.white)
//            .clipShape(Capsule())
//            .scaleEffect(1 - offset * 0.5)
//            .offset(y: calculateYOffset())
//            .onAppear {
//                withAnimation(.linear(duration: 10).repeatForever(autoreverses: false)) {
//                    offset = 1
//                }
//            }
//    }
//
//    private func calculateYOffset() -> CGFloat {
//        let visibleHeight = screenHeight - 100
//        let startY = isTopThought ? -visibleHeight / 2 : visibleHeight / 2
//        let endY: CGFloat = 0
//        let progress = CGFloat(index) / CGFloat(totalCount - 1)
//        return startY + (endY - startY) * progress * offset
//    }
//}

actor ThoughtHandler {
    private let nanoTDFManager: NanoTDFManager
    private let webSocketManager: WebSocketManager
    init(nanoTDFManager: NanoTDFManager, webSocketManager: WebSocketManager) {
        self.nanoTDFManager = nanoTDFManager
        self.webSocketManager = webSocketManager
    }

    func handleIncomingThought(data: Data) async {
        // Assuming the incoming data is a NATSMessage
//        print("NATS message received: \(data.base64EncodedString())")
//        print("NATS payload size: \(data.count)")
        do {
            // FIXME: copy of data after first byte
            let subData = data.subdata(in: 1 ..< data.count)
            // Create a NanoTDF from the payload
            let parser = BinaryParser(data: subData)
            let header = try parser.parseHeader()
            let payload = try parser.parsePayload(config: header.payloadSignatureConfig)
            let nanoTDF = NanoTDF(header: header, payload: payload, signature: nil)
            // Use the nanoTDFManager to handle the incoming NanoTDF
            let id = nanoTDF.header.ephemeralPublicKey
//            print("ephemeralPublicKey: \(id.base64EncodedString())")
            nanoTDFManager.addNanoTDF(nanoTDF, withIdentifier: id)
            webSocketManager.sendRewrapMessage(header: nanoTDF.header)
        } catch let error as ParsingError {
            handleParsingError(error)
        } catch {
            print("Unexpected error: \(error.localizedDescription)")
        }
    }

    private func handleParsingError(_ error: ParsingError) {
        switch error {
        case .invalidFormat:
            print("Invalid NanoTDF format")
        case .invalidEphemeralKey:
            print("Invalid NanoTDF ephemeral key")
        case .invalidPayload:
            print("Invalid NanoTDF payload")
        case .invalidMagicNumber:
            print("Invalid NanoTDF magic number")
        case .invalidVersion:
            print("Invalid NanoTDF version")
        case .invalidKAS:
            print("Invalid NanoTDF kas")
        case .invalidECCMode:
            print("Invalid NanoTDF ecc mode")
        case .invalidPayloadSigMode:
            print("Invalid NanoTDF payload signature mode")
        case .invalidPolicy:
            print("Invalid NanoTDF policy")
        case .invalidPublicKeyLength:
            print("Invalid NanoTDF public key length")
        case .invalidSignatureLength:
            print("Invalid NanoTDF signature length")
        case .invalidSigning:
            print("Invalid NanoTDF signing")
        }
    }
}

class ThoughtStreamViewModel: ObservableObject {
    @Published var allThoughts: [ThoughtWrapper] = []
    let maxThoughts: Int = 100
    public var thoughtHandler: ThoughtHandler?
    @Published var profile: Profile?
    // nano
    @Published var webSocketManager: WebSocketManager
    var nanoTDFManager: NanoTDFManager
    @Binding var kasPublicKey: P256.KeyAgreement.PublicKey?
    private var cancellables = Set<AnyCancellable>()

    init() {
        _webSocketManager = .init(initialValue: WebSocketManager())
        _kasPublicKey = .constant(nil)
        nanoTDFManager = NanoTDFManager()
    }

    func initialize(
        webSocketManager: WebSocketManager,
        nanoTDFManager: NanoTDFManager,
        kasPublicKey: Binding<P256.KeyAgreement.PublicKey?>
    ) {
        self.webSocketManager = webSocketManager
        self.webSocketManager = webSocketManager
        _kasPublicKey = kasPublicKey
        self.nanoTDFManager = nanoTDFManager
        thoughtHandler = ThoughtHandler(nanoTDFManager: nanoTDFManager, webSocketManager: webSocketManager)
        webSocketManager.setCustomMessageCallback { [weak self] data in
            // FIXME: this is called frequently
//            print("setCustomMessageCallback")
            guard let self, let thoughtHandler else { return }
            Task {
                await thoughtHandler.handleIncomingThought(data: data)
            }
        }
    }

    func sendThought(thought: Thought) {
        guard let kasPublicKey else {
            print("KAS public key not available")
            return
        }
        do {
            // Serialize the new Thought
            let serializedThought = try thought.serialize()

            // Create a NanoTDF
            let kasRL = ResourceLocator(protocolEnum: .sharedResourceDirectory, body: "kas.arkavo.net")!
            let kasMetadata = KasMetadata(resourceLocator: kasRL, publicKey: kasPublicKey, curve: .secp256r1)
            // smart contract
            let remotePolicy = ResourceLocator(protocolEnum: .sharedResourceDirectory, body: "5GnJAVumy3NBdo2u9ZEK1MQAXdiVnZWzzso4diP2JszVgSJQ")!
            var policy = Policy(type: .remote, body: nil, remote: remotePolicy, binding: nil)

            let nanoTDF = try createNanoTDF(kas: kasMetadata, policy: &policy, plaintext: serializedThought)

            // Create and send the NATSMessage
            let natsMessage = NATSMessage(payload: nanoTDF.toData())
            let messageData = natsMessage.toData()
//            print("NATS message payload sent: \(natsMessage.payload.base64EncodedString())")

            webSocketManager.sendCustomMessage(messageData) { error in
                if let error {
                    print("Error sending thought: \(error)")
                }
            }
        } catch {
            print("Error creating or serializing NanoTDF: \(error)")
        }
    }

    func receiveThought(_ newThought: Thought) {
        DispatchQueue.main.async {
            self.addThought(newThought)
        }
    }

    private func addThought(_ thought: Thought) {
        let wrappedThought = ThoughtWrapper(thought: thought)
        allThoughts.append(wrappedThought)
        if allThoughts.count > maxThoughts {
            allThoughts.removeFirst()
        }
    }
}

struct ThoughtStreamView_Previews: PreviewProvider {
    static var previews: some View {
        let viewModel = ThoughtStreamViewModel()
        ThoughtStreamView(viewModel: viewModel)
    }
}

struct MessageBubble: View {
    let thought: Thought
    let isCurrentUser: Bool

    var body: some View {
        HStack {
            if isCurrentUser {
                Spacer()
            }
            VStack(alignment: isCurrentUser ? .trailing : .leading) {
                Text(thought.sender)
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text(thought.content.first?.content ?? "")
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
