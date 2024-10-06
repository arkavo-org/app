import AVFoundation
import CoreLocation
import FlatBuffers
import OpenTDFKit
import SwiftData
import SwiftUI

struct ThoughtStreamView: View {
    @StateObject var viewModel: ThoughtStreamViewModel
    @State private var inputText = ""
    @FocusState private var isInputFocused: Bool
    @State private var isSending = false
    @State private var isShareSheetPresented = false
    @State private var isShowingImagePicker = false
    @State private var isShowingCamera = false
    @State private var isShowingLocationPicker = false
    @State private var isShowingStickerPicker = false
    @State private var isStreamProfileExpanded = false

    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 0) {
                Color.clear
                    .frame(height: geometry.safeAreaInsets.top)

                streamProfileHeader
                    .padding(.top, 20)

//                ScrollViewReader { _ in
//                    ScrollView {
//                        LazyVStack(spacing: 8) {
//                            ForEach(Array(viewModel.thoughts.reversed().enumerated()), id: \.element.id) { index, thoughtViewModel in
//                                let totalThoughts = 8
//                                let opacity = Double(totalThoughts - min(index, totalThoughts - 1)) / Double(totalThoughts)
//                                MessageBubble(viewModel: thoughtViewModel, isCurrentUser: thoughtViewModel.creator.name == viewModel.accountProfile?.name)
//                                    .opacity(opacity)
//                                    .id(thoughtViewModel.id)
//                            }
//                        }
//                    }
//
//                    if viewModel.accountProfile != nil {
//                        messageInputArea
//                    }
//                }
            }
            .edgesIgnoringSafeArea(.top)
        }
        .onTapGesture {
            isInputFocused = true
        }
        .sheet(isPresented: $isShowingImagePicker) {
            imagePicker
        }
        .sheet(isPresented: $isShowingCamera) {
            cameraPicker
        }
        .sheet(isPresented: $isShowingLocationPicker) {
            LocationPicker { _ in
                // Handle selected location
            }
        }
        .sheet(isPresented: $isShowingStickerPicker) {
            StickerPicker { _ in
                // Handle selected sticker
            }
        }
        .sheet(isPresented: $isShareSheetPresented) {
            ShareSheet(activityItems: [shareURL].compactMap { $0 },
                       isPresented: $isShareSheetPresented)
        }
    }

    private var shareButton: some View {
        Button(action: prepareShare) {
            Image(systemName: "square.and.arrow.up")
        }
    }

    private var streamProfileHeader: some View {
        HStack {
//            StreamProfileBadge(
//                streamName: viewModel.stream?.profile.name ?? "Unknown Stream",
//                image: Image(systemName: "person.3.fill"),
//                isHighlighted: false,
//                description: "Stream description",
//                topicTags: ["Tag1", "Tag2"],
//                membersProfile: [], // You might want to populate this from your viewModel
//                ownerProfile: AccountProfileViewModel(profile: viewModel.stream?.profile ?? Profile(name: "Unknown"), activityService: ActivityServiceModel()),
//                activityLevel: .medium
//            )
//            .onTapGesture {
//                withAnimation {
//                    isStreamProfileExpanded.toggle()
//                }
//            }
            Spacer()
            shareButton
        }
        .padding(.horizontal)
    }

    private var messageInputArea: some View {
        HStack(alignment: .bottom) {
            Button(action: { isShowingCamera = true }) {
                Image(systemName: "camera")
                    .foregroundColor(.blue)
            }
            Button(action: { isShowingImagePicker = true }) {
                Image(systemName: "photo")
                    .foregroundColor(.blue)
            }
            TextField("Type a message...", text: $inputText)
                .padding(10)
            #if os(iOS) || os(visionOS) || targetEnvironment(macCatalyst)
                .background(Color(.systemGray6))
            #endif
                .clipShape(RoundedRectangle(cornerRadius: 20))
                .focused($isInputFocused)

            Button(action: {
                Task {
                    try await sendThought()
                }
            }) {
                Image(systemName: inputText.isEmpty ? "mic" : "arrow.up.circle.fill")
                    .foregroundColor(.blue)
                    .font(.system(size: 24))
            }
            .disabled(isSending)
        }
        .padding()
        #if os(iOS) || os(visionOS) || targetEnvironment(macCatalyst)
            .background(Color(.systemBackground))
        #endif
    }

    @ViewBuilder
    private var imagePicker: some View {
        #if os(iOS) || os(visionOS) || targetEnvironment(macCatalyst)
            ImagePicker(sourceType: .photoLibrary) { image in
                guard let imageData = image.heifData() else {
                    print("Failed to convert image to HEIF data")
                    return
                }
                Task {
                    try await sendImageThought(imageData)
                }
            }
        #else
            EmptyView()
        #endif
    }

    @ViewBuilder
    private var cameraPicker: some View {
        #if os(iOS)
            ImagePicker(sourceType: .camera) { image in
                guard let imageData = image.heifData() else {
                    print("Failed to convert image to HEIF data")
                    return
                }
                Task {
                    try await sendImageThought(imageData)
                }
            }
        #else
            EmptyView()
        #endif
    }

    private func prepareShare() {
        guard let stream = viewModel.stream
        else {
            print("streamCacheEvent: No stream to cache")
            return
        }
        // cache stream for later retrieval
        var builder = FlatBufferBuilder(initialSize: 1024)
        let targetIdVector = builder.createVector(bytes: stream.publicID)
        do {
            // FIXME: use nanotdf on StreamServiceModel
            let targetPayloadVector = builder.createVector(bytes: stream.publicID)
            // Create CacheEvent
            let cacheEventOffset = Arkavo_CacheEvent.createCacheEvent(
                &builder,
                targetIdVectorOffset: targetIdVector,
                targetPayloadVectorOffset: targetPayloadVector,
                ttl: 3600, // 1 hour TTL, TODOadjust as needed
                oneTimeAccess: false
            )
            // Create the Event object
            let eventOffset = Arkavo_Event.createEvent(
                &builder,
                action: .cache,
                timestamp: UInt64(Date().timeIntervalSince1970),
                status: .preparing,
                dataType: .cacheevent,
                dataOffset: cacheEventOffset
            )
            builder.finish(offset: eventOffset)
            let data = builder.data
            print("streamCacheEvent: \(data.base64EncodedString())")
            try viewModel.streamService.sendEvent(data)
            isShareSheetPresented = true
        } catch {
            print("streamCacheEvent: \(error)")
        }
    }

    private var shareURL: URL? {
        guard let publicID = viewModel.stream?.publicID.base58EncodedString
        else {
            return nil
        }
        return URL(string: "https://app.arkavo.com/stream/\(publicID)")
    }

    private func sendImageThought(_ imageData: Data) async throws {
        let streamPublicIDString = viewModel.stream!.publicID.base58EncodedString
        let account = try await PersistenceController.shared.getOrCreateAccount()
        let thoughtViewModel = ThoughtViewModel.createImage(
            creatorProfile: account.profile!,
            streamPublicIDString: streamPublicIDString,
            imageData: imageData
        )

        await viewModel.send(thoughtViewModel)
    }

    private func sendThought() async throws {
        guard !inputText.isEmpty else { return }
        let streamPublicIDString = viewModel.stream!.publicID.base58EncodedString
        let account = try await PersistenceController.shared.getOrCreateAccount()
        let thoughtViewModel = ThoughtViewModel.createText(creatorProfile: account.profile!, streamPublicIDString: streamPublicIDString, text: inputText)
        await viewModel.send(thoughtViewModel)
        inputText = ""
    }
}

#if os(iOS) || os(visionOS)
    struct ImagePicker: UIViewControllerRepresentable {
        let sourceType: UIImagePickerController.SourceType
        let onImagePicked: (UIImage) -> Void

        func makeUIViewController(context: Context) -> UIImagePickerController {
            let picker = UIImagePickerController()
            picker.sourceType = sourceType
            picker.delegate = context.coordinator
            return picker
        }

        func updateUIViewController(_: UIImagePickerController, context _: Context) {}

        func makeCoordinator() -> Coordinator {
            Coordinator(self)
        }

        class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
            let parent: ImagePicker

            init(_ parent: ImagePicker) {
                self.parent = parent
            }

            func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
                if let image = info[.originalImage] as? UIImage {
                    parent.onImagePicked(image)
                }
                picker.dismiss(animated: true)
            }
        }
    }
#endif

struct LocationPicker: View {
    let onLocationPicked: (CLLocation) -> Void

    var body: some View {
        Text("Location Picker Placeholder")
        // Implement a map view or location selection interface
    }
}

struct StickerPicker: View {
    let onStickerPicked: (String) -> Void

    var body: some View {
        Text("Sticker Picker Placeholder")
        // Implement a sticker selection interface
    }
}

@MainActor
class ThoughtStreamViewModel: StreamViewModel {
    @Published var service: ThoughtService
    @Published var streamService: StreamService
    @Published var thoughts: [ThoughtViewModel] = []

    init(thoughtService: ThoughtService, streamService: StreamService, stream: Stream) {
        service = thoughtService
        self.streamService = streamService
        super.init(stream: stream)
    }

    func loadAndDecrypt(for stream: Stream) {
        self.stream = stream
        for thought in stream.thoughts {
            do {
                try service.sendThought(thought.nano)
            } catch {
                print("sendThought error: \(error)")
            }
        }
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
    }

    func send(_ viewModel: ThoughtViewModel) async {
        guard let stream else { return }

        Task {
            do {
                let nano = try service.createNano(viewModel, stream: stream)
                // persist
                let thought = Thought(id: UUID(), nano: nano)
                thought.stream = stream
                PersistenceController.shared.container.mainContext.insert(thought)
                stream.thoughts.append(thought)
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

struct ThoughtStreamView_Previews: PreviewProvider {
    static var previews: some View {
        ThoughtStreamView(viewModel: previewViewModel)
            .modelContainer(previewContainer)
    }

    static var previewViewModel: ThoughtStreamViewModel {
        let arkavo = ArkavoService()
        let service = ThoughtService(arkavo)
        let streamService = StreamService(arkavo)
        let viewModel = ThoughtStreamViewModel(thoughtService: service, streamService: streamService, stream: previewStream)
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

// Extension to convert UIImage to HEIF data
#if os(iOS) || os(visionOS) || targetEnvironment(macCatalyst)
    extension UIImage {
        func heifData(maxSizeBytes: Int = 1_048_576, initialQuality: CGFloat = 0.9) -> Data? {
            var compressionQuality = initialQuality
            var imageData: Data?

            while compressionQuality > 0.1 {
                let data = NSMutableData()
                guard let destination = CGImageDestinationCreateWithData(data as CFMutableData, AVFileType.heic as CFString, 1, nil) else {
                    return nil
                }

                let options: [CFString: Any] = [
                    kCGImageDestinationLossyCompressionQuality: compressionQuality,
                    kCGImageDestinationOptimizeColorForSharing: true,
                ]

                guard let cgImage else {
                    return nil
                }

                CGImageDestinationAddImage(destination, cgImage, options as CFDictionary)

                if CGImageDestinationFinalize(destination) {
                    imageData = data as Data
                    if let imageData, imageData.count <= maxSizeBytes {
                        return imageData
                    }
                }

                compressionQuality -= 0.1
            }

            // If we couldn't get it under the limit, return nil or consider other options
            return nil
        }
    }
#endif
