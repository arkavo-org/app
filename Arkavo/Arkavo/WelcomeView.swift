import SwiftUI

struct WelcomeView: View {
    var onCreateProfile: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            Text(LocalizedStringKey("Welcome to Arkavo!"))
                .font(.largeTitle)
                .fontWeight(.bold)
            Text(LocalizedStringKey("Your content is always under your control - everywhere"))
                .multilineTextAlignment(.center)
                .padding()
            Text(LocalizedStringKey("Your privacy is our priority. Create your profile using just your name and Apple Passkey — no passwords, no hassle."))
                .multilineTextAlignment(.center)
                .padding()
            VStack(alignment: .leading, spacing: 10) {
                Text(LocalizedStringKey("What makes us different?"))
                    .font(.headline)
                BulletPoint(key: "Leader in Privacy")
                BulletPoint(key: "Leader in Content Security")
                BulletPoint(key: "Military-grade data security powered by OpenTDF.")
                BulletPoint(key: "Start group chats now, with more exciting features coming soon!")
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
    let key: LocalizedStringKey

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Text("•")
                .font(.body)
                .padding(.top, 4)
            Text(key)
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
