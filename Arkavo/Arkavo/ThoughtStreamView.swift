import SwiftUI
import OpenTDFKit
import CryptoKit

// Wrapper struct for Thought
struct ThoughtWrapper: Identifiable {
    let id = UUID()
    let thought: Thought
}

struct ThoughtStreamView: View {
    @ObservedObject var viewModel: ThoughtStreamViewModel
    @State private var inputText = ""
    @FocusState private var isInputFocused: Bool
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Background gradient
                LinearGradient(gradient: Gradient(colors: [Color.gray.opacity(0.2), Color.gray.opacity(0.1)]),
                               startPoint: .top,
                               endPoint: .bottom)
                    .edgesIgnoringSafeArea(.all)
                
                VStack(spacing: 0) {
                    // Thought stream area
                    ZStack {
                        // Flowing thoughts from top
                        ForEach(Array(viewModel.topThoughts.enumerated()), id: \.element.id) { index, wrapper in
                            ThoughtView(thought: wrapper.thought,
                                        index: index,
                                        totalCount: viewModel.topThoughts.count,
                                        screenHeight: geometry.size.height,
                                        isTopThought: true,
                                        color: .blue)
                        }
                        
                        ForEach(Array(viewModel.bottomThoughts.enumerated()), id: \.element.id) { index, wrapper in
                            ThoughtView(thought: wrapper.thought,
                                        index: index,
                                        totalCount: viewModel.bottomThoughts.count,
                                        screenHeight: geometry.size.height,
                                        isTopThought: false,
                                        color: .green)
                        }
                    }
                    .frame(height: geometry.size.height - 100) // Adjust for input box and keyboard
                    
                    // Input box
                    HStack {
                        TextField("Enter your thought...", text: $inputText)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                            .focused($isInputFocused)
                        
                        Button(action: sendThought) {
                            Image(systemName: "arrow.up.circle.fill")
                                .foregroundColor(.blue)
                                .font(.title)
                        }
                    }
                    .padding()
                    .background(Color.white)
                    .shadow(radius: 5)
                }
            }
        }
        .onAppear {
            isInputFocused = false
        }
    }

    private func sendThought() {
        guard !inputText.isEmpty else { return }
        let newThought = Thought.createTextThought(inputText)
        viewModel.sendThought(thought: newThought)
        inputText = ""
    }
}

struct ThoughtView: View {
    let thought: Thought
    let index: Int
    let totalCount: Int
    let screenHeight: CGFloat
    let isTopThought: Bool
    let color: Color
    
    @State private var offset: CGFloat = 0
    
    var body: some View {
        Text(thought.content.first?.content ?? "")
            .padding(8)
            .background(color.opacity(0.7))
            .foregroundColor(.white)
            .clipShape(Capsule())
            .scaleEffect(1 - offset * 0.5)
            .offset(y: calculateYOffset())
            .onAppear {
                withAnimation(.linear(duration: 10).repeatForever(autoreverses: false)) {
                    offset = 1
                }
            }
    }
    
    private func calculateYOffset() -> CGFloat {
        let visibleHeight = screenHeight - 100
        let startY = isTopThought ? -visibleHeight / 2 : visibleHeight / 2
        let endY: CGFloat = 0
        let progress = CGFloat(index) / CGFloat(totalCount - 1)
        return startY + (endY - startY) * progress * offset
    }
}

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
            // FIXME copy of data after first byte
            let subData = data.subdata(in: 1..<data.count)
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
    @Published var topThoughts: [ThoughtWrapper] = []
    @Published var bottomThoughts: [ThoughtWrapper] = []
    let maxThoughtsPerStream: Int = 10
    public var thoughtHandler: ThoughtHandler?
    // nano
    @Published var webSocketManager: WebSocketManager
    var nanoTDFManager: NanoTDFManager
    @Binding var kasPublicKey: P256.KeyAgreement.PublicKey?

    init() {
        self._kasPublicKey = .constant(nil)  // Temporary binding
        _webSocketManager = .init(initialValue: WebSocketManager())
        _kasPublicKey = .constant(nil)
        nanoTDFManager = NanoTDFManager()
    }
    
    func initialize(webSocketManager: WebSocketManager, nanoTDFManager: NanoTDFManager, kasPublicKey: Binding<P256.KeyAgreement.PublicKey?>) {
            self.webSocketManager = webSocketManager
        self.webSocketManager = webSocketManager
        self._kasPublicKey = kasPublicKey
        self.nanoTDFManager = nanoTDFManager
        self.thoughtHandler = ThoughtHandler(nanoTDFManager: nanoTDFManager, webSocketManager: webSocketManager)
        webSocketManager.setCustomMessageCallback { [weak self] data in
            print("setCustomMessageCallback")
            guard let self = self, let thoughtHandler = self.thoughtHandler else { return }
            Task {
                await thoughtHandler.handleIncomingThought(data: data)
            }
        }
    }
    func sendThought(thought: Thought) {
        guard let kasPublicKey = kasPublicKey else {
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
                if let error = error {
                    print("Error sending thought: \(error)")
                }
            }
        } catch {
            print("Error creating or serializing NanoTDF: \(error)")
        }
    }
    func receiveThought(_ newThought: Thought) {
        DispatchQueue.main.async {
            self.addThought(newThought, toTop: true)
        }
    }
    
    func addThought(_ thought: Thought, toTop: Bool) {
        let wrappedThought = ThoughtWrapper(thought: thought)
        if toTop {
            topThoughts.insert(wrappedThought, at: 0)
            if topThoughts.count > maxThoughtsPerStream {
                topThoughts.removeLast()
            }
        } else {
            bottomThoughts.insert(wrappedThought, at: 0)
            if bottomThoughts.count > maxThoughtsPerStream {
                bottomThoughts.removeLast()
            }
        }
    }
}

struct ThoughtStreamView_Previews: PreviewProvider {
    static var previews: some View {
        let viewModel = ThoughtStreamViewModel()
        ThoughtStreamView(viewModel: viewModel)
    }
}
