import SwiftUI

struct AccountProfileCompactView: View {
    @ObservedObject var viewModel: AccountProfileViewModel

    var body: some View {
        HStack {
            Text(viewModel.profile.name)
                .font(.headline)
            Spacer()
            Text(viewModel.profile.blurb ?? "")
                .font(.subheadline)
                .lineLimit(1)
        }
        .padding(.vertical, 8)
    }
}

struct AccountProfileDetailedView: View {
    @ObservedObject var viewModel: AccountProfileViewModel

    var body: some View {
        Form {
            Section(header: Text("Profile Information")) {
                Text("Name: \(viewModel.profile.name)")
                if let blurb = viewModel.profile.blurb {
                    Text("Blurb: \(blurb)")
                }
            }

            Section(header: Text("Profile Details")) {
                Text("ID: \(viewModel.profile.id.uuidString)")
                Text("Created: \(viewModel.profile.dateCreated, formatter: DateFormatter.shortDateTime)")
            }
        }
        .navigationTitle("Account Profile")
    }
}

struct AccountProfileCreateView: View {
    @StateObject var viewModel = AccountProfileCreateViewModel()
    @Environment(\.dismiss) private var dismiss
    var onSave: (Profile) -> Void

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

            Button("Create Profile") {
                if let profile = viewModel.createProfile() {
                    onSave(profile)
                    dismiss()
                }
            }
            .disabled(!viewModel.isValid())
        }
        .navigationTitle("Create Account Profile")
    }
}

class AccountProfileViewModel: ObservableObject {
    @Published var profile: Profile

    init(profile: Profile) {
        self.profile = profile
    }
}

class AccountProfileCreateViewModel: ObservableObject {
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

extension DateFormatter {
    static let shortDateTime: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter
    }()
}
