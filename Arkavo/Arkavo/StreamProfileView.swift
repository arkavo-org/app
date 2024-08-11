import SwiftUI

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

struct CreateStreamProfileView: View {
    @StateObject var viewModel = CreateStreamProfileViewModel()
    @Environment(\.dismiss) private var dismiss
    var onSave: (Profile, Int) -> Void

    var body: some View {
        Form {
            Section(header: Text("Profile Information")) {
                TextField("Name", text: $viewModel.name)
                    .onChange(of: viewModel.name) { _, _ in
                        viewModel.validateName()
                    }
                if let nameError = viewModel.nameError {
                    Text(nameError).foregroundColor(.red)
                }

                TextField("Blurb", text: $viewModel.blurb)
                    .onChange(of: viewModel.blurb) { _, _ in
                        viewModel.validateBlurb()
                    }
                if let blurbError = viewModel.blurbError {
                    Text(blurbError).foregroundColor(.red)
                }
            }

            Section(header: Text("Stream Information")) {
                Stepper("Participants: \(viewModel.participantCount)", value: $viewModel.participantCount, in: 2 ... 100)
                    .onChange(of: viewModel.participantCount) { _, _ in
                        viewModel.validateParticipantCount()
                    }
                if let participantCountError = viewModel.participantCountError {
                    Text(participantCountError).foregroundColor(.red)
                }
            }

            Button("Create Stream Profile") {
                if let (profile, participantCount) = viewModel.createStreamProfile() {
                    onSave(profile, participantCount)
                    dismiss()
                }
            }
            .disabled(!viewModel.isValid())
        }
        .navigationTitle("Create Stream Profile")
    }
}

class StreamProfileViewModel: ObservableObject {
    @Published var profile: Profile
    @Published var participantCount: Int

    init(profile: Profile, participantCount: Int) {
        self.participantCount = participantCount
        self.profile = profile
    }
}

class CreateProfileViewModel: ObservableObject {
    @Published var name: String = ""
    @Published var blurb: String = ""
    @Published var nameError: String?
    @Published var blurbError: String?

    func validateName() {
        if name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            nameError = "Name cannot be empty"
        } else if name.count > 50 {
            nameError = "Name must be 50 characters or less"
        } else {
            nameError = nil
        }
    }

    func validateBlurb() {
        if blurb.count > 200 {
            blurbError = "Blurb must be 200 characters or less"
        } else {
            blurbError = nil
        }
    }

    func isValid() -> Bool {
        validateName()
        validateBlurb()
        return nameError == nil && blurbError == nil
    }

    func createProfile() -> Profile? {
        if isValid() {
            return Profile(name: name, blurb: blurb.isEmpty ? nil : blurb)
        }
        return nil
    }
}

class CreateStreamProfileViewModel: CreateProfileViewModel {
    @Published var participantCount: Int = 2
    @Published var participantCountError: String?

    func validateParticipantCount() {
        if participantCount < 2 {
            participantCountError = "A Stream must have at least 2 participants"
        } else if participantCount > 100 {
            participantCountError = "A Stream can have at most 100 participants"
        } else {
            participantCountError = nil
        }
    }

    override func isValid() -> Bool {
        validateParticipantCount()
        return super.isValid() && participantCountError == nil
    }

    func createStreamProfile() -> (Profile, Int)? {
        if isValid() {
            let profile = Profile(name: name, blurb: blurb.isEmpty ? nil : blurb)
            return (profile, participantCount)
        }
        return nil
    }
}
