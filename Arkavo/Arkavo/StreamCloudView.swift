import CoreGraphics
import SwiftUI
#if canImport(UIKit)
    import UIKit
#elseif canImport(AppKit)
    import AppKit
#endif

struct StreamCloudView: View {
    @StateObject var viewModel: WordCloudViewModel
    @State private var boundingBoxes: [BoundingBox] = []
    @State private var availableSize: CGSize = .zero
    @State private var spacing: CGFloat = 20
    @State private var animationProgress: Double = 0
    @State private var items: [BoundingBox] = []
    @State private var selectedWord: BoundingBox?
    @State private var showingContentView = false
    let animationDuration: Double = 2.0
    let titleSize: CGFloat = 40

    var body: some View {
        GeometryReader { geometry in
            // Title area
            ZStack(alignment: .center) {
                if let selectedWord {
                    Text(selectedWord.word)
                        .font(.system(size: titleSize))
                        .transition(.asymmetric(insertion: .move(edge: .bottom), removal: .opacity))
                }
            }
            .padding(.top, 150)
            .padding(.leading, 20)
            .frame(height: 30)
            .zIndex(1)

            if showingContentView {
                ThoughtView(viewModel: viewModel.thoughtStreamViewModel)
            } else {
                ZStack {
                    ForEach(boundingBoxes) { box in
                        Text(box.word)
                            .font(.system(size: box.size))
                            .foregroundColor(Color(
                                red: .random(in: 0.4 ... 1),
                                green: .random(in: 0.4 ... 1),
                                blue: .random(in: 0.4 ... 1)
                            ))
                            .position(animatedPosition(for: box))
                            .opacity(box.opacity)
                            .rotationEffect(box.rotation)
                            .onTapGesture {
                                withAnimation(.easeInOut(duration: 0.5)) {
                                    selectWord(box, in: geometry.size)
                                }
                            }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.black)
                .onAppear {
                    availableSize = geometry.size
                    calculateSpacing(for: geometry.size)
                    layoutWords(in: geometry.size)
                    startAnimation()
                }
            }
        }
    }

    func selectWord(_ item: BoundingBox, in size: CGSize) {
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

    func startAnimation() {
        withAnimation(.easeInOut(duration: animationDuration)) {
            animationProgress = 1.0

            for i in 0 ..< boundingBoxes.count {
                boundingBoxes[i].opacity = 1.0

                switch viewModel.animationType {
                case .rotating:
                    boundingBoxes[i].rotation = .degrees(360)
                case .explosion, .falling, .rising, .swirling:
                    // These animations are handled in animatedPosition
                    break
                }
            }
        }
    }

    func animatedPosition(for box: BoundingBox) -> CGPoint {
        let startPosition: CGPoint
        let endPosition = box.position

        switch viewModel.animationType {
        case .rotating:
            return endPosition
        case .explosion:
            startPosition = CGPoint(x: availableSize.width / 2, y: availableSize.height / 2)
        case .falling:
            startPosition = CGPoint(x: endPosition.x, y: -box.rect.height)
        case .rising:
            startPosition = CGPoint(x: endPosition.x, y: availableSize.height + box.rect.height)
        case .swirling:
            let angle = animationProgress * 2 * .pi
            let radius = min(availableSize.width, availableSize.height) * 0.4 * (1 - animationProgress)
            return CGPoint(
                x: endPosition.x + cos(angle) * radius,
                y: endPosition.y + sin(angle) * radius
            )
        }

        return CGPoint(
            x: startPosition.x + (endPosition.x - startPosition.x) * animationProgress,
            y: startPosition.y + (endPosition.y - startPosition.y) * animationProgress
        )
    }

    func calculateSpacing(for size: CGSize) {
        let totalArea = size.width * size.height
        let wordCount = CGFloat(viewModel.words.count)
        let averageAreaPerWord = totalArea / wordCount
        spacing = sqrt(averageAreaPerWord) * 0.2 // Increased factor for more spacing
    }

    func layoutWords(in size: CGSize) {
        boundingBoxes.removeAll()

        for word in viewModel.words.sorted(by: { $0.1 > $1.1 }) {
            let wordSize = word.1
            let textSize = textSize(for: word.0, fontSize: wordSize)
            let box = BoundingBox(
                rect: CGRect(origin: .zero, size: CGSize(width: textSize.width + spacing, height: textSize.height + spacing)),
                word: word.0,
                size: wordSize,
                position: .zero // We'll set this later if we find a position
            )

            if let position = findNonOverlappingPosition(for: box, in: size) {
                var newBox = box
                newBox.position = position
                newBox.rect = CGRect(origin: position, size: box.rect.size)
                boundingBoxes.append(newBox)
            }
        }
    }

    func textSize(for text: String, fontSize: CGFloat) -> CGSize {
        #if canImport(UIKit)
            let font = UIFont.systemFont(ofSize: fontSize)
        #elseif canImport(AppKit)
            let font = NSFont.systemFont(ofSize: fontSize)
        #endif
        let attributes = [NSAttributedString.Key.font: font]
        let size = (text as NSString).size(withAttributes: attributes)
        return size
    }

    func findNonOverlappingPosition(for box: BoundingBox, in size: CGSize) -> CGPoint? {
        let stepSize: CGFloat = spacing
        let maxAttempts = 3000

        for attempt in 0 ..< maxAttempts {
            let angle = CGFloat(attempt) * CGFloat.pi * (3 - sqrt(5))
            let radius = sqrt(CGFloat(attempt)) * stepSize

            let x = size.width / 2 + cos(angle) * radius
            let y = size.height / 2 + sin(angle) * radius
            let proposedRect = CGRect(x: x, y: y, width: box.rect.width, height: box.rect.height)

            if proposedRect.minX >= 80, proposedRect.minY >= 0,
               proposedRect.maxX <= size.width + 80, proposedRect.maxY <= size.height,
               !boundingBoxes.contains(where: { $0.rect.intersects(proposedRect) })
            {
                return CGPoint(x: x, y: y)
            }
        }

        return nil
    }
}

struct BoundingBoxView: View {
    let box: BoundingBox

    var body: some View {
        ZStack {
            Rectangle()
                .stroke(Color.red, lineWidth: 1)
                .frame(width: box.rect.width, height: box.rect.height)

            Text(box.word)
                .font(.system(size: box.size))
                .foregroundColor(Color(
                    red: .random(in: 0.4 ... 1),
                    green: .random(in: 0.4 ... 1),
                    blue: .random(in: 0.4 ... 1)
                ))
        }
        .position(x: box.rect.midX, y: box.rect.midY)
    }
}

enum WordCloudAnimationType {
    case rotating
    case explosion
    case falling
    case rising
    case swirling
}

struct WordCloudItem: Identifiable {
    let id = UUID()
    let text: String
    var size: CGFloat
    let color: Color
    var position: CGPoint
    var initialPosition: CGPoint
    var frame: CGRect = .zero
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

struct WordCloudView_Previews: PreviewProvider {
    static var previews: some View {
        let words: [(String, CGFloat)] = [
            ("SwiftUI", 22), ("iOS", 50), ("Xcode", 45), ("Swift", 55),
            ("Apple", 40), ("Developer", 35), ("Code", 30),
            ("UI", 20), ("UX", 15), ("Design", 30), ("Mobile", 25),
        ]
        let moreWords: [(String, CGFloat)] = [
            ("Feedback", 60), ("Technology", 50), ("Fitness", 45), ("Activism", 55),
            ("Sports", 40), ("Career", 35), ("Education", 30), ("Beauty", 25),
            ("Fashion", 20), ("Gaming", 15), ("Entertainment", 30), ("Climate Change", 25),
        ]
        let moreWordsDifferentSize: [(String, CGFloat)] = [
            ("Feedback", 33), ("Technology", 11), ("Fitness", 22), ("Activism", 44),
            ("Sports", 32), ("Career", 21), ("Education", 11), ("Beauty", 35),
            ("Fashion", 38), ("Gaming", 12), ("Entertainment", 36), ("Climate Change", 16),
        ]
        Group {
            StreamCloudView(viewModel: WordCloudViewModel(thoughtStreamViewModel: ThoughtStreamViewModel(), words: moreWordsDifferentSize, animationType: .rotating))
            StreamCloudView(viewModel: WordCloudViewModel(thoughtStreamViewModel: ThoughtStreamViewModel(), words: moreWords, animationType: .explosion))
            StreamCloudView(viewModel: WordCloudViewModel(thoughtStreamViewModel: ThoughtStreamViewModel(), words: words, animationType: .falling))
            StreamCloudView(viewModel: WordCloudViewModel(thoughtStreamViewModel: ThoughtStreamViewModel(), words: moreWords, animationType: .rising))
            StreamCloudView(viewModel: WordCloudViewModel(thoughtStreamViewModel: ThoughtStreamViewModel(), words: words, animationType: .swirling))
        }
    }
}

extension CGRect {
    var area: CGFloat {
        width * height
    }
}

struct BoundingBox: Identifiable {
    let id = UUID()
    var rect: CGRect
    let word: String
    var size: CGFloat
    var position: CGPoint
    var opacity: Double = 0
    var rotation: Angle = .zero
}
