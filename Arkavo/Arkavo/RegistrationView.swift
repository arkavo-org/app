import SwiftUI

enum RegistrationStep: Int, CaseIterable {
    case welcome
    case generateScreenName
    case chooseScreenName
    case selectInterests

    var title: String {
        switch self {
        case .welcome:
            "Welcome"
        case .generateScreenName:
            "Generate Screen Name"
        case .chooseScreenName:
            "Choose Screen Name"
        case .selectInterests:
            "Select Interests"
        }
    }

    var buttonLabel: String {
        switch self {
        case .welcome:
            "Get Started"
        case .generateScreenName:
            "Generate Screen Names"
        case .chooseScreenName:
            "Continue"
        case .selectInterests:
            "Continue"
        }
    }
}

struct RegistrationView: View {
    @Environment(\.modelContext) private var modelContext
    var onComplete: () -> Void

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
                                case .generateScreenName:
                                    generateScreenNameView
                                case .chooseScreenName:
                                    chooseScreenNameView
                                case .selectInterests:
                                    chooseInterestsView
                                }
                            }
                            .opacity(currentStep == step ? 1 : 0)
                            .offset(x: currentStep == step ? 0 : (currentStep.rawValue > step.rawValue ? -geometry.size.width : geometry.size.width))
                            .padding(.top, 20)
                        }
                    }
                    .animation(.easeInOut(duration: 0.3), value: currentStep)
                    .frame(height: geometry.size.height * 0.7)

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
                            if currentStep != .selectInterests {
                                Button("Next") {
                                    handleButtonAction()
                                }
                                .disabled(currentStep == .chooseScreenName && selectedScreenName.isEmpty)
                            }
                        }
                        .padding()
                    }
                }
                .navigationTitle(currentStep.title)
                .navigationBarTitleDisplayMode(.large)
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

    private func handleButtonAction() {
        withAnimation(.easeInOut(duration: 0.3)) {
            slideDirection = .left
            switch currentStep {
            case .welcome:
                currentStep = .generateScreenName
            case .generateScreenName:
                generatedScreenNames = generateScreenNames()
                currentStep = .chooseScreenName
            case .chooseScreenName:
                currentStep = .selectInterests
            case .selectInterests:
                onComplete()
            }
        }
    }

    private var generateScreenNameView: some View {
        VStack(spacing: 20) {
            Text("Your profile name will be revealed only to those fortunate enough to earn your approval.")
                .padding()
        }
        .multilineTextAlignment(.leading)
        .padding()
    }

    private var chooseScreenNameView: some View {
        VStack(spacing: 20) {
            Text("Pick one of the following options:")
                .padding()

            ForEach(generatedScreenNames, id: \.self) { name in
                Button(action: {
                    selectedScreenName = name
                }) {
                    Text(name)
                        .padding()
                        .frame(maxWidth: .infinity)
                        .background(selectedScreenName == name ? Color.blue : Color.gray.opacity(0.2))
                        .foregroundColor(selectedScreenName == name ? .white : .primary)
                        .cornerRadius(8)
                }
            }
        }
        .padding()
    }

    private var chooseInterestsView: some View {
        VStack(spacing: 20) {
            Text("What topics are you interested in?")
                .padding()

            Text("Tell us your likes or dislikes. This helps us match your preference best.")
                .font(.caption)
                .padding(.bottom)

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

            Button("Complete Registration") {
                onComplete()
            }
            .buttonStyle(.borderedProminent)
            .padding(.top)
        }
        .padding()
    }

    private func generateScreenNames() -> [String] {
        // In a real app, you'd implement logic to generate unique screen names
        ["ravioloitaly", "luckyjellyfish", "plantsarefun", "nonameismyname"]
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
                .cornerRadius(15)
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
    RegistrationView(onComplete: {})
        .modelContainer(for: Profile.self, inMemory: true)
}
