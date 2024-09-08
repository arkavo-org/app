import SwiftUI

struct WelcomeView: View {
    var onCreateProfile: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            Text("Welcome to Arkavo!")
                .font(.largeTitle)
                .fontWeight(.bold)
            Text("Your content is always under your control - everywhere")
                .multilineTextAlignment(.center)
                .padding()
            Text("Your privacy is our priority. Create your profile using just your name and Apple Passkey — no passwords, no hassle.")
                .multilineTextAlignment(.center)
                .padding()
            VStack(alignment: .leading, spacing: 10) {
                Text("What makes us different?")
                    .font(.headline)
                BulletPoint(text: "Leader in Privacy")
                BulletPoint(text: "Leader in Content Security")
                BulletPoint(text: "Military-grade data security powered by OpenTDF.")
                BulletPoint(text: "Start group chats now, with more exciting features coming soon!")
            }
            .padding()
            Text("Ready to join?")
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
}

struct BulletPoint: View {
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Text("•")
                .font(.body)
                .padding(.top, 4)
            Text(text)
                .font(.body)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

struct WelcomeView_Previews: PreviewProvider {
    static var previews: some View {
        WelcomeView(onCreateProfile: {})
    }
}
