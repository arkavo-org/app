import AVFoundation
import CoreLocation
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
                                TextField("", text: $inputText)
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
                    if viewModel.creatorProfile != nil {
                        #if os(iOS) || os(visionOS) || targetEnvironment(macCatalyst)
                            HStack(alignment: .bottom) {
                                Button(action: { isShowingCamera = true }) {
                                    Image(systemName: "camera")
                                        .foregroundColor(.blue)
                                }
                                Button(action: { isShowingImagePicker = true }) {
                                    Image(systemName: "photo")
                                        .foregroundColor(.blue)
                                }
//                             Button(action: { isShowingStickerPicker = true }) {
//                                 Image(systemName: "face.smiling")
//                                     .foregroundColor(.blue)
//                             }
//                             Button(action: { isShowingLocationPicker = true }) {
//                                 Image(systemName: "location")
//                                     .foregroundColor(.blue)
//                             }
                                TextField("Type a message...", text: $inputText)
                                    .padding(10)
                                    .background(Color(.systemGray6))
                                    .clipShape(RoundedRectangle(cornerRadius: 20))
                                    .focused($isInputFocused)

                                Button(action: {
                                    Task {
                                        await sendThought()
                                    }
                                }) {
//                                Image(systemName: inputText.isEmpty ? "mic" : "arrow.up.circle.fill")
//                                    .foregroundColor(.blue)
//                                    .font(.system(size: 24))
                                }
                                .disabled(isSending)
                            }
                            .padding()
                            .background(Color(.systemBackground))
                        #endif
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
        .sheet(isPresented: $isShowingImagePicker) {
            #if os(iOS) || os(visionOS) || targetEnvironment(macCatalyst)
                ImagePicker(sourceType: .photoLibrary) { image in
                    guard let imageData = image.heifData() else {
                        print("Failed to convert image to HEIF data")
                        return
                    }
                    Task {
                        await sendImageThought(imageData)
                    }
                }
            #endif
        }
        .sheet(isPresented: $isShowingCamera) {
            #if os(iOS) || os(visionOS)
                ImagePicker(sourceType: .camera) { image in
                    guard let imageData = image.heifData() else {
                        print("Failed to convert image to HEIF data")
                        return
                    }
                    Task {
                        await sendImageThought(imageData)
                    }
                }
            #endif
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

    private func sendImageThought(_ imageData: Data) async {
        guard let streamPublicIdString = viewModel.stream?.publicId.map({ String(format: "%02hhx", $0) }).joined(),
              let creatorProfile = viewModel.creatorProfile
        else {
            return
        }

        let thoughtViewModel = ThoughtViewModel.createImage(
            creatorProfile: creatorProfile,
            streamPublicIdString: streamPublicIdString,
            imageData: imageData
        )

        await viewModel.send(thoughtViewModel)
    }

    private func sendThought() async {
        guard !inputText.isEmpty else { return }
        let streamPublicIDString = viewModel.stream?.publicID.base58EncodedString ?? ""
        let thoughtViewModel = ThoughtViewModel.createText(creatorProfile: viewModel.creatorProfile!, streamPublicIDString: streamPublicIDString, text: inputText)
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
    @Published var content: Data
    @Published var mediaType: MediaType

    init(mediaType: MediaType, content: Data, creator: Profile, streamPublicIDString: String) {
        self.mediaType = mediaType
        self.content = content
        self.creator = creator
        self.streamPublicIDString = streamPublicIDString
    }

    static func == (lhs: ThoughtViewModel, rhs: ThoughtViewModel) -> Bool {
        lhs.id == rhs.id
    }

    static func createText(creatorProfile: Profile, streamPublicIDString: String, text: String) -> ThoughtViewModel {
        ThoughtViewModel(mediaType: .text, content: text.isEmpty ? Data() : text.data(using: .utf8) ?? Data(), creator: creatorProfile, streamPublicIdString: streamPublicIdString)
    }

    static func createImage(creatorProfile: Profile, streamPublicIDString: String, imageData: Data) -> ThoughtViewModel {
        let imageContent = "Image data: \(imageData.count) bytes"
        print(imageContent)
        return ThoughtViewModel(mediaType: .image, content: imageData, creator: creatorProfile, streamPublicIDString: streamPublicIdString)
    }

    static func createAudio(creatorProfile: Profile, streamPublicIDString: String, audioData: Data) -> ThoughtViewModel {
        let audioContent = "Audio data: \(audioData.count) bytes"
        print(audioContent)
        return ThoughtViewModel(mediaType: .audio, content: audioData, creator: creatorProfile, streamPublicIdString: streamPublicIdString)
    }

    static func createVideo(creatorProfile: Profile, streamPublicIDString: String, videoData: Data) -> ThoughtViewModel {
        let videoContent = "Video data: \(videoData.count) bytes"
        print(videoContent)
        return ThoughtViewModel(mediaType: .video, content: videoData, creator: creatorProfile, streamPublicIDString: streamPublicIdString)
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
                Group {
                    switch viewModel.mediaType {
                    case .text:
                        if let text = String(data: viewModel.content, encoding: .utf8) {
                            Text(text)
                                .padding(10)
                                .background(isCurrentUser ? Color.blue : Color(.gray))
                                .foregroundColor(isCurrentUser ? .white : .primary)
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                        } else {
                            Text("Unable to decode text")
                                .foregroundColor(.red)
                        }
                    case .image:
                        #if os(iOS) || os(visionOS) || targetEnvironment(macCatalyst)
                            if let uiImage = UIImage(data: viewModel.content) {
                                Image(uiImage: uiImage)
                                    .resizable()
                                    .scaledToFit()
                                    .frame(maxWidth: 200, maxHeight: 200)
                                    .clipShape(RoundedRectangle(cornerRadius: 10))
                            } else {
                                Text("Unable to load image")
                                    .foregroundColor(.red)
                            }
                        #endif
                    case .audio, .video:
                        Text("Unsupported media type: \(viewModel.mediaType)")
                            .foregroundColor(.red)
                    }
                }
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
