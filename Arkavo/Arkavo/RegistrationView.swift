import CoreML
import NaturalLanguage
import SwiftUI

enum RegistrationStep: Int, CaseIterable {
    case welcome
    case selectInterests
    case generateScreenName
    case enablePasskeys

    var title: String {
        switch self {
        case .welcome:
            "Welcome"
        case .selectInterests:
            "Select Interests" // What topics are you interested in?
        case .generateScreenName:
            "Create Profile"
        case .enablePasskeys:
            "Create Passkey"
        }
    }

    var buttonLabel: String {
        switch self {
        case .welcome:
            "Get Started"
        case .selectInterests:
            "Continue"
        case .generateScreenName:
            "Continue"
        case .enablePasskeys:
            "Enable Face ID"
        }
    }
}

struct RegistrationView: View {
    var onComplete: (_ profile: Profile) async -> Void

    @State private var currentStep: RegistrationStep = .welcome
    @State private var slideDirection: SlideDirection = .right
    @State private var generatedScreenNames: [String] = []
    @State private var selectedScreenName = ""
    @State private var selectedInterests: Set<String> = []
    @State private var currentWelcomeIndex = 0

    let interests = ["Animals", "Arts", "Education", "Environment", "Gaming", "Food", "Human Rights", "Legal", "Music", "Politics", "Sports"]

    let welcomeMessages = [
        "Verify your identity seamlessly.\nNo passwords, no hassle.",
        "Full control over your content.\nThis means you can allow or remove\naccess at anytime.",
        "Encryption trusted by military,\nnow available to you.",
    ]

    var body: some View {
        NavigationView {
            GeometryReader { geometry in
                VStack(spacing: 0) {
                    ZStack(alignment: .top) {
                        ForEach(RegistrationStep.allCases, id: \.self) { step in
                            Group {
                                switch step {
                                case .welcome:
                                    welcomeView
                                case .selectInterests:
                                    chooseInterestsView
                                case .generateScreenName:
                                    generateScreenNameView
                                case .enablePasskeys:
                                    enablePasskeysView
                                }
                            }
                            .frame(width: geometry.size.width, alignment: .top)
                            .opacity(currentStep == step ? 1 : 0)
                            .offset(x: currentStep == step ? 0 : (currentStep.rawValue > step.rawValue ? -geometry.size.width : geometry.size.width))
                        }
                    }
                    .animation(.easeInOut(duration: 0.3), value: currentStep)
                    .frame(height: geometry.size.height * 0.7, alignment: .top)

                    Spacer()

                    VStack {
                        Button(action: {
                            handleButtonAction()
                        }) {
                            Text(currentStep.buttonLabel)
                                .frame(width: geometry.size.width * 0.8)
                                .padding(.vertical, 6)
                        }
                        .buttonStyle(.borderedProminent)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .disabled(currentStep == .generateScreenName && selectedScreenName.isEmpty)

                        ProgressView(value: Double(currentStep.rawValue), total: Double(RegistrationStep.allCases.count - 1))
                            .padding()

                        HStack {
                            if currentStep != .welcome {
                                Button("Back") {
                                    withAnimation(.easeInOut(duration: 0.3)) {
                                        slideDirection = .right
                                        currentStep = RegistrationStep(rawValue: currentStep.rawValue - 1) ?? .welcome
                                    }
                                }
                            }
                            Spacer()
                            if currentStep == .welcome {
                                Button("Next") {
                                    handleButtonAction()
                                }
                                .disabled(currentStep == .generateScreenName && selectedScreenName.isEmpty)
                            }
                        }
                        .padding()
                    }
                }
                .navigationTitle(currentStep.title)
                #if ios
                    .navigationBarTitleDisplayMode(.large)
                #endif
            }
        }
    }

    private var welcomeView: some View {
        VStack {
            LogoView()
                .frame(width: 300, height: 300)
            Text("Arkavo")
                .font(.largeTitle)
                .fontWeight(.light)
                .padding(.bottom, 50)

            GeometryReader { geometry in
                HStack(spacing: 0) {
                    ForEach(0 ..< welcomeMessages.count, id: \.self) { index in
                        Text(welcomeMessages[index])
                            .frame(width: geometry.size.width, height: 100)
                            .multilineTextAlignment(.center)
                            .padding(0)
                    }
                }
                .offset(x: CGFloat(currentWelcomeIndex) * -geometry.size.width)
                .animation(.easeInOut, value: currentWelcomeIndex)
            }
            .frame(height: 100)
        }
        .onAppear {
            startWelcomeAnimation()
        }
    }

    private func startWelcomeAnimation() {
        Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { _ in
            withAnimation {
                currentWelcomeIndex = (currentWelcomeIndex + 1) % welcomeMessages.count
            }
        }
    }

    private var enablePasskeysView: some View {
        VStack(spacing: 20) {
            Image(systemName: "faceid")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 100, height: 100)
                .foregroundColor(.blue)
                .padding()
                .background(
                    RoundedRectangle(cornerRadius: 20)
                        .stroke(Color.gray.opacity(0.2), lineWidth: 2)
                )

            Text("Enable passkeys")
                .font(.title)
                .fontWeight(.bold)

            Text("Use your face ID to verify it's you.\nThere's no need for a password.")
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)

            Spacer()

            Text("Learn more, view our")
                .foregroundColor(.secondary)

            Button("Face ID Terms & Conditions") {
                // Action to show terms and conditions
            }
            .foregroundColor(.blue)
        }
        .padding()
    }

    private func handleButtonAction() {
        withAnimation(.easeInOut(duration: 0.3)) {
            slideDirection = .left
            switch currentStep {
            case .welcome:
                currentStep = .selectInterests
            case .selectInterests:
                currentStep = .generateScreenName
                generatedScreenNames = []
            case .generateScreenName:
                currentStep = .enablePasskeys
            case .enablePasskeys:
                let newProfile = Profile(
                    name: selectedScreenName,
                    interests: Array(selectedInterests).joined(separator: ","),
                    hasHighEncryption: true,
                    hasHighIdentityAssurance: true
                )
                Task {
                    await onComplete(newProfile)
                }
            }
        }
    }

    private var generateScreenNameView: some View {
        VStack(spacing: 20) {
            Text("Your profile name will be revealed only to those fortunate enough to earn your approval.")
                .padding()
            HStack {
                TextField("Enter profile name", text: $selectedScreenName)
                    .writingToolsBehavior(.automatic)
                    .padding()
                    .disableAutocorrection(true)
                    .border(.secondary)
                Button(action: generateScreenNames) {
                    Image(systemName: "wand.and.stars")
                        .foregroundColor(.white)
                        .padding(10)
                        .background(Color.blue)
                        .cornerRadius(8)
                }
            }
            .padding()
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 100))], spacing: 10) {
                ForEach(generatedScreenNames, id: \.self) { name in
                    Button(action: {
                        selectedScreenName = name
                    }) {
                        Text(name)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(selectedScreenName == name ? Color.blue : Color.gray.opacity(0.2))
                            .foregroundColor(selectedScreenName == name ? .white : .primary)
                            .cornerRadius(20)
                            .lineLimit(1)
                            .minimumScaleFactor(0.5)
                    }
                }
            }
        }
        .multilineTextAlignment(.leading)
        .padding()
    }

    private func generateScreenNames() {
        do {
            let configuration = MLModelConfiguration()
            let recommender = try MyRecommender_1(configuration: configuration)
            let items = Dictionary(uniqueKeysWithValues: selectedInterests.map { ($0, 1.0) })
            let input = MyRecommender_1Input(items: items, k: 5, restrict_: nil, exclude: nil)
            let output = try recommender.prediction(input: input)
            generatedScreenNames = output.recommendations
        } catch {
            print("recommendation error: \(error.localizedDescription)")
        }
    }

    private var chooseInterestsView: some View {
        VStack(spacing: 20) {
            Text("Tell us your likes or dislikes. This helps us match your preference best.")
                .padding()
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 100))], spacing: 10) {
                ForEach(interests, id: \.self) { interest in
                    InterestButton(interest: interest, isSelected: selectedInterests.contains(interest)) {
                        if selectedInterests.contains(interest) {
                            selectedInterests.remove(interest)
                        } else {
                            selectedInterests.insert(interest)
                        }
                    }
                }
            }
        }
        .padding()
    }
}

struct InterestButton: View {
    let interest: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(interest)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(isSelected ? Color.blue : Color.gray.opacity(0.2))
                .foregroundColor(isSelected ? .white : .primary)
                .cornerRadius(20)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
        }
    }
}

struct LogoView: View {
    @State private var offsetY: CGFloat = 0

    var body: some View {
        Image("AppLogo")
            .resizable()
            .scaledToFit()
            .accessibilityLabel("logo")
            .offset(y: offsetY)
    }
}

enum SlideDirection {
    case left, right
}

#Preview {
    RegistrationView(onComplete: { _ in })
        .modelContainer(for: Profile.self, inMemory: true)
}
