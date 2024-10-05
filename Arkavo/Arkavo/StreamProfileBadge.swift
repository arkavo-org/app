import SwiftUI

struct StreamProfileBadge: View {
    var streamName: String
    var image: Image = Image(systemName: "person.3.fill")
    var isHighlighted: Bool = false
    var description: String = ""
    var topicTags: [String] = []
    var membersProfile: [String] = []
    var ownerProfile: Image = Image(systemName: "person.fill")
    var activityLevel: String = ""

    @State private var isAnimating = false

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
                ownerProfile
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 30, height: 30)
                    .clipShape(Circle())
            }
            
            HStack {
                Text("Members:")
                    .font(.subheadline)
                    .bold()
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack {
                        ForEach(membersProfile, id: \.self) { member in
                            Image(systemName: member)
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(width: 30, height: 30)
                                .clipShape(Circle())
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
            if activityLevel.lowercased() == "high" {
                withAnimation(Animation.easeInOut(duration: 0.5).repeatForever(autoreverses: true)) {
                    isAnimating = true
                }
            }
        }
    }
    
    private var activityIcon: some View {
        Image(systemName: "waveform.path.ecg")
            .foregroundColor(activityColor)
            .scaleEffect(isAnimating && activityLevel.lowercased() == "high" ? 1.2 : 1.0)
    }
    
    private var activityColor: Color {
        switch activityLevel.lowercased() {
        case "high":
            return .green
        case "medium":
            return .yellow
        case "low":
            return .red
        default:
            return .gray
        }
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
                    "person.circle.fill",
                    "person.circle.fill",
                    "person.circle.fill"
                ],
                ownerProfile: Image(systemName: "person.fill"),
                activityLevel: "High"
            )
            .previewLayout(.sizeThatFits)
            .padding()

            StreamProfileBadge(
                streamName: "Arkavo Family",
                description: "Stay in touch with family members through Arkavo.",
                topicTags: ["Family", "Support"],
                membersProfile: [
                    "person.circle.fill",
                    "person.circle.fill"
                ],
                ownerProfile: Image(systemName: "person.fill"),
                activityLevel: "Medium"
            )
            .previewLayout(.sizeThatFits)
            .padding()

            StreamProfileBadge(
                streamName: "Invitation to Group Chat",
                description: "Join the Arkavo Stream to share thoughts and ideas.",
                topicTags: ["Ideas", "Collaboration"],
                membersProfile: [
                    "person.circle.fill",
                    "person.circle.fill",
                    "person.circle.fill",
                    "person.circle.fill"
                ],
                ownerProfile: Image(systemName: "person.fill"),
                activityLevel: "Low"
            )
            .previewLayout(.sizeThatFits)
            .padding()
        }
    }
}

// Example usage of StreamProfileBadge
struct ContentView: View {
    var body: some View {
        VStack {
            StreamProfileBadge(streamName: "Stream on Map", isHighlighted: true, activityLevel: "High")
            StreamProfileBadge(streamName: "Invitation to Group Chat", activityLevel: "Low")
        }
        .padding()
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
