import SwiftUI

// MARK: - CompactStreamProfileView

struct CompactStreamProfileView: View {
    @ObservedObject var viewModel: StreamProfileViewModel

    var body: some View {
        HStack {
            Text(viewModel.profile.name)
                .font(.headline)
            Spacer()
            Text("Participants: \(viewModel.participantCount)")
                .font(.subheadline)
        }
        .padding(.vertical, 8)
    }
}

// MARK: - DetailedStreamProfileView

struct DetailedStreamProfileView: View {
    @ObservedObject var viewModel: StreamProfileViewModel

    var body: some View {
        List {
            Section(header: Text("Profile Information")) {
                LabeledContent("Name", value: viewModel.profile.name)
                if let blurb = viewModel.profile.blurb {
                    LabeledContent("Blurb", value: blurb)
                }
            }

            Section(header: Text("Stream Information")) {
                LabeledContent("Participants", value: "\(viewModel.participantCount)")
            }

            Section(header: Text("Profile Details")) {
                LabeledContent("ID", value: viewModel.profile.id.uuidString)
                LabeledContent("Created", value: viewModel.profile.dateCreated.formatted(.dateTime))
            }
        }
        .navigationTitle("Stream Profile")
    }
}

// MARK: - StreamProfileViewModel

class StreamProfileViewModel: ObservableObject {
    @Published var profile: Profile
    @Published var participantCount: Int

    init(profile: Profile, participantCount: Int) {
        self.profile = profile
        self.participantCount = participantCount
    }
}

// MARK: - CreateStreamProfileView

struct CreateStreamProfileView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel = CreateStreamProfileViewModel()
    var onSave: (Profile, Int) -> Void

    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Profile Information")) {
                    TextField("Name", text: $viewModel.name)
                        .autocapitalization(.words)
                    if !viewModel.nameError.isEmpty {
                        Text(viewModel.nameError).foregroundColor(.red)
                    }
                    
                    TextField("Blurb", text: $viewModel.blurb)
                    if !viewModel.blurbError.isEmpty {
                        Text(viewModel.blurbError).foregroundColor(.red)
                    }
                }
                
                Section(header: Text("Stream Information")) {
                    Stepper("Participants: \(viewModel.participantCount)", value: $viewModel.participantCount, in: 2...100)
                    if !viewModel.participantCountError.isEmpty {
                        Text(viewModel.participantCountError).foregroundColor(.red)
                    }
                }
            }
            .navigationTitle("Create Stream")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") {
                        if let (profile, participantCount) = viewModel.createStreamProfile() {
                            onSave(profile, participantCount)
                            dismiss()
                        }
                    }
                    .disabled(!viewModel.isValid)
                }
            }
        }
        .onChange(of: viewModel.name) { oldValue, newValue in
            viewModel.validateName()
        }
        .onChange(of: viewModel.blurb) { oldValue, newValue in
            viewModel.validateBlurb()
        }
        .onChange(of: viewModel.participantCount) { oldValue, newValue in
            viewModel.validateParticipantCount()
        }
    }
}

// MARK: - CreateStreamProfileViewModel

class CreateStreamProfileViewModel: ObservableObject {
    @Published var name = ""
    @Published var blurb = ""
    @Published var participantCount = 2
    @Published var nameError = ""
    @Published var blurbError = ""
    @Published var participantCountError = ""
    @Published var isValid = false

    private let maxNameLength = 50
    private let maxBlurbLength = 200
    private let minParticipants = 2
    private let maxParticipants = 100

    func validateName() {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedName.isEmpty {
            nameError = "Name cannot be empty"
        } else if trimmedName.count > maxNameLength {
            nameError = "Name must be \(maxNameLength) characters or less"
        } else {
            nameError = ""
        }
        updateValidity()
    }

    func validateBlurb() {
        if blurb.count > maxBlurbLength {
            blurbError = "Blurb must be \(maxBlurbLength) characters or less"
        } else {
            blurb = ""
        }
        updateValidity()
    }

    func validateParticipantCount() {
        if participantCount < minParticipants {
            participantCountError = "A Stream must have at least \(minParticipants) participants"
        } else if participantCount > maxParticipants {
            participantCountError = "A Stream can have at most \(maxParticipants) participants"
        } else {
            participantCountError = ""
        }
        updateValidity()
    }

    private func updateValidity() {
        isValid = nameError.isEmpty && blurbError.isEmpty && participantCountError.isEmpty && !name.isEmpty
    }

    func createStreamProfile() -> (Profile, Int)? {
        guard isValid else { return nil }
        let profile = Profile(name: name.trimmingCharacters(in: .whitespacesAndNewlines),
                              blurb: blurb.isEmpty ? nil : blurb)
        return (profile, participantCount)
    }
}
