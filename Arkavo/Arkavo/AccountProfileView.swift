import Combine
import SwiftData
import SwiftUI

struct AccountProfileDetailedView: View {
    @ObservedObject var viewModel: AccountProfileViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section(header: Text("Profile Information")) {
                    Text("Name: \(viewModel.profile.name)")
                    if let blurb = viewModel.profile.blurb {
                        Text("Blurb: \(blurb)")
                    }
                }
//                Section(header: Text("Profile Details")) {
//                    Text("ID: \(viewModel.profile.id.uuidString)")
//                    Text("Created: \(viewModel.profile.dateCreated, formatter: DateFormatter.shortDateTime)")
//                }
                NavigationLink(destination: AccountView()) {
                    Text("My Account")
                }
                NavigationLink(destination: RegistrationInterestsView()) {
                    Text("Refine Interests")
                }
            }
            .navigationTitle("Account Profile")
            .toolbar {
                #if os(iOS)
                    ToolbarItem(placement: .navigationBarTrailing) {
                        dismissButton
                    }
                #else
                    ToolbarItem(placement: .automatic) {
                        dismissButton
                    }
                #endif
            }
        }
        #if os(macOS)
        .frame(minWidth: 300, minHeight: 400)
        #endif
    }

    private var dismissButton: some View {
        Button(action: {
            dismiss()
        }) {
            Image(systemName: "xmark.circle")
                .font(.system(size: 20, weight: .light))
        }
    }
}

class Interest {
    var name: String
    var isSelected: Bool

    init(name: String, isSelected: Bool) {
        self.name = name
        self.isSelected = isSelected
    }
}

class AccountProfileViewModel: ObservableObject {
    @Published var profile: Profile
    @Published var profileImage = Image(systemName: "person.fill")
    @Published var activityServiceModel: ActivityServiceModel?

    init(profile: Profile, activityService: ActivityServiceModel = ActivityServiceModel()) {
        self.profile = profile
        activityServiceModel = activityService
    }

    var topicTags: [String] {
        profile.interests.components(separatedBy: ",")
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

struct AccountProfileDetailedView_Previews: PreviewProvider {
    static var previews: some View {
        let sampleProfile = Profile(name: "John Doe", blurb: "A sample user", interests: "Sports,Music")
        let viewModel = AccountProfileViewModel(profile: sampleProfile, activityService: ActivityServiceModel())

        Group {
            AccountProfileDetailedView(viewModel: viewModel)
                .previewDisplayName("Detailed")
                .previewDevice("iPhone 13")
        }
    }
}
