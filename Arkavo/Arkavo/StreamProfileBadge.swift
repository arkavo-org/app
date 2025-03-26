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
                        Text(viewModel.stream?.policiesSafe.admission.rawValue ?? "")
                            .font(.caption)
                            .padding(5)
                            .background(Color.blue.opacity(0.2))
                            .cornerRadius(5)
                    }

                    HStack {
                        Text("Interaction Policy:")
                            .font(.subheadline)
                            .bold()
                        Text(viewModel.stream?.policiesSafe.interaction.rawValue ?? "")
                            .font(.caption)
                            .padding(5)
                            .background(Color.blue.opacity(0.2))
                            .cornerRadius(5)
                    }

                    HStack {
                        Text("Age Policy:")
                            .font(.subheadline)
                            .bold()
                        Text(viewModel.stream?.policiesSafe.age.rawValue ?? "")
                            .font(.caption)
                            .padding(8)
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
