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
        Form {
            Section(header: Text("Profile Information")) {
                Text("Name: \(viewModel.profile.name)")
                if let blurb = viewModel.profile.blurb {
                    Text("Blurb: \(blurb)")
                }
            }

            Section(header: Text("Stream Information")) {
                Text("Participants: \(viewModel.participantCount)")
            }

            Section(header: Text("Profile Details")) {
                Text("ID: \(viewModel.profile.id.uuidString)")
                Text("Created: \(viewModel.profile.dateCreated, formatter: DateFormatter.shortDateTime)")
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
        self.participantCount = participantCount
        self.profile = profile
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
                        .padding(.leading, 20)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    
                    if !viewModel.nameError.isEmpty {
                        Text(viewModel.nameError).foregroundColor(.red)
                    }

                    TextField("Blurb", text: $viewModel.blurb)
                        .padding(.leading, 20)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    
                    if !viewModel.blurbError.isEmpty {
                        Text(viewModel.blurbError).foregroundColor(.red)
                    }
                }
                .padding()

                Section(header: Text("Stream Information")) {
                    HStack {
                        Stepper("Participants: \(viewModel.participantCount)", value: $viewModel.participantCount, in: 2 ... 100)
                            .padding(.leading, 20)
                            .frame(maxWidth: .infinity, alignment: .leading) 
                        
                        if !viewModel.participantCountError.isEmpty {
                            Text(viewModel.participantCountError).foregroundColor(.red)
                        }
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
        .onChange(of: viewModel.name) { viewModel.validateName() }
        .onChange(of: viewModel.blurb) { viewModel.validateBlurb() }
        .onChange(of: viewModel.participantCount) { viewModel.validateParticipantCount() }
    }
}


// MARK: - CreateStreamProfileViewModel

class CreateStreamProfileViewModel: ObservableObject {
    @Published var name: String = ""
    @Published var blurb: String = ""
    @Published var participantCount: Int = 2
    @Published var nameError: String = ""
    @Published var blurbError: String = ""
    @Published var participantCountError: String = ""
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

    func validateParticipantCount() {
        if participantCount < 2 {
            participantCountError = "A Stream must have at least 2 participants"
        } else if participantCount > 100 {
            participantCountError = "A Stream can have at most 100 participants"
        } else {
            participantCountError = ""
        }
        updateValidity()
    }

    private func updateValidity() {
        isValid = nameError.isEmpty && blurbError.isEmpty && participantCountError.isEmpty && !name.isEmpty
    }

    func createStreamProfile() -> (Profile, Int)? {
        if isValid {
            let profile = Profile(name: name, blurb: blurb.isEmpty ? nil : blurb)
            return (profile, participantCount)
        }
        return nil
    }
}
