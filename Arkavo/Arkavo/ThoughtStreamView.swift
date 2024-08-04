import SwiftUI
import OpenTDFKit
import CryptoKit

struct ThoughtStreamView: View {
    @StateObject private var viewModel: ThoughtStreamViewModel
    @State private var topThoughts: [Thought] = [
        Thought(text: "Top thought 1...", offset: 0, color: .blue),
        Thought(text: "Top thought 2...", offset: 0.2, color: .blue),
        Thought(text: "Top thought 3...", offset: 0.4, color: .blue),
        Thought(text: "Top thought 4...", offset: 0.6, color: .blue),
        Thought(text: "Top thought 5...", offset: 0.8, color: .blue)
    ]
    @State private var bottomThoughts: [Thought] = [
        Thought(text: "Bottom thought 1...", offset: 0, color: .green),
        Thought(text: "Bottom thought 2...", offset: 0.2, color: .green),
        Thought(text: "Bottom thought 3...", offset: 0.4, color: .green),
        Thought(text: "Bottom thought 4...", offset: 0.6, color: .green),
        Thought(text: "Bottom thought 5...", offset: 0.8, color: .green)
    ]
    @State private var inputText = ""
    @FocusState private var isInputFocused: Bool
    
    @ObservedObject var webSocketManager: WebSocketManager
    let nanoTDFManager: NanoTDFManager
    @Binding var kasPublicKey: P256.KeyAgreement.PublicKey?
    
    init(webSocketManager: WebSocketManager, nanoTDFManager: NanoTDFManager, kasPublicKey: Binding<P256.KeyAgreement.PublicKey?>) {
        _viewModel = StateObject(wrappedValue: ThoughtStreamViewModel(webSocketManager: webSocketManager, nanoTDFManager: nanoTDFManager, kasPublicKey: kasPublicKey))
        self.webSocketManager = webSocketManager
        _kasPublicKey = kasPublicKey
        self.nanoTDFManager = nanoTDFManager
    }
    
    let topColor = Color.blue
    let bottomColor = Color.green
    
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
                        ForEach(topThoughts) { thought in
                            ThoughtView(thought: thought,
                                        screenHeight: geometry.size.height,
                                        isTopThought: true)
                        }
                        
                        // Flowing thoughts from bottom
                        ForEach(bottomThoughts) { thought in
                            ThoughtView(thought: thought,
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
                        
                        Button(action: addThought) {
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
            viewModel.setupCustomMessageHandling()
            startThoughtAnimation()
            isInputFocused = false
        }
    }

    private func addThought() {
         guard !inputText.isEmpty else { return }
         guard let kasPublicKey = kasPublicKey else {
             print("KAS public key not available")
             return
         }

         do {
             // Create a NanoTDF
             let thoughtData = inputText.data(using: .utf8)!
             let kasRL = ResourceLocator(protocolEnum: .sharedResourceDirectory, body: "kas.arkavo.net")!
             let kasMetadata = KasMetadata(resourceLocator: kasRL, publicKey: kasPublicKey, curve: .secp256r1)
             // smart contract
             let remotePolicy = ResourceLocator(protocolEnum: .sharedResourceDirectory, body: "5GnJAVumy3NBdo2u9ZEK1MQAXdiVnZWzzso4diP2JszVgSJQ")!
             var policy = Policy(type: .remote, body: nil, remote: remotePolicy, binding: nil)

             let nanoTDF = try createNanoTDF(kas: kasMetadata, policy: &policy, plaintext: thoughtData)
            
             // Create and send the NATSMessage
             let natsMessage = NATSMessage(payload: nanoTDF.toData())
             let messageData = natsMessage.toData()
             // test parseHeader
             print("NATS message payload sent: \(natsMessage.payload.base64EncodedString())")

             webSocketManager.sendCustomMessage(messageData) { error in
                 if let error = error {
                     print("Error sending thought: \(error)")
                     // Handle error (e.g., show an alert to the user)
                 } else {
                     print("Thought sent successfully")
                     // Add the thought to the local arrays
                     DispatchQueue.main.async {
                         self.addThoughtToLocalArrays()
                     }
                 }
             }

             // Add the thought to the local arrays
             let newThought = Thought(text: inputText, offset: 0, color: topThoughts.count <= bottomThoughts.count ? topColor : bottomColor)
             
             if topThoughts.count <= bottomThoughts.count {
                 topThoughts.insert(newThought, at: 0)
                 if topThoughts.count > 5 {
                     topThoughts.removeLast()
                 }
             } else {
                 bottomThoughts.insert(newThought, at: 0)
                 if bottomThoughts.count > 5 {
                     bottomThoughts.removeLast()
                 }
             }
             
             // Reset offsets for flowing effect
             for i in 0..<topThoughts.count {
                 topThoughts[i].offset = Double(i) * 0.2
             }
             for i in 0..<bottomThoughts.count {
                 bottomThoughts[i].offset = Double(i) * 0.2
             }

             // Clear the input field
             inputText = ""
         } catch {
             print("Error creating NanoTDF: \(error)")
         }
     }
    
    private func startThoughtAnimation() {
        for i in 0..<topThoughts.count {
            withAnimation(.linear(duration: 10).repeatForever(autoreverses: false)) {
                topThoughts[i].offset = 1.0
            }
        }
        for i in 0..<bottomThoughts.count {
            withAnimation(.linear(duration: 10).repeatForever(autoreverses: false)) {
                bottomThoughts[i].offset = 1.0
            }
        }
    }
    
    private func addThoughtToLocalArrays() {
        let newThought = Thought(text: inputText, offset: 0, color: topThoughts.count <= bottomThoughts.count ? topColor : bottomColor)
        
        if topThoughts.count <= bottomThoughts.count {
            topThoughts.insert(newThought, at: 0)
            if topThoughts.count > 5 {
                topThoughts.removeLast()
            }
        } else {
            bottomThoughts.insert(newThought, at: 0)
            if bottomThoughts.count > 5 {
                bottomThoughts.removeLast()
            }
        }
        
        // Reset offsets for flowing effect
        for i in 0..<topThoughts.count {
            topThoughts[i].offset = Double(i) * 0.2
        }
        for i in 0..<bottomThoughts.count {
            bottomThoughts[i].offset = Double(i) * 0.2
        }
    }
}

struct Thought: Identifiable {
    let id = UUID()
    let text: String
    var offset: Double
    let color: Color
}

struct ThoughtView: View {
    let thought: Thought
    let screenHeight: CGFloat
    let isTopThought: Bool
    
    var body: some View {
        Text(thought.text)
            .font(.caption)
            .padding(8)
            .background(thought.color.opacity(0.7))
            .foregroundColor(.white)
            .clipShape(Capsule())
            .scaleEffect(1 - thought.offset * 0.5) // Decrease size as it moves to center
            .opacity(1 - thought.offset) // Fade out as it moves to center
            .offset(y: calculateYOffset())
    }
    
    private func calculateYOffset() -> CGFloat {
        let visibleHeight = screenHeight - 100 // Adjust for input box and keyboard
        let startY = isTopThought ? -visibleHeight / 2 : visibleHeight / 2
        let endY: CGFloat = 0 // Center of the visible area
        return startY + CGFloat(thought.offset) * (endY - startY)
    }
}

actor ThoughtHandler {
   
    func handleIncomingThought(data: Data) async {
        // Assuming the incoming data is a NATSMessage
//        print("NATS message payload received: \(natsMessage.payload.base64EncodedString())")
//        print("NATS payload size: \(natsMessage.payload.count)")
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
//            nanoTDFManager.addNanoTDF(nanoTDF, withIdentifier: id)
//            webSocketManager.sendRewrapMessage(header: nanoTDF.header)
            
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
    @Published var webSocketManager: WebSocketManager
    let nanoTDFManager: NanoTDFManager
    @Binding var kasPublicKey: P256.KeyAgreement.PublicKey?
    
    init(webSocketManager: WebSocketManager, nanoTDFManager: NanoTDFManager, kasPublicKey: Binding<P256.KeyAgreement.PublicKey?>) {
        self.webSocketManager = webSocketManager
        self.nanoTDFManager = nanoTDFManager
        self._kasPublicKey = kasPublicKey
    }
    
    func setupCustomMessageHandling() {
        let handler = ThoughtHandler()
        webSocketManager.setCustomMessageCallback { data in
            Task {
                await handler.handleIncomingThought(data: data)
            }
        }
    }

    private func handleIncomingThought(data: Data) {

    }
}

struct ThoughtStreamView_Previews: PreviewProvider {
    static var previews: some View {
        ThoughtStreamView(
            webSocketManager: WebSocketManager(),
            nanoTDFManager: NanoTDFManager(),
            kasPublicKey: .constant(nil)
        )
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
