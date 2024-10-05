import SwiftUI

struct StreamProfileBadge: View {
    @State private var isAnimating = false
    var streamName: String
    var image: Image = .init(systemName: "person.3.fill")
    var isHighlighted: Bool = false
    var description: String = ""
    var topicTags: [String] = []
    var membersProfile: [AccountProfileViewModel] = []
    var ownerProfile: AccountProfileViewModel
    var activityLevel: ActivityLevel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                image
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 50, height: 50)
                    .padding(10)
                    .background(isHighlighted ? Color.blue.opacity(0.2) : Color.gray.opacity(0.2))
                    .clipShape(Circle())
                    .overlay(
                        Circle()
                            .stroke(isHighlighted ? Color.blue : Color.gray, lineWidth: 2)
                    )
                VStack(alignment: .leading) {
                    Text(streamName)
                        .font(.headline)
                        .foregroundColor(.primary)
                    Text(description)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            }

            HStack {
                Text("Topic Tags:")
                    .font(.subheadline)
                    .bold()
                ForEach(topicTags, id: \.self) { tag in
                    Text(tag)
                        .font(.caption)
                        .padding(5)
                        .background(Color.blue.opacity(0.2))
                        .cornerRadius(5)
                }
            }

            HStack {
                Text("Owner:")
                    .font(.subheadline)
                    .bold()
                AccountProfileBadge(viewModel: ownerProfile)
            }

            HStack {
                Text("Members:")
                    .font(.subheadline)
                    .bold()
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack {
                        ForEach(membersProfile, id: \.profile.id) { member in
                            AccountProfileBadge(viewModel: member)
                        }
                    }
                }
            }

            HStack {
                activityIcon
            }
        }
        .padding()
        .background(Color.gray.opacity(0.1))
        .cornerRadius(10)
        .shadow(radius: 5)
        .onAppear {
            if activityLevel == .high {
                withAnimation(Animation.easeInOut(duration: 0.5).repeatForever(autoreverses: true)) {
                    isAnimating = true
                }
            }
        }
    }

    private var activityIcon: some View {
        Image(systemName: "waveform.path.ecg")
            .foregroundColor(activityLevel.color)
            .scaleEffect(isAnimating && activityLevel == .high ? 1.2 : 1.0)
    }
}

struct StreamProfileBadge_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            StreamProfileBadge(
                streamName: "Arkavo Friends",
                isHighlighted: true,
                description: "A group for all Arkavo friends to stay connected.",
                topicTags: ["Friends", "Community", "Fun"],
                membersProfile: [
                    AccountProfileViewModel(profile: Profile(name: "Alice"), activityService: ActivityServiceModel()),
                    AccountProfileViewModel(profile: Profile(name: "Bob"), activityService: ActivityServiceModel()),
                    AccountProfileViewModel(profile: Profile(name: "Charlie"), activityService: ActivityServiceModel()),
                ],
                ownerProfile: AccountProfileViewModel(profile: Profile(name: "Owner"), activityService: ActivityServiceModel()),
                activityLevel: .high
            )
            .previewLayout(.sizeThatFits)
            .padding()

            StreamProfileBadge(
                streamName: "Arkavo Family",
                description: "Stay in touch with family members through Arkavo.",
                topicTags: ["Family", "Support"],
                membersProfile: [
                    AccountProfileViewModel(profile: Profile(name: "Dave"), activityService: ActivityServiceModel()),
                    AccountProfileViewModel(profile: Profile(name: "Eve"), activityService: ActivityServiceModel()),
                ],
                ownerProfile: AccountProfileViewModel(profile: Profile(name: "Family Owner"), activityService: ActivityServiceModel()),
                activityLevel: .medium
            )
            .previewLayout(.sizeThatFits)
            .padding()

            StreamProfileBadge(
                streamName: "Invitation to Group Chat",
                description: "Join the Arkavo Stream to share thoughts and ideas.",
                topicTags: ["Ideas", "Collaboration"],
                membersProfile: [
                    AccountProfileViewModel(profile: Profile(name: "Frank"), activityService: ActivityServiceModel()),
                    AccountProfileViewModel(profile: Profile(name: "Grace"), activityService: ActivityServiceModel()),
                    AccountProfileViewModel(profile: Profile(name: "Heidi"), activityService: ActivityServiceModel()),
                    AccountProfileViewModel(profile: Profile(name: "Ivan"), activityService: ActivityServiceModel()),
                ],
                ownerProfile: AccountProfileViewModel(profile: Profile(name: "Grace"), activityService: ActivityServiceModel()),
                activityLevel: .low
            )
            .previewLayout(.sizeThatFits)
            .padding()

            StreamProfileBadge(
                streamName: "Stream on Map",
                isHighlighted: true,
                ownerProfile: AccountProfileViewModel(profile: Profile(name: "Map Owner"), activityService: ActivityServiceModel()), activityLevel: .high
            )
            .previewLayout(.sizeThatFits)
            .padding()

            StreamProfileBadge(
                streamName: "Invitation to Group Chat",
                ownerProfile: AccountProfileViewModel(profile: Profile(name: "Chat Owner"), activityService: ActivityServiceModel()), activityLevel: .high
            )
            .previewLayout(.sizeThatFits)
            .padding()
        }
    }
}
