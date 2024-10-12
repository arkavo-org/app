import SwiftUI

struct TopicNode: Identifiable {
    let id = UUID()
    let name: String
    var position: CGPoint
    var isDragging = false
    var isBreaking = false
    var color: Color
    var isMainTopic: Bool
    var subtopics: [TopicNode]?
    var isSelected: Bool = false
}

struct Bucket: Identifiable {
    let id = UUID()
    let name: String
    let color: Color
    var position: CGPoint
    var topics: [TopicNode] = []
}

struct RegistrationInterestsView: View {
    @State private var topics: [TopicNode] = []
    @State private var selectedTopic: TopicNode?
    @State private var buckets: [Bucket]

    init() {
        _buckets = State(initialValue: [
            Bucket(name: "Yes", color: .green, position: CGPoint(x: 200, y: 700)),
            Bucket(name: "No", color: .red, position: CGPoint(x: 200, y: 100)),
        ])
    }

    var body: some View {
        GeometryReader { _ in
            ZStack {
                // Draw nodes
                ForEach($topics) { $topic in
                    TopicNodeView(topic: $topic)
                        .gesture(
                            DragGesture()
                                .onChanged { value in
                                    topic.position = value.location
                                    topic.isDragging = true

                                    // Check if the topic is over a bucket
                                    if isOverBucket(position: value.location) {
                                        topic.isBreaking = true
                                    } else {
                                        topic.isBreaking = false
                                    }
                                }
                                .onEnded { value in
                                    topic.isDragging = false
                                    topic.isBreaking = false

                                    // Check if the topic should be dropped into a bucket
                                    if let bucketIndex = getBucketIndexAtPosition(value.location) {
                                        dropTopicIntoBucket(topic, bucketIndex: bucketIndex)
                                    }
                                }
                        )
                        .onTapGesture {
                            if topic.isMainTopic {
                                selectedTopic = topic.isSelected ? nil : topic
                                topic.isSelected.toggle()
                            }
                        }
                }

                // Draw subtopics if a main topic is selected
                if let selectedTopic, let subtopics = selectedTopic.subtopics {
                    ForEach(subtopics) { subtopic in
                        TopicNodeView(topic: .constant(subtopic))
                    }
                }

                // Draw buckets
                ForEach($buckets) { $bucket in
                    BucketView(bucket: $bucket)
                        .position(bucket.position)
                }
            }
        }
        .onAppear {
            loadTopics()
        }
    }

    private func isOverBucket(position: CGPoint) -> Bool {
        buckets.contains { bucket in
            position.distance(to: bucket.position) < 75
        }
    }

    private func getBucketIndexAtPosition(_ position: CGPoint) -> Int? {
        buckets.firstIndex { bucket in
            position.distance(to: bucket.position) < 75
        }
    }

    private func dropTopicIntoBucket(_ topic: TopicNode, bucketIndex: Int) {
        print("Dropped \(topic.name) into \(buckets[bucketIndex].name) bucket")

        // Remove the topic from the main topics list
        if let index = topics.firstIndex(where: { $0.id == topic.id }) {
            topics.remove(at: index)
        }

        // Add the topic to the bucket
        buckets[bucketIndex].topics.append(topic)

        if buckets[bucketIndex].name == "No" {
            return
        }

        // If the topic has subtopics, add them to the main topics list
        if let subtopics = topic.subtopics {
            // Calculate new positions for subtopics
            let radius: CGFloat = 100
            let angleStep = (2 * .pi) / CGFloat(subtopics.count)

            for (index, var subtopic) in subtopics.enumerated() {
                let angle = CGFloat(index) * angleStep
                let x = radius * cos(angle) + UIScreen.main.bounds.width / 2
                let y = radius * sin(angle) + UIScreen.main.bounds.height / 2
                subtopic.position = CGPoint(x: x, y: y)
                topics.append(subtopic)
            }
        }
    }

    private func loadTopics() {
        let mainTopics = [
            ("Self", Color.blue),
            ("Career", Color.green),
            ("Society", Color.red),
            ("Education", Color.purple),
        ]

        // Generate topics
        topics = mainTopics.enumerated().map { index, topicInfo in
            let (topicName, topicColor) = topicInfo
            let angle = 2 * .pi * Double(index) / Double(mainTopics.count)
            let radius = 160.0 // Adjusted radius to ensure topics are within the screen
            let x = radius * cos(angle) + UIScreen.main.bounds.width / 2
            let y = radius * sin(angle) + UIScreen.main.bounds.height / 2
            return TopicNode(name: topicName, position: CGPoint(x: x, y: y), color: topicColor, isMainTopic: true, subtopics: getSubtopics(for: topicName, color: topicColor))
        }
    }

    private func getSubtopics(for mainTopic: String, color: Color) -> [TopicNode] {
        let subtopics: [String] = switch mainTopic {
        case "Self":
            ["Family", "Relationships", "Health", "Hobbies", "Sports"]
        case "Career":
            ["Growth", "Dynamics", "Trends"]
        case "Society":
            ["Politics", "Issues", "Traditions", "Media", "Entertainment"]
        case "Education":
            ["Academics", "Skills", "Growth"]
        default:
            []
        }

        return subtopics.map { subtopic in
            TopicNode(name: subtopic, position: .zero, color: color.opacity(0.7), isMainTopic: false)
        }
    }
}

struct TopicNodeView: View {
    @Binding var topic: TopicNode

    var body: some View {
        Text(topic.name)
            .padding(10)
            .background(topic.color)
            .foregroundColor(.white)
            .cornerRadius(10)
            .position(topic.position)
            .scaleEffect(topic.isDragging ? 1.2 : 1.0)
            .opacity(topic.isBreaking ? 0.5 : 1.0)
    }
}

struct BucketView: View {
    @Binding var bucket: Bucket

    var body: some View {
        VStack {
            Text(bucket.name)
                .foregroundColor(.white)
            Image(systemName: "checkmark.fill")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 60, height: 60)
            Text("\(bucket.topics.count)")
                .foregroundColor(.white)
                .font(.headline)
        }
        .padding()
        .background(bucket.color)
        .cornerRadius(10)
    }
}

extension CGPoint {
    func distance(to point: CGPoint) -> CGFloat {
        sqrt(pow(x - point.x, 2) + pow(y - point.y, 2))
    }
}

// Preview
struct InteractiveTopicGraphView_Previews: PreviewProvider {
    static var previews: some View {
        RegistrationInterestsView()
    }
}
