import SwiftUI

// MARK: - UX Redesign for EULA Acceptance

// This redesign addresses:
// 1. Checkbox visibility issues
// 2. Automation tool compatibility
// 3. Legal compliance requirements
// 4. User experience improvements

extension RegistrationView {
    // Redesigned EULA view with fixed layout
    private var redesignedEulaView: some View {
        VStack(spacing: 0) {
            // MARK: Fixed Header

            VStack(alignment: .leading, spacing: 8) {
                Text("Terms of Service")
                    .font(.largeTitle)
                    .fontWeight(.bold)

                Text("Please review and accept our terms")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
            .background(Color(UIColor.systemBackground))

            Divider()

            // MARK: Scrollable Content

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // Summary Section (New)
                    VStack(alignment: .leading, spacing: 12) {
                        Label("Key Points", systemImage: "checkmark.shield")
                            .font(.headline)
                            .foregroundColor(.blue)

                        VStack(alignment: .leading, spacing: 8) {
                            BulletPoint("Zero-tolerance for harmful content")
                            BulletPoint("Military-grade encryption for your data")
                            BulletPoint("You own your content")
                            BulletPoint("Privacy by design")
                        }
                    }
                    .padding()
                    .background(Color.blue.opacity(0.1))
                    .cornerRadius(12)

                    // Full EULA Text
                    Group {
                        Text("End User License Agreement (EULA)")
                            .font(.title2)
                            .fontWeight(.semibold)

                        Text("Effective Date: 2025-01-15")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        // EULA sections
                        eulaSection(
                            title: "1. Agreement to Terms",
                            content: "By creating an account or using Arkavo (\"App\"), you agree to be bound by this End User License Agreement (\"EULA\"). If you do not agree to these terms, you must not use the App.",
                        )

                        eulaSection(
                            title: "2. Prohibited Conduct",
                            content: "Arkavo has a zero-tolerance policy for objectionable content or abusive behavior. Users are prohibited from:",
                            bullets: [
                                "Posting or sharing content that is defamatory, obscene, violent, hateful, or discriminatory",
                                "Engaging in harassment, threats, or abuse towards other users",
                                "Sharing content that infringes intellectual property rights or violates laws",
                            ],
                        )

                        // Additional sections...
                    }
                }
                .padding()
            }
            .background(Color(UIColor.secondarySystemBackground))

            // MARK: Fixed Bottom Section

            VStack(spacing: 16) {
                Divider()

                // Acceptance Controls
                VStack(spacing: 12) {
                    // Checkbox with improved visibility
                    HStack(spacing: 12) {
                        Image(systemName: eulaAccepted ? "checkmark.square.fill" : "square")
                            .font(.title2)
                            .foregroundColor(eulaAccepted ? .blue : .gray)
                            .onTapGesture {
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                    eulaAccepted.toggle()
                                }
                            }
                            .accessibilityLabel("EULA Checkbox")
                            .accessibilityHint(eulaAccepted ? "Checked" : "Unchecked")
                            .accessibilityAddTraits(.isButton)

                        Text("I have read and agree to the End User License Agreement")
                            .font(.footnote)
                            .fixedSize(horizontal: false, vertical: true)
                            .onTapGesture {
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                    eulaAccepted.toggle()
                                }
                            }

                        Spacer()
                    }
                    .padding(.horizontal)
                    .contentShape(Rectangle()) // Improves tap area

                    // Action Buttons
                    HStack(spacing: 12) {
                        // Secondary Action
                        Button(action: {
                            // Navigate back
                            withAnimation(.easeInOut(duration: 0.3)) {
                                slideDirection = .right
                                currentStep = .welcome
                            }
                        }) {
                            Text("Back")
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                        }
                        .buttonStyle(.bordered)
                        .accessibilityLabel("Go Back")

                        // Primary Action
                        Button(action: {
                            handleButtonAction()
                        }) {
                            HStack {
                                Text("Accept & Continue")
                                Image(systemName: "arrow.right")
                                    .font(.footnote)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(!eulaAccepted)
                        .accessibilityLabel("Accept and Continue")
                        .accessibilityHint(eulaAccepted ? "Tap to continue" : "Accept terms first")
                    }
                    .padding(.horizontal)

                    // Legal Links
                    HStack {
                        Button("Privacy Policy") {
                            // Open privacy policy
                        }
                        .font(.caption)

                        Spacer()

                        Button("Contact Support") {
                            // Open support
                        }
                        .font(.caption)
                    }
                    .padding(.horizontal)
                    .foregroundColor(.blue)
                }
                .padding(.vertical, 12)
                .background(Color(UIColor.systemBackground))
            }
        }
        .ignoresSafeArea(.container, edges: .bottom)
    }

    // Helper view for bullet points
    private struct BulletPoint: View {
        let text: String

        init(_ text: String) {
            self.text = text
        }

        var body: some View {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.caption)
                    .foregroundColor(.green)
                    .offset(y: 2)

                Text(text)
                    .font(.subheadline)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // Helper function for EULA sections
    private func eulaSection(title: String, content: String, bullets: [String]? = nil) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)
                .padding(.top, 8)

            Text(content)
                .font(.body)
                .fixedSize(horizontal: false, vertical: true)

            if let bullets {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(bullets, id: \.self) { bullet in
                        HStack(alignment: .top, spacing: 8) {
                            Text("•")
                                .font(.body)
                            Text(bullet)
                                .font(.body)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .padding(.leading, 16)
            }
        }
    }
}

// MARK: - Automation Helpers

extension RegistrationView {
    // Automation-friendly checkbox implementation
    private var automationFriendlyCheckbox: some View {
        Button(action: {
            eulaAccepted.toggle()
        }) {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(eulaAccepted ? Color.blue : Color.gray, lineWidth: 2)
                        .frame(width: 24, height: 24)

                    if eulaAccepted {
                        Image(systemName: "checkmark")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(.blue)
                    }
                }

                Text("I have read and agree to the End User License Agreement")
                    .font(.body)
                    .multilineTextAlignment(.leading)
                    .foregroundColor(.primary)

                Spacer()
            }
        }
        .buttonStyle(PlainButtonStyle())
        .accessibilityLabel("EULA Agreement Checkbox")
        .accessibilityValue(eulaAccepted ? "Checked" : "Unchecked")
        .accessibilityHint("Double tap to toggle agreement")
    }
}
