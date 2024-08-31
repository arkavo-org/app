import SwiftUI

struct WordCloudItem: Identifiable {
    let id = UUID()
    let text: String
    var size: CGFloat
    let color: Color
    var angle: Double
    var position: CGPoint
}

class WordCloudViewModel: ObservableObject {
    @Published var words: [(String, CGFloat)] = [
        ("SwiftUI", 60), ("iOS", 50), ("Xcode", 45), ("Swift", 55),
        ("Apple", 40), ("Developer", 35), ("Code", 30), ("App", 25),
        ("UI", 20), ("UX", 15), ("Design", 30), ("Mobile", 25),
    ]

    @Published var thoughtStreamViewModel: ThoughtStreamViewModel

    init(thoughtStreamViewModel: ThoughtStreamViewModel) {
        self.thoughtStreamViewModel = thoughtStreamViewModel
    }

    func updateWords(_ newWords: [(String, CGFloat)]) {
        words = newWords
    }
}

struct WordCloudView: View {
    @StateObject var viewModel: WordCloudViewModel
    @State private var items: [WordCloudItem] = []
    @State private var scale: CGFloat = 0.1
    @State private var rotationProgress: CGFloat = 0
    @State private var selectedWord: WordCloudItem?
    @State private var showingContentView = false
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
                .padding(.top, 150)
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
                                .position(
                                    x: geometry.size.width / 2 + cos(item.angle) * 200 * scale,
                                    y: geometry.size.height / 2 + sin(item.angle) * 200 * scale
                                )
                                .rotationEffect(.degrees(-item.angle * (180 / .pi) * (1 - rotationProgress)))
                                .onTapGesture {
                                    withAnimation(.easeInOut(duration: 0.5)) {
                                        selectWord(item, in: geometry)
                                    }
                                }
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.black)
                }
            }
        }
        .onAppear {
            setupWordCloud()
            withAnimation(.easeOut(duration: animationDuration)) {
                scale = 1.0
                rotationProgress = 1.0
            }
        }
    }

    func setupWordCloud() {
        items = viewModel.words.enumerated().map { index, word in
            let angle = Double(index) / Double(viewModel.words.count) * 2 * .pi
            return WordCloudItem(
                text: word.0,
                size: word.1,
                color: Color(
                    red: .random(in: 0.4 ... 1),
                    green: .random(in: 0.4 ... 1),
                    blue: .random(in: 0.4 ... 1)
                ),
                angle: angle,
                position: .zero // Will be set in updatePositions
            )
        }

        updatePositions()
    }

    func updatePositions() {
        for i in 0 ..< items.count {
            let angle = items[i].angle
            items[i].position = CGPoint(
                x: 200 + cos(angle) * 200 * scale,
                y: 200 + sin(angle) * 200 * scale
            )
        }
    }

    func selectWord(_ item: WordCloudItem, in geometry: GeometryProxy) {
        selectedWord = item

        // Animate the selected word to the title area
        if let index = items.firstIndex(where: { $0.id == item.id }) {
            items[index].position = CGPoint(x: geometry.size.width / 2, y: 30)
            items[index].size = titleSize
            items[index].angle = 0
        }

        // Show the content view after a short delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            showingContentView = true
        }
    }
}

struct WordCloudView_Previews: PreviewProvider {
    static var previews: some View {
        WordCloudView(viewModel: WordCloudViewModel(thoughtStreamViewModel: ThoughtStreamViewModel()))
    }
}


