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
    @EnvironmentObject private var sharedState: SharedState

    private let skipPasskeysFlag: Bool = {
        let args = ProcessInfo.processInfo.arguments
        if args.contains("-ArkavoSkipPasskey") { return true }
        if UserDefaults.standard.bool(forKey: "ArkavoSkipPasskey") { return true }
        return false
    }()

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
    @FocusState private var isHandleFieldFocused: Bool

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
        NavigationStack {
            VStack(spacing: 0) {
                // Custom title bar
                HStack {
                    Text(currentStep.title)
                        .font(.largeTitle)
                        .fontWeight(.bold)
                        .padding()
                    Spacer()
                }
                .background(Color.gray.opacity(0.1))

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
//                                    case .selectInterests:
//                                        chooseInterestsView
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
                                Text(currentButtonLabel)
                                    .frame(width: geometry.size.width * 0.8)
                                    .padding(.vertical, 6)
                            }
                            .buttonStyle(.borderedProminent)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .disabled(currentStep == .generateScreenName && (selectedScreenName.isEmpty || !isScreenNameAvailable || isCheckingAvailability) || (currentStep == .eula && !eulaAccepted))

                            ProgressView(value: Double(currentStep.rawValue), total: Double(RegistrationStep.allCases.count - 1))
                                .padding()

                            if let details = sharedState.lastRegistrationErrorDetails, !details.isEmpty {
                                VStack(alignment: .leading, spacing: 8) {
                                    HStack(alignment: .top, spacing: 8) {
                                        Image(systemName: "exclamationmark.triangle.fill")
                                            .foregroundColor(.orange)
                                        Text("Registration issue: \(details)")
                                            .font(.footnote)
                                            .foregroundColor(.secondary)
                                            .textSelection(.enabled)
                                    }
                                    Text("You can retry, or contact support@arkavo.com with these details.")
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                }
                                .padding(10)
                                .background(Color(UIColor.secondarySystemBackground))
                                .cornerRadius(8)
                                .padding(.horizontal)
                            }

                            HStack {
                                if currentStep != .welcome {
                                    Button("Back") {
                                        withAnimation(.easeInOut(duration: 0.3)) {
                                            slideDirection = .right
                                            currentStep = RegistrationStep(rawValue: currentStep.rawValue - 1) ?? .welcome
                                        }
                                    }
                                } else {
                                    Button("Skip for now") {
                                        // Return to offline mode / network connections
                                        sharedState.isOfflineMode = true
                                    }
                                    .foregroundStyle(.secondary)
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
                }
            }
            .navigationBarHidden(true) // Hide the default navigation bar
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
                        .stroke(Color.gray.opacity(0.2), lineWidth: 2),
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

    private var currentButtonLabel: String {
        if currentStep == .generateScreenName, skipPasskeysFlag {
            return "Finish Registration"
        }
        return currentStep.buttonLabel
    }

    private func handleButtonAction() {
        withAnimation(.easeInOut(duration: 0.3)) {
            slideDirection = .left
            switch currentStep {
            case .welcome:
                currentStep = .eula
                generatedScreenNames = []
            case .eula:
                currentStep = .generateScreenName
                generatedScreenNames = []
//            case .selectInterests:
//                currentStep = .generateScreenName
//                generatedScreenNames = []
            case .generateScreenName:
                if skipPasskeysFlag {
                    let newProfile = Profile(
                        name: selectedScreenName,
                        interests: Array(selectedInterests).joined(separator: ","),
                        hasHighEncryption: true,
                        hasHighIdentityAssurance: true,
                    )
                    Task { await onComplete(newProfile) }
                } else {
                    currentStep = .enablePasskeys
                }
            case .enablePasskeys:
                let newProfile = Profile(
                    name: selectedScreenName,
                    interests: Array(selectedInterests).joined(separator: ","),
                    hasHighEncryption: true,
                    hasHighIdentityAssurance: true,
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
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .padding()
                        .border(.secondary)
                        .textFieldStyle(.roundedBorder)
                        .focused($isHandleFieldFocused)
                        .accessibilityLabel("Handle input field")
                        .accessibilityIdentifier("handleTextField")
                        .accessibilityHint("Enter your unique handle for arkavo.social")
                        .onAppear {
                            // Commenting out auto-focus as it might interfere with keyboard input
                            // DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                            //     isHandleFieldFocused = true
                            // }
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
                        .focused($isHandleFieldFocused)
                        .accessibilityLabel("Handle input field")
                        .accessibilityIdentifier("handleTextField")
                        .accessibilityHint("Enter your unique handle for arkavo.social")
                        .onAppear {
                            // Commenting out auto-focus as it might interfere with keyboard input
                            // DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                            //     isHandleFieldFocused = true
                            // }
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
            },
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

    private var eulaView: some View {
        VStack(spacing: 0) {
            // Fixed Header (HIG-compliant)
            VStack(alignment: .leading, spacing: 8) {
                Text("Please review and accept our terms")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
            .background(Color(UIColor.systemBackground))

            Divider()

            // Scrollable Content
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    // Key Points Summary (HIG-compliant)
                    VStack(alignment: .leading, spacing: 12) {
                        Label("Key Points", systemImage: "checkmark.shield.fill")
                            .font(.headline)
                            .foregroundColor(.accentColor)

                        VStack(alignment: .leading, spacing: 8) {
                            Label("Zero-tolerance for harmful content", systemImage: "checkmark.circle.fill")
                                .font(.subheadline)
                                .labelStyle(HorizontalLabelStyle())
                            Label("Military-grade encryption for your data", systemImage: "checkmark.circle.fill")
                                .font(.subheadline)
                                .labelStyle(HorizontalLabelStyle())
                            Label("You own your content", systemImage: "checkmark.circle.fill")
                                .font(.subheadline)
                                .labelStyle(HorizontalLabelStyle())
                            Label("Privacy by design", systemImage: "checkmark.circle.fill")
                                .font(.subheadline)
                                .labelStyle(HorizontalLabelStyle())
                        }
                    }
                    .padding()
                    .background(Color.accentColor.opacity(0.1))
                    .cornerRadius(12)

                    Text("End User License Agreement (EULA)")
                        .font(.title2.bold())

                    Text("Effective Date: 2025-01-15")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    VStack(alignment: .leading, spacing: 16) {
                        Group {
                            Text("1. Agreement to Terms")
                                .font(.headline)
                                .fontWeight(.semibold)

                            Text("By creating an account or using Arkavo (\"App\"), you agree to be bound by this End User License Agreement (\"EULA\"). If you do not agree to these terms, you must not use the App.")
                        }

                        Group {
                            Text("2. Prohibited Conduct")
                                .font(.headline)
                                .fontWeight(.semibold)

                            Text("Arkavo has a zero-tolerance policy for objectionable content or abusive behavior. Users are prohibited from:")

                            VStack(alignment: .leading, spacing: 8) {
                                BulletPoint("Posting or sharing content that is defamatory, obscene, violent, hateful, or discriminatory.")
                                BulletPoint("Engaging in harassment, threats, or abuse towards other users.")
                                BulletPoint("Sharing content that infringes intellectual property rights or violates laws.")
                                BulletPoint("Misusing the platform to distribute spam or malicious software.")
                            }
                        }

                        Group {
                            Text("3. Content Moderation")
                                .font(.headline)
                                .fontWeight(.semibold)

                            Text("Arkavo implements a comprehensive content moderation system to filter objectionable material. Automated tools, combined with manual review processes, ensure compliance with this EULA and applicable laws.")
                        }

                        Group {
                            Text("4. Reporting and Flagging Mechanisms")
                                .font(.headline)
                                .fontWeight(.semibold)

                            Text("Users can report objectionable content through the following steps:")

                            VStack(alignment: .leading, spacing: 8) {
                                NumberedPoint(1, "Use the \"Report\" button available on all posts and user profiles.")
                                NumberedPoint(2, "Specify the nature of the objectionable content or behavior.")
                            }

                            Text("Arkavo's moderation team will review reports within 24 hours and take appropriate action, including removing the content and addressing the user's account.")
                        }

                        Group {
                            Text("5. Blocking Abusive Users")
                                .font(.headline)
                                .fontWeight(.semibold)

                            Text("Arkavo allows users to block other users who engage in abusive behavior. To block a user:")

                            VStack(alignment: .leading, spacing: 8) {
                                NumberedPoint(1, "Navigate to the user's profile.")
                                NumberedPoint(2, "Select the \"Block User\" option.")
                            }

                            Text("Blocked users will no longer be able to interact with or view the blocker's profile or content.")
                        }

                        Group {
                            Text("6. Enforcement Actions")
                                .font(.headline)
                                .fontWeight(.semibold)

                            Text("Users found violating this EULA may face one or more of the following actions:")

                            VStack(alignment: .leading, spacing: 8) {
                                BulletPoint("Warning notifications for minor violations.")
                                BulletPoint("Temporary suspension of account privileges.")
                                BulletPoint("Permanent account termination for severe or repeated violations.")
                            }
                        }

                        Group {
                            Text("7. Developer's Responsibility")
                                .font(.headline)
                                .fontWeight(.semibold)

                            Text("Arkavo's development team is committed to:")

                            VStack(alignment: .leading, spacing: 8) {
                                BulletPoint("Reviewing and acting on all reports of objectionable content within 24 hours.")
                                BulletPoint("Permanently removing content that violates this EULA.")
                                BulletPoint("Ejecting users who repeatedly or severely violate these terms.")
                            }
                        }

                        Group {
                            Text("8. Updates to the EULA")
                                .font(.headline)
                                .fontWeight(.semibold)

                            Text("Arkavo reserves the right to modify this EULA at any time. Updates will be communicated through the App, and continued use constitutes acceptance of the revised terms.")
                        }

                        Group {
                            Text("9. Contact Information")
                                .font(.headline)
                                .fontWeight(.semibold)

                            Text("For questions or concerns about this EULA, please contact Arkavo Support at support@arkavo.com.")
                        }

                        Divider()
                            .padding(.vertical)

                        Text("By using Arkavo, you agree to abide by these terms and help maintain a safe and respectful community.")
                            .fontWeight(.medium)
                    }
                }
                .padding()
            }
            .background(Color(UIColor.secondarySystemBackground))

            // Fixed Footer (HIG-compliant)
            VStack(spacing: 16) {
                Divider()

                // Custom checkbox button for better automation support
                Button(action: {
                    eulaAccepted.toggle()
                }) {
                    HStack(alignment: .center, spacing: 12) {
                        Image(systemName: eulaAccepted ? "checkmark.square.fill" : "square")
                            .foregroundColor(eulaAccepted ? .accentColor : Color(UIColor.tertiaryLabel))
                            .font(.system(size: 22))

                        Text("I have read and agree to the End User License Agreement")
                            .font(.footnote)
                            .foregroundColor(.primary)
                            .multilineTextAlignment(.leading)

                        Spacer()
                    }
                }
                .padding(.horizontal)
                .accessibilityLabel("EULA Agreement Checkbox")
                .accessibilityHint(eulaAccepted ? "Agreement accepted" : "Tap to accept agreement")
                .accessibilityAddTraits(.isButton)

                // Support links
                HStack {
                    Link("Privacy Policy", destination: URL(string: "https://arkavo.com/privacy.html")!)
                        .font(.caption)

                    Spacer()

                    Link("Contact Support", destination: URL(string: "mailto:support@arkavo.com")!)
                        .font(.caption)
                }
                .padding(.horizontal)
                .foregroundColor(.accentColor)
            }
            .padding(.vertical, 12)
            .background(Color(UIColor.systemBackground))
            .overlay(
                Rectangle()
                    .frame(height: 1)
                    .foregroundColor(Color(UIColor.separator)),
                alignment: .top,
            )
        }
    }
}

// HIG-compliant horizontal label style
struct HorizontalLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(alignment: .center, spacing: 8) {
            configuration.icon
                .foregroundColor(.green)
                .imageScale(.small)
            configuration.title
        }
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

struct BulletPoint: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        HStack(alignment: .top) {
            Text("•")
                .padding(.trailing, 4)
            Text(text)
        }
    }
}

struct NumberedPoint: View {
    let number: Int
    let text: String

    init(_ number: Int, _ text: String) {
        self.number = number
        self.text = text
    }

    var body: some View {
        HStack(alignment: .top) {
            Text("\(number).")
                .padding(.trailing, 4)
            Text(text)
        }
    }
}
