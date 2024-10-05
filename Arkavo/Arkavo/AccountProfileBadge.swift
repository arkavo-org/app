import SwiftUI

struct AccountProfileBadge: View {
    @StateObject var viewModel: AccountProfileViewModel
    @State private var isExpanded = false
    @State private var rotationAngle: Double = 0

    var body: some View {
        VStack {
            if isExpanded {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        viewModel.profileImage
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 30, height: 30)
                            .clipShape(Circle())

                        if viewModel.profile.hasHighIdentityAssurance {
                            Image(systemName: "checkmark.seal.fill")
                                .foregroundColor(.orange)
                        }
                    }
                    .onTapGesture {
                        withAnimation {
                            isExpanded.toggle()
                        }
                    }

                    Text(viewModel.profile.name)
                        .font(.headline)

                    HStack {
                        Text("Topic Tags:")
                            .font(.subheadline)
                            .bold()
                        ForEach(viewModel.topicTags, id: \.self) { tag in
                            Text(tag)
                                .font(.caption)
                                .padding(5)
                                .background(Color.blue.opacity(0.2))
                                .cornerRadius(5)
                        }
                    }

                    Text("Location: \(viewModel.profile.location)")
                    if let activityService = viewModel.activityServiceModel {
                        Text("Expert Level: \(activityService.expertLevel)")
                        Text("Activity Level: \(activityService.activityLevel)")
                        Text("Trust Level: \(activityService.trustLevel)")
                        Text("Member since: \(activityService.dateCreated, formatter: DateFormatter.shortDateTime)")
                    }

                    if viewModel.profile.hasHighEncryption {
                        Image(systemName: "lock.shield")
                            .foregroundColor(.green)
                            .font(.title)
                            .rotationEffect(.degrees(rotationAngle))
                            .onAppear {
                                withAnimation(.linear(duration: 2).repeatForever(autoreverses: false)) {
                                    rotationAngle = 360
                                }
                            }
                    }
                }
                .padding()
                .background(Color.gray.opacity(0.1))
                .cornerRadius(10)
                .shadow(radius: 5)
            } else {
                HStack {
                    viewModel.profileImage
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 30, height: 30)
                        .clipShape(Circle())

                    Text(viewModel.profile.name)
                        .font(.caption)
                        .foregroundColor(.primary)

                    if viewModel.profile.hasHighIdentityAssurance {
                        Image(systemName: "checkmark.seal.fill")
                            .foregroundColor(.orange)
                            .font(.caption)
                    }
                }
                .onTapGesture {
                    withAnimation {
                        isExpanded.toggle()
                    }
                }
            }
        }
    }
}

struct AccountProfileBadge_Previews: PreviewProvider {
    static var previews: some View {
        let activityServiceModel = ActivityServiceModel(
            dateCreated: Date(),
            expertLevel: "Advanced",
            activityLevel: .high,
            trustLevel: "Very High"
        )
        let sampleProfile = Profile(
            name: "John Doe",
            interests: "Swift,iOS,SwiftUI",
            location: "New York, NY",
            hasHighEncryption: true,
            hasHighIdentityAssurance: true
        )
        let viewModel = AccountProfileViewModel(profile: sampleProfile, activityService: activityServiceModel)

        AccountProfileBadge(viewModel: viewModel)
            .previewLayout(.sizeThatFits)
            .padding()
    }
}
