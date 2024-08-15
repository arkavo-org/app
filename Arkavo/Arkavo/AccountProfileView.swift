import SwiftData
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
    @Environment(\.modelContext) var modelContext
    var onSave: (Profile) -> Void

    var body: some View {
        Form {
            Section(header: Text("Profile Information")) {
                TextField("Name", text: $viewModel.name)
                if let nameError = viewModel.nameError {
                    Text(nameError).foregroundColor(.red)
                }

                TextField("Blurb", text: $viewModel.blurb)
                if let blurbError = viewModel.blurbError {
                    Text(blurbError).foregroundColor(.red)
                }
            }

            Button("Create Profile") {
                let profile = Profile(name: viewModel.name, blurb: viewModel.blurb.isEmpty ? nil : viewModel.blurb)
                modelContext.insert(profile)
                onSave(profile)
                dismiss()
            }
            .disabled(!viewModel.isValid)
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

    var nameError: String? {
        if name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "Name cannot be empty"
        } else if name.count > 50 {
            return "Name must be 50 characters or less"
        }
        return nil
    }

    var blurbError: String? {
        if blurb.count > 200 {
            return "Blurb must be 200 characters or less"
        }
        return nil
    }

    var isValid: Bool {
        nameError == nil && blurbError == nil && !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func createProfile() -> Profile? {
        guard isValid else { return nil }
        return Profile(name: name, blurb: blurb.isEmpty ? nil : blurb)
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
