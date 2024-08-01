import SwiftUI

struct ThoughtStreamView: View {
    @State private var topThoughts: [Thought] = [
        Thought(text: "Top thought 1...", offset: 0, color: .blue),
        Thought(text: "Top thought 2...", offset: 0.2, color: .blue),
        Thought(text: "Top thought 3...", offset: 0.4, color: .blue),
        Thought(text: "Top thought 4...", offset: 0.6, color: .blue),
        Thought(text: "Top thought 5...", offset: 0.8, color: .blue)
    ]
    @State private var bottomThoughts: [Thought] = [
        Thought(text: "Bottom thought 1...", offset: 0, color: .green),
        Thought(text: "Bottom thought 2...", offset: 0.2, color: .green),
        Thought(text: "Bottom thought 3...", offset: 0.4, color: .green),
        Thought(text: "Bottom thought 4...", offset: 0.6, color: .green),
        Thought(text: "Bottom thought 5...", offset: 0.8, color: .green)
    ]
    @State private var inputText = ""
    @FocusState private var isInputFocused: Bool
    
    let topColor = Color.blue
    let bottomColor = Color.green
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Background gradient
                LinearGradient(gradient: Gradient(colors: [Color.gray.opacity(0.2), Color.gray.opacity(0.1)]),
                               startPoint: .top,
                               endPoint: .bottom)
                    .edgesIgnoringSafeArea(.all)
                
                VStack(spacing: 0) {
                    // Thought stream area
                    ZStack {
                        // Flowing thoughts from top
                        ForEach(topThoughts) { thought in
                            ThoughtView(thought: thought,
                                        screenHeight: geometry.size.height,
                                        isTopThought: true)
                        }
                        
                        // Flowing thoughts from bottom
                        ForEach(bottomThoughts) { thought in
                            ThoughtView(thought: thought,
                                        screenHeight: geometry.size.height,
                                        isTopThought: false)
                        }
                    }
                    .frame(height: geometry.size.height - 100) // Adjust for input box and keyboard
                    
                    // Input box
                    HStack {
                        TextField("Enter your thought...", text: $inputText)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                            .focused($isInputFocused)
                        
                        Button(action: addThought) {
                            Image(systemName: "arrow.up.circle.fill")
                                .foregroundColor(.blue)
                                .font(.title)
                        }
                    }
                    .padding()
                    .background(Color.white)
                    .shadow(radius: 5)
                }
            }
        }
        .onAppear {
            startThoughtAnimation()
            isInputFocused = false
        }
    }
    
    private func addThought() {
        guard !inputText.isEmpty else { return }
        let newThought = Thought(text: inputText, offset: 0, color: topThoughts.count <= bottomThoughts.count ? topColor : bottomColor)
        
        // Alternate between adding to top and bottom
        if topThoughts.count <= bottomThoughts.count {
            topThoughts.insert(newThought, at: 0)
            if topThoughts.count > 5 {
                topThoughts.removeLast()
            }
        } else {
            bottomThoughts.insert(newThought, at: 0)
            if bottomThoughts.count > 5 {
                bottomThoughts.removeLast()
            }
        }
        
        inputText = ""
        
        // Reset offsets for flowing effect
        for i in 0..<topThoughts.count {
            topThoughts[i].offset = Double(i) * 0.2
        }
        for i in 0..<bottomThoughts.count {
            bottomThoughts[i].offset = Double(i) * 0.2
        }
    }
    
    private func startThoughtAnimation() {
        for i in 0..<topThoughts.count {
            withAnimation(.linear(duration: 10).repeatForever(autoreverses: false)) {
                topThoughts[i].offset = 1.0
            }
        }
        for i in 0..<bottomThoughts.count {
            withAnimation(.linear(duration: 10).repeatForever(autoreverses: false)) {
                bottomThoughts[i].offset = 1.0
            }
        }
    }
}

struct Thought: Identifiable {
    let id = UUID()
    let text: String
    var offset: Double
    let color: Color
}

struct ThoughtView: View {
    let thought: Thought
    let screenHeight: CGFloat
    let isTopThought: Bool
    
    var body: some View {
        Text(thought.text)
            .font(.caption)
            .padding(8)
            .background(thought.color.opacity(0.7))
            .foregroundColor(.white)
            .clipShape(Capsule())
            .scaleEffect(1 - thought.offset * 0.5) // Decrease size as it moves to center
            .opacity(1 - thought.offset) // Fade out as it moves to center
            .offset(y: calculateYOffset())
    }
    
    private func calculateYOffset() -> CGFloat {
        let visibleHeight = screenHeight - 100 // Adjust for input box and keyboard
        let startY = isTopThought ? -visibleHeight / 2 : visibleHeight / 2
        let endY: CGFloat = 0 // Center of the visible area
        return startY + CGFloat(thought.offset) * (endY - startY)
    }
}

struct ThoughtStreamView_Previews: PreviewProvider {
    static var previews: some View {
        ThoughtStreamView()
    }
}
