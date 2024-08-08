import SwiftUI

struct WordCloudView: View {
    @State private var items: [WordCloudItem] = []
    @State private var scale: CGFloat = 0.1
    @State private var rotationProgress: CGFloat = 0
    
    let animationDuration: Double = 2.0
    
    var body: some View {
        GeometryReader { geometry in
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
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.black)
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
        // Example data - replace with your actual data source
        let words = [
            ("SwiftUI", 60), ("iOS", 50), ("Xcode", 45), ("Swift", 55),
            ("Apple", 40), ("Developer", 35), ("Code", 30), ("App", 25),
            ("UI", 20), ("UX", 15), ("Design", 30), ("Mobile", 25)
        ]
        
        items = words.enumerated().map { index, word in
            let angle = Double(index) / Double(words.count) * 2 * .pi
            return WordCloudItem(
                text: word.0,
                size: CGFloat(word.1),
                color: Color(
                    red: .random(in: 0.4...1),
                    green: .random(in: 0.4...1),
                    blue: .random(in: 0.4...1)
                ),
                angle: angle
            )
        }
    }
}

struct WordCloudItem: Identifiable {
    let id = UUID()
    let text: String
    let size: CGFloat
    let color: Color
    let angle: Double
}


struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        WordCloudView()
    }
}
