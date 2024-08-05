import SwiftUI
import OpenTDFKit
import CryptoKit

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
                        ForEach(viewModel.topThoughts.indices, id: \.self) { index in
                            ThoughtView(thought: viewModel.topThoughts[index],
                                        screenHeight: geometry.size.height,
                                        isTopThought: true)
                        }
                        
                        // Flowing thoughts from bottom
                        ForEach(viewModel.bottomThoughts.indices, id: \.self) { index in
                            ThoughtView(thought: viewModel.bottomThoughts[index],
                                        screenHeight: geometry.size.height,
                                        isTopThought: false)
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
            startThoughtAnimation()
            isInputFocused = false
        }
    }

    private func sendThought() {
        guard !inputText.isEmpty else { return }
        let newThought = Thought.createTextThought(inputText)
        viewModel.sendThought(thought: newThought)
        inputText = ""
    }
    
    private func startThoughtAnimation() {
        for i in 0..<viewModel.topThoughts.count {
            withAnimation(.linear(duration: 10).repeatForever(autoreverses: false)) {
                viewModel.topThoughts[i].uiProperties.offset = 1.0
            }
        }
        for i in 0..<viewModel.bottomThoughts.count {
            withAnimation(.linear(duration: 10).repeatForever(autoreverses: false)) {
                viewModel.bottomThoughts[i].uiProperties.offset = 1.0
            }
        }
    }
}

struct ThoughtView: View {
    let thought: Thought
    let screenHeight: CGFloat
    let isTopThought: Bool
    
    var body: some View {
        Text(thought.content.first?.content ?? "")
            .font(.caption)
            .padding(8)
            .background(thought.uiProperties.color.opacity(0.7))
            .foregroundColor(.white)
            .clipShape(Capsule())
            .scaleEffect(1 - thought.uiProperties.offset * 0.5) // Decrease size as it moves to center
            .opacity(1 - thought.uiProperties.offset) // Fade out as it moves to center
            .offset(y: calculateYOffset())
    }
    
    private func calculateYOffset() -> CGFloat {
        let visibleHeight = screenHeight - 100 // Adjust for input box and keyboard
        let startY = isTopThought ? -visibleHeight / 2 : visibleHeight / 2
        let endY: CGFloat = 0 // Center of the visible area
        return startY + CGFloat(thought.uiProperties.offset) * (endY - startY)
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
        print("NATS message received: \(data.base64EncodedString())")
        print("NATS payload size: \(data.count)")
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
            print("ephemeralPublicKey: \(id.base64EncodedString())")
            nanoTDFManager.addNanoTDF(nanoTDF, withIdentifier: id)
            webSocketManager.sendRewrapMessage(header: nanoTDF.header)
            
            // TODO: handle RewrappedKey
            // let decryptedData = try nanoTDF.getPayloadPlaintext(symmetricKey: storedKey)
            // let decryptedMessage = String(data: decryptedData, encoding: .utf8)
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
    @Published var topThoughts: [Thought] = []
    @Published var bottomThoughts: [Thought] = []
    let maxThoughtsPerStream: Int = 5
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
            print("NATS message payload sent: \(natsMessage.payload.base64EncodedString())")

            webSocketManager.sendCustomMessage(messageData) { error in
                if let error = error {
                    print("Error sending thought: \(error)")
                } else {
                    print("Thought sent successfully")
                }
            }
        } catch {
            print("Error creating or serializing NanoTDF: \(error)")
        }
    }
    func receiveThought(_ newThought: Thought) {
        DispatchQueue.main.async {
            self.addThoughtToLocalArrays(newThought)
        }
    }
    private func addThoughtToLocalArrays(_ newThought: Thought) {
        if topThoughts.count <= bottomThoughts.count {
            addThought(newThought, to: &topThoughts, color: .blue)
        } else {
            addThought(newThought, to: &bottomThoughts, color: .green)
        }
    }
    
    private func addThought(_ thought: Thought, to thoughts: inout [Thought], color: Color) {
        var updatedThought = thought
        updatedThought.uiProperties = Thought.UIProperties(offset: 0, color: color)
        
        thoughts.insert(updatedThought, at: 0)
        if thoughts.count > maxThoughtsPerStream {
            thoughts.removeLast()
        }
        
        updateOffsets(for: &thoughts)
    }
    
    private func updateOffsets(for thoughts: inout [Thought]) {
        for i in 0..<thoughts.count {
            thoughts[i].uiProperties.offset = Double(i) * 0.2
        }
    }
}

struct ThoughtStreamView_Previews: PreviewProvider {
    static var previews: some View {
        let viewModel = ThoughtStreamViewModel()
        ThoughtStreamView(viewModel: viewModel)
    }
}

// Extension for UI-specific properties
extension Thought {
    struct UIProperties {
        var offset: Double
        var color: Color
    }
    
    var uiProperties: UIProperties {
        get { UIProperties(offset: 0, color: .blue) }
        set { }
    }
}

//actor DebugDataReader {
//    private var data: Data
//    private var cursor: Int
//
//    init(data: Data) {
//        // copy data for debug
//        self.data = Data(data)
//        self.cursor = 0
//        print("First \(min(32, data.count)) bytes of data: \(data.prefix(32).map { String(format: "%02x", $0) }.joined(separator: " "))")
//    }
//
//    func read(length: Int) -> Data? {
//        print("read called with length: \(length), cursor: \(cursor), data.count: \(data.count)")
//        
//        guard length > 0 else {
//            print("Error: Attempted to read non-positive length")
//            return nil
//        }
//        
//        guard cursor >= 0 else {
//            print("Error: Cursor is negative")
//            return nil
//        }
//        
//        guard cursor < data.count else {
//            print("Error: Cursor is beyond data bounds")
//            return nil
//        }
//        
//        guard cursor + length <= data.count else {
//            print("Error: Requested range exceeds data bounds")
//            return nil
//        }
//        
//        let range = cursor..<(cursor + length)
//        print("Attempting to read range: \(range)")
//        
//        let result = data.subdata(in: range)
//        cursor += length
//        
//        print("Read successful. New cursor position: \(cursor)")
//        return result
//    }
//
//    func resetCursor() {
//        cursor = 0
//        print("Cursor reset to 0")
//    }
//
//    func getState() -> (cursor: Int, dataCount: Int) {
//        return (cursor, data.count)
//    }
//}
