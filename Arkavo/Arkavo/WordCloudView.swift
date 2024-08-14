import SwiftUI

struct WordCloudItem: Identifiable {
    let id = UUID()
    let text: String
    var size: CGFloat
    let color: Color
    var position: CGPoint
    var initialPosition: CGPoint
    var frame: CGRect = .zero
}

enum WordCloudAnimationType {
    case circleRotation
    case explosion
    case falling
}

class WordCloudViewModel: ObservableObject {
    @Published var words: [(String, CGFloat)]
    @Published var thoughtStreamViewModel: ThoughtStreamViewModel
    let animationType: WordCloudAnimationType

    init(
        thoughtStreamViewModel: ThoughtStreamViewModel,
        words: [(String, CGFloat)],
        animationType: WordCloudAnimationType
    ) {
        self.thoughtStreamViewModel = thoughtStreamViewModel
        self.words = words
        self.animationType = animationType
    }

    func updateWords(_ newWords: [(String, CGFloat)]) {
        words = newWords
    }
}

struct WordCloudView: View {
    @StateObject var viewModel: WordCloudViewModel
    @State private var items: [WordCloudItem] = []
    @State private var animationProgress: CGFloat = 0
    @State private var selectedWord: WordCloudItem?
    @State private var showingContentView = false
    @State private var availableSize: CGSize = .zero
    let animationDuration: Double = 2.0
    let titleSize: CGFloat = 40

    var body: some View {
        GeometryReader { geometry in
            VStack {
                // Title area
                ZStack(alignment: .center) {
                    if let selectedWord {
                        Text(selectedWord.text)
                            .font(.system(size: titleSize))
                            .foregroundColor(selectedWord.color)
                            .transition(.asymmetric(insertion: .move(edge: .bottom), removal: .opacity))
                    }
                }
                .frame(height: 30)
                .zIndex(1)

                if showingContentView {
                    ThoughtStreamView(viewModel: viewModel.thoughtStreamViewModel)
                } else {
                    // Word cloud area
                    ZStack {
                        ForEach(items) { item in
                            Text(item.text)
                                .font(.system(size: item.size))
                                .foregroundColor(item.color)
                                .position(animatedPosition(for: item, in: geometry.size))
                                .animation(.easeInOut(duration: animationDuration), value: animationProgress)
                                .background(GeometryReader { itemGeometry in
                                    Color.clear.preference(key: ItemPreferenceKey.self, value: ItemPreference(id: item.id, frame: itemGeometry.frame(in: .named("wordCloud"))))
                                })
                                .onTapGesture {
                                    withAnimation(.easeInOut(duration: 0.5)) {
                                        selectWord(item, in: geometry.size)
                                    }
                                }
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.black)
                    .coordinateSpace(name: "wordCloud")
                    .onPreferenceChange(ItemPreferenceKey.self) { preference in
                        if let preference = preference,
                           let index = items.firstIndex(where: { $0.id == preference.id }) {
                            items[index].frame = preference.frame
                        }
                    }
                }
            }
            .onAppear {
                availableSize = geometry.size
                setupWordCloud(in: geometry.size)
                withAnimation(.easeOut(duration: animationDuration)) {
                    animationProgress = 1.0
                }
            }
        }
    }

    func setupWordCloud(in size: CGSize) {
        items = viewModel.words.enumerated().map { index, word in
            WordCloudItem(
                text: word.0,
                size: word.1,
                color: Color(
                    red: .random(in: 0.4 ... 1),
                    green: .random(in: 0.4 ... 1),
                    blue: .random(in: 0.4 ... 1)
                ),
                position: .zero,
                initialPosition: getInitialPosition(for: viewModel.animationType, in: size)
            )
        }

        layoutWords(in: size)
    }

    func layoutWords(in size: CGSize) {
        var placedItems: [WordCloudItem] = []

        for i in 0 ..< items.count {
            var item = items[i]
            var attempts = 0
            var placed = false

            while !placed && attempts < 100 {
                let angle = CGFloat.random(in: 0...(2 * .pi))
                let radius = CGFloat.random(in: 0...min(size.width, size.height) / 2 - item.size)
                let newPosition = CGPoint(
                    x: size.width / 2 + cos(angle) * radius,
                    y: size.height / 2 + sin(angle) * radius
                )

                item.position = newPosition
                item.frame = CGRect(origin: newPosition, size: CGSize(width: item.size, height: item.size))

                if !placedItems.contains(where: { $0.frame.insetBy(dx: -10, dy: -10).intersects(item.frame) }) {
                    placedItems.append(item)
                    placed = true
                }

                attempts += 1
            }

            if placed {
                items[i] = item
            } else {
                // If we couldn't place the item after 100 attempts, we'll just place it at a random position
                items[i].position = CGPoint(x: CGFloat.random(in: item.size...size.width-item.size),
                                            y: CGFloat.random(in: item.size...size.height-item.size))
            }
        }
    }

    func selectWord(_ item: WordCloudItem, in size: CGSize) {
        selectedWord = item

        // Animate the selected word to the title area
        if let index = items.firstIndex(where: { $0.id == item.id }) {
            items[index].position = CGPoint(x: size.width / 2, y: 30)
            items[index].size = titleSize
        }

        // Show the content view after a short delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            showingContentView = true
        }
    }

    func getInitialPosition(for animationType: WordCloudAnimationType, in size: CGSize) -> CGPoint {
        switch animationType {
        case .circleRotation, .explosion:
            return CGPoint(x: size.width / 2, y: size.height / 2)
        case .falling:
            return CGPoint(x: CGFloat.random(in: 0...size.width), y: -50)
        }
    }

    func animatedPosition(for item: WordCloudItem, in size: CGSize) -> CGPoint {
        switch viewModel.animationType {
        case .circleRotation:
            let angle = 2 * .pi * animationProgress
            let radius = distance(from: CGPoint(x: size.width / 2, y: size.height / 2), to: item.position)
            return CGPoint(
                x: size.width / 2 + cos(angle) * radius * animationProgress,
                y: size.height / 2 + sin(angle) * radius * animationProgress
            )
        case .explosion:
            return CGPoint(
                x: item.initialPosition.x + (item.position.x - item.initialPosition.x) * animationProgress,
                y: item.initialPosition.y + (item.position.y - item.initialPosition.y) * animationProgress
            )
        case .falling:
            return CGPoint(
                x: item.position.x,
                y: item.initialPosition.y + (item.position.y - item.initialPosition.y) * animationProgress
            )
        }
    }

    func distance(from point1: CGPoint, to point2: CGPoint) -> CGFloat {
        return sqrt(pow(point2.x - point1.x, 2) + pow(point2.y - point1.y, 2))
    }
}

struct ItemPreference: Equatable {
    let id: UUID
    let frame: CGRect
}

struct ItemPreferenceKey: PreferenceKey {
    static var defaultValue: ItemPreference?
    
    static func reduce(value: inout ItemPreference?, nextValue: () -> ItemPreference?) {
        value = nextValue() ?? value
    }
}

struct WordCloudView_Previews: PreviewProvider {
    static var previews: some View {
        let words : [(String, CGFloat)] = [
           ("SwiftUI", 60), ("iOS", 50), ("Xcode", 45), ("Swift", 55),
           ("Apple", 40), ("Developer", 35), ("Code", 30), ("App", 25),
           ("UI", 20), ("UX", 15), ("Design", 30), ("Mobile", 25),
       ]
        Group {
            WordCloudView(viewModel: WordCloudViewModel(thoughtStreamViewModel: ThoughtStreamViewModel(), words: words, animationType: .circleRotation))
            WordCloudView(viewModel: WordCloudViewModel(thoughtStreamViewModel: ThoughtStreamViewModel(), words: words, animationType: .explosion))
            WordCloudView(viewModel: WordCloudViewModel(thoughtStreamViewModel: ThoughtStreamViewModel(), words: words, animationType: .falling))
        }
    }
}
