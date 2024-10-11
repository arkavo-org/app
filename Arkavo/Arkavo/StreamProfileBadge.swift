import SwiftUI

class StreamBadgeViewModel: StreamViewModel {
    @Published var isHighlighted: Bool
    @Published var isExpanded: Bool
    @Published var topicTags: [String]
    @Published var membersProfile: [AccountProfileViewModel]
    @Published var ownerProfile: AccountProfileViewModel
    @Published var activityLevel: ActivityLevel

    init(stream: Stream, isHighlighted: Bool = false, isExpanded: Bool = false, topicTags: [String] = [], membersProfile: [AccountProfileViewModel] = [], ownerProfile: AccountProfileViewModel, activityLevel: ActivityLevel = .medium) {
        self.isHighlighted = isHighlighted
        self.isExpanded = isExpanded
        self.topicTags = topicTags
        self.membersProfile = membersProfile
        self.ownerProfile = ownerProfile
        self.activityLevel = activityLevel
        super.init(stream: stream)
    }
}

struct StreamProfileBadge: View {
    @StateObject var viewModel: StreamBadgeViewModel
    @State private var isAnimating = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: "person.3.fill")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: viewModel.isExpanded ? 50 : 30, height: viewModel.isExpanded ? 50 : 30)
                    .padding(viewModel.isExpanded ? 10 : 5)
                    .background(viewModel.isHighlighted ? Color.blue.opacity(0.2) : Color.gray.opacity(0.2))
                    .clipShape(Circle())
                    .overlay(
                        Circle()
                            .stroke(viewModel.isHighlighted ? Color.blue : Color.gray, lineWidth: 2)
                    )
                VStack(alignment: .leading) {
                    Text(viewModel.stream?.profile.name ?? "")
                        .font(viewModel.isExpanded ? .headline : .subheadline)
                        .foregroundColor(.primary)
                    if viewModel.isExpanded, let blurb = viewModel.stream?.profile.blurb {
                        Text(blurb)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                }
                Spacer()
                activityIcon
            }

            if viewModel.isExpanded {
                VStack(alignment: .leading, spacing: 10) {
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

                    HStack {
                        Text("Owner:")
                            .font(.subheadline)
                            .bold()
                        AccountProfileBadge(viewModel: viewModel.ownerProfile)
                    }

                    HStack {
                        Text("Members:")
                            .font(.subheadline)
                            .bold()
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack {
                                ForEach(viewModel.membersProfile, id: \.profile.id) { member in
                                    AccountProfileBadge(viewModel: member)
                                }
                            }
                        }
                    }

                    HStack {
                        Text("Admission Policy:")
                            .font(.subheadline)
                            .bold()
                        Text(viewModel.stream?.admissionPolicy.rawValue ?? "")
                            .font(.caption)
                            .padding(5)
                            .background(Color.blue.opacity(0.2))
                            .cornerRadius(5)
                    }

                    HStack {
                        Text("Interaction Policy:")
                            .font(.subheadline)
                            .bold()
                        Text(viewModel.stream?.interactionPolicy.rawValue ?? "")
                            .font(.caption)
                            .padding(5)
                            .background(Color.blue.opacity(0.2))
                            .cornerRadius(5)
                    }
                }
            }
        }
        .padding()
        .background(Color.gray.opacity(0.1))
        .cornerRadius(10)
        .shadow(radius: 5)
        .onTapGesture {
            withAnimation(.spring()) {
                viewModel.isExpanded.toggle()
            }
        }
        .onAppear {
            if viewModel.activityLevel == .high {
                withAnimation(Animation.easeInOut(duration: 0.5).repeatForever(autoreverses: true)) {
                    isAnimating = true
                }
            }
        }
    }

    private var activityIcon: some View {
        Image(systemName: "waveform.path.ecg")
            .foregroundColor(viewModel.activityLevel.color)
            .scaleEffect(isAnimating && viewModel.activityLevel == .high ? 1.2 : 1.0)
    }
}

struct StreamProfileBadge_Previews: PreviewProvider {
    static var previews: some View {
        let previewStream = Stream(creatorPublicID: Data(), profile: Profile(name: "Preview Stream", blurb: "This is a preview stream"), admissionPolicy: .open, interactionPolicy: .open)
        let ownerProfile = AccountProfileViewModel(profile: Profile(name: "Owner"), activityService: ActivityServiceModel())
        let membersProfile = [
            AccountProfileViewModel(profile: Profile(name: "Member 1"), activityService: ActivityServiceModel()),
            AccountProfileViewModel(profile: Profile(name: "Member 2"), activityService: ActivityServiceModel()),
        ]
        Group {
            StreamProfileBadge(viewModel: StreamBadgeViewModel(
                stream: previewStream,
                isHighlighted: true,
                topicTags: ["Swift", "SwiftUI", "iOS"],
                membersProfile: membersProfile,
                ownerProfile: ownerProfile,
                activityLevel: .high
            ))
            .previewLayout(.sizeThatFits)
            .padding()

            StreamProfileBadge(viewModel: StreamBadgeViewModel(
                stream: previewStream,
                isHighlighted: true,
                isExpanded: true,
                topicTags: ["Swift", "SwiftUI", "iOS"],
                membersProfile: membersProfile,
                ownerProfile: ownerProfile,
                activityLevel: .high
            ))
            .previewLayout(.sizeThatFits)
            .padding()
        }
    }
}

// struct StreamProfileBadge_Previews: PreviewProvider {
//    static var previews: some View {
//        Group {
//            StreamProfileBadge(
//                streamName: "Arkavo Friends",
//                isHighlighted: true,
//                description: "A group for all Arkavo friends to stay connected.",
//                topicTags: ["Friends", "Community", "Fun"],
//                membersProfile: [
//                    AccountProfileViewModel(profile: Profile(name: "Alice"), activityService: ActivityServiceModel()),
//                    AccountProfileViewModel(profile: Profile(name: "Bob"), activityService: ActivityServiceModel()),
//                    AccountProfileViewModel(profile: Profile(name: "Charlie"), activityService: ActivityServiceModel()),
//                ],
//                ownerProfile: AccountProfileViewModel(profile: Profile(name: "Owner"), activityService: ActivityServiceModel()),
//                activityLevel: .high
//            )
//            .previewLayout(.sizeThatFits)
//            .padding()
//
//            StreamProfileBadge(
//                streamName: "Arkavo Family",
//                description: "Stay in touch with family members through Arkavo.",
//                topicTags: ["Family", "Support"],
//                membersProfile: [
//                    AccountProfileViewModel(profile: Profile(name: "Dave"), activityService: ActivityServiceModel()),
//                    AccountProfileViewModel(profile: Profile(name: "Eve"), activityService: ActivityServiceModel()),
//                ],
//                ownerProfile: AccountProfileViewModel(profile: Profile(name: "Family Owner"), activityService: ActivityServiceModel()),
//                activityLevel: .medium
//            )
//            .previewLayout(.sizeThatFits)
//            .padding()
//
//            // New expanded preview
//            StreamProfileBadge(
//                isExpanded: true,
//                streamName: "Tech Enthusiasts",
//                image: Image(systemName: "laptopcomputer"),
//                isHighlighted: true,
//                description: "A community for tech lovers to discuss the latest trends and innovations.",
//                topicTags: ["Technology", "Innovation", "Gadgets"],
//                membersProfile: [
//                    AccountProfileViewModel(profile: Profile(name: "John"), activityService: ActivityServiceModel()),
//                    AccountProfileViewModel(profile: Profile(name: "Sarah"), activityService: ActivityServiceModel()),
//                    AccountProfileViewModel(profile: Profile(name: "Mike"), activityService: ActivityServiceModel()),
//                    AccountProfileViewModel(profile: Profile(name: "Emma"), activityService: ActivityServiceModel()),
//                ],
//                ownerProfile: AccountProfileViewModel(profile: Profile(name: "TechGuru"), activityService: ActivityServiceModel()),
//                activityLevel: .high
//            )
//            .previewLayout(.sizeThatFits)
//            .padding()
//            .previewDisplayName("Expanded Tech Enthusiasts Stream")
//        }
//    }
// }
