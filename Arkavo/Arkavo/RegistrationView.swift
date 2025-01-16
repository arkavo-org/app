import Combine
import CoreML
import NaturalLanguage
import SwiftUI

enum RegistrationStep: Int, CaseIterable {
    case welcome
    case eula
//    case selectInterests
    case generateScreenName
    case enablePasskeys

    var title: String {
        switch self {
        case .welcome:
            "Welcome"
        case .eula:
            "Terms of Service"
//        case .selectInterests:
//            "Select Interests" // What topics are you interested in?
        case .generateScreenName:
            "Create Handle"
        case .enablePasskeys:
            "Create Passkey"
        }
    }

    var buttonLabel: String {
        switch self {
        case .welcome:
            "Get Started"
        case .eula:
            "Accept & Continue"
//        case .selectInterests:
//            "Continue"
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
    @State private var isCheckingAvailability = false
    @State private var isScreenNameAvailable = true
    @State private var screenNameCancellable: AnyCancellable?
    @State private var eulaAccepted = false

    private var debouncedScreenNamePublisher: Publishers.Debounce<NotificationCenter.Publisher, RunLoop> {
        NotificationCenter.default
            .publisher(for: UITextField.textDidChangeNotification)
            .debounce(for: .seconds(0.2), scheduler: RunLoop.main)
    }

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
                                case .eula:
                                    eulaView
//                                case .selectInterests:
//                                    chooseInterestsView
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
                        .disabled(currentStep == .generateScreenName && (selectedScreenName.isEmpty || !isScreenNameAvailable || isCheckingAvailability) || (currentStep == .eula && !eulaAccepted))

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
                                .disabled(currentStep == .generateScreenName && (selectedScreenName.isEmpty || !isScreenNameAvailable || isCheckingAvailability))
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

    private var eulaView: some View {
        VStack(spacing: 20) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("End User License Agreement (EULA)")
                        .font(.title2)
                        .fontWeight(.bold)
                        .padding(.bottom, 8)

                    Text(EULA) // Store the EULA text in a constant
                        .font(.body)

                    Toggle("I have read and agree to the End User License Agreement", isOn: $eulaAccepted)
                        .padding(.vertical)
                }
                .padding()
            }
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
                currentStep = .generateScreenName
                generatedScreenNames = []
            case .eula:
                currentStep = .generateScreenName
                generatedScreenNames = []
//            case .selectInterests:
//                currentStep = .generateScreenName
//                generatedScreenNames = []
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
            Text("Your handle must be unique within arkavo.social")
                .padding()
            HStack {
                #if os(iOS)
                    TextField("Enter handle", text: screenNameBinding)
                        .writingToolsBehavior(.automatic)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .padding()
                        .border(.secondary)
                        .onAppear {
                            screenNameCancellable = debouncedScreenNamePublisher
                                .sink { _ in
                                    Task {
                                        await checkScreenNameAvailability()
                                    }
                                }
                        }
                        .onDisappear {
                            screenNameCancellable?.cancel()
                        }
                #else
                    TextField("Enter handle", text: screenNameBinding)
                        .writingToolsBehavior(.automatic)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .padding()
                        .border(.secondary)
                        .onAppear {
                            screenNameCancellable = debouncedScreenNamePublisher
                                .sink { _ in
                                    Task {
                                        await checkScreenNameAvailability()
                                    }
                                }
                        }
                        .onDisappear {
                            screenNameCancellable?.cancel()
                        }
                #endif
//                Button(action: generateScreenNames) {
//                    Image(systemName: "wand.and.stars")
//                        .foregroundColor(.white)
//                        .padding(10)
//                        .background(Color.blue)
//                        .cornerRadius(8)
//                }
                if isCheckingAvailability {
                    ProgressView()
                        .padding(.horizontal)
                } else if !selectedScreenName.isEmpty {
                    Image(systemName: isScreenNameAvailable ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .foregroundColor(isScreenNameAvailable ? .green : .red)
                        .padding(.horizontal)
                }
                if !selectedScreenName.isEmpty {
                    Text(isScreenNameAvailable ? "Available" : "Not available")
                        .font(.caption)
                        .foregroundColor(isScreenNameAvailable ? .green : .red)
                        .padding(.leading)
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

    // filter characters
    private func validateAndFormatScreenName(_ input: String) -> String {
        // Convert to lowercase and keep only allowed characters
        let filtered = input.lowercased().filter { char in
            char.isLetter || char.isNumber || char == "-"
        }
        return filtered
    }

    // TextField binding to use the validation
    private var screenNameBinding: Binding<String> {
        Binding(
            get: { selectedScreenName },
            set: { newValue in
                selectedScreenName = validateAndFormatScreenName(newValue)
            }
        )
    }

    private func checkScreenNameAvailability() async {
        // Empty state should show as available
        guard !selectedScreenName.isEmpty else {
            isCheckingAvailability = false
            isScreenNameAvailable = true
            return
        }

        // Only check if handle is at least 3 characters
        guard selectedScreenName.count >= 3 else {
            isCheckingAvailability = false
            isScreenNameAvailable = true
            return
        }

        isCheckingAvailability = true
        let urlString = "https://xrpc.arkavo.net/xrpc/com.atproto.identity.resolveHandle?handle=\(selectedScreenName).arkavo.social"

        guard let url = URL(string: urlString) else {
            isCheckingAvailability = false
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "HEAD"

        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            if let httpResponse = response as? HTTPURLResponse {
                isScreenNameAvailable = httpResponse.statusCode != 200
            }
        } catch {
            // Handle network errors
            print("Error checking availability: \(error.localizedDescription)")
        }

        isCheckingAvailability = false
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
    @State private var scale: CGFloat = 4.0

    var body: some View {
        Image("AppLogo")
            .resizable()
            .scaledToFit()
            .accessibilityLabel("logo")
            .scaleEffect(scale)
            .offset(y: offsetY)
            .onAppear {
                withAnimation(.easeOut(duration: 2.0)) {
                    scale = 1.0
                }
            }
    }
}

enum SlideDirection {
    case left, right
}

private let EULA = """
**End User License Agreement (EULA)**

**Effective Date:** [Insert Date]

**1. Agreement to Terms**
By creating an account or using Arkavo (“App”), you agree to be bound by this End User License Agreement (“EULA”). If you do not agree to these terms, you must not use the App.

**2. Prohibited Conduct**
Arkavo has a zero-tolerance policy for objectionable content or abusive behavior. Users are prohibited from:

- Posting or sharing content that is defamatory, obscene, violent, hateful, or discriminatory.
- Engaging in harassment, threats, or abuse towards other users.
- Sharing content that infringes intellectual property rights or violates laws.
- Misusing the platform to distribute spam or malicious software.

**3. Content Moderation**
Arkavo implements a comprehensive content moderation system to filter objectionable material. Automated tools, combined with manual review processes, ensure compliance with this EULA and applicable laws.

**4. Reporting and Flagging Mechanisms**
Users can report objectionable content through the following steps:

1. Use the “Report” button available on all posts and user profiles.
2. Specify the nature of the objectionable content or behavior.

Arkavo’s moderation team will review reports within 24 hours and take appropriate action, including removing the content and addressing the user’s account.

**5. Blocking Abusive Users**
Arkavo allows users to block other users who engage in abusive behavior. To block a user:

1. Navigate to the user’s profile.
2. Select the “Block User” option.

Blocked users will no longer be able to interact with or view the blocker’s profile or content.

**6. Enforcement Actions**
Users found violating this EULA may face one or more of the following actions:

- Warning notifications for minor violations.
- Temporary suspension of account privileges.
- Permanent account termination for severe or repeated violations.

**7. Developer’s Responsibility**
Arkavo’s development team is committed to:

- Reviewing and acting on all reports of objectionable content within 24 hours.
- Permanently removing content that violates this EULA.
- Ejecting users who repeatedly or severely violate these terms.

**8. Updates to the EULA**
Arkavo reserves the right to modify this EULA at any time. Updates will be communicated through the App, and continued use constitutes acceptance of the revised terms.

**9. Contact Information**
For questions or concerns about this EULA, please contact Arkavo Support at support@arkavo.com.

---

By using Arkavo, you agree to abide by these terms and help maintain a safe and respectful community.

"""
