import SwiftData
import SwiftUI

class StreamViewModel: ObservableObject {
    @Published var stream: Stream?

    init(stream: Stream) {
        self.stream = stream
    }
}

struct CompactStreamProfileView: View {
    @StateObject var viewModel: StreamViewModel

    var body: some View {
        HStack {
            Text(viewModel.stream!.profile.name)
                .font(.headline)
            Spacer()
        }
        .padding(.vertical, 8)
    }
}

struct DetailedStreamProfileView: View {
    @StateObject var viewModel: StreamViewModel
    @State var isShareSheetPresented: Bool = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack {
                Form {
                    Section(header: Text("Profile")) {
                        Text("\(viewModel.stream!.profile.name)")
                        if let blurb = viewModel.stream!.profile.blurb {
                            Text("\(blurb)")
                        }
                    }
                    Section(header: Text("Policies")) {
                        Text("Admission: \(viewModel.stream!.admissionPolicy.rawValue)")
                        Text("Interaction: \(viewModel.stream!.interactionPolicy.rawValue)")
                        Text("Age Policy: \(viewModel.stream!.agePolicy.rawValue)")
                    }
                    Section(header: Text("Public ID")) {
                        Text(viewModel.stream!.publicID.base58EncodedString)
                            .font(.system(.footnote, design: .monospaced))
                            .textSelection(.enabled)
                    }
                }
            }
            .navigationTitle("Stream")
            #if !os(macOS)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button(action: {
                            dismiss()
                        }) {
                            Image(systemName: "x.circle")
                        }
                    }
                    if viewModel.stream!.admissionPolicy != .closed {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button(action: {
                                isShareSheetPresented = true
                            }) {
                                HStack {
                                    Text("Invite Friends")
                                    Image(systemName: "square.and.arrow.up")
                                }
                            }
                        }
                    }
                }
                .sheet(isPresented: $isShareSheetPresented) {
                    ShareSheet(activityItems: [URL(string: "https://app.arkavo.com/stream/\(viewModel.stream!.publicID.base58EncodedString)")!],
                               isPresented: $isShareSheetPresented)
                }
            #endif
        }
    }
}

#if os(iOS) || os(visionOS)
    struct ShareSheet: UIViewControllerRepresentable {
        let activityItems: [Any]
        @Binding var isPresented: Bool

        func makeUIViewController(context _: Context) -> UIActivityViewController {
            let controller = UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
            return controller
        }

        func updateUIViewController(_: UIActivityViewController, context _: Context) {}
    }

#elseif os(macOS)
    struct ShareSheet: View {
        let activityItems: [Any]
        @Binding var isPresented: Bool

        var body: some View {
            VStack {
                ForEach(activityItems.indices, id: \.self) { index in
                    let item = activityItems[index]
                    if let url = item as? URL {
                        ShareLink(item: url) {
                            Label("Share URL", systemImage: "link")
                        }
                    } else if let string = item as? String {
                        ShareLink(item: string) {
                            Label("Share Text", systemImage: "text.quote")
                        }
                    }
                }
                Button("Done") {
                    isPresented = false
                }
            }
            .padding()
        }
    }
#endif

struct CreateStreamProfileView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel = CreateStreamViewModel()
    var onSave: (Profile, AdmissionPolicy, InteractionPolicy, AgePolicy) -> Void

    var body: some View {
        VStack {
            HStack {
                Text("Create Stream")
                    .font(.title)
                    .padding(.leading, 16)
                Spacer()
                Button("Cancel") {
                    dismiss()
                }
                .padding(.trailing, 16)
            }
            Form {
                Section {
                    Text("A stream lets you start conversations about any topic. You can choose who joins and interacts with your stream.")
                        .font(.footnote)
                }
                Section {
                    TextField("What We are Discussing", text: $viewModel.name)
                    if !viewModel.nameError.isEmpty {
                        Text(viewModel.nameError).foregroundColor(.red)
                    }
                    TextField("Topic of Interest", text: $viewModel.blurb)
                    if !viewModel.blurbError.isEmpty {
                        Text(viewModel.blurbError).foregroundColor(.red)
                    }
                }
                Section(header: Text("Policies")) {
                    Picker("Admission", selection: $viewModel.admissionPolicy) {
                        ForEach(AdmissionPolicy.allCases, id: \.self) { policy in
                            Text(policy.rawValue).tag(policy)
                        }
                    }
                    Picker("Interaction", selection: $viewModel.interactionPolicy) {
                        ForEach(InteractionPolicy.allCases, id: \.self) { policy in
                            Text(policy.rawValue).tag(policy)
                        }
                    }
                    Picker("Age", selection: $viewModel.agePolicy) {
                        ForEach(AgePolicy.allCases, id: \.self) { policy in
                            Text(policy.rawValue).tag(policy)
                        }
                    }
                }
            }
            Button(action: {
                let profile = Profile(name: viewModel.name, blurb: viewModel.blurb)
                onSave(profile, viewModel.admissionPolicy, viewModel.interactionPolicy, viewModel.agePolicy)
                dismiss()
            }) {
                Text("Save")
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(viewModel.isValid ? Color.blue : Color.gray)
                    .foregroundColor(.white)
                    .cornerRadius(10)
            }
            .padding()
            .disabled(!viewModel.isValid)
        }
        .onChange(of: viewModel.name) { viewModel.validateName() }
        .onChange(of: viewModel.blurb) { viewModel.validateBlurb() }
    }
}

class CreateStreamViewModel: ObservableObject {
    @Published var name: String = ""
    @Published var blurb: String = ""
    @Published var participantCount: Int = 2
    @Published var admissionPolicy: AdmissionPolicy = .open
    @Published var interactionPolicy: InteractionPolicy = .open
    @Published var agePolicy: AgePolicy = .forAll
    @Published var nameError: String = ""
    @Published var blurbError: String = ""
    @Published var isValid: Bool = false

    func validateName() {
        if name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            nameError = "Name cannot be empty"
        } else if name.count > 50 {
            nameError = "Name must be 50 characters or less"
        } else {
            nameError = ""
        }
        updateValidity()
    }

    func validateBlurb() {
        if blurb.count > 200 {
            blurbError = "Blurb must be 200 characters or less"
        } else {
            blurbError = ""
        }
        updateValidity()
    }

    private func updateValidity() {
        isValid = nameError.isEmpty && blurbError.isEmpty && !name.isEmpty
    }

    func createStreamProfile() -> (Profile, Int, AdmissionPolicy, InteractionPolicy)? {
        if isValid {
            let profile = Profile(name: name, blurb: blurb.isEmpty ? nil : blurb)
            return (profile, participantCount, admissionPolicy, interactionPolicy)
        }
        return nil
    }
}

extension StreamProfileView_Previews {
    static var previewStream: Stream {
        let profile = Profile(name: "Example Stream", blurb: "This is a sample stream for preview purposes.")
        return Stream(creatorPublicID: Data(), profile: profile, admissionPolicy: .closed, interactionPolicy: .closed, agePolicy: .forAll)
    }
}

struct StreamProfileView_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            CompactStreamProfileView(viewModel: StreamViewModel(stream: previewStream))
                .previewLayout(.sizeThatFits)
                .previewDisplayName("Compact Stream Profile")

            DetailedStreamProfileView(viewModel: StreamViewModel(stream: previewStream))
                .previewDisplayName("Detailed Stream Profile")

            CreateStreamProfileView { _, _, _, _ in
                // This closure is just for preview, so we'll leave it empty
            }
            .previewDisplayName("Create Stream Profile")
        }
        .modelContainer(previewContainer)
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

            let profile = Profile(name: "Example Stream", blurb: "This is a sample stream for preview purposes.")
            let stream = Stream(creatorPublicID: Data(), profile: profile, admissionPolicy: .open, interactionPolicy: .open, agePolicy: .forAll)
            account.streams.append(stream)
            try context.save()

            return container
        } catch {
            fatalError("Failed to create preview container: \(error.localizedDescription)")
        }
    }
}
