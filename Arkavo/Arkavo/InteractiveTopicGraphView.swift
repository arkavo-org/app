import SwiftUI

struct TopicNode: Identifiable {
    let id = UUID()
    let name: String
    var position: CGPoint
    var isDragging = false
    var isBreaking = false
}

struct Bucket: Identifiable {
    let id = UUID()
    let name: String
    let color: Color
}

struct InteractiveTopicGraphView: View {
    @State private var topics: [TopicNode] = []
    @State private var edges: [(String, String)] = []

    let buckets = [
        Bucket(name: "Yes", color: .green),
        Bucket(name: "No", color: .red),
    ]

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Draw edges
                ForEach(edges, id: \.0) { source, target in
                    EdgeView(source: source, target: target, topics: topics)
                }

                // Draw nodes
                ForEach($topics) { $topic in
                    TopicNodeView(topic: $topic)
                        .gesture(
                            DragGesture()
                                .onChanged { value in
                                    topic.position = value.location
                                    topic.isDragging = true

                                    // Check if the topic is over a bucket
                                    if isOverBucket(position: value.location, geometry: geometry) {
                                        topic.isBreaking = true
                                    } else {
                                        topic.isBreaking = false
                                    }
                                }
                                .onEnded { value in
                                    topic.isDragging = false
                                    topic.isBreaking = false

                                    // Check if the topic should be dropped into a bucket
                                    if let bucket = getBucketAtPosition(value.location, geometry: geometry) {
                                        print("Dropped \(topic.name) into \(bucket.name) bucket")
                                        // Here you can implement the logic to handle the topic being placed in a bucket
                                    }
                                }
                        )
                }

                // Draw buckets
                VStack {
                    Spacer()
                    HStack {
                        ForEach(buckets) { bucket in
                            BucketView(bucket: bucket)
                                .frame(width: 100, height: 100)
                        }
                    }
                }
            }
        }
        .onAppear {
            loadTopics()
        }
    }

    private func isOverBucket(position: CGPoint, geometry: GeometryProxy) -> Bool {
        position.y > geometry.size.height - 150
    }

    private func getBucketAtPosition(_ position: CGPoint, geometry: GeometryProxy) -> Bucket? {
        if position.x < geometry.size.width / 2 {
            buckets[0]
        } else {
            buckets[1]
        }
    }

    private func loadTopics() {
        let mainTopics = ["Self", "Career", "Society", "Education", "Technology", "Economics", "Leisure", "Philosophy", "Events", "Psychology", "Future"]

        // Generate topics
        topics = mainTopics.enumerated().map { index, topicName in
            let angle = 2 * .pi * Double(index) / Double(mainTopics.count)
            let x = 200 * cos(angle) + UIScreen.main.bounds.width / 2
            let y = 200 * sin(angle) + UIScreen.main.bounds.height / 2
            return TopicNode(name: topicName, position: CGPoint(x: x, y: y))
        }

        // Create edges based on the Topics structure
        edges = [
            ("Self", "Career"),
            ("Self", "Education"),
            ("Career", "Technology"),
            ("Society", "Events"),
            ("Technology", "Future"),
        ]
    }
}

struct EdgeView: View {
    let source: String
    let target: String
    let topics: [TopicNode]

    var body: some View {
        Path { path in
            if let sourceNode = topics.first(where: { $0.name == source }),
               let targetNode = topics.first(where: { $0.name == target })
            {
                path.move(to: sourceNode.position)
                path.addLine(to: targetNode.position)
            }
        }
        .stroke(Color.gray, lineWidth: 1)
    }
}

struct TopicNodeView: View {
    @Binding var topic: TopicNode

    var body: some View {
        Text(topic.name)
            .padding(10)
            .background(Color.blue)
            .foregroundColor(.white)
            .cornerRadius(10)
            .position(topic.position)
            .scaleEffect(topic.isDragging ? 1.2 : 1.0)
            .opacity(topic.isBreaking ? 0.5 : 1.0)
    }
}

struct BucketView: View {
    let bucket: Bucket

    var body: some View {
        VStack {
            Text(bucket.name)
                .foregroundColor(.white)
            Image(systemName: "bucket.fill")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 60, height: 60)
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
        InteractiveTopicGraphView()
    }
}
