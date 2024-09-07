import SwiftData
import SwiftUI

struct AccountProfileDetailedView: View {
    @ObservedObject var viewModel: AccountProfileViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Spacer()

        HStack {
            Spacer()

            Text("View Profile")
                .font(.title3)

            Spacer()

            Button(action: {
                dismiss()
            }, label: {
                Image(systemName: "xmark.circle")
                    .font(.system(size: 20, weight: .light))
            })
        } //: HSTACK

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
        } //: FORM
        .navigationTitle("Account Profile")
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

struct AccountProfileCreateView: View {
    @StateObject var viewModel = AccountProfileCreateViewModel()
    @Environment(\.dismiss) private var dismiss
    var onSave: (Profile) -> Void
    @Binding var selectedView: ArkavoView.SelectedView

    @State private var interests: [Interest] = [
        Interest(name: "Sports", isSelected: false),
        Interest(name: "Music", isSelected: false),
        Interest(name: "Food", isSelected: false),
        Interest(name: "Politics", isSelected: false),
        Interest(name: "Gaming", isSelected: false),
    ]

    @State private var areSelected: [Bool] = [false, false, false, false, false]

    var currentInterest: String {
        var curInterest: [String] = []

        for interest in interests {
            if interest.isSelected {
                curInterest.append(interest.name)
            }
        }

        return curInterest.joined(separator: ",")
    }

    var body: some View {
        Spacer()

        HStack {
            Spacer()

            Text("Create Profile")
                .font(.title3)

            Spacer()

            Button(action: {
                dismiss()
            }, label: {
                Image(systemName: "xmark.circle")
                    .font(.system(size: 20, weight: .light))
            })
            .padding(.trailing, 10)
        }

        Form {
            Section(header: Text("Profile Information")) {
                TextField("Name", text: $viewModel.name)

//                if let nameError = viewModel.nameError {
//                    Text(nameError).foregroundColor(.red)
//                }

                TextField("Blurb", text: $viewModel.blurb)
                if let blurbError = viewModel.blurbError {
                    Text(blurbError).foregroundColor(.red)
                }
            }
            Section(header: Text("Interests")) {
                List {
                    ForEach(interests.indices, id: \.self) { i in
                        HStack {
                            Text(interests[i].name)

                            Spacer()

                            Button(action: {
                                areSelected[i].toggle()
                                interests[i].isSelected = areSelected[i]

                            }, label: {
                                Image(systemName: areSelected[i] ? "circle.fill" : "circle")
                                    .font(.system(size: 20, weight: .light))
                            })
                        }
                    }
                }
            }
            Button(action: {
                let profile = Profile(name: viewModel.name, blurb: viewModel.blurb.isEmpty ? nil : viewModel.blurb, interests: currentInterest)
                onSave(profile)
                dismiss()
            }) {
                Text("Register")
                    .fontWeight(.semibold)
                    .foregroundColor(.white)
                    .frame(minWidth: 200)
                    .padding()
                    .background(Color.blue)
                    .cornerRadius(10)
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
