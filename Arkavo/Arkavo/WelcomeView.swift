import SwiftUI

struct WelcomeView: View {
    var onCreateProfile: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            Text(LocalizedStringKey("Welcome to Arkavo!"))
                .font(.largeTitle)
                .fontWeight(.bold)
            Text(LocalizedStringKey("Take control of your content — anytime, anywhere."))
                .multilineTextAlignment(.center)
                .padding()
            Text(LocalizedStringKey("Create your profile in seconds using Apple Passkey — no passwords, no hassle."))
                .multilineTextAlignment(.center)
                .padding()
            VStack(alignment: .leading, spacing: 10) {
                Text(differenceText)
                    .font(.headline)
                BulletPoint(text: "Unmatched Privacy: Your data is yours, and we keep it that way.")
                BulletPoint(text: "Top-Notch Security: Military-Grade Encryption ensures your content is always safe.")
                BulletPoint(text: "More to Come: Group chats and more exciting features are just the beginning")
                BulletPoint(text: "Your data stays yours: Arkavo will never collect, store, or share any of your personal data at any time. Not even your email address!")
            }
            .padding()
            Text("Ready to Secure Your Socials?")
                .font(.headline)
            Button(action: onCreateProfile) {
                Text("Create Profile")
                    .fontWeight(.semibold)
                    .foregroundColor(.white)
                    .frame(minWidth: 200)
                    .padding()
                    .background(Color.blue)
                    .cornerRadius(10)
            }
        }
        .padding()
    }
    
    private var differenceText: AttributedString {
        var text = AttributedString("What makes Arkavo different? Your privacy is actually our priority.")
        // this probably breaks l10n
        if let range = text.range(of: "actually") {
            text[range].font = .headline.italic()
        }
        return text
    }
    
}

struct BulletPoint: View {
    let text: String

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            Text("•")
                .font(.body)
            Text(attributedString)
                .font(.body)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
    
    private var attributedString: AttributedString {
        var attributedString = AttributedString(text)
        if let colonRange = attributedString.range(of: ":") {
            attributedString[..<colonRange.lowerBound].font = .body.bold()
        }
        return attributedString
    }
}

struct WelcomeView_Previews: PreviewProvider {
    static var previews: some View {
        WelcomeView(onCreateProfile: {})
    }
}
