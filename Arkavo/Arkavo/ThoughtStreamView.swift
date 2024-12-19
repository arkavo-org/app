import AVFoundation
import CoreLocation
import CryptoKit
import FlatBuffers
import OpenTDFKit
import SwiftData
import SwiftUI

struct ThoughtStreamView: View {
    @Environment(\.dismiss) private var dismiss
    @State var service: ThoughtService
    @State var streamService: StreamService
    @StateObject var viewModel: ThoughtStreamViewModel
    @State var streamBadgeViewModel: StreamBadgeViewModel
    @State var accountProfile: Profile?
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
                topSection(geometry: geometry)
                thoughtsList
                messageInputArea
            }
            .edgesIgnoringSafeArea(.top)
            .navigationBarBackButtonHidden(true)
            .toolbar {
                #if os(iOS)
                    ToolbarItem(placement: .navigationBarLeading) {
                        Button("Back") { dismiss() }
                    }
                #else
                    ToolbarItem(placement: .automatic) {
                        Button("Back") { dismiss() }
                    }
                #endif
            }
            .onAppear(perform: onAppear)
            .onDisappear(perform: onDisappear)
            .onTapGesture { isInputFocused = true }
            #if os(iOS)
                .sheet(isPresented: $isShowingImagePicker) { imagePicker }
                .sheet(isPresented: $isShowingCamera) { cameraPicker }
            #endif
                .sheet(isPresented: $isShowingLocationPicker) { locationPicker }
                .sheet(isPresented: $isShowingStickerPicker) { stickerPicker }
                .sheet(isPresented: $isShareSheetPresented) { shareSheet }
        }
    }

    private var thoughtsList: some View {
        ScrollViewReader { _ in
            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(viewModel.thoughts) { thoughtViewModel in
                        MessageBubble(
                            viewModel: thoughtViewModel,
                            isCurrentUser: thoughtViewModel.creator.publicID == accountProfile?.publicID
                        )
                        .id(thoughtViewModel.id)
                    }
                }
            }
        }
    }

    private func topSection(geometry: GeometryProxy) -> some View {
        VStack(spacing: 0) {
            Color.clear
                .frame(height: geometry.safeAreaInsets.top)
            HStack {
                StreamProfileBadge(viewModel: streamBadgeViewModel)
                    .onTapGesture {
                        withAnimation {
                            isStreamProfileExpanded.toggle()
                        }
                    }
                Spacer()
                shareButton
            }
            .padding(.horizontal)
            .padding(.top, 20)
        }
    }

    private var shareButton: some View {
        Button(action: {
            Task {
                await prepareShare()
            }
        }) {
            Image(systemName: "square.and.arrow.up")
        }
    }

    private var messageInputArea: some View {
        HStack(alignment: .bottom) {
            Menu {
                Button(action: { isShowingCamera = true
                }) {
                    Label("Camera", systemImage: "camera")
                }
                Button(action: {
                    onLocationProtected()
                }) {
                    Label("Camera Location Protected", systemImage: "camera.viewfinder")
                }
                Button(action: {
                    // TODO: Handle Camera Time Protected action
                }) {
                    Label("Camera Time Protected", systemImage: "camera.aperture")
                }
                Button(action: { isShowingImagePicker = true }) {
                    Label("Photo", systemImage: "photo")
                }
            } label: {
                Image(systemName: "plus.circle")
                    .font(.system(size: 24))
                    .foregroundColor(.blue)
            }

            TextField("Type a message...", text: $inputText)
                .padding(10)
                //  .background(Color.)
                .clipShape(RoundedRectangle(cornerRadius: 20))
                .focused($isInputFocused)

            sendButton
        }
        .padding()
        .background(Color.blue.opacity(0.1))
    }

    private var sendButton: some View {
        Button(action: {
            Task {
                try await sendThought()
            }
        }) {
            Image(systemName: inputText.isEmpty ? "mic.slash" : "arrow.up.circle.fill")
                .foregroundColor(inputText.isEmpty ? .gray : .blue)
                .font(.system(size: 24))
        }
        .disabled(inputText.isEmpty || isSending)
        .opacity(inputText.isEmpty || isSending ? 0.5 : 1.0) // Dim the button when disabled
    }

    #if os(iOS)
        private var imagePicker: some View {
            ImagePicker(sourceType: .photoLibrary) { image in
                guard let imageData = image.heifData() else {
                    print("Failed to convert image to HEIF data")
                    return
                }
                Task {
                    try await sendImageThought(imageData)
                }
            }
        }

        private var cameraPicker: some View {
            ImagePicker(sourceType: .camera) { image in
                guard let imageData = image.heifData() else {
                    print("Failed to convert image to HEIF data")
                    return
                }
                Task {
                    try await sendImageThought(imageData)
                }
            }
        }
    #endif
    private var locationPicker: some View {
        LocationPicker { _ in
            // Handle selected location
        }
    }

    private var stickerPicker: some View {
        StickerPicker { _ in
            // Handle selected sticker
        }
    }

    private var shareSheet: some View {
        ShareSheet(activityItems: [shareURL].compactMap(\.self),
                   isPresented: $isShareSheetPresented)
    }

    private func onLocationProtected() {
        print("Handle Camera Location Protected action")
        // relative location -
        // TODO: get all stream members, then request location from all
        if let stream = viewModel.stream {
            let memberPublicID = stream.creatorPublicID
            Task {
                let locationData = try await streamService.requestLocationAndWait(for: memberPublicID)
                await MainActor.run {
                    print("Received locationData: \(locationData.latitude), \(locationData.longitude)")
                }
            }
        }
    }

    private func onAppear() {
        streamBadgeViewModel.isExpanded = false
        viewModel.service.thoughtStreamViewModel = viewModel
        Task {
            let account = try await PersistenceController.shared.getOrCreateAccount()
            accountProfile = account.profile
            if let stream = viewModel.stream {
                for thought in stream.thoughts {
                    do {
                        try service.sendThought(thought.nano)
                    } catch {
                        print("sendThought error: \(error)")
                    }
                }
            }
        }
    }

    private func onDisappear() {
        viewModel.service.thoughtStreamViewModel = nil
    }

    private func prepareShare() async {
        guard let stream = viewModel.stream
        else {
            print("streamCacheEvent: No stream to cache")
            return
        }
        // cache stream for later retrieval
        do {
            try await streamService.sendStreamEvent(stream)
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
        guard let stream = viewModel.stream else { return }
        let streamPublicIDString = stream.publicID.base58EncodedString
        let account = try await PersistenceController.shared.getOrCreateAccount()
        let thoughtViewModel = ThoughtViewModel.createImage(
            creatorProfile: account.profile!,
            streamPublicIDString: streamPublicIDString,
            imageData: imageData
        )
        await service.send(viewModel: thoughtViewModel, stream: stream)
        viewModel.thoughts.append(thoughtViewModel)
    }

    private func sendThought() async throws {
        guard !inputText.isEmpty else { return }
        guard let stream = viewModel.stream else { return }
        let streamPublicIDString = stream.publicID.base58EncodedString
        let account = try await PersistenceController.shared.getOrCreateAccount()
        let thoughtViewModel = ThoughtViewModel.createText(creatorProfile: account.profile!, streamPublicIDString: streamPublicIDString, text: inputText)
        await service.send(viewModel: thoughtViewModel, stream: stream)
        // show
        viewModel.thoughts.append(thoughtViewModel)
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
    var service: ThoughtService
    @Published var thoughts: [ThoughtViewModel] = []

    init(service: ThoughtService, stream: Stream) {
        self.service = service
        super.init(stream: stream)
    }

    @MainActor func handle(_ decryptedData: Data, policy _: ArkavoPolicy, nano: NanoTDF) async throws {
        guard let stream else { throw ThoughtServiceError.missingThoughtStreamViewModel }
        let thoughtServiceModel = try ThoughtServiceModel.deserialize(from: decryptedData)
        // dedupe PersistenceController.shared
        let found = try await PersistenceController.shared.fetchThought(withPublicID: thoughtServiceModel.publicID)
        if found != nil {
            // FIXME: is it saved multiple places, should we return
            print("Thought already exists \(thoughtServiceModel.publicID.base58EncodedString)")
//            return
        }
        if stream.publicID != thoughtServiceModel.streamPublicID {
            print("Wrong stream")
            return
        }
        let account = try await PersistenceController.shared.getOrCreateAccount()
        guard let accountProfile = account.profile,
              accountProfile.publicID != thoughtServiceModel.creatorPublicID
        else {
            // mine, just return
            return
        }
        // persist
        let thought = Thought(nano: nano.toData())
        thought.publicID = thoughtServiceModel.publicID
        thought.nano = nano.toData()
        thought.stream = stream
        let isNew = try PersistenceController.shared.saveThought(thought)
        if !isNew { return }
        stream.thoughts.append(thought)
        try await PersistenceController.shared.saveChanges()
        // show
        let creatorProfile = Profile(name: thoughtServiceModel.creatorPublicID.base58EncodedString)
        let streamPublicIDString = stream.publicID.base58EncodedString
        let viewModel: ThoughtViewModel
        switch thoughtServiceModel.mediaType {
        case .text:
            let text = String(decoding: thoughtServiceModel.content, as: UTF8.self)
            viewModel = ThoughtViewModel.createText(creatorProfile: creatorProfile, streamPublicIDString: streamPublicIDString, text: text)
        case .image:
            viewModel = ThoughtViewModel.createImage(creatorProfile: creatorProfile, streamPublicIDString: streamPublicIDString, imageData: thoughtServiceModel.content)
        case .audio:
            viewModel = ThoughtViewModel.createAudio(creatorProfile: creatorProfile, streamPublicIDString: streamPublicIDString, audioData: thoughtServiceModel.content)
        case .video:
            viewModel = ThoughtViewModel.createVideo(creatorProfile: creatorProfile, streamPublicIDString: streamPublicIDString, videoData: thoughtServiceModel.content)
        }
        DispatchQueue.main.async {
            self.thoughts.append(viewModel)
        }
    }

    enum ThoughtServiceError: Error {
        case missingThoughtStreamViewModel
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

struct ThoughtStreamView_Previews: PreviewProvider {
    static var previews: some View {
        ThoughtStreamView(
            service: previewThoughtService,
            streamService: previewStreamService,
            viewModel: previewViewModel,
            streamBadgeViewModel: previewStreamBadgeViewModel,
            accountProfile: previewProfile
        )
        .modelContainer(previewContainer)
    }

    static var creatorUUID = UUID()
    static var creatorPublicID: Data {
        withUnsafeBytes(of: creatorUUID) { buffer in
            Data(SHA256.hash(data: buffer))
        }
    }

    static var previewThoughtService: ThoughtService {
        ThoughtService(ArkavoService())
    }

    static var previewStreamService: StreamService {
        StreamService(ArkavoService())
    }

    static var previewViewModel: ThoughtStreamViewModel {
        let arkavo = ArkavoService()
        let service = ThoughtService(arkavo)
        let viewModel = ThoughtStreamViewModel(service: service, stream: previewStream)
        // Add some sample thoughts
        viewModel.thoughts = [
            ThoughtViewModel.createText(creatorProfile: Profile(id: creatorUUID, name: "Alice"), streamPublicIDString: creatorPublicID.base58EncodedString, text: "Hello, this is a test message!"),
            ThoughtViewModel.createText(creatorProfile: Profile(name: "Bob"), streamPublicIDString: "abc123", text: "Hi Alice, great to see you here!"),
            ThoughtViewModel.createText(creatorProfile: Profile(name: "Eve"), streamPublicIDString: "abc123", text: "Welcome everyone to this stream!"),
        ]
        return viewModel
    }

    static var previewStreamBadgeViewModel: StreamBadgeViewModel {
        StreamBadgeViewModel(
            stream: previewStream,
            topicTags: ["Swift", "iOS", "Programming"],
            membersProfile: [
                AccountProfileViewModel(profile: Profile(name: "Bob"), activityService: ActivityServiceModel()),
                AccountProfileViewModel(profile: Profile(name: "Eve"), activityService: ActivityServiceModel()),
            ],
            ownerProfile: AccountProfileViewModel(profile: Profile(id: creatorUUID, name: "Alice"), activityService: ActivityServiceModel()),
            activityLevel: .medium
        )
    }

    static var previewProfile: Profile {
        Profile(name: "Preview User")
    }

    static var previewStream: Stream {
        let profile = Profile(name: "Preview Stream")
        return Stream(creatorPublicID: creatorPublicID, profile: profile, admissionPolicy: .open, interactionPolicy: .open, agePolicy: .forAll)
    }

    static var previewContainer: ModelContainer {
        let schema = Schema([Account.self, Profile.self, Stream.self, Thought.self])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)

        do {
            let container = try ModelContainer(for: schema, configurations: [configuration])
            let context = container.mainContext

            // Create and save sample data
            let account = Account()
            try context.save()

            let profile = Profile(name: "Preview Stream")
            let stream = Stream(creatorPublicID: creatorPublicID, profile: profile, admissionPolicy: .open, interactionPolicy: .open, agePolicy: .forAll)
            account.streams.append(stream)
            try context.save()

            return container
        } catch {
            fatalError("Failed to create preview container: \(error.localizedDescription)")
        }
    }
}
