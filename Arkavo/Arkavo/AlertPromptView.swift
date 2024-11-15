import SwiftUI

struct AlertPromptView: View {
    var body: some View {
        VStack(spacing: 16) {
            PromptCard(
                icon: "exclamationmark.triangle.fill",
                title: "High Risk",
                description: "This action requires additional review",
                color: .red
            )

            PromptCard(
                icon: "info.circle.fill",
                title: "Additional Information Required",
                description: "Please provide further details to proceed",
                color: .blue
            )

            PromptCard(
                icon: "exclamationmark.circle.fill",
                title: "Warning",
                description: "Placeholder for additional prompt",
                color: .orange
            )
        }
        .padding()
    }
}

struct PromptCard: View {
    let icon: String
    let title: String
    let description: String
    let color: Color

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .foregroundColor(color)
                .font(.system(size: 24))

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                    .foregroundColor(color)

                Text(description)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
        }
        .padding()
        .background(color.opacity(0.1))
        .cornerRadius(12)
    }
}

#Preview("Alert Prompts") {
    AlertPromptView()
}
